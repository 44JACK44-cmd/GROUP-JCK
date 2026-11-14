-- STEP 6 — Rendición del motorizado y cierre diario
-- Reejecutable. No destructivo.

alter table public.gastos
  add column if not exists medio_pago text not null default 'EFECTIVO';

alter table public.gastos drop constraint if exists gastos_medio_pago_check;
alter table public.gastos
  add constraint gastos_medio_pago_check
  check (medio_pago in ('EFECTIVO', 'YAPE', 'OTRO'));

create table if not exists public.rendiciones (
  id                  uuid primary key default gen_random_uuid(),
  empresa_id          uuid not null references public.empresas(id),
  motorizado_id       uuid not null references auth.users(id),
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

drop policy if exists "rendiciones_select" on public.rendiciones;
create policy "rendiciones_select" on public.rendiciones
  for select to authenticated
  using (empresa_id = public.mi_empresa()
         and (public.es_admin() or motorizado_id = auth.uid()));

drop policy if exists "rendiciones_insert" on public.rendiciones;
create policy "rendiciones_insert" on public.rendiciones
  for insert to authenticated
  with check (empresa_id = public.mi_empresa()
              and (public.es_admin() or motorizado_id = auth.uid()));

drop policy if exists "rendiciones_update" on public.rendiciones;
create policy "rendiciones_update" on public.rendiciones
  for update to authenticated
  using (empresa_id = public.mi_empresa()
         and (public.es_admin() or motorizado_id = auth.uid()))
  with check (empresa_id = public.mi_empresa()
              and (public.es_admin() or motorizado_id = auth.uid()));

create table if not exists public.cierre_diario (
  id                     uuid primary key default gen_random_uuid(),
  empresa_id             uuid not null references public.empresas(id),
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
