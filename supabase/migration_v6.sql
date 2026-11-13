-- ============================================================
-- MIGRACIÓN v6 — Zonas de reparto y asignación automática
-- (Grupo JCK)
--
-- Qué resuelve:
--  1. Campo `zona` en `clientes` para identificar la zona de reparto.
--  2. Campo `zona` en `perfiles` para asignar motorizados a zonas.
--  3. Función `asignar_por_zona` para asignación automática.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor → New query
-- Es REEJECUTABLE. NO destructivo.
-- ============================================================

-- ---------- 1. Zona en clientes ----------
alter table public.clientes
  add column if not exists zona text;

-- ---------- 2. Zona en perfiles (motorizados) ----------
alter table public.perfiles
  add column if not exists zona text;

-- ---------- 3. Función de asignación por zona ----------
create or replace function public.asignar_por_zona(p_pedido_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa uuid;
  v_zona text;
  v_motorizado uuid;
begin
  -- Obtener empresa y zona del pedido
  select p.empresa_id, c.zona into v_empresa, v_zona
    from public.pedidos p
    join public.clientes c on c.id = p.cliente_id
   where p.id = p_pedido_id;

  if v_empresa is null then
    return null;
  end if;

  -- Buscar motorizado de la misma zona y empresa, activo
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
end $$;

grant execute on function public.asignar_por_zona(uuid) to authenticated;

-- ---------- 4. Índices ----------
create index if not exists idx_clientes_zona on public.clientes(empresa_id, zona);
create index if not exists idx_perfiles_zona on public.perfiles(empresa_id, zona, rol);

-- ---------- 5. Verificación ----------
select 'migracion v6 aplicada' as resultado,
       (select count(*) from information_schema.columns
        where table_name = 'clientes' and column_name = 'zona') as campo_zona_clientes,
       (select count(*) from information_schema.columns
        where table_name = 'perfiles' and column_name = 'zona') as campo_zona_perfiles;