# FASE 14 — Suma/resta real de movimientos, botones directos y estilos

## 1. La regla única de dinero

Toda la app usa **una sola** fórmula (en `rendicion_repo.dart`, `deuda.dart` y
`CalculoCierre`):

```text
VENTAS            = Σ totales de pedidos ENTREGADO
EFECTIVO COBRADO  = Σ pagos con método EFECTIVO
YAPE              = Σ pagos con método YAPE  (NUNCA entra al efectivo)
DEUDA             = Σ (total pedido − pagos de ese pedido), nunca negativa

FONDO EFECTIVO    = Σ fondo_vuelto donde medio_pago = EFECTIVO
FONDO YAPE        = Σ fondo_vuelto donde medio_pago = YAPE  (no es efectivo físico)

GASTOS EFECTIVO   = Σ gastos con medio_pago = EFECTIVO
GASTOS YAPE/OTRO  = se muestran aparte, NO descuentan el efectivo

EFECTIVO ESPERADO = FONDO EFECTIVO + EFECTIVO COBRADO − GASTOS EFECTIVO
DIFERENCIA        = EFECTIVO DECLARADO − EFECTIVO ESPERADO
BALONES PENDIENTES= Σ balones entregados − Σ balones devueltos
```

Cada concepto está separado: precio, cobro, deuda y gasto **no se mezclan**.

## 2. El caso del vuelto que planteaste

Antes: el fondo de S/ 50 se sumaba siempre al efectivo esperado. Si el billete
de 50 no servía para dar cambio y el admin lo enviaba por Yape, la rendición
quedaba mal: contaba S/ 50 físicos que no existen.

Ahora, al registrar el fondo el ADMIN elige **Efectivo** o **Yape**:

| Entrega del fondo | Efectivo esperado |
|---|---|
| S/ 50 en efectivo | suma S/ 50 |
| S/ 50 por Yape | **no suma**; se muestra como "Fondo por Yape (no es efectivo)" |

Ejemplo real con tus datos: fondo Yape 50 + efectivo cobrado 100 + gastos 0
→ esperado **100** (antes habría mostrado 150). Cubierto por
`rendicion_flujo_test.dart`.

## 3. El caso del combustible

Gasto de S/ 10 en efectivo:

```text
fondo efectivo 100 + efectivo cobrado 192 − gasto combustible 10 = esperado 282
```

El gasto **sí se resta** de lo generado y aparece en la rendición dentro de
"Gastos en efectivo". El gasto por Yape no descuenta el efectivo físico.

## 4. Botones directos agregados

### MOTORIZADO (inicio)
- Llenar combustible → formulario de gasto con categoría "Combustible" ya marcada.
- Cobrar → registrar pago/abono.
- Devolver balón → lista de clientes con balones pendientes y botón "Devuelve 1".
- Deudas → clientes que deben.
- Informe final → rendición de un solo clic, ya calculada.

### ADMIN (inicio)
- Deudas por cobrar, Balones pendientes, Seguimiento, Pagos, Devolución balón, Movimientos.

Nueva pantalla `DevolucionBalonPage`: calcula `entregados − devueltos` con la
misma fuente (`movimiento_bal_on`), permite registrar la devolución, funciona
offline por el Outbox y avisa por Realtime. No crea pagos ni ventas ficticias.

## 5. Estilos

- Fila de accesos con botones 104×82, iconos Material, colores suaves,
  `Semantics` y `Wrap` para pantallas pequeñas/grandes.
- Tema: azul moderado, verde éxito, naranja advertencia, rojo solo error;
  fondo gris claro, sin gradientes ni emojis.
- `Divider`, `Chip`, `ProgressIndicator` y `FloatingActionButton` con el mismo
  lenguaje visual en toda la app.

## 6. Verificación

- `flutter analyze`: 0 errores, 0 warnings (30 infos).
- `flutter test`: **135 pruebas en verde** (incluye la nueva prueba del vuelto Yape).
- `flutter build apk --release --split-per-abi --target-platform android-arm64`: OK.
- APK **1.0.16+16** (`versionCode` real 2016), `releases/app-v16.apk`,
  `app_versiones.version_code=2016`.
  SHA-256: `5D195D76D165C09CCFA533D04180441602466C302203AF46BD69DAA0301B38D5`.

## 7. Acción necesaria y pendiente

**Aplicar el paso 17** en Supabase → SQL Editor:

```text
G:\misProyectos\GROUP JCK\supabase\steps\v7_17_fondo_yape.sql
```

Sin ese paso la columna `fondo_vuelto.medio_pago` no existe; la app mantiene
compatibilidad (todo se considera efectivo) y la prueba de integración lo
reporta como PENDIENTE, no como fallo oculto.

Sigue pendiente lo ya documentado: Realtime con dos teléfonos, Google Maps con
clave real e historial de puntos GPS.
