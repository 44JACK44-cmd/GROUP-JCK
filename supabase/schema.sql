-- ============================================================
-- GROUP JCK Gas — Esquema Supabase MULTI-INQUILINO (PostgreSQL)
-- Una app, varias empresas. Cada fila pertenece a una empresa
-- y las reglas de seguridad (RLS) aíslan los datos.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor → New query
-- ============================================================

-- ---------- Empresas (los "locales" / negocios) ----------
create table if not exists public.empresas (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null unique,
  slug       text unique,
  activo     boolean not null default true,
  creado_en  timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- Perfiles (datos del usuario de la app) ----------
create table if not exists public.perfiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  empresa_id  uuid not null references public.empresas(id),
  nombre      text not null,
  telefono    text,
  rol         text not null check (rol in ('ADMIN', 'MOTORIZADO')),
  activo      boolean not null default true,
  creado_en   timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (empresa_id, telefono)
);

-- ---------- Clientes ----------
create table if not exists public.clientes (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas(id),
  nombre         text not null,
  telefono       text,
  tipo           text not null default 'PARTICULAR'
                 check (tipo in ('PARTICULAR', 'RESTAURANTE', 'NEGOCIO', 'OTRO')),
  direccion      text,
  referencia     text,
  latitud        double precision,
  longitud       double precision,
  observaciones  text,
  activo         boolean not null default true,
  uuid_offline   text unique,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create table if not exists public.direcciones_cliente (
  id           uuid primary key default gen_random_uuid(),
  empresa_id   uuid not null references public.empresas(id),
  cliente_id   uuid not null references public.clientes(id) on delete cascade,
  direccion    text not null,
  referencia   text,
  latitud      double precision,
  longitud     double precision,
  es_principal boolean not null default false,
  creado_en    timestamptz not null default now()
);

-- ---------- Productos y precios ----------
create table if not exists public.productos (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references public.empresas(id),
  nombre        text not null,
  capacidad_kg  numeric(6,2),
  precio_base   numeric(10,2) not null,
  descripcion   text,
  activo        boolean not null default true
);

create table if not exists public.precios_cliente (
  id           uuid primary key default gen_random_uuid(),
  empresa_id   uuid not null references public.empresas(id),
  cliente_id   uuid not null references public.clientes(id) on delete cascade,
  producto_id  uuid not null references public.productos(id) on delete cascade,
  precio       numeric(10,2) not null,
  unique (empresa_id, cliente_id, producto_id)
);

-- ---------- Pedidos ----------
create table if not exists public.pedidos (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references public.empresas(id),
  numero        bigint generated always as identity,
  cliente_id    uuid not null references public.clientes(id),
  repartidor_id uuid references auth.users(id),
  estado        text not null default 'NUEVO'
                check (estado in ('NUEVO', 'ASIGNADO', 'EN_CAMINO', 'ENTREGADO', 'CANCELADO')),
  forma_pago    text check (forma_pago in ('EFECTIVO', 'YAPE', 'PLIN', 'TRANSFERENCIA', 'OTRO')),
  observaciones text,
  total         numeric(10,2) not null default 0,
  creado_por    uuid references auth.users(id),
  fecha         timestamptz not null default now(),
  uuid_offline  text unique,
  version       int not null default 0
);

create table if not exists public.detalle_pedido (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  pedido_id       uuid not null references public.pedidos(id) on delete cascade,
  producto_id     uuid not null references public.productos(id),
  cantidad        int not null check (cantidad > 0),
  precio_unitario numeric(10,2) not null
);

create table if not exists public.entregas (
  id                    uuid primary key default gen_random_uuid(),
  empresa_id            uuid not null references public.empresas(id),
  pedido_id             uuid not null unique references public.pedidos(id),
  estado_bal_on_vacio   text not null
                        check (estado_bal_on_vacio in ('RECIBIDO', 'NO_RECIBIDO', 'NO_APLICA')),
  estado_pago           text not null check (estado_pago in ('PAGADO', 'PENDIENTE')),
  fecha                 timestamptz not null default now(),
  registrado_por        uuid references auth.users(id),
  uuid_offline          text unique
);

-- ---------- Pagos ----------
create table if not exists public.pagos (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  pedido_id       uuid references public.pedidos(id),
  cliente_id      uuid not null references public.clientes(id),
  monto           numeric(10,2) not null check (monto > 0),
  metodo          text not null
                  check (metodo in ('EFECTIVO', 'YAPE', 'PLIN', 'TRANSFERENCIA', 'OTRO')),
  fecha           timestamptz not null default now(),
  registrado_por  uuid references auth.users(id),
  uuid_offline    text unique
);

-- ---------- Balones y fierros (activos retornables) ----------
create table if not exists public.movimiento_bal_on (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas(id),
  cliente_id  uuid not null references public.clientes(id),
  tipo        text not null
              check (tipo in ('ENTREGA_LLENO', 'DEVOLUCION_VACIO')),
  pedido_id   uuid references public.pedidos(id),
  cantidad    int not null check (cantidad > 0),
  fecha       timestamptz not null default now(),
  usuario_id  uuid references auth.users(id),
  uuid_offline text unique
);

create table if not exists public.movimiento_fierro (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas(id),
  cliente_id  uuid not null references public.clientes(id),
  tipo        text not null
              check (tipo in ('ENTREGA', 'DEVOLUCION')),
  pedido_id   uuid references public.pedidos(id),
  cantidad    int not null check (cantidad > 0),
  fecha       timestamptz not null default now(),
  usuario_id  uuid references auth.users(id),
  uuid_offline text unique
);

-- ---------- Vehículos, caja, gastos, combustible ----------
create table if not exists public.vehiculos (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references public.empresas(id),
  nombre        text not null,
  placa         text,
  repartidor_id uuid references auth.users(id),
  activo        boolean not null default true
);

create table if not exists public.cajas (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references public.empresas(id),
  fecha_apertura  timestamptz not null default now(),
  fondo_inicial   numeric(10,2) not null default 0,
  estado          text not null default 'ABIERTA' check (estado in ('ABIERTA', 'CERRADA')),
  fecha_cierre    timestamptz,
  monto_declarado numeric(10,2)
);

create table if not exists public.movimiento_caja (
  id            uuid primary key default gen_random_uuid(),
  empresa_id    uuid not null references public.empresas(id),
  caja_id       uuid not null references public.cajas(id),
  tipo          text not null check (tipo in ('INGRESO', 'EGRESO')),
  origen        text not null,
  referencia_id uuid,
  monto         numeric(10,2) not null check (monto > 0),
  descripcion   text,
  fecha         timestamptz not null default now(),
  usuario_id    uuid references auth.users(id)
);

create table if not exists public.gastos (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas(id),
  descripcion        text not null,
  monto              numeric(10,2) not null check (monto > 0),
  categoria          text,
  fecha              timestamptz not null default now(),
  usuario_id         uuid references auth.users(id),
  movimiento_caja_id uuid references public.movimiento_caja(id)
);

create table if not exists public.combustible (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas(id),
  vehiculo_id        uuid references public.vehiculos(id),
  fecha              timestamptz not null default now(),
  monto              numeric(10,2) not null check (monto > 0),
  kilometraje        int,
  observacion        text,
  usuario_id         uuid references auth.users(id),
  movimiento_caja_id uuid references public.movimiento_caja(id)
);

create table if not exists public.auditoria (
  id         uuid primary key default gen_random_uuid(),
  empresa_id uuid references public.empresas(id),
  entidad    text not null,
  entidad_id text not null,
  accion     text not null,
  usuario_id uuid references auth.users(id),
  fecha      timestamptz not null default now(),
  detalle    jsonb
);

-- ============================================================
-- ÍNDICES
-- ============================================================
create index if not exists idx_clientes_empresa on public.clientes(empresa_id);
create index if not exists idx_clientes_nombre on public.clientes using gin (to_tsvector('spanish', nombre));
create index if not exists idx_pedidos_empresa_estado on public.pedidos(empresa_id, estado);
create index if not exists idx_pedidos_repartidor on public.pedidos(repartidor_id);
create index if not exists idx_pedidos_fecha on public.pedidos(fecha desc);
create index if not exists idx_pagos_cliente on public.pagos(cliente_id);
create index if not exists idx_movbal_cliente on public.movimiento_bal_on(cliente_id);
create index if not exists idx_productos_empresa on public.productos(empresa_id);
create index if not exists idx_perfiles_empresa on public.perfiles(empresa_id);

-- ============================================================
-- FUNCIONES DE AYUDA (security definer para evitar recursión RLS)
-- ============================================================
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

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
alter table public.empresas enable row level security;
alter table public.perfiles enable row level security;
alter table public.clientes enable row level security;
alter table public.direcciones_cliente enable row level security;
alter table public.productos enable row level security;
alter table public.precios_cliente enable row level security;
alter table public.pedidos enable row level security;
alter table public.detalle_pedido enable row level security;
alter table public.entregas enable row level security;
alter table public.pagos enable row level security;
alter table public.movimiento_bal_on enable row level security;
alter table public.movimiento_fierro enable row level security;
alter table public.vehiculos enable row level security;
alter table public.cajas enable row level security;
alter table public.movimiento_caja enable row level security;
alter table public.gastos enable row level security;
alter table public.combustible enable row level security;
alter table public.auditoria enable row level security;

-- Elimina políticas existentes para que el script sea reejecutable
do $$
declare p record;
begin
  for p in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- ---------- Empresas: cada usuario solo ve la suya ----------
create policy "empresas_select" on public.empresas
  for select to authenticated
  using (id = public.mi_empresa());
-- Alta/baja de empresas: solo service_role (dashboard), no desde la app.

-- ---------- Perfiles: admin gestiona su empresa; cada quien ve el suyo ----------
create policy "perfiles_select" on public.perfiles
  for select to authenticated
  using (id = auth.uid() or (public.es_admin() and empresa_id = public.mi_empresa()));
create policy "perfiles_insert" on public.perfiles
  for insert to authenticated
  with check (public.es_admin() and empresa_id = public.mi_empresa());
create policy "perfiles_update" on public.perfiles
  for update to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

-- ---------- Datos maestros: lectura todos los de la empresa, escritura solo admin ----------
create policy "clientes_select" on public.clientes for select to authenticated
  using (empresa_id = public.mi_empresa());
create policy "clientes_admin" on public.clientes for insert to authenticated
  with check (public.es_admin() and empresa_id = public.mi_empresa());
create policy "clientes_admin_upd" on public.clientes for update to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());
create policy "clientes_admin_del" on public.clientes for delete to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa());

