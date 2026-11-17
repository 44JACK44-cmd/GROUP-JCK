-- ============================================================
-- PASO 15 — Flujo simple, completo y sincronizado
--
-- Esta migración se ejecuta SOLA y también después de las anteriores.
-- Es reejecutable y no destructiva: no borra datos ni columnas.
--
-- Qué corrige:
--   1. "No autorizado" del motorizado al registrar pedidos y gastos:
--      repone TODAS las políticas RLS del motorizado (clientes, pedidos,
--      detalle, gastos, incidencias, entregas, pagos, movimientos y
--      rendiciones) aunque los pasos 10–14 no se hayan aplicado.
--   2. Repone columnas aditivas que la app ya usa (origen del pedido,
--      comprobante de Yape, tipo de producto, días de trabajo).
--   3. Crea `fondo_vuelto`: el dinero que el administrador entrega al
--      motorizado al inicio de la jornada. No es venta ni ingreso.
--   4. Publica en Realtime todas las tablas que mueven la interfaz.
--   5. Reconcilia pedidos con entrega real que quedaron con estado viejo.
--
-- Ejecutar en Supabase Dashboard → SQL Editor → New query → Run.
-- ============================================================

-- ---------------------------------------------------------------------------
-- 0) Funciones de ayuda (por si el esquema base no las tiene)
-- ---------------------------------------------------------------------------
create or replace function public.mi_empresa()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select empresa_id from public.perfiles where id = auth.uid()
$$;

create or replace function public.mi_rol()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select rol from public.perfiles where id = auth.uid()
$$;

create or replace function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.mi_rol() = 'ADMIN', false)
$$;

-- ---------------------------------------------------------------------------
-- 0.5) Tablas de pasos anteriores, por si no se aplicaron
--      (sin esto un `alter table` fallaría y detendría el paso 15)
-- ---------------------------------------------------------------------------
create table if not exists public.incidencias (
  id           uuid primary key default gen_random_uuid(),
  empresa_id   uuid not null references public.empresas(id) on delete cascade,
  usuario_id   uuid not null references auth.users(id) on delete cascade,
  tipo         text not null
               check (tipo in ('FALLA', 'REPARACION', 'MANTENIMIENTO',
                               'ESTACIONAMIENTO', 'PEAJE', 'OTRO')),
  descripcion  text not null,
  monto        numeric(10,2) not null default 0 check (monto >= 0),
  fecha        timestamptz not null default now(),
  uuid_offline text unique
);
alter table public.incidencias enable row level security;

create table if not exists public.rendiciones (
  id                  uuid primary key default gen_random_uuid(),
  empresa_id          uuid not null references public.empresas(id) on delete cascade,
  motorizado_id       uuid not null references auth.users(id) on delete cascade,
  fecha               date not null default current_date,
  efectivo_declarado  numeric(10,2) not null default 0,
  yape_declarado      numeric(10,2) not null default 0,
  observaciones       text,
  hora_entrega        timestamptz not null default now(),
  recibido_por        uuid references auth.users(id),
  estado              text not null default 'PENDIENTE'
                      check (estado in ('PENDIENTE', 'EN_REVISION', 'CON_DIFERENCIA',
                                        'OBSERVADA', 'APROBADA')),
  diferencia          numeric(10,2) not null default 0,
  justificacion       text,
  aprobado_por        uuid references auth.users(id),
  fecha_aprobacion    timestamptz,
  uuid_offline        text unique
);
alter table public.rendiciones enable row level security;

create table if not exists public.cierre_diario (
  id                     uuid primary key default gen_random_uuid(),
  empresa_id             uuid not null references public.empresas(id) on delete cascade,
  fecha                  date not null default current_date,
  total_ventas           numeric(10,2) not null default 0,
  efectivo_esperado      numeric(10,2) not null default 0,
  efectivo_recibido      numeric(10,2) not null default 0,
  yape_total             numeric(10,2) not null default 0,
  deudas_total           numeric(10,2) not null default 0,
  gastos_total           numeric(10,2) not null default 0,
  rendiciones_pendientes int not null default 0,
  diferencias            numeric(10,2) not null default 0,
  pedidos_pendientes     int not null default 0,
  cerrado_por            uuid references auth.users(id),
  fecha_cierre           timestamptz,
  justificacion          text,
  estado                 text not null default 'ABIERTO'
                         check (estado in ('ABIERTO', 'CERRADO'))
);
alter table public.cierre_diario enable row level security;

-- ---------------------------------------------------------------------------
-- 1) Columnas aditivas (la app las usa; sin ellas el flujo falla)
-- ---------------------------------------------------------------------------
-- Origen del pedido: ADMIN (recepción) o MOTORIZADO (cuaderno del motorizado).
alter table public.pedidos
  add column if not exists origen text not null default 'ADMIN';
