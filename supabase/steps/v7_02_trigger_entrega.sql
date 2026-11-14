-- STEP 2 — Al registrar una entrega, el pedido pasa a ENTREGADO
-- Reejecutable. No destructivo.

create or replace function public.trg_entrega_pedido_estado()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  update public.pedidos
     set estado = 'ENTREGADO'
   where id = new.pedido_id
     and empresa_id = new.empresa_id
     and estado in ('NUEVO', 'ASIGNADO', 'EN_CAMINO', 'NO_ENTREGADO');
  return new;
end
$fn$;

drop trigger if exists trg_entrega_pedido_estado on public.entregas;
create trigger trg_entrega_pedido_estado
  after insert on public.entregas
  for each row execute function public.trg_entrega_pedido_estado();
