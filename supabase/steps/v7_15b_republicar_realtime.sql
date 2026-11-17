-- REPARACIÓN RÁPIDA DEL PASO 15
-- Ejecutar si el paso 15 falló con:
--   42P01: relation "public.ubicaciones_motorizado" does not exist
-- Crea la tabla de GPS si falta y publica en Realtime las tablas que existan.
-- Reejecutable y no destructivo.

create table if not exists public.ubicaciones_motorizado (
  usuario_id     uuid primary key references auth.users(id) on delete cascade,
  empresa_id     uuid not null references public.empresas(id) on delete cascade,
  latitud        double precision not null,
  longitud       double precision not null,
  precision_m    double precision,
  actualizado_en timestamptz not null default now()
);

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
  with check (empresa_id = public.mi_empresa() and usuario_id = auth.uid());

drop policy if exists "ubicaciones_update" on public.ubicaciones_motorizado;
create policy "ubicaciones_update" on public.ubicaciones_motorizado
  for update to authenticated
  using (usuario_id = auth.uid())
  with check (empresa_id = public.mi_empresa() and usuario_id = auth.uid());

drop policy if exists "ubicaciones_delete" on public.ubicaciones_motorizado;
create policy "ubicaciones_delete" on public.ubicaciones_motorizado
  for delete to authenticated
  using (usuario_id = auth.uid());

-- Publicar solo lo que exista; nunca abortar por una tabla ausente.
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
      begin
        if to_regclass(format('public.%I', t)) is not null then
          execute format(
            'alter publication supabase_realtime add table public.%I', t
          );
        end if;
      exception when others then
        -- Ya estaba publicada o no se puede publicar: se omite.
        null;
      end;
    end loop;
  end if;
end $$;

select tablename,
       case when to_regclass('public.' || tablename) is not null
            then 'OK' else 'FALTA' end as existe
  from pg_publication_tables
 where pubname = 'supabase_realtime' and schemaname = 'public'
   and tablename in (
     'pedidos','pagos','gastos','entregas','incidencias',
     'ubicaciones_motorizado','rendiciones','fondo_vuelto'
   )
 order by tablename;
