import 'dart:convert';
import 'dart:io';

/// Terrakin backend on Vercel: contract addresses, starter funding, and signed
/// bond vouchers. Every call carries the player's Privy access token.
class BackendApi {
  static const base = 'https://terrakin.vercel.app';

  static Future<Map<String, dynamic>> _req(String method, String path, {String? token, Object? body}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.openUrl(method, Uri.parse('$base$path'));
      if (token != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(const Duration(seconds: 40));
      final text = await res.transform(utf8.decoder).join();
      final j = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
      if (res.statusCode != 200) throw BackendException(j['error']?.toString() ?? 'HTTP ${res.statusCode}', res.statusCode);
      return j;
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> config() => _req('GET', '/api/config');
  static Future<Map<String, dynamic>> fund(String token) => _req('POST', '/api/fund', token: token);
  /// Signed proof the player stands in the hex at ([lat], [lng]).
  static Future<Map<String, dynamic>> presence(String token, double lat, double lng) =>
      _req('POST', '/api/presence', token: token, body: {'lat': lat, 'lng': lng});

  /// Joins the season leaderboards; the backend pays the gas.
  static Future<Map<String, dynamic>> enroll(String token) => _req('POST', '/api/enroll', token: token);

  /// Signed pass to attack today's raid boss at the Landmark the player is at.
  static Future<Map<String, dynamic>> raidPass(String token, double lat, double lng) =>
      _req('POST', '/api/raidpass', token: token, body: {'lat': lat, 'lng': lng});

  static Future<Map<String, dynamic>> voucher(String token, Map<String, Object?> body) =>
      _req('POST', '/api/voucher', token: token, body: body);
}

class BackendException implements Exception {
  BackendException(this.message, this.status);
  final String message;
  final int status;
  @override
  String toString() => message;
}
