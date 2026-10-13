# 06b admin page (replace the placeholder in lib/admin.dart)

Edit ONLY `lib/admin.dart`. Do not touch pubspec.yaml (it already has `http`, `qr_flutter`), main.dart, or any other file.
`package:http/http.dart as http`, `dart:convert`, `package:flutter/services.dart` (Clipboard) and `package:qr_flutter/qr_flutter.dart` are available. `import 'sync.dart';` gives `Sync.worker` (the proxy base URL).
The class must stay `class AdminPage extends StatefulWidget` with a const constructor `const AdminPage({super.key})`.

## Helpers (put these at the top of the file, copy exactly)
```dart
String _basic(String user, String pass) => 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';

Future<http.Response> _call(String method, String path, String auth,
    {String? body, Map<String, String> headers = const {}}) async {
  final req = http.Request(method, Uri.parse('${Sync.worker}$path'))
    ..headers.addAll({'Authorization': auth, ...headers});
  if (body != null) req.body = body;
  return http.Response.fromStream(await req.send());
}

/// Creates one public link share and returns its token; throws String on failure.
Future<String> _share(String auth, String path, int permissions, String expire) async {
  final r = await _call('POST', '/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json', auth,
      body: 'path=${Uri.encodeQueryComponent(path)}&shareType=3&permissions=$permissions&expireDate=$expire',
      headers: {'OCS-APIRequest': 'true', 'Accept': 'application/json',
                'Content-Type': 'application/x-www-form-urlencoded'});
  if (r.statusCode != 200) throw 'share failed: HTTP ${r.statusCode} ${r.body}';
  final token = (jsonDecode(r.body) as Map)['ocs']['data']['token'];
  if (token is! String) throw 'share failed: ${r.body}';
  return token;
}
```

## Page
A `StatefulWidget` with a `State` holding four `TextEditingController`s (user, app password obscured via `obscureText: true`, session name, expiry days default `3`), a `String _status`, a `bool _busy`, and a result `({String host, String viewer})?`.
Layout: dark theme as everywhere, `Scaffold` > `Center` > `ConstrainedBox(maxWidth: 480)` > `SingleChildScrollView` > `Column` with padding 16. Title text "Admin: new session". A line of small text: "The app password is kept in memory only." No emoji.

### `_create()` (async, sets `_busy`, wraps in try/catch String and Object, shows the error in a red `SelectableText`)
1. Validate: user and password non-empty, name matches `^[A-Za-z0-9-]+$`, days parses to an int 1..30. On failure set `_status` and return.
2. `auth = _basic(user, pass)`; `dav = '/remote.php/dav/files/$user/sessions'`.
3. `MKCOL $dav` : accept 201 or 405 (exists); anything else throw `'folder failed: HTTP ...'`.
4. `MKCOL $dav/$name` : accept 201 only; on 405 throw `'session name already exists'`.
5. `PUT $dav/$name/state.json` body `{}` and `PUT $dav/$name/notes.json` body `{}` (header Content-Type application/json); accept 201 or 204.
6. `expire` = today + days as `YYYY-MM-DD` (use `DateTime.now().add(Duration(days: days))` and pad month/day).
7. `edit = await _share(auth, '/sessions/$name/state.json', 3, expire)`, `notes = ... notes.json, 3`, `read = ... state.json, 1`.
8. `base = Uri.base.replace(fragment: '').toString()` with a trailing `#` removed if present; `host = '$base#/host/$edit/$notes/$read'`, `viewer = '$base#/view/$read'`. Set the result.
Update `_status` with a short progress line before each step ("Creating folder...").

### Result block (when a result exists), for each of host and viewer link
Label, `SelectableText(url)`, a `TextButton.icon` "Copy" doing `Clipboard.setData(ClipboardData(text: url))` plus a SnackBar "Copied", a white-background `QrImageView(data: url, size: 200)`, and a `SelectableText` with the mailto line `mailto:?subject=${Uri.encodeComponent('Defence timer')}&body=${Uri.encodeComponent(url)}` labelled "Email link (paste into your mail client)".

## Acceptance
`flutter analyze` and `flutter test` pass with no new warnings.
