import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../network/api_exception.dart';
import '../network/server_url.dart';
import '../providers.dart';

part 'session_controller.g.dart';

class Session {
  const Session({this.serverUrl, this.authenticated = false, this.hasUser});

  /// Base URL of the configured server; null until the user sets one up.
  final String? serverUrl;
  final bool authenticated;

  /// Whether the server already has its single account (login vs register).
  final bool? hasUser;

  Session copyWith({bool? authenticated, bool? hasUser}) => Session(
        serverUrl: serverUrl,
        authenticated: authenticated ?? this.authenticated,
        hasUser: hasUser ?? this.hasUser,
      );
}

/// Owns the server address and login state and drives app routing.
@Riverpod(keepAlive: true)
class SessionController extends _$SessionController {
  static const _serverKey = 'server_url';

  /// Server the local database content belongs to; switching to another
  /// server wipes local data.
  static const _dataServerKey = 'data_server_url';

  @override
  Future<Session> build() async {
    final prefs = ref.watch(sharedPreferencesProvider);
    final url = prefs.getString(_serverKey);
    if (url == null) return const Session();
    final tokens = await ref.watch(tokenStoreProvider).read();
    return Session(serverUrl: url, authenticated: tokens != null, hasUser: tokens != null ? true : null);
  }

  /// The server whose data is stored locally, if any.
  String? localDataServer() => ref.read(sharedPreferencesProvider).getString(_dataServerKey);

  /// Validates and stores the server address. Throws [FormatException] for
  /// a malformed address and [ApiException] if it can't be reached.
  Future<void> connect(String input) async {
    final url = normalizeServerUrl(input);
    final public = ref.read(publicApiProvider);
    await public.health(url);
    final hasUser = await public.hasUser(url);

    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getString(_dataServerKey) != url) {
      await ref.read(appDatabaseProvider).wipe();
      await ref.read(tokenStoreProvider).clear();
      await prefs.setString(_dataServerKey, url);
    }
    await prefs.setString(_serverKey, url);
    state = AsyncData(Session(serverUrl: url, hasUser: hasUser));
  }

  /// Logs in, or registers the single account when [register] is true.
  Future<void> authenticate({required String email, required String password, required bool register}) async {
    final session = state.requireValue;
    final url = session.serverUrl!;
    final public = ref.read(publicApiProvider);
    try {
      final tokens = register
          ? await public.register(url, email.trim(), password)
          : await public.login(url, email.trim(), password);
      await ref.read(tokenStoreProvider).write(tokens);
      state = AsyncData(session.copyWith(authenticated: true, hasUser: true));
    } on ApiException catch (e) {
      if (e.code == 'registration_disabled') {
        state = AsyncData(session.copyWith(hasUser: true));
      }
      rethrow;
    }
  }

  /// Re-reads whether the server has an account (auth screen refresh).
  Future<void> refreshHasUser() async {
    final session = state.requireValue;
    final hasUser = await ref.read(publicApiProvider).hasUser(session.serverUrl!);
    state = AsyncData(session.copyWith(hasUser: hasUser));
  }

  /// Ends the session on the server (refresh tokens never expire, so this
  /// is what invalidates them) and forgets the tokens. Local data is kept so
  /// unsynced edits survive until the next login.
  Future<void> logout() async {
    await _endServerSession();
    await ref.read(tokenStoreProvider).clear();
    final s = state.value;
    if (s != null) state = AsyncData(s.copyWith(authenticated: false, hasUser: true));
  }

  /// The server rejected the refresh token (session revoked): just forget
  /// the tokens, there is no session left to end.
  Future<void> sessionExpired() async {
    await ref.read(tokenStoreProvider).clear();
    final s = state.value;
    if (s != null) state = AsyncData(s.copyWith(authenticated: false, hasUser: true));
  }

  Future<void> _endServerSession() async {
    final url = state.value?.serverUrl;
    final tokens = await ref.read(tokenStoreProvider).read();
    if (url != null && tokens != null) await ref.read(publicApiProvider).logout(url, tokens.refreshToken);
  }

  /// Forgets the server address and returns to setup. Local data is only
  /// wiped if a different server is connected afterwards.
  Future<void> changeServer() async {
    await _endServerSession();
    await ref.read(tokenStoreProvider).clear();
    await ref.read(sharedPreferencesProvider).remove(_serverKey);
    state = const AsyncData(Session());
  }
}
