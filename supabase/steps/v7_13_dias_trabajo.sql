-- PASO 13 — Días de trabajo del motorizado (programación semanal)
-- Reejecutable y no destructivo.

-- 1) Columna con los días de la semana en que trabaja el motorizado.
--    Valores: 1=Lunes ... 7=Domingo. NULL = trabaja todos los días (compatibilidad).
alter table public.perfiles
  add column if not exists dias_trabajo int[];

-- 2) Check razonable (no obligatorio, solo documenta los valores válidos).
alter table public.perfiles
  drop constraint if exists perfiles_dias_trabajo_check;
alter table public.perfiles
  add constraint perfiles_dias_trabajo_check
  check (dias_trabajo is null
         or dias_trabajo <@ array[1,2,3,4,5,6,7]::int[])
  not valid;