import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import 'sync.dart';

/// "New session": the Worker holds the Nextcloud credentials and makes the
/// share links, so no password is typed or shipped here.
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _days = TextEditingController(text: '3');

  String _status = '';
  bool _busy = false;
  ({String host, String viewer})? _result;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _status = '';
    });
    try {
      final days = int.tryParse(_days.text.trim());
      if (days == null || days < 1 || days > 30) {
        _status = 'Expiry in days must be a whole number between 1 and 30.';
        return;
      }
      final r = await http.post(Uri.parse('${Sync.worker}/new?days=$days'));
      final body = jsonDecode(r.body);
      if (r.statusCode != 200 || body is! Map || body['edit'] is! String) {
        _status =
            'Could not create the session: ${body is Map ? body['error'] : r.statusCode}';
        return;
      }
      final base = Uri.base
          .replace(fragment: '', query: '')
          .toString()
          .replaceAll('#', '');
      _result = (
        host: '$base#/host/${body['edit']}/${body['notes']}/${body['read']}',
        viewer: '$base#/view/${body['read']}',
      );
      _status = '';
    } catch (_) {
      _status = 'Something went wrong. Check the connection and try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
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
      appBar: AppBar(title: const Text('New session')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _days,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Links expire after (days)',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _create,
                  child: Text(_busy ? 'Working…' : 'Create session'),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  _status,
                  style: TextStyle(color: Colors.red[700]),
                ),
                if (_result != null) ...[
                  const SizedBox(height: 24),
                  ..._links(
                    _result!.host,
                    'Host link (you and other professors: controls and notes)',
                  ),
                  const SizedBox(height: 16),
                  ..._links(
                    _result!.viewer,
                    'Viewer link (students, projector)',
                  ),
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
    Wrap(
      spacing: 8,
      children: [
        TextButton.icon(
          onPressed: () => _copy(url),
          icon: const Icon(Icons.copy),
          label: const Text('Copy'),
        ),
      ],
    ),
    const SizedBox(height: 8),
    QrImageView(data: url, size: 200, backgroundColor: Colors.white),
  ];
}
