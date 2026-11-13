-- ============================================================
-- MIGRACIÓN: agregar multi-inquilino (empresa_id) a la base existente
-- Ejecutar en Supabase SQL Editor, DESPUÉS ejecutar schema.sql completo
-- ============================================================

-- 1. Tabla de empresas
create table if not exists public.empresas (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null unique,
  slug       text unique,
  activo     boolean not null default true,
  creado_en  timestamptz not null default now()
);

insert into public.empresas (nombre, slug) values ('Grupo JCK', 'group-jck')
on conflict (nombre) do nothing;

-- 2. perfiles.empresa_id
alter table public.perfiles
  add column if not exists empresa_id uuid references public.empresas(id);

update public.perfiles p
set empresa_id = (select id from public.empresas where slug = 'group-jck')
where p.empresa_id is null;

alter table public.perfiles alter column empresa_id set not null;

-- 3. empresa_id en todas las tablas de negocio
alter table public.clientes            add column if not exists empresa_id uuid references public.empresas(id);
alter table public.direcciones_cliente add column if not exists empresa_id uuid references public.empresas(id);
alter table public.productos           add column if not exists empresa_id uuid references public.empresas(id);
alter table public.precios_cliente     add column if not exists empresa_id uuid references public.empresas(id);
alter table public.pedidos             add column if not exists empresa_id uuid references public.empresas(id);
alter table public.detalle_pedido      add column if not exists empresa_id uuid references public.empresas(id);
alter table public.entregas            add column if not exists empresa_id uuid references public.empresas(id);
alter table public.pagos               add column if not exists empresa_id uuid references public.empresas(id);
alter table public.movimiento_bal_on   add column if not exists empresa_id uuid references public.empresas(id);
alter table public.movimiento_fierro   add column if not exists empresa_id uuid references public.empresas(id);
alter table public.vehiculos           add column if not exists empresa_id uuid references public.empresas(id);
alter table public.cajas               add column if not exists empresa_id uuid references public.empresas(id);
alter table public.movimiento_caja     add column if not exists empresa_id uuid references public.empresas(id);
alter table public.gastos              add column if not exists empresa_id uuid references public.empresas(id);
alter table public.combustible         add column if not exists empresa_id uuid references public.empresas(id);
alter table public.auditoria           add column if not exists empresa_id uuid references public.empresas(id);

-- 4. Todos los datos existentes pertenecen a Grupo JCK
do $$
declare t text;
begin
  foreach t in array array[
    'clientes','direcciones_cliente','productos','precios_cliente','pedidos',
    'detalle_pedido','entregas','pagos','movimiento_bal_on','movimiento_fierro',
    'vehiculos','cajas','movimiento_caja','gastos','combustible','auditoria'
  ] loop
    execute format(
      'update public.%I set empresa_id = (select id from public.empresas where slug = ''group-jck'') where empresa_id is null',
      t);
    execute format('alter table public.%I alter column empresa_id set not null', t);
  end loop;
end $$;

-- 5. Datos iniciales que dependen de empresa_id
update public.productos p
set empresa_id = (select id from public.empresas where slug = 'group-jck')
where p.empresa_id is null;

update public.vehiculos v
set empresa_id = (select id from public.empresas where slug = 'group-jck')
where v.empresa_id is null;
