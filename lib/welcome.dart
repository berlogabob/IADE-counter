import 'package:flutter/material.dart';

import 'admin.dart';
import 'quick.dart';
import 'theme.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: calmColor,
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
            (
              'Quick timer',
              'One timer on this device. Nothing is saved.',
              QuickPage(),
            ),
            (
              'New session',
              'Teams, draw, notes and scores for professors.',
              AdminPage(),
            ),
          ])
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  SizedBox(
                    width: 280,
                    height: 64,
                    child: FilledButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute<void>(builder: (_) => entry.$3)),
                      child: Text(entry.$1),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 280,
                    child: Text(
                      entry.$2,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