alter table public.pedidos drop constraint if exists pedidos_origen_check;
alter table public.pedidos
  add constraint pedidos_origen_check
  check (origen in ('ADMIN', 'MOTORIZADO'));

-- Estado NO_ENTREGADO (pedido que no se pudo entregar).
alter table public.pedidos drop constraint if exists pedidos_estado_check;
alter table public.pedidos
  add constraint pedidos_estado_check
  check (estado in ('NUEVO', 'ASIGNADO', 'EN_CAMINO', 'ENTREGADO',
                    'CANCELADO', 'NO_ENTREGADO'));

-- Idempotencia offline.
alter table public.pedidos
  add column if not exists uuid_offline text unique;
alter table public.pedidos
  add column if not exists creado_por uuid references auth.users(id);

-- Foto del comprobante de Yape asociada al cobro.
alter table public.pagos
  add column if not exists comprobante_url text;
alter table public.pagos
  add column if not exists uuid_offline text unique;

-- Idempotencia de entregas y movimientos.
alter table public.entregas
  add column if not exists uuid_offline text unique;
alter table public.movimiento_bal_on
  add column if not exists uuid_offline text unique;
alter table public.movimiento_fierro
  add column if not exists uuid_offline text unique;

-- Gastos: medio de pago e idempotencia.
alter table public.gastos
  add column if not exists medio_pago text not null default 'EFECTIVO';
alter table public.gastos
  add column if not exists uuid_offline text unique;
alter table public.gastos drop constraint if exists gastos_medio_pago_check;
alter table public.gastos
  add constraint gastos_medio_pago_check
  check (medio_pago in ('EFECTIVO', 'YAPE', 'OTRO'));

-- Catálogo: tipo de producto (vendible / retornable).
alter table public.productos
  add column if not exists tipo text not null default 'PRODUCTO';
alter table public.productos drop constraint if exists productos_tipo_check;
alter table public.productos
  add constraint productos_tipo_check
  check (tipo in ('PRODUCTO', 'RETORNABLE'));

-- Días de trabajo: 1=Lunes … 7=Domingo. NULL = todos.
alter table public.perfiles
  add column if not exists dias_trabajo int[];

-- Fondo inicial y efectivo esperado guardados al declarar la rendición.
alter table public.rendiciones
  add column if not exists fondo_inicial numeric(10,2) not null default 0;
alter table public.rendiciones
  add column if not exists efectivo_esperado numeric(10,2) not null default 0;

-- ---------------------------------------------------------------------------
-- 2) FONDO DE VUELTO
--    Dinero que el admin entrega al motorizado al iniciar la jornada.
--    No es venta, no es ingreso y no se suma a las ventas.
-- ---------------------------------------------------------------------------
create table if not exists public.fondo_vuelto (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas(id) on delete cascade,
  motorizado_id  uuid not null references auth.users(id) on delete cascade,
  monto          numeric(10,2) not null check (monto > 0),
  fecha          timestamptz not null default now(),
  entregado_por  uuid references auth.users(id),
  observaciones  text,
  uuid_offline   text unique
);

create index if not exists idx_fondo_vuelto_moto
  on public.fondo_vuelto (empresa_id, motorizado_id, fecha desc);

alter table public.fondo_vuelto enable row level security;

drop policy if exists "fondo_vuelto_select" on public.fondo_vuelto;
create policy "fondo_vuelto_select" on public.fondo_vuelto
  for select to authenticated
  using (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or motorizado_id = auth.uid())
  );

drop policy if exists "fondo_vuelto_insert" on public.fondo_vuelto;
create policy "fondo_vuelto_insert" on public.fondo_vuelto
  for insert to authenticated
  with check (
    empresa_id = public.mi_empresa()
    and public.es_admin()
    and entregado_por = auth.uid()
  );

drop policy if exists "fondo_vuelto_update" on public.fondo_vuelto;
create policy "fondo_vuelto_update" on public.fondo_vuelto
  for update to authenticated
  using (empresa_id = public.mi_empresa() and public.es_admin())
  with check (empresa_id = public.mi_empresa() and public.es_admin());

drop policy if exists "fondo_vuelto_delete" on public.fondo_vuelto;
create policy "fondo_vuelto_delete" on public.fondo_vuelto
  for delete to authenticated
  using (empresa_id = public.mi_empresa() and public.es_admin());

-- ---------------------------------------------------------------------------
-- 3) UBICACIÓN DEL MOTORIZADO (seguimiento GPS honesto)
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
-- 4) RLS: CLIENTES
--    El motorizado puede crear un cliente y actualizar su ubicación, pero
--    siempre dentro de su propia empresa.
-- ---------------------------------------------------------------------------
drop policy if exists "clientes_select" on public.clientes;
create policy "clientes_select" on public.clientes
  for select to authenticated
  using (empresa_id = public.mi_empresa());

