/// Aviso honesto cuando la compilación no tiene clave de Google Maps.
/// El mapa alternativo sigue funcionando, pero el usuario debe saber que la
/// navegación con Google no está disponible en esta compilación.
library;

import 'package:gas_app/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../config.dart';

class AvisoGoogleMaps extends StatelessWidget {
  AvisoGoogleMaps({super.key});

  @override
  Widget build(BuildContext context) {
    if (hayClaveGoogleMaps) return SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppTheme.warning.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: AppTheme.warning),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Esta compilación no tiene clave de Google Maps. '
              'Configúrala para navegación y rutas.',
              style: TextStyle(fontSize: 12, color: AppColors.textoPrincipal),
            ),
          ),
        ],
      ),
    );
  }
}