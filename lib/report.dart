import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'session.dart';
import 'sync.dart';

/// Read-only summary of a session: timetable, professors, and every team with
/// its scores and notes. The Worker gathers all notes files behind one token.
class ReportPage extends StatefulWidget {
  const ReportPage({super.key, required this.token});
  final String token;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  Map<String, dynamic>? _data;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = '');
    try {
      final r = await http.get(
        Uri.parse('${Sync.worker}/report?t=${widget.token}'),
      );
      final body = jsonDecode(r.body);
      if (r.statusCode != 200 || body is! Map<String, dynamic>) {
        throw '${body is Map ? body['error'] : r.statusCode}';
      }
      setState(() => _data = body);
    } catch (e) {
      setState(() => _error = 'Could not load the report: $e');
    }
  }

  /// The whole report as plain text, for email and archive.
  String _text() {
    final d = _data!;
    final state = Snapshot.fromJson(d['state'] as Map<String, dynamic>);
    final notes = (d['notes'] as List).cast<Map<String, dynamic>>();
    final b = StringBuffer('SESSION REPORT\n\nTIMETABLE\n');
    b.writeln(
      state.log.isEmpty ? 'No presentation finished.' : state.log.join('\n'),
    );
    b.writeln('\nPROFESSORS\n${(d['professors'] as List).join(', ')}');
    for (var i = 0; i < state.groups.length; i++) {
      final name = state.groups[i].name;
      b.writeln(
        '\nTEAM: $name${state.done.contains(i) ? '' : ' (not presented)'}',
      );
      for (final n in notes) {
        final score = '${n['_score:$name'] ?? ''}';
        final text = '${n[name] ?? ''}'.trim();
        if (score.isEmpty && text.isEmpty) continue;
        b.writeln(
          '- ${n['_professor'] ?? 'Professor'}: ${score.isEmpty ? '-' : score}  $text',
        );
      }
    }
    return b.toString();
  }

  /// Host: copy the full text and open the mail app (optional address). The
  /// mail body holds as much as a mailto link safely carries.
  Future<void> _email() async {
    final to = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Email the report to yourself'),
        content: TextField(
          controller: to,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Your email (optional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Open mail'),
          ),
        ],
      ),
    );
    final address = to.text.trim();
    to.dispose();
    if (ok != true) return;
    final text = _text();
    await Clipboard.setData(ClipboardData(text: text));
    final body = text.length > 1500
        ? '${text.substring(0, 1500)}\n...\n(Full report is on your clipboard: paste it here.)'
        : text;
    // Uri(queryParameters) writes spaces as '+', which mail apps show literally.
    await launchUrl(
      Uri.parse(
        'mailto:${Uri.encodeComponent(address)}'
        '?subject=${Uri.encodeComponent('Session report')}'
        '&body=${Uri.encodeComponent(body)}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final theme = Theme.of(context);
    Widget body;
    if (d == null) {
      body = Center(
        child: _error.isEmpty
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText(_error),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
      );
    } else {
      final state = Snapshot.fromJson(d['state'] as Map<String, dynamic>);
      final notes = (d['notes'] as List).cast<Map<String, dynamic>>();
      final profs = (d['professors'] as List).map((e) => '$e').toList();
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Timetable', style: theme.textTheme.titleLarge),
          if (state.log.isEmpty) const Text('No presentation finished yet.'),
          for (final l in state.log) Text(l),
          const SizedBox(height: 24),
          Text(
            'Professors (${profs.length})',
            style: theme.textTheme.titleLarge,
          ),
          Text(profs.isEmpty ? 'Nobody joined.' : profs.join(', ')),
          const SizedBox(height: 24),
          Text(
            'Teams (${state.done.length} of ${state.groups.length} done)',
            style: theme.textTheme.titleLarge,
          ),
          for (var i = 0; i < state.groups.length; i++)
            _team(state.groups[i].name, state.done.contains(i), notes),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session report'),
        actions: [
          if (d != null)
            IconButton(
              tooltip: 'Email me this report',
              onPressed: _email,
              icon: const Icon(Icons.email),
            ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: body,
        ),
      ),
    );
  }

  Widget _team(String name, bool done, List<Map<String, dynamic>> notes) {
    final rows = <Widget>[];
    final scores = <int>[];
    for (final n in notes) {
      final score = int.tryParse('${n['_score:$name'] ?? ''}');
      final text = '${n[name] ?? ''}'.trim();
      if (score == null && text.isEmpty) continue;
      if (score != null) scores.add(score);
      rows.add(
        Text('${n['_professor'] ?? 'Professor'}: ${score ?? '-'}  $text'),
      );
    }
    final avg = scores.isEmpty
        ? ''
        : ' · average ${(scores.reduce((a, b) => a + b) / scores.length).toStringAsFixed(1)}';
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$name${done ? '' : ' (not presented)'}$avg',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ...rows,
          ],
        ),
      ),
    );
  }
}
