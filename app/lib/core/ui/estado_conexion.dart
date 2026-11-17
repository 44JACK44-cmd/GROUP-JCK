/// Aviso de conexión / sincronización.
///
/// No es decorativo: dice la verdad sobre si los datos que se ven pueden estar
/// desactualizados y si hay operaciones guardadas en el dispositivo esperando
/// a subir. Se muestra inline en las pantallas principales.
library;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../state/bus.dart';

class EstadoConexion extends StatelessWidget {
  EstadoConexion({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SyncBus.enLinea,
      builder: (context, enLinea, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: SyncBus.sincronizando,
          builder: (context, sincronizando, _) {
            if (enLinea && !sincronizando) return SizedBox.shrink();
            final color = enLinea ? AppTheme.info : AppTheme.warning;
            final texto = sincronizando
                ? 'Sincronizando cambios guardados...'
                : 'Sin conexión. Los cambios se guardan en el dispositivo.';
            return Container(
              margin: EdgeInsets.only(bottom: 10),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    sincronizando ? Icons.sync : Icons.cloud_off_outlined,
                    size: 17,
                    color: color,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      texto,
                      style: TextStyle(color: color, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}