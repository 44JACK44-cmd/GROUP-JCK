import 'package:material_ui/material_ui.dart';

import '../../../shared/widgets/empty_state.dart';

/// Sección con su título y estado vacío; se completa en su fase correspondiente.
class SectionScreen extends StatelessWidget {
  const SectionScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.emptyTitle,
    required this.emptyMessage,
    this.showAppBar = true,
  });

  final String title;
  final IconData icon;
  final String emptyTitle;
  final String emptyMessage;
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), automaticallyImplyLeading: showAppBar),
      body: SafeArea(child: EmptyState(icon: icon, title: emptyTitle, message: emptyMessage)),
    );
  }
}
