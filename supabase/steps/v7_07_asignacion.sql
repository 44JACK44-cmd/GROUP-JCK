-- STEP 7 — Zonas de reparto y asignación de pedidos
-- Reejecutable. No destructivo.

alter table public.clientes add column if not exists zona text;
alter table public.perfiles add column if not exists zona text;

create or replace function public.asignar_por_zona(p_pedido_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_empresa uuid;
  v_zona text;
  v_motorizado uuid;
begin
  select p.empresa_id, c.zona into v_empresa, v_zona
    from public.pedidos p
    join public.clientes c on c.id = p.cliente_id
   where p.id = p_pedido_id;

  if v_empresa is null then
    return null;
  end if;

  select pr.id into v_motorizado
    from public.perfiles pr
   where pr.empresa_id = v_empresa
     and pr.rol = 'MOTORIZADO'
     and pr.activo = true
     and (v_zona is null or pr.zona = v_zona or pr.zona is null)
   order by (
     select count(*) from public.pedidos pp
      where pp.repartidor_id = pr.id
        and pp.estado in ('ASIGNADO', 'EN_CAMINO')
   ) asc
   limit 1;

  if v_motorizado is not null then
    update public.pedidos
       set repartidor_id = v_motorizado,
           estado = 'ASIGNADO'
     where id = p_pedido_id
       and estado = 'NUEVO';
  end if;

  return v_motorizado;
end
$fn$;

grant execute on function public.asignar_por_zona(uuid) to authenticated;

-- El motorizado toma un pedido libre (valida empresa, rol y estado en servidor)
create or replace function public.tomar_pedido(p_pedido_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_empresa uuid := public.mi_empresa();
  v_rol text := public.mi_rol();
  v_estado text;
  v_repartidor uuid;
  v_empresa_pedido uuid;
begin
  if v_empresa is null then
    raise exception 'Sin empresa asociada' using errcode = 'P0001';
  end if;

  select estado, repartidor_id, empresa_id
    into v_estado, v_repartidor, v_empresa_pedido
    from public.pedidos
   where id = p_pedido_id;

  if v_empresa_pedido is null or v_empresa_pedido <> v_empresa then
    raise exception 'El pedido no existe' using errcode = 'P0001';
  end if;

  if v_rol <> 'MOTORIZADO' then
    raise exception 'Solo un motorizado puede tomar pedidos' using errcode = '42501';
  end if;

  if v_estado <> 'NUEVO' then
    raise exception 'El pedido ya no esta disponible (estado %)', v_estado using errcode = 'P0001';
  end if;

  if v_repartidor is not null and v_repartidor <> auth.uid() then
    raise exception 'El pedido ya fue tomado por otro motorizado' using errcode = 'P0001';
  end if;

  update public.pedidos
     set repartidor_id = auth.uid(),
         estado = 'ASIGNADO'
   where id = p_pedido_id
     and empresa_id = v_empresa
     and estado = 'NUEVO'
     and (repartidor_id is null or repartidor_id = auth.uid());

  if not found then
    raise exception 'No se pudo tomar el pedido' using errcode = 'P0001';
  end if;

  return true;
end
$fn$;

grant execute on function public.tomar_pedido(uuid) to authenticated;

-- El admin libera un pedido para que otro motorizado lo tome
create or replace function public.liberar_pedido(p_pedido_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_empresa uuid := public.mi_empresa();
begin
  if v_empresa is null or not public.es_admin() then
    raise exception 'Solo un administrador puede liberar pedidos' using errcode = '42501';
  end if;

  update public.pedidos
     set repartidor_id = null,
         estado = 'NUEVO'
   where id = p_pedido_id
     and empresa_id = v_empresa
     and estado in ('NUEVO', 'ASIGNADO', 'EN_CAMINO', 'NO_ENTREGADO');

  if not found then
    raise exception 'El pedido no se puede liberar en su estado actual' using errcode = 'P0001';
  end if;

  return true;
end
$fn$;

grant execute on function public.liberar_pedido(uuid) to authenticated;
