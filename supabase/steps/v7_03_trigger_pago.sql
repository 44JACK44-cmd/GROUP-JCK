-- STEP 3 — Cada cobro genera el ingreso en la caja abierta
-- Reejecutable. No destructivo.

create or replace function public.trg_pago_ingreso_caja()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_caja uuid;
begin
  select id into v_caja
    from public.cajas
   where empresa_id = new.empresa_id
     and estado = 'ABIERTA'
   order by fecha_apertura desc
   limit 1;

  if v_caja is not null then
    insert into public.movimiento_caja
      (empresa_id, caja_id, tipo, origen, referencia_id, monto, descripcion, usuario_id)
    values
      (new.empresa_id, v_caja, 'INGRESO', 'PAGO', new.id, new.monto,
       'Cobro de pedido', new.registrado_por);
  end if;
  return new;
end
$fn$;

drop trigger if exists trg_pago_ingreso_caja on public.pagos;
create trigger trg_pago_ingreso_caja
  after insert on public.pagos
  for each row execute function public.trg_pago_ingreso_caja();