drop policy if exists "clientes_moto_insert" on public.clientes;
create policy "clientes_moto_insert" on public.clientes
  for insert to authenticated
  with check (empresa_id = public.mi_empresa() and auth.uid() is not null);

drop policy if exists "clientes_admin_upd" on public.clientes;
create policy "clientes_admin_upd" on public.clientes
  for update to authenticated
  using (empresa_id = public.mi_empresa())
  with check (empresa_id = public.mi_empresa());

drop policy if exists "clientes_admin_del" on public.clientes;
create policy "clientes_admin_del" on public.clientes
  for delete to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa());

-- ---------------------------------------------------------------------------
-- 5) RLS: PEDIDOS Y DETALLE
-- ---------------------------------------------------------------------------
drop policy if exists "pedidos_select" on public.pedidos;
create policy "pedidos_select" on public.pedidos
  for select to authenticated
  using (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or repartidor_id = auth.uid() or repartidor_id is null)
  );

drop policy if exists "pedidos_insert" on public.pedidos;
create policy "pedidos_insert" on public.pedidos
  for insert to authenticated
  with check (public.es_admin() and empresa_id = public.mi_empresa());

drop policy if exists "pedidos_moto_insert" on public.pedidos;
create policy "pedidos_moto_insert" on public.pedidos
  for insert to authenticated
  with check (
    empresa_id = public.mi_empresa()
    and origen = 'MOTORIZADO'
    and estado = 'NUEVO'
    and creado_por = auth.uid()
  );

drop policy if exists "pedidos_update" on public.pedidos;
create policy "pedidos_update" on public.pedidos
  for update to authenticated
  using (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or repartidor_id = auth.uid())
  )
  with check (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or repartidor_id = auth.uid())
  );

drop policy if exists "detalle_select" on public.detalle_pedido;
create policy "detalle_select" on public.detalle_pedido
  for select to authenticated
  using (empresa_id = public.mi_empresa());

drop policy if exists "detalle_admin" on public.detalle_pedido;
create policy "detalle_admin" on public.detalle_pedido
  for all to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

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
-- 6) RLS: ENTREGAS, PAGOS, BALONES Y FIERROS
--    Cada usuario registra sus propios movimientos; el admin ve todo.
-- ---------------------------------------------------------------------------
drop policy if exists "entregas_select" on public.entregas;
create policy "entregas_select" on public.entregas
  for select to authenticated
  using (empresa_id = public.mi_empresa());

drop policy if exists "entregas_insert" on public.entregas;
create policy "entregas_insert" on public.entregas
  for insert to authenticated
  with check (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or registrado_por = auth.uid())
  );

drop policy if exists "entregas_admin" on public.entregas;
create policy "entregas_admin" on public.entregas
  for update to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

drop policy if exists "pagos_select" on public.pagos;
create policy "pagos_select" on public.pagos
  for select to authenticated
  using (empresa_id = public.mi_empresa());

drop policy if exists "pagos_insert" on public.pagos;
create policy "pagos_insert" on public.pagos
  for insert to authenticated
  with check (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or registrado_por = auth.uid())
  );

drop policy if exists "pagos_admin" on public.pagos;
create policy "pagos_admin" on public.pagos
  for update to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

drop policy if exists "mbal_select" on public.movimiento_bal_on;
create policy "mbal_select" on public.movimiento_bal_on
  for select to authenticated
  using (empresa_id = public.mi_empresa());

drop policy if exists "mbal_insert" on public.movimiento_bal_on;
create policy "mbal_insert" on public.movimiento_bal_on
  for insert to authenticated
  with check (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or usuario_id = auth.uid())
  );

drop policy if exists "mbal_admin" on public.movimiento_bal_on;
create policy "mbal_admin" on public.movimiento_bal_on
  for update to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

drop policy if exists "mfierro_select" on public.movimiento_fierro;
create policy "mfierro_select" on public.movimiento_fierro
  for select to authenticated
  using (empresa_id = public.mi_empresa());

drop policy if exists "mfierro_insert" on public.movimiento_fierro;
create policy "mfierro_insert" on public.movimiento_fierro
  for insert to authenticated
  with check (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or usuario_id = auth.uid())
  );

drop policy if exists "mfierro_admin" on public.movimiento_fierro;
create policy "mfierro_admin" on public.movimiento_fierro
  for update to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

-- ---------------------------------------------------------------------------
-- 7) RLS: GASTOS (lo que el motorizado gasta en su jornada)
-- ---------------------------------------------------------------------------
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
    and (public.es_admin() or usuario_id = auth.uid())
  );

drop policy if exists "gastos_moto_update" on public.gastos;
create policy "gastos_moto_update" on public.gastos
  for update to authenticated
  using (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or usuario_id = auth.uid())
  )
  with check (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or usuario_id = auth.uid())
  );

