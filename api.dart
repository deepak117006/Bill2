import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiError implements Exception {
  final String message;
  ApiError(this.message);
  @override
  String toString() => message;
}

class AuthExpired implements Exception {}

/// Talks to the Perixa Billing Pro PC app over the local Wi-Fi.
class Api {
  static String base = '';
  static String cookie = '';
  static void Function()? onAuthLost;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    base = p.getString('base') ?? '';
    cookie = p.getString('cookie') ?? '';
  }

  static Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('base', base);
    await p.setString('cookie', cookie);
  }

  static Future<void> setServer(String addr) async {
    var a = addr.trim();
    if (a.isEmpty) throw ApiError('Enter the PC address');
    if (!a.startsWith('http')) a = 'http://$a';
    if (!RegExp(r':\d+$').hasMatch(a)) a = '$a:5057';
    base = a.replaceAll(RegExp(r'/+$'), '');
    await _save();
  }

  static bool get hasSession => base.isNotEmpty && cookie.isNotEmpty;

  static Future<void> logout() async {
    cookie = '';
    await _save();
  }

  static Map<String, String> _headers(bool json) => {
        'X-Requested-With': 'fetch',
        if (cookie.isNotEmpty) 'Cookie': cookie,
        if (json) 'Content-Type': 'application/json',
      };

  static Future<http.Response> _send(String method, String url, Object? body) async {
    final req = http.Request(method, Uri.parse(url))..headers.addAll(_headers(body != null));
    if (body != null) req.body = jsonEncode(body);
    try {
      final r = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 15)));
      final sc = r.headers['set-cookie'];
      if (sc != null) {
        final m = RegExp(r'session=[^;]+').firstMatch(sc);
        if (m != null) {
          cookie = m.group(0)!;
          _save();
        }
      }
      return r;
    } on TimeoutException {
      throw ApiError('PC not reachable. Is the PC on, and are you on the same Wi-Fi?');
    } on Exception catch (e) {
      if (e is ApiError) rethrow;
      throw ApiError('Cannot reach the PC. Check the address and Wi-Fi.');
    }
  }

  static Future<dynamic> call(String method, String path, [Object? body]) async {
    final r = await _send(method, '$base/api/$path', body);
    dynamic j;
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      j = null;
    }
    if (r.statusCode == 401 && path != 'login') {
      onAuthLost?.call();
      throw AuthExpired();
    }
    if (r.statusCode >= 400) {
      throw ApiError(j is Map && j['error'] != null
          ? j['error'].toString()
          : r.statusCode == 403
              ? 'Phone access is off on the PC (Settings > Phone)'
              : 'Error ${r.statusCode}');
    }
    return j;
  }

  static Future<dynamic> get(String p) => call('GET', p);
  static Future<dynamic> post(String p, [Object? b]) => call('POST', p, b ?? {});
  static Future<dynamic> put(String p, Object b) => call('PUT', p, b);
  static Future<dynamic> delete(String p) => call('DELETE', p);

  static Future<void> login(String user, String pass) async {
    await call('POST', 'login', {'username': user, 'password': pass});
  }

  static Future<Uint8List?> bytes(String path) async {
    try {
      final r = await _send('GET', '$base$path', null);
      return r.statusCode == 200 ? r.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }
}
