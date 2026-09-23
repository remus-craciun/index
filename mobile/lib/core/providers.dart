import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db/app_database.dart';
import 'network/api.dart';
import 'network/token_store.dart';
import 'session/session_controller.dart';

part 'providers.g.dart';

@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}

/// Overridden in main() with the instance loaded before runApp.
@Riverpod(keepAlive: true)
SharedPreferences sharedPreferences(Ref ref) =>
    throw UnimplementedError('sharedPreferencesProvider must be overridden');

@Riverpod(keepAlive: true)
TokenStore tokenStore(Ref ref) => SecureTokenStore();

@Riverpod(keepAlive: true)
PublicApi publicApi(Ref ref) => PublicApi();

/// The authenticated API for the current server, or null before setup.
@Riverpod(keepAlive: true)
Api? api(Ref ref) {
  final serverUrl = ref.watch(sessionControllerProvider.select((s) => s.value?.serverUrl));
  if (serverUrl == null) return null;
  return Api.create(
    serverUrl: serverUrl,
    tokens: ref.watch(tokenStoreProvider),
    publicApi: ref.watch(publicApiProvider),
    onSessionExpired: () => ref.read(sessionControllerProvider.notifier).sessionExpired(),
  );
}