create policy "dirs_select" on public.direcciones_cliente for select to authenticated
  using (empresa_id = public.mi_empresa());
create policy "dirs_admin" on public.direcciones_cliente for all to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

create policy "prod_select" on public.productos for select to authenticated
  using (empresa_id = public.mi_empresa());
create policy "prod_admin" on public.productos for all to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

create policy "precios_select" on public.precios_cliente for select to authenticated
  using (empresa_id = public.mi_empresa());
create policy "precios_admin" on public.precios_cliente for all to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

-- ---------- Pedidos ----------
create policy "pedidos_select" on public.pedidos for select to authenticated
  using (empresa_id = public.mi_empresa()
         and (public.es_admin() or repartidor_id = auth.uid() or repartidor_id is null));
create policy "pedidos_insert" on public.pedidos for insert to authenticated
  with check (public.es_admin() and empresa_id = public.mi_empresa());
create policy "pedidos_update" on public.pedidos for update to authenticated
  using (empresa_id = public.mi_empresa()
         and (public.es_admin() or repartidor_id = auth.uid()))
  with check (empresa_id = public.mi_empresa()
         and (public.es_admin() or repartidor_id = auth.uid()));

create policy "detalle_select" on public.detalle_pedido for select to authenticated
  using (empresa_id = public.mi_empresa());
