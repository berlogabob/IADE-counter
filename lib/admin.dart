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
  static const _steps = ['Presenters', 'Timing', 'Share'];
  static const _labels = [
    'Setup',
    'Presentation',
    'Warning before end',
    'Q&A',
    'Pack',
  ];
  final _roster = TextEditingController();
  final _times = [
    for (final value in ['2', '15', '1', '10', '1'])
      TextEditingController(text: value),
  ];
  int _step = 0;
  final _days = TextEditingController(text: '3');

  String _status = '';
  bool _busy = false;
  ({
    String edit,
    String notes,
    String read,
    String jury,
    String profs,
    String base,
  })?
  _made;

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
    if (_step == 2) {
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
      final made = (
        edit: body['edit'] as String,
        notes: body['notes'] as String,
        read: body['read'] as String,
        jury: body['jury'] as String,
        profs: body['profs'] as String,
        base: base,
      );
      final ms = _minutes.map((v) => (v! * 60000).round()).toList();
      await Sync(made.edit).push(
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
      _made = made;
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
    final made = _made;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          made == null
              ? 'Step ${_step + 1} of 3 · ${_steps[_step]}'
              : 'Session ready',
        ),
      ),
      bottomNavigationBar: made != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _busy || _step == 0
                          ? null
                          : () => setState(() {
                              _status = '';
                              _step--;
                            }),
                      child: const Text('Back'),
                    ),
                    FilledButton(
                      onPressed:
                          _busy ||
                              (_step == 0 && parseRoster(_roster.text).isEmpty)
                          ? null
                          : _next,
                      child: Text(_step == 2 ? 'Create session' : 'Next'),
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
                if (made == null && _step == 0) ...[
                  TextField(
                    controller: _roster,
                    minLines: 10,
                    maxLines: 10,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                      labelText: 'Presenters: one name per line',
                      hintText: 'Team A\nTeam B\nTeam C',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${parseRoster(_roster.text).length} presenters',
                    ),
                  ),
                ],
                if (made == null && _step == 1)
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
                if (made == null && _step == 2) ...[
                  TextField(
                    controller: _days,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Links expire after (days)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_busy) const Center(child: CircularProgressIndicator()),
                ],
                if (made != null) ..._share(made),
                if (_status.isNotEmpty)
                  SelectableText(
                    _status,
                    style: TextStyle(color: Colors.red[700]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The three links as three clear cards: host, professors, students.
  List<Widget> _share(
    ({
      String edit,
      String notes,
      String read,
      String jury,
      String profs,
      String base,
    })
    m,
  ) {
    final host = '${m.base}#/host/${m.edit}/${m.notes}/${m.read}/${m.profs}';
    final jury = '${m.base}#/jury/${m.jury}/${m.read}';
    final viewer = '${m.base}#/view/${m.read}';
    return [
      _card(
        'You: host',
        'Runs the session: start, skip, stop, close. Keep this link private.',
        host,
        extra: FilledButton.icon(
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => TimerPage(
                sync: Sync(m.edit),
                notesSync: Sync(m.notes),
                readToken: m.read,
                profsSync: Sync(m.profs),
              ),
            ),
          ),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Open host screen'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
        ),
      ),
      _card(
        'Other professors',
        'One link for all of them. Each enters their name and writes their own notes.',
        jury,
        qr: 170,
      ),
      _card(
        'Students and projector',
        'Read-only: the clock and the draw.',
        viewer,
        qr: 240,
      ),
    ];
  }

  Widget _card(
    String title,
    String hint,
    String url, {
    Widget? extra,
    double? qr,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
          if (extra != null) ...[const SizedBox(height: 12), extra],
          if (qr != null) ...[
            const SizedBox(height: 12),
            Center(
              child: QrImageView(
                data: url,
                size: qr,
                backgroundColor: Colors.white,
              ),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _copy(url),
            icon: const Icon(Icons.copy),
            label: const Text('Copy link'),
          ),
        ],
      ),
    ),
  );
}
