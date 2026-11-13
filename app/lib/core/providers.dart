import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network/api_client.dart';
import 'storage/session_storage.dart';
import '../features/auth/presentation/auth_controller.dart';

final sessionStorageProvider = Provider<SessionStorage>((ref) => SessionStorage());

final dioProvider = Provider<Dio>((ref) {
  return createApiClient(
    storage: ref.watch(sessionStorageProvider),
    onSessionExpired: () => ref.read(authControllerProvider.notifier).sessionExpired(),
  );
});
