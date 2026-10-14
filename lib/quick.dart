import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'cycle.dart';
import 'phase.dart';
import 'theme.dart';

class QuickPage extends StatefulWidget {
  const QuickPage({super.key});

  @override
  State<QuickPage> createState() => _QuickPageState();
}

class _QuickPageState extends State<QuickPage> {
  static const _labels = ['Setup', 'Presentation', 'Warning', 'Q&A', 'Pack'];
  final _fields = [
    for (final value in ['2', '15', '1', '10', '1'])
      TextEditingController(text: value),
  ];
  Cycle? _cycle;
  Stage _stage = Stage.setup;
  DateTime? _end;
  Duration? _paused;
  Timer? _timer;
  AudioPlayer? _player;
  bool _warned = false;

  Duration get _remaining =>
      _end?.difference(DateTime.now()) ?? _paused ?? Duration.zero;

  Future<void> _sound(String asset) async {
    try {
      await (_player ??= AudioPlayer()).play(AssetSource(asset));
    } catch (_) {
      // The timer still works when audio is unavailable.
    }
  }

  Future<void> _wake(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {
      // Some platforms do not provide a wakelock.
    }
  }

  void _start() {
    final minutes = _fields
        .map((f) => double.tryParse(f.text.trim().replaceAll(',', '.')))
        .toList();
    if (minutes.any((m) => m == null || !m.isFinite || m < 0) ||
        minutes[1]! <= 0 ||
        minutes[2]! <= 0 ||
        minutes[2]! >= minutes[1]!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Check the times: 0 < warning < presentation, others 0 or more',
          ),
        ),
      );
      return;
    }
    final times = minutes
        .map((m) => Duration(milliseconds: (m! * 60000).round()))
        .toList();
    final cycle = Cycle(
      setup: times[0],
      talk: times[1],
      warn: times[2],
      qa: times[3],
      pack: times[4],
    );
    if (cycle.talk <= Duration.zero ||
        cycle.warn <= Duration.zero ||
        cycle.warn >= cycle.talk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Presentation and warning must be at least 1 ms apart'),
        ),
      );
      return;
    }
    _cycle = cycle;
    _stage = cycle.setup == Duration.zero
        ? cycle.next(Stage.pack)
        : Stage.setup;
    _enterStage();
    _run();
  }

  void _enterStage() {
    _warned = false;
    final length = _cycle!.lengthOf(_stage);
    if (_paused != null) {
      _paused = length;
    } else {
      _end = DateTime.now().add(length);
    }
  }

  void _run() {
    _end = DateTime.now().add(_paused ?? _remaining);
    _paused = null;
    _wake(true);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_remaining <= Duration.zero) {
        _sound('final.wav');
        _stage = _cycle!.next(_stage);
        _enterStage();
      }
      if (!_warned && _cycle!.warning(_stage, _remaining)) {
        _warned = true;
        _sound('warn.wav');
      }
      setState(() {});
    });
    setState(() {});
  }

  void _pause() {
    _timer?.cancel();
    _paused = _remaining;
    _end = null;
    _wake(false);
    setState(() {});
  }

  void _stop() {
    _timer?.cancel();
    _wake(false);
    setState(() {
      _cycle = null;
      _end = null;
      _paused = null;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _player?.dispose();
    _wake(false);
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = _cycle != null;
    final warning = running && _cycle!.warning(_stage, _remaining);
    return Scaffold(
      backgroundColor: !running
          ? calmColor
          : warning
          ? warnColor
          : stageColor(_stage.name),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: running
              ? Column(
                  children: [
                    Text(
                      stageLabel(_stage),
                      style: const TextStyle(color: Colors.white, fontSize: 32),
                    ),
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          child: Text(
                            formatRemaining(_remaining),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 240,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 16,
                      children: [
                        FilledButton(
                          onPressed: _paused == null ? _pause : _run,
                          child: Text(_paused == null ? 'Pause' : 'Resume'),
                        ),
                        FilledButton(
                          onPressed: () => setState(() {
                            _stage = _cycle!.next(_stage);
                            _enterStage();
                          }),
                          child: const Text('Next'),
                        ),
                        FilledButton(
                          onPressed: _stop,
                          child: const Text('Stop'),
                        ),
                      ],
                    ),
                  ],
                )
              : Center(
                  child: SingleChildScrollView(
                    child: SizedBox(
                      width: 320,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < _fields.length; i++)
                            TextField(
                              controller: _fields[i],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: _labels[i],
                                suffixText: 'min',
                              ),
                            ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 64,
                            child: FilledButton(
                              onPressed: _start,
                              child: const Text('Start'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
