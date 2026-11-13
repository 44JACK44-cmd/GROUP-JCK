import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../domain/user_session.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, UserSession?>(AuthController.new);

class AuthController extends AsyncNotifier<UserSession?> {
  @override
  Future<UserSession?> build() => ref.read(authRepositoryProvider).restore();

  /// Devuelve el mensaje de error para mostrar, o null si ingresó.
  Future<String?> login(String usuario, String password) async {
    try {
      final user = await ref.read(authRepositoryProvider).login(usuario, password);
      state = AsyncData(user);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
  }

  void sessionExpired() => state = const AsyncData(null);
}
