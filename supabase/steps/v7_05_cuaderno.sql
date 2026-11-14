-- STEP 5 — Cuaderno digital: origen del pedido e incidencias
-- Reejecutable. No destructivo.

alter table public.pedidos
  add column if not exists origen text not null default 'ADMIN';

alter table public.pedidos drop constraint if exists pedidos_origen_check;
alter table public.pedidos
  add constraint pedidos_origen_check
  check (origen in ('ADMIN', 'MOTORIZADO'));

create table if not exists public.incidencias (
  id           uuid primary key default gen_random_uuid(),
  empresa_id   uuid not null references public.empresas(id),
  usuario_id   uuid not null references auth.users(id),
  tipo         text not null
               check (tipo in ('FALLA', 'REPARACION', 'MANTENIMIENTO',
                               'ESTACIONAMIENTO', 'PEAJE', 'OTRO')),
  descripcion  text not null,
  monto        numeric(10,2) not null default 0 check (monto >= 0),
  fecha        timestamptz not null default now(),
  uuid_offline text unique
);

alter table public.incidencias enable row level security;

drop policy if exists "incidencias_select" on public.incidencias;
create policy "incidencias_select" on public.incidencias
  for select to authenticated
  using (empresa_id = public.mi_empresa()
         and (public.es_admin() or usuario_id = auth.uid()));

drop policy if exists "incidencias_insert" on public.incidencias;
create policy "incidencias_insert" on public.incidencias
  for insert to authenticated
  with check (empresa_id = public.mi_empresa()
              and (public.es_admin() or usuario_id = auth.uid()));
