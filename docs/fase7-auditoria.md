# FASE 7 — Auditoría de complejidad (antes de simplificar)

## 1. Problemas encontrados

### Flujo de nuevo pedido (`nuevo_pedido_page.dart`, 588 líneas)
- Exigía que el cliente **ya existiera** en la base antes de poder crear un
  pedido: no había forma de registrar a un cliente nuevo desde la llamada.
- Mostraba **todos los productos a la vez** con un campo de precio por cada
  uno, aunque el 95 % de los pedidos son un solo balón. El usuario tenía que
  poner cantidad 0 en los que no quería y editar el precio en cada fila.
- El precio por producto se inicializaba con `precio_base` (a veces 0) y la
  única validación era `precio <= 0`, lo que se sentía como "el sistema decide
  el precio" en vez de "el recepcionista cobra lo que quiere".
- No capturaba **teléfono** del cliente, ni **ubicación**, ni **motorizado**:
  la asignación se hacía después, en otra pantalla, o con el switch
  "asignar por zona".
- El campo "observaciones" estaba escondido al final.

### Lista de pedidos (`pedidos_page.dart`)
- Filtros: Pendientes · En camino · Completados · Cancelados. No había
  "Todos", así que ver todo implicaba cambiar de pestaña.
- La tarjeta no mostraba qué producto se llevaba ni quién lo llevaba.

### Motorizado (`mis_pedidos_page.dart`)
- Para entregar había que abrir el detalle, esperar a que cargara y pulsar
  "Entregar". Tres pantallas para una acción que se hace en la puerta.
- "Navegar" no existía como botón directo: primero había que abrir el detalle
  y luego "En camino".

### Configuración (`ajustes_page.dart`)
- Ya estaba disponible antes del login (engranaje en bienvenida y login), pero:
  * no tenía botón "Buscar actualización" (decía "inicia sesión y búscalo").
  * no listaba otros permisos (micrófono, notificaciones, almacenamiento).
  * no había una "prueba de mapa".
- El permiso de ubicación se mostraba, pero no se explicaba qué permisos
  **no** se usan.

### Precio
- No existía un helper único para interpretar el texto del campo "cuánto
  cobrar": la pantalla y las pruebas podían divergir (coma vs punto, "S/ 55").

### Complejidad general
- `pedido_detalle_page.dart` (727 líneas) mezclaba asignación, cancelación,
  no-entregado, ruta y entrega en una sola pantalla.
- El motorizado no tenía acceso directo a "Cobros" hasta FASE 6.

## 2. Qué se mantuvo (no se borró nada)
- Toda la lógica financiera, RLS, Outbox, auditoría, mapas y voz.
- `TarjetaPedido`, `EstadoBadge`, `mostrarFormularioEntrega`, `RutaPage`.
- El detalle del pedido sigue existiendo para acciones administrativas.

## 3. Qué se cambió en FASE 7
Ver `docs/fase7-informe-final.md`.
