import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'main.dart';
import 'sync.dart';

/// Jury link landing page: the professor types a name, the Worker gives them a
/// notes file of their own, and they continue to the jury screen.
class JoinPage extends StatefulWidget {
  const JoinPage({super.key, required this.juryToken, required this.readToken});

  final String juryToken;
  final String readToken;

  @override
  State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  final _name = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final name = _name.text.trim();
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final r = await http.post(
        Uri.parse(
          '${Sync.worker}/join?t=${widget.juryToken}&name=${Uri.encodeQueryComponent(name)}',
        ),
      );
      final body = jsonDecode(r.body);
      if (r.statusCode != 200 || body is! Map || body['notes'] is! String) {
        _error = body is Map && body['error'] != null
            ? 'Could not join: ${body['error']}'
            : 'Could not join (HTTP ${r.statusCode}).';
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TimerPage(
            sync: Sync(widget.readToken),
            notesSync: Sync(body['notes'] as String),
            readToken: widget.readToken,
            viewer: true,
            professor: name,
          ),
        ),
      );
    } catch (_) {
      _error = 'Something went wrong. Check the connection and try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Jury',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter your name. Your notes are saved in a file of your own.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (_name.text.trim().isNotEmpty && !_busy) _join();
                  },
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Your name',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || _name.text.trim().isEmpty ? null : _join,
                  child: Text(_busy ? 'Joining…' : 'Join'),
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SelectableText(
                    _error,
                    style: TextStyle(color: Colors.red[700]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
