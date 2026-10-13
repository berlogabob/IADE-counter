import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'sync.dart';

String _basic(String user, String pass) =>
    'Basic ${base64Encode(utf8.encode('$user:$pass'))}';

Future<http.Response> _call(
  String method,
  String path,
  String auth, {
  String? body,
  Map<String, String> headers = const {},
}) async {
  final req = http.Request(method, Uri.parse('${Sync.worker}$path'))
    ..headers.addAll({'Authorization': auth, ...headers});
  if (body != null) req.body = body;
  return http.Response.fromStream(await req.send());
}

/// Creates one public link share and returns its token; throws String on failure.
Future<String> _share(
  String auth,
  String path,
  int permissions,
  String expire,
) async {
  final r = await _call(
    'POST',
    '/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json',
    auth,
    body:
        'path=${Uri.encodeQueryComponent(path)}&shareType=3&permissions=$permissions&expireDate=$expire',
    headers: {
      'OCS-APIRequest': 'true',
      'Accept': 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
    },
  );
  if (r.statusCode != 200) throw 'share failed: HTTP ${r.statusCode} ${r.body}';
  final token = (jsonDecode(r.body) as Map)['ocs']['data']['token'];
  if (token is! String) throw 'share failed: ${r.body}';
  return token;
}

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  final _days = TextEditingController(text: '3');

  String _status = '';
  bool _busy = false;
  ({String host, String viewer})? _result;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _name.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    _status = '';
    setState(() => _busy = true);
    try {
      final user = _user.text.trim();
      final pass = _pass.text;
      final name = _name.text.trim();
      final daysRaw = _days.text.trim();

      if (user.isEmpty || pass.isEmpty) {
        _status = 'Enter a user and an app password.';
        return;
      }
      if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(name)) {
        _status = 'Session name may only contain letters, digits and "-"; keep it short.';
        return;
      }
      final days = int.tryParse(daysRaw);
      if (days == null || days < 1 || days > 30) {
        _status = 'Expiry in days must be a whole number between 1 and 30.';
        return;
      }

      final auth = _basic(user, pass);
      final dav = '/remote.php/dav/files/$user/sessions';

      setState(() => _status = 'Creating folder...');
      final mkcol = await _call('MKCOL', dav, auth);
      if (mkcol.statusCode != 201 && mkcol.statusCode != 405) {
        throw 'folder failed: HTTP ${mkcol.statusCode} ${mkcol.body}';
      }

      setState(() => _status = 'Creating session...');
      final mkSession = await _call('MKCOL', '$dav/$name', auth);
      if (mkSession.statusCode == 405) {
        throw 'session name already exists';
      }
      if (mkSession.statusCode != 201) {
        throw 'session failed: HTTP ${mkSession.statusCode} ${mkSession.body}';
      }

      setState(() => _status = 'Writing files...');
      for (final file in ['state.json', 'notes.json']) {
        final put = await _call(
          'PUT',
          '$dav/$name/$file',
          auth,
          body: '{}',
          headers: {'Content-Type': 'application/json'},
        );
        if (put.statusCode != 201 && put.statusCode != 204) {
          throw 'file failed: HTTP ${put.statusCode} ${put.body}';
        }
      }

      final expire = DateTime.now()
          .add(Duration(days: days))
          .toIso8601String()
          .substring(0, 10);
      setState(() => _status = 'Creating links...');
      final edit = await _share(auth, '/sessions/$name/state.json', 3, expire);
      final notes = await _share(auth, '/sessions/$name/notes.json', 3, expire);
      final read = await _share(auth, '/sessions/$name/state.json', 1, expire);

      var base = Uri.base.replace(fragment: '').toString();
      if (base.endsWith('#')) base = base.substring(0, base.length - 1);
      final host = '$base#/host/$edit/$notes/$read';
      final viewer = '$base#/view/$read';

      _result = (host: host, viewer: viewer);
      _status = 'Done.';
    } on String catch (e) {
      _status = e;
    } catch (_) {
      _status = 'Something went wrong.';
    } finally {
      if (mounted)
        setState(() => _busy = false); // also repaints early-return messages
    }
  }

  void _copy(String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Admin: new session',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'The app password is kept in memory only.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _user,
                  decoration: const InputDecoration(labelText: 'User'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'App password'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Session name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _days,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Expiry in days',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _create,
                  child: Text(_busy ? 'Working…' : 'Create'),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  _status,
                  style: TextStyle(color: Colors.red[700]),
                ),
                if (_result != null) ...[
                  const SizedBox(height: 24),
                  ..._links(_result!.host, 'Host link'),
                  const SizedBox(height: 16),
                  ..._links(_result!.viewer, 'Viewer link'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _links(String url, String label) => [
    Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    const SizedBox(height: 4),
    SelectableText(url),
    const SizedBox(height: 8),
    TextButton.icon(
      onPressed: () => _copy(url),
      icon: const Icon(Icons.copy),
      label: const Text('Copy'),
    ),
    const SizedBox(height: 8),
    QrImageView(data: url, size: 200, backgroundColor: Colors.white),
    const SizedBox(height: 8),
    SelectableText(
      'mailto:?subject=${Uri.encodeComponent('Defence timer')}'
      '&body=${Uri.encodeComponent(url)}',
    ),
  ];
}
