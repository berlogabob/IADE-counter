import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
