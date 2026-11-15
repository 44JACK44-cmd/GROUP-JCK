-- Verificación posterior a la migración (solo lectura)
-- Ejecutar después de los 11 pasos. Debe devolver todo en "OK".

select 'tabla rendiciones' as control,
       case when to_regclass('public.rendiciones') is not null then 'OK' else 'FALTA' end as resultado
union all
select 'tabla cierre_diario',
       case when to_regclass('public.cierre_diario') is not null then 'OK' else 'FALTA' end
union all
select 'tabla incidencias',
       case when to_regclass('public.incidencias') is not null then 'OK' else 'FALTA' end
union all
select 'columna pedidos.origen',
       case when exists (select 1 from information_schema.columns
                          where table_schema = 'public' and table_name = 'pedidos'
                            and column_name = 'origen') then 'OK' else 'FALTA' end
union all
select 'columna gastos.medio_pago',
       case when exists (select 1 from information_schema.columns
                          where table_schema = 'public' and table_name = 'gastos'
                            and column_name = 'medio_pago') then 'OK' else 'FALTA' end
union all
select 'columna clientes.zona',
       case when exists (select 1 from information_schema.columns
                          where table_schema = 'public' and table_name = 'clientes'
                            and column_name = 'zona') then 'OK' else 'FALTA' end
union all
select 'columna perfiles.zona',
       case when exists (select 1 from information_schema.columns
                          where table_schema = 'public' and table_name = 'perfiles'
                            and column_name = 'zona') then 'OK' else 'FALTA' end
union all
select 'trigger entrega->ENTREGADO',
       case when exists (select 1 from pg_trigger
                          where tgname = 'trg_entrega_pedido_estado' and not tgisinternal)
            then 'OK' else 'FALTA' end
union all
select 'trigger pago->caja',
       case when exists (select 1 from pg_trigger
                          where tgname = 'trg_pago_ingreso_caja' and not tgisinternal)
            then 'OK' else 'FALTA' end
union all
select 'trigger guard estado',
       case when exists (select 1 from pg_trigger
                          where tgname = 'trg_pedidos_guarda_estado' and not tgisinternal)
            then 'OK' else 'FALTA' end
union all
select 'trigger valida entrega',
       case when exists (select 1 from pg_trigger
                          where tgname = 'trg_valida_entrega' and not tgisinternal)
            then 'OK' else 'FALTA' end
union all
select 'funcion reactivar_pedido',
       case when to_regprocedure('public.reactivar_pedido(uuid,text)') is not null
            then 'OK' else 'FALTA' end
union all
select 'funcion tomar_pedido',
       case when to_regprocedure('public.tomar_pedido(uuid)') is not null
            then 'OK' else 'FALTA' end
union all
select 'funcion asignar_por_zona',
       case when to_regprocedure('public.asignar_por_zona(uuid)') is not null
            then 'OK' else 'FALTA' end
union all
select 'funcion registrar_ingreso_caja',
       case when to_regprocedure('public.registrar_ingreso_caja(uuid)') is not null
            then 'OK' else 'FALTA' end
union all
select 'realtime pedidos',
       case when exists (select 1 from pg_publication_tables
                          where pubname = 'supabase_realtime'
                            and schemaname = 'public' and tablename = 'pedidos')
            then 'OK' else 'FALTA' end
union all
select 'columna productos.tipo',
       case when exists (select 1 from information_schema.columns
                          where table_schema = 'public' and table_name = 'productos'
                            and column_name = 'tipo') then 'OK' else 'FALTA' end
union all
select 'indice unico producto activo',
       case when exists (select 1 from pg_indexes
                          where schemaname = 'public'
                            and indexname = 'ux_productos_empresa_nombre_activo')
            then 'OK' else 'FALTA' end
union all
select 'concepto fierro/balon vacio',
       case when exists (select 1 from public.productos
                          where activo and tipo = 'RETORNABLE'
                            and lower(btrim(nombre)) = lower('Fierro / Balón vacío'))
            then 'OK' else 'FALTA' end
union all
select 'permiso pedido del motorizado',
       case when exists (select 1 from pg_policies
                          where schemaname = 'public'
                            and tablename = 'pedidos'
                            and policyname = 'pedidos_moto_insert')
            then 'OK' else 'FALTA' end
union all
select 'permiso lineas del motorizado',
       case when exists (select 1 from pg_policies
                          where schemaname = 'public'
                            and tablename = 'detalle_pedido'
                            and policyname = 'detalle_moto_insert')
            then 'OK' else 'FALTA' end
union all
select 'permiso cliente del motorizado',
       case when exists (select 1 from pg_policies
                          where schemaname = 'public'
                            and tablename = 'clientes'
                            and policyname = 'clientes_moto_insert')
            then 'OK' else 'FALTA' end
union all
select 'columna pagos.comprobante_url',
       case when exists (select 1 from information_schema.columns
                          where table_schema = 'public' and table_name = 'pagos'
                            and column_name = 'comprobante_url')
            then 'OK' else 'FALTA' end;
