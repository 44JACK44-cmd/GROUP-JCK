-- STEP 4 — Protección de estados cerrados + reactivación por ADMIN
-- Reejecutable. No destructivo.

create or replace function public.trg_pedidos_guarda_estado()
returns trigger
language plpgsql
as $fn$
begin
  if old.estado is distinct from new.estado
     and old.estado in ('ENTREGADO', 'CANCELADO')
     and coalesce(current_setting('app.allow_reopen', true), '0') <> '1' then
    raise exception 'Transicion no permitida: % a %', old.estado, new.estado
      using errcode = 'P0001';
  end if;
  return new;
end
$fn$;

drop trigger if exists trg_pedidos_guarda_estado on public.pedidos;
create trigger trg_pedidos_guarda_estado
  before update on public.pedidos
  for each row execute function public.trg_pedidos_guarda_estado();

create or replace function public.reactivar_pedido(p_pedido_id uuid, p_motivo text default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $fn$
declare
  v_empresa uuid := public.mi_empresa();
  v_rol text := public.mi_rol();
  v_estado text;
begin
  if v_empresa is null then
    raise exception 'Sin empresa asociada' using errcode = 'P0001';
  end if;
  if v_rol <> 'ADMIN' then
    raise exception 'Solo un administrador puede reactivar un pedido' using errcode = '42501';
  end if;

  select estado into v_estado
    from public.pedidos
   where id = p_pedido_id and empresa_id = v_empresa;

  if v_estado is null then
    raise exception 'El pedido no existe' using errcode = 'P0001';
  end if;
  if v_estado not in ('CANCELADO', 'ENTREGADO', 'NO_ENTREGADO') then
    raise exception 'Este pedido no se puede reactivar' using errcode = 'P0001';
  end if;

  perform set_config('app.allow_reopen', '1', true);
  update public.pedidos
     set estado = 'NUEVO',
         repartidor_id = null
   where id = p_pedido_id and empresa_id = v_empresa;
  perform set_config('app.allow_reopen', '0', true);

  insert into public.auditoria (empresa_id, entidad, entidad_id, accion, usuario_id, detalle)
  values (v_empresa, 'pedido', p_pedido_id::text, 'REACTIVAR', auth.uid(),
          jsonb_build_object('desde', v_estado, 'motivo', p_motivo));

  return true;
end
$fn$;

grant execute on function public.reactivar_pedido(uuid, text) to authenticated;
