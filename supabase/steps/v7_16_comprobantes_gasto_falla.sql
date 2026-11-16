-- ============================================================
-- PASO 16 — Fotos de comprobantes de gastos y fallas
--
-- Aditivo, reejecutable y no destructivo. No cambia ningún dato existente.
-- Las fotos se suben al bucket `comprobantes` (ya creado en el paso 12/15).
-- Ejecutar en Supabase Dashboard → SQL Editor → Run.
-- ============================================================

alter table public.gastos
  add column if not exists comprobante_url text;

-- Por si el paso 15 no se aplicó y la tabla no existe todavía.
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

alter table public.incidencias
  add column if not exists comprobante_url text;

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

-- Verificación rápida
select
  exists (select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'gastos'
             and column_name = 'comprobante_url') as gasto_comprobante,
  exists (select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'incidencias'
             and column_name = 'comprobante_url') as incidencia_comprobante;