create policy "detalle_admin" on public.detalle_pedido for all to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

-- ---------- Entregas / pagos / movimientos ----------
create policy "entregas_select" on public.entregas for select to authenticated
  using (empresa_id = public.mi_empresa());
create policy "entregas_insert" on public.entregas for insert to authenticated
  with check (empresa_id = public.mi_empresa()
              and (public.es_admin() or registrado_por = auth.uid()));
create policy "entregas_admin" on public.entregas for update to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

create policy "pagos_select" on public.pagos for select to authenticated
  using (empresa_id = public.mi_empresa());
create policy "pagos_insert" on public.pagos for insert to authenticated
  with check (empresa_id = public.mi_empresa()
              and (public.es_admin() or registrado_por = auth.uid()));
create policy "pagos_admin" on public.pagos for update to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

create policy "mbal_select" on public.movimiento_bal_on for select to authenticated
  using (empresa_id = public.mi_empresa());
create policy "mbal_insert" on public.movimiento_bal_on for insert to authenticated
  with check (empresa_id = public.mi_empresa()
              and (public.es_admin() or usuario_id = auth.uid()));
create policy "mbal_admin" on public.movimiento_bal_on for update to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

create policy "mfierro_select" on public.movimiento_fierro for select to authenticated
  using (empresa_id = public.mi_empresa());
