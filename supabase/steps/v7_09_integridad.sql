-- STEP 9 — Integridad y conciliación (endurecimiento)
-- Reejecutable. No destructivo.
-- Nota: si algún índice único falla por datos duplicados existentes,
-- avísame y lo depuramos sin borrar historial.

-- Una sola rendición por motorizado, empresa y día.
create unique index if not exists idx_rendiciones_empresa_motorizado_fecha
  on public.rendiciones (empresa_id, motorizado_id, fecha);

-- Un solo cierre diario por empresa y fecha.
create unique index if not exists idx_cierre_diario_empresa_fecha
  on public.cierre_diario (empresa_id, fecha);

-- Solo una caja ABIERTA por empresa.
create unique index if not exists idx_cajas_unica_abierta
  on public.cajas (empresa_id)
  where estado = 'ABIERTA';

-- Idempotencia de cobros: un movimiento de caja por pago.
create unique index if not exists idx_movimiento_caja_origen_ref
  on public.movimiento_caja (origen, referencia_id);

-- Montos no negativos.
alter table public.pedidos drop constraint if exists pedidos_total_no_negativo_check;
alter table public.pedidos
  add constraint pedidos_total_no_negativo_check
  check (total >= 0);
