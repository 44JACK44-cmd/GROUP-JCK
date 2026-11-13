import 'package:material_ui/material_ui.dart';

/// Botón principal de ancho completo. Muestra carga y evita doble toque.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.onPressed, this.icon, this.loading = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 24), const SizedBox(width: 10)],
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          );
    return FilledButton(onPressed: loading ? null : onPressed, child: child);
  }
}
