import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// Dart supports this import cycle; open the host without changing WelcomePage.
import 'main.dart';
import 'session.dart';
import 'sync.dart';

/// "New session": the Worker makes the Nextcloud shares, then the host screen
/// opens straight away. Teams, times and links are all set there.
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  String _error = '';

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    setState(() => _error = '');
    try {
      final r = await http.post(Uri.parse('${Sync.worker}/new?days=3'));
      final body = jsonDecode(r.body);
      if (r.statusCode != 200 || body is! Map || body['edit'] is! String) {
        _fail('${body is Map ? body['error'] : r.statusCode}');
        return;
      }
      final edit = body['edit'] as String;
      final notes = body['notes'] as String;
      final read = body['read'] as String;
      final profs = body['profs'] as String;
      final jury = body['jury'] as String;
      await Sync(edit).push(
        const Snapshot(
          student: 1,
          totalMs: 900000,
          warnMs: 60000,
          qaMs: 600000,
          setupMs: 120000,
          packMs: 60000,
        ),
      );
      if (!mounted) return;
      // Put the host route in the address bar so a reload or bookmark returns here.
      SystemNavigator.routeInformationUpdated(
        uri: Uri.parse('/host/$edit/$notes/$read/$profs/$jury'),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TimerPage(
            sync: Sync(edit),
            notesSync: Sync(notes),
            readToken: read,
            profsSync: Sync(profs),
            juryToken: jury,
          ),
        ),
      );
    } catch (_) {
      _fail('Check the connection.');
    }
  }

  void _fail(String why) {
    if (mounted) setState(() => _error = 'Could not create the session: $why');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: _error.isEmpty
          ? const CircularProgressIndicator()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(_error),
                const SizedBox(height: 16),
                FilledButton(onPressed: _create, child: const Text('Try again')),
              ],
            ),
    ),
  );
}
