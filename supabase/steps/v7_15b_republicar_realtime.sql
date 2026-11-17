-- REPARACIÓN COMPLETA DEL PASO 15
-- Ejecutar si el paso 15 falló con 42P01 (ubicaciones_motorizado / fondo_vuelto).
-- Crea TODAS las tablas y columnas que faltan, y publica en Realtime solo lo
-- que exista. Reejecutable y no destructivo.

-- Funciones base (por si no existen).
create or replace function public.mi_empresa()
returns uuid language sql stable security definer set search_path = public
as $$ select empresa_id from public.perfiles where id = auth.uid() $$;

create or replace function public.mi_rol()
returns text language sql stable security definer set search_path = public
as $$ select rol from public.perfiles where id = auth.uid() $$;

create or replace function public.es_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce(public.mi_rol() = 'ADMIN', false) $$;

-- Columnas aditivas que usa la app.
alter table public.pedidos add column if not exists origen text not null default 'ADMIN';
alter table public.pedidos add column if not exists uuid_offline text unique;
alter table public.pedidos add column if not exists creado_por uuid references auth.users(id);
alter table public.pagos add column if not exists comprobante_url text;
alter table public.pagos add column if not exists uuid_offline text unique;
alter table public.gastos add column if not exists medio_pago text not null default 'EFECTIVO';
alter table public.gastos add column if not exists uuid_offline text unique;
alter table public.productos add column if not exists tipo text not null default 'PRODUCTO';
alter table public.perfiles add column if not exists dias_trabajo int[];

-- Tablas del paso 15, creadas aunque no existan.
create table if not exists public.incidencias (
  id           uuid primary key default gen_random_uuid(),
  empresa_id   uuid not null references public.empresas(id) on delete cascade,
  usuario_id   uuid not null references auth.users(id) on delete cascade,
  tipo         text not null
               check (tipo in ('FALLA','REPARACION','MANTENIMIENTO',
                               'ESTACIONAMIENTO','PEAJE','OTRO')),
  descripcion  text not null,
  monto        numeric(10,2) not null default 0 check (monto >= 0),
  fecha        timestamptz not null default now(),
  uuid_offline text unique
);
alter table public.incidencias enable row level security;

create table if not exists public.rendiciones (
  id                 uuid primary key default gen_random_uuid(),
  empresa_id         uuid not null references public.empresas(id) on delete cascade,
  motorizado_id      uuid not null references auth.users(id) on delete cascade,
  fecha              date not null default current_date,
  efectivo_declarado numeric(10,2) not null default 0,
  yape_declarado     numeric(10,2) not null default 0,
  observaciones      text,
  hora_entrega       timestamptz not null default now(),
  recibido_por       uuid references auth.users(id),
  estado             text not null default 'PENDIENTE'
                     check (estado in ('PENDIENTE','EN_REVISION','CON_DIFERENCIA',
                                       'OBSERVADA','APROBADA')),
  diferencia         numeric(10,2) not null default 0,
  justificacion      text,
  aprobado_por       uuid references auth.users(id),
  fecha_aprobacion   timestamptz,
  uuid_offline       text unique
);
alter table public.rendiciones enable row level security;
alter table public.rendiciones add column if not exists fondo_inicial numeric(10,2) not null default 0;
alter table public.rendiciones add column if not exists efectivo_esperado numeric(10,2) not null default 0;

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
                         check (estado in ('ABIERTO','CERRADO'))
);
alter table public.cierre_diario enable row level security;

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
alter table public.fondo_vuelto enable row level security;

drop policy if exists "fondo_vuelto_select" on public.fondo_vuelto;
create policy "fondo_vuelto_select" on public.fondo_vuelto
  for select to authenticated
  using (empresa_id = public.mi_empresa()
         and (public.es_admin() or motorizado_id = auth.uid()));

drop policy if exists "fondo_vuelto_insert" on public.fondo_vuelto;
create policy "fondo_vuelto_insert" on public.fondo_vuelto
  for insert to authenticated
  with check (empresa_id = public.mi_empresa() and public.es_admin()
              and entregado_por = auth.uid());

drop policy if exists "fondo_vuelto_update" on public.fondo_vuelto;
create policy "fondo_vuelto_update" on public.fondo_vuelto
  for update to authenticated
  using (empresa_id = public.mi_empresa() and public.es_admin())
  with check (empresa_id = public.mi_empresa() and public.es_admin());

drop policy if exists "fondo_vuelto_delete" on public.fondo_vuelto;
create policy "fondo_vuelto_delete" on public.fondo_vuelto
  for delete to authenticated
  using (empresa_id = public.mi_empresa() and public.es_admin());

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
