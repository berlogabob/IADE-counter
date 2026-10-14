import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

// Dart supports this import cycle; open the host without changing WelcomePage.
import 'main.dart';
import 'session.dart';
import 'sync.dart';

/// "New session": the Worker holds the Nextcloud credentials and makes the
/// share links, so no password is typed or shipped here.
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  static const _steps = ['Presenters', 'Timing', 'Invite', 'Start'];
  static const _labels = ['Setup', 'Presentation', 'Warning', 'Q&A', 'Pack'];
  final _roster = TextEditingController();
  final _times = [
    for (final value in ['2', '15', '1', '10', '1'])
      TextEditingController(text: value),
  ];
  int _step = 0;
  late List<String> _tokens;
  final _days = TextEditingController(text: '3');

  String _status = '';
  bool _busy = false;
  ({String host, String jury, String viewer})? _result;

  @override
  void dispose() {
    _roster.dispose();
    for (final field in _times) {
      field.dispose();
    }
    _days.dispose();
    super.dispose();
  }

  List<double?> get _minutes => _times
      .map((f) => double.tryParse(f.text.trim().replaceAll(',', '.')))
      .toList();
  void _next() {
    final m = _minutes;
    if (_step == 1 &&
        (m.any((v) => v == null || !v.isFinite || v < 0) ||
            m[1]! <= 0 ||
            m[2]! <= 0 ||
            m[2]! >= m[1]!)) {
      setState(
        () => _status =
            'Check the times: 0 < warning < presentation, others 0 or more',
      );
      return;
    }
    if (_step == 2 && _result == null) {
      _create();
      return;
    }
    setState(() {
      _status = '';
      _step++;
    });
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
      _tokens = [
        for (final key in ['edit', 'notes', 'read']) body[key] as String,
      ];
      final ms = _minutes.map((v) => (v! * 60000).round()).toList();
      await Sync(_tokens[0]).push(
        Snapshot(
          groups: parseRoster(_roster.text),
          student: 1,
          totalMs: ms[1],
          warnMs: ms[2],
          qaMs: ms[3],
          setupMs: ms[0],
          packMs: ms[4],
        ),
      );
      _result = (
        host: '$base#/host/${body['edit']}/${body['notes']}/${body['read']}',
        jury: '$base#/jury/${body['notes']}/${body['read']}',
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
      appBar: AppBar(title: Text('${_step + 1} of 4 · ${_steps[_step]}')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _busy || _step == 0
                    ? null
                    : () => setState(() {
                        if (_step < 3) _result = null;
                        _status = '';
                        _step--;
                      }),
                child: const Text('Back'),
              ),
              if (_step < 3)
                FilledButton(
                  onPressed:
                      _busy || (_step == 0 && parseRoster(_roster.text).isEmpty)
                      ? null
                      : _next,
                  child: Text(
                    _step == 2 && _result == null ? 'Create session' : 'Next',
                  ),
                ),
            ],
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_step == 0)
                  TextField(
                    controller: _roster,
                    maxLines: 6,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'One name per line (team, group or student)',
                    ),
                  ),
                if (_step == 1)
                  for (var i = 0; i < _times.length; i++)
                    TextField(
                      controller: _times[i],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: '${_labels[i]} (minutes)',
                      ),
                    ),
                if (_step == 2) ...[
                  TextField(
                    controller: _days,
                    enabled: !_busy && _result == null,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Links expire after (days)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_busy) const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 16),
                  if (_result != null) ...[
                    const SizedBox(height: 24),
                    ..._links(
                      _result!.host,
                      'Host link (only you: controls and notes)',
                    ),
                    const Text(
                      'Keep this one to yourself. It starts, skips and stops the session.',
                    ),
                    const SizedBox(height: 16),
                    ..._links(
                      _result!.jury,
                      'Jury link (other professors: follow and write notes)',
                    ),
                    const SizedBox(height: 16),
                    ..._links(
                      _result!.viewer,
                      'Viewer link (students, projector)',
                    ),
                    const Text(
                      'Show this QR on the projector or send it to students',
                    ),
                  ],
                ],
                if (_status.isNotEmpty)
                  SelectableText(
                    _status,
                    style: TextStyle(color: Colors.red[700]),
                  ),
                if (_step == 2 && _status.isNotEmpty)
                  TextButton(
                    onPressed: _busy ? null : _create,
                    child: const Text('Retry'),
                  ),
                if (_step == 3)
                  FilledButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => TimerPage(
                          sync: Sync(_tokens[0]),
                          notesSync: Sync(_tokens[1]),
                          readToken: _tokens[2],
                        ),
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(24),
                    ),
                    child: const Text('Open host screen'),
                  ),
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
