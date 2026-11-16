-- PASO 14 — Sincronización total, gastos del motorizado y seguimiento GPS
--
-- Problema que corrige:
--   * `gastos` solo tenía política de ADMIN: el motorizado no podía guardar ni
--     ver sus gastos, así que "Mi registro" nunca los mostraba.
--   * Realtime solo publicaba `pedidos`: los cobros y gastos no avisaban a las
--     pantallas abiertas.
--   * No existía una ubicación compartida para el seguimiento del admin.
--   * Algunos pedidos quedaron con entrega/pago registrados pero estado
--     EN_CAMINO (se entregaron antes de aplicar los triggers).
--
-- Qué hace (todo NO destructivo):
--   1. Crea `ubicaciones_motorizado` (una fila por motorizado) con RLS.
--   2. Añade `gastos.uuid_offline` y sus políticas (motorizado + admin).
--   3. Repite las políticas del cuaderno del motorizado (paso 11) para que
--      pueda registrar pedidos y líneas aunque el paso no se haya aplicado.
--   4. Añade columnas aditivas que la app ya usa (comprobante de Yape, tipo de
--      producto, días de trabajo) si todavía no existen.
--   5. Publica en Realtime las tablas que mueven la UI.
--   6. Reconcilia pedidos con entrega real pero estado viejo → ENTREGADO.
--
-- Reejecutable: se puede correr las veces que haga falta.

-- ---------------------------------------------------------------------------
-- 1) Ubicación de los motorizados
-- ---------------------------------------------------------------------------
create table if not exists public.ubicaciones_motorizado (
  usuario_id     uuid primary key references auth.users(id) on delete cascade,
  empresa_id     uuid not null references public.empresas(id) on delete cascade,
  latitud        double precision not null,
  longitud       double precision not null,
  precision_m    double precision,
  actualizado_en timestamptz not null default now()
);

create index if not exists ix_ubicaciones_empresa
  on public.ubicaciones_motorizado (empresa_id, actualizado_en desc);

alter table public.ubicaciones_motorizado enable row level security;

drop policy if exists "ubicaciones_select" on public.ubicaciones_motorizado;
create policy "ubicaciones_select" on public.ubicaciones_motorizado
  for select to authenticated
  using (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or usuario_id = auth.uid())
  );

drop policy if exists "ubicaciones_insert" on public.ubicaciones_motorizado;
create policy "ubicaciones_insert" on public.ubicaciones_motorizado
  for insert to authenticated
  with check (
    empresa_id = public.mi_empresa()
    and usuario_id = auth.uid()
  );

drop policy if exists "ubicaciones_update" on public.ubicaciones_motorizado;
create policy "ubicaciones_update" on public.ubicaciones_motorizado
  for update to authenticated
  using (usuario_id = auth.uid())
  with check (empresa_id = public.mi_empresa() and usuario_id = auth.uid());

drop policy if exists "ubicaciones_delete" on public.ubicaciones_motorizado;
create policy "ubicaciones_delete" on public.ubicaciones_motorizado
  for delete to authenticated
  using (usuario_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 2) Gastos: idempotencia offline y permisos del motorizado
-- ---------------------------------------------------------------------------
alter table public.gastos
  add column if not exists uuid_offline text unique;

drop policy if exists "gastos_select" on public.gastos;
create policy "gastos_select" on public.gastos
  for select to authenticated
  using (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or usuario_id = auth.uid())
  );

drop policy if exists "gastos_moto_insert" on public.gastos;
create policy "gastos_moto_insert" on public.gastos
  for insert to authenticated
  with check (
    empresa_id = public.mi_empresa()
    and usuario_id = auth.uid()
  );

-- ---------------------------------------------------------------------------
-- 3) Cuaderno del motorizado (mismas reglas del paso 11)
-- ---------------------------------------------------------------------------
drop policy if exists "clientes_moto_insert" on public.clientes;
create policy "clientes_moto_insert" on public.clientes
  for insert to authenticated
  with check (
    empresa_id = public.mi_empresa()
    and auth.uid() is not null
  );

drop policy if exists "pedidos_moto_insert" on public.pedidos;
create policy "pedidos_moto_insert" on public.pedidos
  for insert to authenticated
  with check (
    empresa_id = public.mi_empresa()
    and origen = 'MOTORIZADO'
    and estado = 'NUEVO'
    and creado_por = auth.uid()
  );

drop policy if exists "detalle_moto_insert" on public.detalle_pedido;
create policy "detalle_moto_insert" on public.detalle_pedido
  for insert to authenticated
  with check (
    empresa_id = public.mi_empresa()
    and exists (
      select 1
        from public.pedidos p
       where p.id = detalle_pedido.pedido_id
         and p.empresa_id = detalle_pedido.empresa_id
         and p.origen = 'MOTORIZADO'
         and p.creado_por = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 4) Columnas aditivas que la app ya usa (sin borrar ni renombrar nada)
-- ---------------------------------------------------------------------------
-- Foto del comprobante de Yape.
alter table public.pagos
  add column if not exists comprobante_url text;

-- Subida/lectura de comprobantes (bucket público `comprobantes`).
drop policy if exists "comprobantes_insert_auth" on storage.objects;
create policy "comprobantes_insert_auth" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'comprobantes');

drop policy if exists "comprobantes_select_public" on storage.objects;
create policy "comprobantes_select_public" on storage.objects
  for select to public
  using (bucket_id = 'comprobantes');

-- Catálogo: tipo de producto (vendible / retornable).
alter table public.productos
  add column if not exists tipo text not null default 'PRODUCTO';
alter table public.productos
  drop constraint if exists productos_tipo_check;
alter table public.productos
  add constraint productos_tipo_check
  check (tipo in ('PRODUCTO', 'RETORNABLE'));

-- Días de trabajo: 1=Lunes … 7=Domingo. NULL = todos (compatibilidad).
alter table public.perfiles
  add column if not exists dias_trabajo int[];

-- ---------------------------------------------------------------------------
-- 5) Realtime: publicar las tablas que mueven la interfaz
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array[
      'pedidos', 'pagos', 'gastos', 'entregas',
      'incidencias', 'ubicaciones_motorizado'
    ]
    loop
      if not exists (
        select 1
          from pg_publication_tables
         where pubname = 'supabase_realtime'
           and schemaname = 'public'
           and tablename = t
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I', t
        );
      end if;
    end loop;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 6) Reconciliación: pedido con entrega real = ENTREGADO
--    No toca cancelados. Solo corrige estados que quedaron viejos.
-- ---------------------------------------------------------------------------
update public.pedidos p
   set estado = 'ENTREGADO'
 where p.estado in ('NUEVO', 'ASIGNADO', 'EN_CAMINO', 'NO_ENTREGADO')
   and exists (
     select 1 from public.entregas e where e.pedido_id = p.id
   );
