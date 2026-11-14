-- STEP 8 — Validación en servidor: solo el motorizado asignado
-- (o el ADMIN de la empresa) puede registrar entrega/cobro de un pedido.
-- Reejecutable. No destructivo.

create or replace function public.puede_operar_pedido(p_pedido_id uuid, p_empresa_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $fn$
  select exists (
    select 1
      from public.pedidos p
     where p.id = p_pedido_id
       and p.empresa_id = p_empresa_id
       and p.empresa_id = public.mi_empresa()
       and (
            public.es_admin()
         or p.repartidor_id = auth.uid()
       )
  );
$fn$;

create or replace function public.trg_valida_operacion_pedido()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  if auth.uid() is null then
    return new;
  end if;

  if not public.puede_operar_pedido(new.pedido_id, new.empresa_id) then
    raise exception 'No autorizado: el pedido no esta asignado a este usuario'
      using errcode = '42501';
  end if;

  return new;
end
$fn$;

drop trigger if exists trg_valida_entrega on public.entregas;
create trigger trg_valida_entrega
  before insert on public.entregas
  for each row execute function public.trg_valida_operacion_pedido();

drop trigger if exists trg_valida_pago on public.pagos;
create trigger trg_valida_pago
  before insert on public.pagos
  for each row execute function public.trg_valida_operacion_pedido();
