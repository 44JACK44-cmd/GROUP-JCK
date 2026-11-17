# FASE 19 — Navegación robusta, pedidos, rendiciones y avisos

## NAVEGACIÓN

- `core/navegacion/navegacion_service.dart`: ruta actual y avisos internos.
- `main.dart`: `PopScope` global:
  1. si hay stack → `Navigator.pop()` (vuelve a la pantalla anterior);
  2. si no hay stack y no está en Inicio → `go('/inicio')`;
  3. si está en Inicio → confirmación "Salir de GasApp" (nunca cierre accidental).
- `AppShell` actualiza la ruta actual; las rutas completas la actualizan en el redirect.
- `AppBarVolver`: botón "← Volver" visible en detalle de pedido y Mi rendición;
  hace pop o vuelve al inicio.
- Rutas revisadas: `/inicio`, `/pedidos`, `/pedidos/nuevo`, `/clientes`, `/caja`,
  `/motorizados-actividad`, `/rendicion`, `/declarar-rendicion`,
  `/aprobacion-rendiciones`, `/cierre-diario`, `/balones`, `/movimientos`,
  `/mi-registro`, `/mis-pedidos`, `/ajustes`, `/mas`, `/mas-moto`,
  `/pedido_detalle` (vía push), `/combustible` y `/devolucion-balon` (redirigen
  a sus módulos únicos). Resultado: sin salida accidental desde internas.

**Pendiente:** recorrido físico completo en Android (botón y gesto) y verificar
que todas las página secundarias muestren el botón visible. La corrección global
ya está aplicada; la cobertura visual página por página queda para prueba en equipo.

## PEDIDOS

- Se eliminó "¿Cómo pagará?" del alta de pedido. El pedido registra cliente,
  producto, cantidad, precio, dirección, referencia, ubicación, prioridad y
  observaciones; `forma_pago` ya no se envía al crear.
- El pago se registra **en la entrega**: efectivo, Yape (con foto obligatoria),
  deuda o pago parcial, con vuelto calculado y comprobante persistido.
- Notificación interna cuando aumenta el número de pedidos asignados: banner
  "Nuevo pedido asignado" con botón **VER** que abre el pedido.

## INFORMES

Se conservan los informes existentes (motorizados, actividad, caja, rendiciones)
alimentados por datos reales: pedidos, pagos, gastos, incidencias, balones y
movimientos. La vista de administrador incluye ahora un panel de
**Rendiciones pendientes** en el inicio con acceso directo a revisión.

**Pendiente:** el informe individual no muestra aún la línea de tiempo completa
con horas de aceptación/salida/llegada porque esos campos no existen en la base
(solo `fecha` y `estado`). No se inventaron datos.

## NOTIFICACIONES

- Asignación: aviso interno en tiempo real con sonido/vibración nativos **pendiente**
  (requiere Firebase Cloud Messaging y permisos Android; no se agregó dependencia
  nueva sin configuración del proyecto).
- No se genera spam: solo avisa cuando cambia el conteo de pedidos asignados.
- Acceso directo del banner al detalle del pedido.

## RENDICIÓN

- Una sola pantalla "Mi rendición" con resumen, dinero recibido, gastos,
  dinero esperado y declaración; carga la rendición existente del día.
- ADMIN: panel de pendientes en inicio → revisión → aprobación (auditoría y
  estado ya implementados). Realtime avisa a ambas partes.
- Estados actuales de la base: PENDIENTE/EN_REVISION/CON_DIFERENCIA/OBSERVADA/APROBADA.
  No se renombraron para no romper contratos.

## ERRORES CORREGIDOS

- Error real de "No pudimos declarar la rendición": duplicado 23505 por índice
  único; ahora se carga/actualiza la existente (verificado contra Supabase).
- Aviso OTA que desaparecía: contexto raíz estable y `barrierDismissible: false`.
- Pago en el alta de pedido: eliminado.

## PRUEBAS

- `flutter analyze`: **0 errores, 0 warnings** (96 infos).
- `flutter test`: **143 pruebas en verde** (2 nuevas de navegación/avisos).
- Build release arm64 OK. APK **1.0.21+21**, `versionCode` 2021.
  SHA-256: `0DD977021FB019C2FB2B559A1FB19223A3A05A5E3EC3826B64AE1C9B03C68A71`.

## PENDIENTE REAL

No se declara terminado: faltan prueba física del back en Android, notificaciones
push reales (FCM) y horas de aceptación/salida/llegada en la base para el informe
completo. Lo implementado está verificado por analyze/test y por la lógica real
contra Supabase, no solo por interfaz.
