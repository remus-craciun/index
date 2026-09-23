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
    final isLocal = host == 'localhost' || RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host);
    s = '${isLocal ? 'http' : 'https'}://$s';
  }
  final uri = Uri.tryParse(s);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
    throw const FormatException('Not a valid server address');
  }
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path.endsWith('/api/v1')) path = path.substring(0, path.length - '/api/v1'.length);
  return uri.replace(path: path, query: null, fragment: null).toString().replaceAll(RegExp(r'[?#]$'), '');
}