drop policy if exists "gastos_moto_delete" on public.gastos;
create policy "gastos_moto_delete" on public.gastos
  for delete to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa());

-- ---------------------------------------------------------------------------
-- 8) RLS: INCIDENCIAS (fallas, mantenimiento, peajes…)
-- ---------------------------------------------------------------------------
drop policy if exists "incidencias_select" on public.incidencias;
create policy "incidencias_select" on public.incidencias
  for select to authenticated
  using (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or usuario_id = auth.uid())
  );

drop policy if exists "incidencias_insert" on public.incidencias;
create policy "incidencias_insert" on public.incidencias
  for insert to authenticated
  with check (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or usuario_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- 9) RLS: RENDICIONES DEL MOTORIZADO
-- ---------------------------------------------------------------------------
drop policy if exists "rendiciones_select" on public.rendiciones;
create policy "rendiciones_select" on public.rendiciones
  for select to authenticated
  using (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or motorizado_id = auth.uid())
  );

drop policy if exists "rendiciones_insert" on public.rendiciones;
create policy "rendiciones_insert" on public.rendiciones
  for insert to authenticated
  with check (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or motorizado_id = auth.uid())
  );

drop policy if exists "rendiciones_update" on public.rendiciones;
create policy "rendiciones_update" on public.rendiciones
  for update to authenticated
  using (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or motorizado_id = auth.uid())
  )
  with check (
    empresa_id = public.mi_empresa()
    and (public.es_admin() or motorizado_id = auth.uid())
  );

-- Cierre diario: solo el administrador puede verlo y cerrarlo.
drop policy if exists "cierre_select" on public.cierre_diario;
create policy "cierre_select" on public.cierre_diario
  for select to authenticated
  using (empresa_id = public.mi_empresa() and public.es_admin());

drop policy if exists "cierre_insert" on public.cierre_diario;
create policy "cierre_insert" on public.cierre_diario
  for insert to authenticated
  with check (empresa_id = public.mi_empresa() and public.es_admin());

drop policy if exists "cierre_update" on public.cierre_diario;
create policy "cierre_update" on public.cierre_diario
  for update to authenticated
  using (empresa_id = public.mi_empresa() and public.es_admin())
  with check (empresa_id = public.mi_empresa() and public.es_admin());

-- ---------------------------------------------------------------------------
-- 10) COMPROBANTES DE YAPE (Storage)
-- ---------------------------------------------------------------------------
drop policy if exists "comprobantes_insert_auth" on storage.objects;
create policy "comprobantes_insert_auth" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'comprobantes');

drop policy if exists "comprobantes_select_public" on storage.objects;
create policy "comprobantes_select_public" on storage.objects
  for select to public
  using (bucket_id = 'comprobantes');

-- ---------------------------------------------------------------------------
-- 11) REALTIME: publicar las tablas que mueven la interfaz
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array[
      'pedidos', 'pagos', 'gastos', 'entregas', 'incidencias',
      'ubicaciones_motorizado', 'rendiciones', 'fondo_vuelto'
    ]
    loop
      -- Solo publicar tablas que realmente existen. Si el editor ejecutó
      -- este bloque antes que el CREATE TABLE, se omite en vez de abortar.
      if to_regclass(format('public.%I', t)) is not null
         and not exists (
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
-- 12) RECONCILIACIÓN: entrega real = pedido ENTREGADO
--     No toca cancelados. Corrige estados que quedaron viejos.
-- ---------------------------------------------------------------------------
update public.pedidos p
   set estado = 'ENTREGADO'
 where p.estado in ('NUEVO', 'ASIGNADO', 'EN_CAMINO', 'NO_ENTREGADO')
   and exists (
     select 1 from public.entregas e where e.pedido_id = p.id
   );

-- ---------------------------------------------------------------------------
-- 13) VERIFICACIÓN RÁPIDA (debe devolver todo en `true`)
-- ---------------------------------------------------------------------------
select
  exists (select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'pedidos'
             and column_name = 'origen')                          as pedidos_origen,
  exists (select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'pagos'
             and column_name = 'comprobante_url')                 as pagos_comprobante,
  exists (select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'gastos'
             and column_name = 'medio_pago')                      as gastos_medio_pago,
  exists (select 1 from information_schema.tables
           where table_schema = 'public' and table_name = 'fondo_vuelto') as fondo_vuelto,
  exists (select 1 from pg_policies
           where schemaname = 'public' and tablename = 'gastos'
             and policyname = 'gastos_moto_insert')               as policy_gastos,
  exists (select 1 from pg_policies
           where schemaname = 'public' and tablename = 'pedidos'
             and policyname = 'pedidos_moto_insert')              as policy_pedidos;
