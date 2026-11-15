/// Precio de venta libre.
///
/// Regla del negocio: **el precio lo decide quien vende**, no el catálogo.
/// `productos.precio_base` y `precios_cliente` son solo una *sugerencia* para
/// no escribir de cero; nunca bloquean ni corrigen lo que el usuario escribe.
///
/// Aquí vive la única interpretación válida del texto que se escribe en el
/// campo "¿Cuánto debe cobrar?", para que la pantalla y las pruebas usen la
/// misma regla.
library;

class PrecioLibre {
  PrecioLibre._();

  /// Tope de cordura para detectar un error de tecleo (p. ej. 5500000).
  /// No es una restricción comercial: cualquier precio real de gas está muy
  /// por debajo.
  static const double tope = 99999;

  /// Interpreta lo que escribió el usuario.
  ///
  /// Acepta `55`, `55.5`, `55,50`, `S/ 63.50`. Devuelve `null` si no hay un
  /// número positivo utilizable.
  static double? parse(String texto) {
    if (texto.contains('-')) return null;
    var t = texto.trim().replaceAll(',', '.');
    t = t.replaceAll(RegExp(r'[^0-9.]'), '');
    if (t.isEmpty) return null;

    // Si hay varios puntos, el primero es el decimal y el resto se descarta
    // como separador de miles mal escrito: "1.234.50" → 1234.50
    final primero = t.indexOf('.');
    if (primero >= 0 && t.indexOf('.', primero + 1) >= 0) {
      final enteros = t.substring(0, primero);
      final decimales = t.substring(primero + 1).replaceAll('.', '');
      t = '$enteros.$decimales';
    }

    final v = double.tryParse(t);
    if (v == null || v.isNaN || v.isInfinite) return null;
    if (v <= 0 || v > tope) return null;
    return double.parse(v.toStringAsFixed(2));
  }

  /// ¿El precio escrito se puede cobrar?
  static bool esValido(String texto) => parse(texto) != null;

  /// Precio sugerido: primero el del cliente, luego el del catálogo.
  ///
  /// Devuelve `null` si no hay referencia: el campo queda vacío para que el
  /// usuario escriba el precio real.
  static double? sugerido({double? precioCliente, double? precioBase}) {
    final p = precioCliente ?? precioBase;
    if (p == null || p <= 0) return null;
    return p;
  }

  /// Texto cómodo para editar: sin ceros de relleno.
  static String paraEditar(double valor) {
    if (valor == valor.roundToDouble()) return valor.toStringAsFixed(0);
    return valor.toStringAsFixed(2);
  }
}
