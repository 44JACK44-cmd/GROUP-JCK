-- STEP 1 — Estados y formas de pago
-- Reejecutable. No destructivo.

alter table public.pedidos drop constraint if exists pedidos_forma_pago_check;
alter table public.pedidos
  add constraint pedidos_forma_pago_check
  check (forma_pago in ('EFECTIVO', 'YAPE', 'PLIN', 'TRANSFERENCIA', 'OTRO', 'DEUDA'));

alter table public.pedidos drop constraint if exists pedidos_estado_check;
alter table public.pedidos
  add constraint pedidos_estado_check
  check (estado in ('NUEVO', 'ASIGNADO', 'EN_CAMINO', 'ENTREGADO', 'CANCELADO', 'NO_ENTREGADO'));

alter table public.entregas drop constraint if exists entregas_estado_pago_check;
alter table public.entregas
  add constraint entregas_estado_pago_check
  check (estado_pago in ('PAGADO', 'PARCIAL', 'PENDIENTE'));
