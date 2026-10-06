import 'package:flutter/foundation.dart';

/// Origin of this page when the web app was built to be served by the API
/// (`--dart-define=INDEX_SAME_ORIGIN=true`). Null on Android and when running
/// `flutter run -d chrome`, where the page origin is the dev server.
String? embeddedServerOrigin() {
  if (!kIsWeb) return null;
  const enabled = bool.fromEnvironment('INDEX_SAME_ORIGIN');
  if (!enabled) return null;
  final origin = Uri.base.origin;
  if (origin.isEmpty) return null;
  return origin;
}

/// Address shown in the setup field before the user types. A stored server
/// wins; otherwise the embedded build offers this page's origin.
String initialServerAddress({String? stored, String? pageOrigin}) {
  if (stored != null && stored.isNotEmpty) return stored;
  return pageOrigin ?? '';
}

/// First launch of the embedded web build connects to the page origin on its
/// own. Once this browser has local data, the setup form stays so the user
/// can point it somewhere else.
bool shouldAutoConnectEmbeddedServer({
  String? storedDataServer,
  String? pageOrigin,
}) {
  if (pageOrigin == null || pageOrigin.isEmpty) return false;
  return storedDataServer == null || storedDataServer.isEmpty;
}

/// Normalises what the user typed as the server address into a base URL
/// without trailing slash or API prefix, e.g. `192.168.1.5:8080` becomes
/// `http://192.168.1.5:8080` and `api.example.com/` becomes
/// `https://api.example.com`.
///
/// Bare IPs and `localhost` default to http (typical for a home server);
/// everything else defaults to https. Throws [FormatException] if invalid.
String normalizeServerUrl(String input) {
  var s = input.trim();
  if (s.isEmpty) throw const FormatException('Enter the server address');
  if (!s.contains('://')) {
    final host = s.split(RegExp(r'[:/]')).first;
    final isLocal =
        host == 'localhost' ||
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);
    s = '${isLocal ? 'http' : 'https'}://$s';
  }
  final uri = Uri.tryParse(s);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty) {
    throw const FormatException('Not a valid server address');
  }
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.endsWith('/api/v1'))
    path = path.substring(0, path.length - '/api/v1'.length);
  return uri
      .replace(path: path, query: null, fragment: null)
      .toString()
      .replaceAll(RegExp(r'[?#]$'), '');
}
