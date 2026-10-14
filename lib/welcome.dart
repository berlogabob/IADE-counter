import 'package:flutter/material.dart';

import 'admin.dart';
import 'quick.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF10151C),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Defence Timer',
            style: TextStyle(color: Colors.white, fontSize: 32),
          ),
          const SizedBox(height: 24),
          for (final entry in const [
            ('Quick timer', QuickPage()),
            ('New session', AdminPage()),
          ])
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: 280,
                height: 64,
                child: FilledButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => entry.$2)),
                  child: Text(entry.$1),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
