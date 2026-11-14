-- ============================================================
-- MIGRACIÓN v8 — Endurecimiento detectado en auditoría ETAPA A
-- ============================================================

-- 8.1 Una sola rendición por motorizado por empresa y día.
create unique index if not exists idx_rendiciones_empresa_motorizado_fecha
  on public.rendiciones (empresa_id, motorizado_id, fecha);

-- 8.2 Solo una caja ABIERTA por empresa.
create unique index if not exists idx_cajas_unica_abierta
  on public.cajas (empresa_id)
  where estado = 'ABIERTA';

-- 8.3 Idempotencia de movimientos (origen + referencia).
create unique index if not exists idx_movimiento_caja_origen_ref
  on public.movimiento_caja (origen, referencia_id);

-- 8.4 Saneamiento de montos (no negativos).
alter table public.pedidos
  add constraint pedidos_total_no_negativo_check
  check (total >= 0);
