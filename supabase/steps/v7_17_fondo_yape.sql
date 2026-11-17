-- ============================================================
-- PASO 17 — Fondo de vuelto en EFECTIVO o por YAPE
--
-- Problema real: el admin entrega S/ 50 de "vuelto" en un solo billete de 50.
-- Ese billete NO sirve para dar cambio, así que el vuelto se envía por Yape.
-- Si se contara como efectivo, la rendición quedaría mal.
--
-- Regla nueva:
--   fondo EFECTIVO  -> suma al efectivo esperado
--   fondo YAPE      -> NO suma al efectivo esperado (se muestra aparte)
--
-- Aditivo, reejecutable y no destructivo.
-- ============================================================

alter table public.fondo_vuelto
  add column if not exists medio_pago text not null default 'EFECTIVO';

alter table public.fondo_vuelto drop constraint if exists fondo_vuelto_medio_pago_check;
alter table public.fondo_vuelto
  add constraint fondo_vuelto_medio_pago_check
  check (medio_pago in ('EFECTIVO', 'YAPE'));

-- Verificación rápida
select
  exists (select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'fondo_vuelto'
             and column_name = 'medio_pago') as fondo_medio_pago;