create policy "mfierro_insert" on public.movimiento_fierro for insert to authenticated
  with check (empresa_id = public.mi_empresa()
              and (public.es_admin() or usuario_id = auth.uid()));
create policy "mfierro_admin" on public.movimiento_fierro for update to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

-- ---------- Vehículos / caja / gastos ----------
create policy "veh_select" on public.vehiculos for select to authenticated
  using (empresa_id = public.mi_empresa());
create policy "veh_admin" on public.vehiculos for all to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

create policy "caja_admin" on public.cajas for all to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());
create policy "movcaja_admin" on public.movimiento_caja for all to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());
create policy "gastos_admin" on public.gastos for all to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

-- Combustible: repartidor puede registrar el suyo
create policy "comb_select" on public.combustible for select to authenticated
  using (empresa_id = public.mi_empresa());
create policy "comb_insert" on public.combustible for insert to authenticated
  with check (empresa_id = public.mi_empresa()
              and (public.es_admin() or usuario_id = auth.uid()));
create policy "comb_admin" on public.combustible for update to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa())
  with check (public.es_admin() and empresa_id = public.mi_empresa());

-- Auditoría: todos pueden insertar, solo admin de la empresa lee
create policy "aud_insert" on public.auditoria for insert to authenticated
  with check (empresa_id is null or empresa_id = public.mi_empresa());
create policy "aud_admin" on public.auditoria for select to authenticated
  using (public.es_admin() and empresa_id = public.mi_empresa());

-- ============================================================
-- DATOS INICIALES
-- ============================================================
insert into public.empresas (nombre, slug) values ('Grupo JCK', 'group-jck')
on conflict (nombre) do nothing;

insert into public.productos (empresa_id, nombre, capacidad_kg, precio_base)
select e.id, p.nombre, p.capacidad_kg, p.precio_base
from public.empresas e
cross join (values
  ('Balón 10 kg', 10::numeric, 45.00::numeric),
  ('Balón 15 kg', 15::numeric, 60.00::numeric),
  ('Balón 45 kg', 45::numeric, 170.00::numeric)
) as p(nombre, capacidad_kg, precio_base)
where e.slug = 'group-jck'
on conflict do nothing;

insert into public.vehiculos (empresa_id, nombre, placa)
select e.id, 'Moto 01', null
from public.empresas e where e.slug = 'group-jck'
on conflict do nothing;

-- ============================================================
-- VERSIONES DE LA APP (actualización OTA)
-- ============================================================
create table if not exists public.app_versiones (
  id             int primary key default 1 check (id = 1),
  version_code   int not null,
  version_name   text not null,
  apk_url        text not null,
  notas          text,
  obligatoria    boolean not null default false,
  actualizado_en timestamptz not null default now()
);
alter table public.app_versiones enable row level security;
drop policy if exists "versiones_public_read" on public.app_versiones;
create policy "versiones_public_read" on public.app_versiones
  for select to anon, authenticated using (true);

-- ---------- Perfiles de los usuarios ----------
-- Crear los usuarios en Authentication → Users ANTES de ejecutar esto.
-- El teléfono de login se convierte en <telefono>@grupojck.app
insert into public.perfiles (id, empresa_id, nombre, telefono, rol)
select u.id, e.id, 'Administrador', 'admin', 'ADMIN'
from auth.users u
cross join public.empresas e
where u.email = 'admin@grupojck.app' and e.slug = 'group-jck'
on conflict (id) do nothing;

insert into public.perfiles (id, empresa_id, nombre, telefono, rol)
select u.id, e.id, 'Carlos Repartidor', '999888777', 'MOTORIZADO'
from auth.users u
cross join public.empresas e
where u.email = '999888777@grupojck.app' and e.slug = 'group-jck'
on conflict (id) do nothing;
