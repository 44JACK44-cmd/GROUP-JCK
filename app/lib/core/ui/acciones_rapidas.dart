/// Fila compacta de acciones directas.
///
/// Botones grandes para uso con una sola mano, iconos profesionales, colores
/// suaves y `Semantics`. Se adapta con `Wrap` a teléfonos pequeños y grandes.
library;

import 'package:flutter/material.dart';

class AccionDirecta {
  final String texto;
  final IconData icono;
  final Color color;
  final VoidCallback onPressed;
  final String? badges;

  const AccionDirecta({
    required this.texto,
    required this.icono,
    required this.color,
    required this.onPressed,
    this.badges,
  });
}

class AccionesDirectas extends StatelessWidget {
  final List<AccionDirecta> acciones;

  const AccionesDirectas({super.key, required this.acciones});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in acciones)
          SizedBox(
            width: 104,
            height: 82,
            child: Semantics(
              button: true,
              label: a.texto,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: a.onPressed,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE6E8E5)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          children: [
                            Icon(a.icono, size: 25, color: a.color),
                            if (a.badges != null)
                              Positioned(
                                right: -10,
                                top: -4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: a.color,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    a.badges!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          a.texto,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
