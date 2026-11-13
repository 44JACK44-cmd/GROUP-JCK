-- ============================================================
-- MIGRACIÓN v4 — Cuaderno digital del motorizado (Grupo JCK)
--
-- Qué resuelve:
--  1. Campo `origen` en `pedidos` para distinguir pedidos creados por
--     el ADMIN (recepción) de los registrados por el MOTORIZADO
--     ("cuaderno digital", cuando el receptor se olvidó de anotar).
--  2. Tabla `incidencias` para que el motorizado registre fallas,
--     reparaciones, mantenimiento, etc. durante la jornada.
--  3. Índices para consultas eficientes del cuaderno digital.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor → New query
-- Es REEJECUTABLE: no rompe nada si se ejecuta dos veces.
-- NO destructivo: no borra datos.
-- ============================================================

-- ---------- 1. Campo origen en pedidos ----------
alter table public.pedidos
  add column if not exists origen text not null default 'ADMIN'
  check (origen in ('ADMIN', 'MOTORIZADO'));

-- ---------- 2. Tabla incidencias ----------
create table if not exists public.incidencias (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas(id),
  usuario_id  uuid not null references auth.users(id),
  tipo        text not null
              check (tipo in ('FALLA', 'REPARACION', 'MANTENIMIENTO',
                              'ESTACIONAMIENTO', 'PEAJE', 'OTRO')),
  descripcion text not null,
  monto       numeric(10,2) not null default 0 check (monto >= 0),
  fecha       timestamptz not null default now(),
  uuid_offline text unique
);

alter table public.incidencias enable row level security;

-- Políticas RLS: motorizado puede insertar/ver los suyos, admin ve todos de su empresa.
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

-- ---------- 3. Índices ----------
create index if not exists idx_pedidos_origen
  on public.pedidos (empresa_id, origen, fecha desc);

create index if not exists idx_incidencias_empresa_usuario_fecha
  on public.incidencias (empresa_id, usuario_id, fecha desc);

-- ---------- 4. Verificación ----------
select 'migracion v4 aplicada' as resultado,
       (select count(*) from information_schema.columns
        where table_name = 'pedidos' and column_name = 'origen') as campo_origen,
       (select count(*) from information_schema.tables
        where table_name = 'incidencias') as tabla_incidencias;