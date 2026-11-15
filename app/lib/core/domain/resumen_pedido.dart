/// Lectura compacta de un pedido para las tarjetas de la lista.
///
/// La lista trae el pedido con `detalle_pedido(...)` y `productos(...)`
/// incrustados. Estas funciones toleran que el servidor no los traiga (versión
/// antigua o migración pendiente): en ese caso devuelven textos vacíos en vez
/// de romper la pantalla.
library;

/// Una línea del pedido tal como llega de la consulta.
class LineaResumen {
  final String nombre;
  final int cantidad;
  final String tipo;

  const LineaResumen({
    required this.nombre,
    required this.cantidad,
    required this.tipo,
  });

  bool get esRetornable => tipo == 'RETORNABLE';
}

/// Líneas del pedido (vacío si la consulta no las incluyó).
List<LineaResumen> lineasDe(Map<String, dynamic> pedido) {
  final detalle = pedido['detalle_pedido'];
  if (detalle is! List) return const [];
  final lineas = <LineaResumen>[];
  for (final d in detalle) {
    if (d is! Map) continue;
    final producto = d['productos'];
    final nombreProducto = producto is Map ? producto['nombre'] as String? : null;
    final kg = producto is Map ? producto['capacidad_kg'] : null;
    final tipo = producto is Map ? (producto['tipo'] as String? ?? 'PRODUCTO') : 'PRODUCTO';
    final cantidad = (d['cantidad'] as num? ?? 0).toInt();
    if (cantidad <= 0) continue;
    final nombre = nombreProducto == null
        ? 'Producto'
        : (kg == null ? nombreProducto : '$nombreProducto ${kg}kg');
    lineas.add(LineaResumen(nombre: nombre, cantidad: cantidad, tipo: tipo));
  }
  return lineas;
}

/// Texto corto: "Balón 10kg × 2 · Fierro / Balón vacío × 1".
String resumenProductos(Map<String, dynamic> pedido) {
  final lineas = lineasDe(pedido);
  if (lineas.isEmpty) return '';
  return lineas.map((l) => '${l.nombre} × ${l.cantidad}').join(' · ');
}

/// Cuántos balones (productos que se venden) lleva el pedido.
///
/// Si la lista no trae líneas se asume 1: es lo normal en una entrega y evita
/// que el motorizado tenga que corregirlo.
int balonesDe(Map<String, dynamic> pedido) {
  final lineas = lineasDe(pedido);
  if (lineas.isEmpty) return 1;
  final n = lineas
      .where((l) => !l.esRetornable)
      .fold<int>(0, (s, l) => s + l.cantidad);
  return n <= 0 ? 1 : n;
}

/// Cuántos fierros / soportes retornables lleva el pedido.
int fierrosDe(Map<String, dynamic> pedido) {
  return lineasDe(pedido)
      .where((l) => l.esRetornable)
      .fold<int>(0, (s, l) => s + l.cantidad);
}
