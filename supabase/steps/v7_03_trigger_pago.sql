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

-- Misma operación, invocable desde la app. Idempotente: si el trigger ya
-- registró el ingreso, devuelve true sin duplicar.
create or replace function public.registrar_ingreso_caja(p_pago_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_pago public.pagos%rowtype;
  v_caja uuid;
begin
  select * into v_pago from public.pagos where id = p_pago_id;
  if v_pago.id is null then
    return false;
  end if;

  if exists (select 1 from public.movimiento_caja
              where origen = 'PAGO' and referencia_id = p_pago_id) then
    return true;
  end if;

  select id into v_caja
    from public.cajas
   where empresa_id = v_pago.empresa_id
     and estado = 'ABIERTA'
   order by fecha_apertura desc
   limit 1;

  if v_caja is null then
    return false;
  end if;

  insert into public.movimiento_caja
    (empresa_id, caja_id, tipo, origen, referencia_id, monto, descripcion, usuario_id)
  values
    (v_pago.empresa_id, v_caja, 'INGRESO', 'PAGO', v_pago.id, v_pago.monto,
     'Cobro de pedido', v_pago.registrado_por);

  return true;
exception
  when unique_violation then
    return true;
end
$fn$;

grant execute on function public.registrar_ingreso_caja(uuid) to authenticated;
