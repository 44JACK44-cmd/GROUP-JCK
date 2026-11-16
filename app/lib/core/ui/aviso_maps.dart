/// Aviso honesto cuando la compilación no tiene clave de Google Maps.
/// El mapa alternativo sigue funcionando, pero el usuario debe saber que la
/// navegación con Google no está disponible en esta compilación.
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../config.dart';

class AvisoGoogleMaps extends StatelessWidget {
  const AvisoGoogleMaps({super.key});

  @override
  Widget build(BuildContext context) {
    if (hayClaveGoogleMaps) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppTheme.warning.withValues(alpha: 0.12),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: AppTheme.warning),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Esta compilación no tiene clave de Google Maps. '
              'Configúrala para navegación y rutas.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
