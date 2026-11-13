-- ============================================================
-- MIGRACIÓN v2: multi-tenant completo
-- - Roles: ADMINISTRADOR→ADMIN, REPARTIDOR→MOTORIZADO
-- - vehiculos.repartidor_id (motorizado asignado al vehículo)
-- - updated_at en empresas y perfiles
-- - trigger genérico de updated_at
-- Ejecutar en Supabase SQL Editor. NO destructivo.
-- ============================================================

-- ---------- 1. Roles nuevos ----------
alter table public.perfiles drop constraint if exists perfiles_rol_check;

update public.perfiles set rol = 'ADMIN'       where rol = 'ADMINISTRADOR';
update public.perfiles set rol = 'MOTORIZADO'  where rol = 'REPARTIDOR';

alter table public.perfiles
  add constraint perfiles_rol_check check (rol in ('ADMIN', 'MOTORIZADO'));

-- ---------- 2. Vehículo asignado a motorizado ----------
alter table public.vehiculos
  add column if not exists repartidor_id uuid references auth.users(id);

create index if not exists idx_vehiculos_repartidor on public.vehiculos(repartidor_id);

-- ---------- 3. updated_at ----------
alter table public.empresas add column if not exists updated_at timestamptz not null default now();
alter table public.perfiles add column if not exists updated_at timestamptz not null default now();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_empresas_updated_at on public.empresas;
create trigger trg_empresas_updated_at
  before update on public.empresas
  for each row execute function public.set_updated_at();

drop trigger if exists trg_perfiles_updated_at on public.perfiles;
create trigger trg_perfiles_updated_at
  before update on public.perfiles
  for each row execute function public.set_updated_at();

-- ---------- 4. Email del motorizado demo → convención teléfono ----------
-- Permite entrar a la app escribiendo 999888777 (→ 999888777@grupojck.app)
update auth.users
set email = '999888777@grupojck.app'
where email = 'repartidor@grupojck.app';

update auth.identities
set identity_data = jsonb_set(identity_data, '{email}', '"999888777@grupojck.app"')
where provider = 'email'
  and identity_data->>'email' = 'repartidor@grupojck.app';
