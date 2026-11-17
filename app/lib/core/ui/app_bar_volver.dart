/// AppBar con botón "Volver" siempre visible.
///
/// Si hay stack, hace pop; si no, vuelve al Inicio. Nunca cierra la app.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppBarVolver extends StatelessWidget implements PreferredSizeWidget {
  final String titulo;
  final List<Widget>? actions;

  const AppBarVolver({
    super.key,
    required this.titulo,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        tooltip: 'Volver',
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          final nav = Navigator.of(context);
          if (nav.canPop()) {
            nav.pop();
          } else {
            context.go('/inicio');
          }
        },
      ),
      title: Text(titulo),
      automaticallyImplyLeading: false,
      actions: actions,
    );
  }
}
