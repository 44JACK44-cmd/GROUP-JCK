import 'package:flutter_test/flutter_test.dart';
import 'package:gas_app/app/theme.dart';

void main() {
  test('El tema usa el color primario definido', () {
    final theme = AppTheme.light();
    expect(theme.colorScheme.primary, AppTheme.primary);
    expect(theme.scaffoldBackgroundColor, AppTheme.background);
  });
}
