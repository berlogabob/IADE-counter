import 'dart:convert';

import 'package:http/http.dart' as http;

import 'session.dart';

/// Host pushes state, viewer mirrors it, over a Nextcloud public share.
///
/// The share is a single file; the server hands back an ETag we keep on the
/// If-None-Match to avoid 304s, and a Date header we use to skew local time
/// so host and viewer agree on "now" even with different clocks.
///
/// No `dart:io`: `HttpDate`/`HttpHeaders` live there, and the web build rejects
/// it, so we use literal header names and a small RFC 7231 date parser instead.
class Sync {
  Sync(this.token, {http.Client? client}) : _http = client ?? http.Client();
  static const worker = 'https://iade-sync.counter-iade.workers.dev';
  final String token;
  final http.Client _http;

  int offsetMs = 0; // server clock minus local clock
  String? _etag;

  int nowMs() => DateTime.now().millisecondsSinceEpoch + offsetMs;

  String get _url => '$worker/public.php/dav/files/$token';

  /// Fetch the share's raw body (same URL/ETag/error rules as [getText]).
  /// Returns null on 304, non-200, connection error, or an empty body (a
  /// brand-new, empty share). Viewer keeps running on its last known state.
  Future<String?> getText() async {
    try {
      final headers = <String, String>{};
      if (_etag != null) headers['if-none-match'] = _etag!;
      final resp = await _http.get(Uri.parse(_url), headers: headers);

      if (resp.statusCode == 304) return null;
      if (resp.statusCode != 200) return null;
      final date = resp.headers['date'];
      if (date != null) {
        final server = httpDateToEpoch(date);
        if (server != -1) {
          offsetMs = server - DateTime.now().millisecondsSinceEpoch;
        }
      }
      final body = resp.body.trim();
      if (body.isEmpty) return null; // new, empty share
      _etag = resp.headers['etag'];
      return body;
    } catch (_) {
      return null;
    }
  }

  /// Write the share's raw body. Failures are swallowed: the host keeps
  /// running offline; a failed push is not a failure.
  Future<void> putText(String text) async {
    try {
      await _http.put(
        Uri.parse(_url),
        headers: {'content-type': 'text/plain'},
        body: text,
      );
    } catch (_) {
      // host keeps running offline; a failed push is not a failure
    }
  }

  Future<Snapshot?> poll() async {
    final body = await getText();
    if (body == null) return null;
    return Snapshot.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  Future<void> push(Snapshot s) async => putText(jsonEncode(s.toJson()));

  /// RFC 7231 HTTP-date (IMF-fixdate: `Wed, 01 Jan 2024 00:00:00 GMT`) to epoch
  /// ms, or -1 when unparseable. Kept local so this file stays web-safe.
  static int httpDateToEpoch(String raw) {
    const months = <String, int>{
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final s = raw.trim().toLowerCase();
    final body = s.contains(',') ? s.substring(s.indexOf(',') + 1) : s;
    final parts = body.trim().split(RegExp(r'\s+'));
    // [day, month, year, hh:mm:ss, gmt]
    if (parts.length < 5) return -1;
    final month = months[parts[1]];
    if (month == null) return -1;
    final year = int.tryParse(parts[2]);
    if (year == null) return -1;
    final time = parts[3].split(':');
    if (time.length != 3) return -1;
    final day = int.tryParse(parts[0]);
    final hour = int.tryParse(time[0]);
    final minute = int.tryParse(time[1]);
    final second = int.tryParse(time[2]);
    if (day == null || hour == null || minute == null || second == null) {
      return -1;
    }
    final y = year < 70
        ? 2000 + year
        : year < 100
        ? 1900 + year
        : year;
    final date = DateTime.utc(y, month, day, hour, minute, second);
    return date.millisecondsSinceEpoch;
  }
}
