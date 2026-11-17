# FASE 18 — Corrección integral de caja, rendiciones y duplicados

## 1. Problemas encontrados

| Problema | Evidencia real / causa |
|---|---|
| "No pudimos declarar la rendición" | Consulta real con token MOTORIZADO: ya existía rendición de hoy y el `INSERT` devolvía **23505 duplicate key value violates unique constraint `idx_rendiciones_empresa_motorizado_fecha`**. El repositorio lanzaba excepción en vez de cargar/actualizar la existente. |
| Dinero esperado confuso | Había `efectivoEsperado`, `totalEsperado` y gastos en conceptos separados, sin un "TOTAL RECIBIDO" claro ni "DINERO ESPERADO" = recibido − gastos. |
| Módulos duplicados | `/combustible` registraba gasolina fuera de Gastos; `/devolucion-balon` repetía lo que ya hace Balones; el botón de inicio apuntaba a la página duplicada. |
| Aviso de nueva versión desaparecía | El diálogo usaba el `context` del GoRouter, que se desactiva al cambiar el estado de autenticación. |
| Texto blanco sobre claro | Contenedores de filtros y fondos de opciones usaban `Colors.white` fijo, invisible en modo oscuro o sobre superficies claras del tema. |
| Historial de caja incompleto | No mostraba fecha/hora del movimiento. |

## 2. Cambios realizados

### Frontend
- `rendicion_repo.dart`: nuevos conceptos `totalRecibido` (efectivo + Yape),
  `totalGastos`, `dineroEsperado` (recibido − gastos) y
  `gastosPorCategoria`. Misma regla en `CalculoCierre` y `ResumenCaja`.
- `rendicion_page.dart` y `declarar_rendicion_page.dart`: resumen con
  "Efectivo cobrado / Yape cobrado / Total recibido / Total gastos / DINERO ESPERADO"
  y desglose de gastos por categoría.
- `caja_page.dart`: resumen de caja con los mismos conceptos; historial con
  fecha y hora.
- `declarar_rendicion_page.dart`: una sola pantalla, estado de carga real,
  carga la rendición existente del día (no parpadea ni desaparece).
- `main.dart`: aviso de actualización con contexto raíz estable,
  `barrierDismissible: false` (solo se cierra con "Actualizar" o "Más tarde").

### Backend / datos
- Sin migraciones nuevas: los índices y columnas ya existen (pasos 15–17).
- `rendicionesRepo.declarar`: si existe rendición del día se **actualiza**; si
  el `INSERT` choca con el índice único se recupera la fila existente. Registra
  el error real con `debugPrint('[RENDICION] …')` y muestra mensaje de negocio.
- RLS, empresas, roles y Outbox intactos.

## 3. Funciones eliminadas / unificadas

| Función | Antes | Ahora |
|---|---|---|
| Fierros | Se mencionaba como módulo aparte | Parte del control de Balones (marcado "Con fierro / Sin fierro"), sin ruta propia. |
| Devolución de balones | Ruta `/devolucion-balon` y botón propio | Unificada en Balones; `/devolucion-balon` redirige a `/balones`. |
| Combustible | Ruta `/combustible` con su propio formulario | Es un gasto con categoría Combustible; `/combustible` redirige al formulario de gasto. |
| Gastos | Formulario canónico | Único punto para combustible, peaje, estacionamiento, mantenimiento, reparación y otros. |

## 4. Flujo final de caja

```text
Ingresos (pagos reales)
  Efectivo cobrado
  Yape cobrado
  → TOTAL RECIBIDO
        │
        ▼
Gastos (por categoría)
  → TOTAL GASTOS
        │
        ▼
DINERO ESPERADO = TOTAL RECIBIDO − TOTAL GASTOS
        │
        ▼
Rendición del motorizado (una por día, se carga si ya existe)
        │
        ▼
Conciliación = esperado vs declarado → diferencia
        │
        ▼
Aprobación (auditoría, estado, fecha y usuario)
        │
        ▼
Cierre diario (una vez por día)
```

El fondo de vuelto sigue mostrándose aparte: es dinero entregado por ADMIN,
no una venta; el fondo por Yape nunca se cuenta como efectivo físico.

## 5. Pruebas

- `flutter analyze`: **0 errores, 0 warnings** (96 infos de estilo).
- `flutter test`: **141 pruebas en verde** (2 nuevas: total recibido/gastos y
  dinero esperado; nunca negativo).
- Pruebas reales Supabase: **23 PASS**; sin datos residuales.
- `flutter build apk --release --split-per-abi --target-platform android-arm64`: OK.
- APK **1.0.20+20**, `versionCode` 2020, `releases/app-v20.apk`.
  SHA-256: `91237B3B83D33ED0B4708846644C80EFD4C07908DAD404160D9B212807ACFCC8`.

## 6. Errores / pendientes

- **Pendiente:** el cierre diario, la conciliación y la aprobación ya existen y
  funcionan, pero sus diálogos no muestran aún todo el detalle solicitado
  (advertencias previas y confirmación con diferencia). Queda como mejora UX,
  no como error de cálculo.
- **Pendiente:** verificación en teléfono del aviso de actualización persistente
  y del formulario de rendición (no hay dispositivo en este entorno).
- No se declara terminado solamente porque compile: la corrección del error real
  de duplicado se verificó contra Supabase (23505 reproducible) y la lógica
  quedó cubierta por pruebas.
