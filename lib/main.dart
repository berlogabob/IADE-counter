import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'phase.dart';

void main() => runApp(
  MaterialApp(
    title: 'Defence Timer',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: const TimerPage(),
  ),
);

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage>
    with SingleTickerProviderStateMixin {
  static const _calm = Color(0xFF10151C);
  static const _amber = Color(0xFFB36B00);
  static const _red = Color(0xFFD00000);

  // Presets come from the page URL (?total=15&warn=1&qa=10); Android has none.
  static String _preset(String key, String fallback) =>
      Uri.base.queryParameters[key] ?? fallback;

  final _totalCtl = TextEditingController(text: _preset('total', '15'));
  final _warnCtl = TextEditingController(text: _preset('warn', '1'));
  final _qaCtl = TextEditingController(text: _preset('qa', '10'));
  final _player = AudioPlayer();
  late final _blink = AnimationController(vsync: this);

  Duration _total = const Duration(minutes: 15);
  Duration _warn = const Duration(minutes: 1);
  Duration _qa = const Duration(minutes: 10);
  DateTime? _end; // set while running
  Duration? _paused; // remaining time while paused
  Phase _phase = Phase.running;
  Timer? _ticker;
  bool _inQa = false;
  bool _silent = false;
  Duration _talkTaken = Duration.zero;
  // ponytail: in memory only, lost when the app closes; persist to a file or
  // shared_preferences if the log must survive a restart.
  final _log = <String>[];

  bool get _idle => _end == null && _paused == null;
  Duration get _limit => _inQa ? _qa : _total;

  // Wall clock, not tick counting: ticks drift and browsers throttle hidden tabs.
  Duration get _remaining =>
      _end?.difference(DateTime.now()) ?? _paused ?? _limit;

  static Duration? _minutes(String text) {
    final m = double.tryParse(text.trim().replaceAll(',', '.'));
    return m == null ? null : Duration(milliseconds: (m * 60000).round());
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _snack('Copied');
  }

  void _start() {
    if (_idle) {
      final total = _minutes(_totalCtl.text);
      final warn = _minutes(_warnCtl.text);
      final qa = _minutes(_qaCtl.text);
      if (total == null ||
          warn == null ||
          qa == null ||
          warn <= Duration.zero ||
          warn >= total ||
          qa < Duration.zero) {
        _snack('Check the times: 0 < warning < total, Q&A 0 or more');
        return;
      }
      _total = total;
      _warn = warn;
      _qa = qa;
    }
    _run(_remaining);
  }

  void _run(Duration remaining) {
    setState(() {
      _end = DateTime.now().add(remaining);
      _paused = null;
    });
    WakelockPlus.enable();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  void _pause() {
    _ticker?.cancel();
    WakelockPlus.disable();
    setState(() {
      _paused = _remaining;
      _end = null;
    });
  }

  void _stopEffects() {
    _player.stop();
    _blink
      ..stop()
      ..value = 0;
    _phase = Phase.running;
  }

  void _startQa() {
    _talkTaken = _total - _remaining;
    _stopEffects();
    _inQa = true;
    _run(_qa);
  }

  void _nextStudent() {
    final talk = _inQa ? _talkTaken : _total - _remaining;
    final qa = _inQa ? _qa - _remaining : Duration.zero;
    _log.add(logLine(_log.length + 1, talk, _total, qa));
    _reset();
  }

  void _reset() {
    _ticker?.cancel();
    WakelockPlus.disable();
    _stopEffects();
    setState(() {
      _end = null;
      _paused = null;
      _inQa = false;
    });
  }

  void _tick() {
    // A warning that is not shorter than the Q&A itself would fire at once.
    final warn = _inQa && _warn >= _qa ? Duration.zero : _warn;
    final phase = phaseFor(_remaining, warn);
    // Effects fire on the transition only, so pause/resume never replays them.
    if (phase != _phase) {
      _phase = phase;
      if (phase == Phase.warning) {
        _alert(
          _silent ? null : 'warn.wav',
          const Duration(milliseconds: 500),
          5,
        );
      } else if (phase == Phase.done) {
        _alert('final.wav', const Duration(milliseconds: 150), 33);
      }
    }
    setState(() {});
  }

  /// Plays [asset] (or vibrates when null) and blinks the background [cycles]
  /// times, then holds the colour.
  void _alert(String? asset, Duration halfPeriod, int cycles) {
    if (asset != null) {
      _player.play(AssetSource(asset));
    } else {
      // One system haptic pulse is easy to miss, so send three.
      for (var i = 0; i < 3; i++) {
        Future.delayed(Duration(milliseconds: 400 * i), HapticFeedback.vibrate);
      }
    }
    _blink.duration = halfPeriod;
    _blink
        .repeat(reverse: true, count: cycles * 2)
        .whenComplete(() => _blink.value = 1);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _blink.dispose();
    _player.dispose();
    _totalCtl.dispose();
    _warnCtl.dispose();
    _qaCtl.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Widget _field(TextEditingController ctl, String label) => SizedBox(
    width: 150,
    child: TextField(
      controller: ctl,
      onChanged: (_) => setState(() {}),
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: 'min'),
    ),
  );

  Widget _setup() => Column(
    children: [
      Wrap(
        spacing: 24,
        alignment: WrapAlignment.center,
        children: [
          _field(_totalCtl, 'Talk time'),
          _field(_warnCtl, 'Warning before end'),
          _field(_qaCtl, 'Q&A time'),
        ],
      ),
      if (kIsWeb)
        TextButton.icon(
          onPressed: () => _copy(
            Uri.base
                .replace(
                  queryParameters: {
                    'total': _totalCtl.text,
                    'warn': _warnCtl.text,
                    'qa': _qaCtl.text,
                  },
                )
                .toString(),
          ),
          icon: const Icon(Icons.link),
          label: const Text('Copy link with these times'),
        )
      else
        SizedBox(
          width: 320,
          child: SwitchListTile(
            title: const Text('Silent warning (vibrate)'),
            value: _silent,
            onChanged: (v) => setState(() => _silent = v),
          ),
        ),
      if (_log.isNotEmpty) ...[
        Text(_log.join('\n')),
        Wrap(
          children: [
            TextButton(
              onPressed: () => _copy(_log.join('\n')),
              child: const Text('Copy log'),
            ),
            TextButton(
              onPressed: () => setState(_log.clear),
              child: const Text('Clear log'),
            ),
          ],
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final time = _idle
        ? formatRemaining(_minutes(_totalCtl.text) ?? _total)
        : formatRemaining(_remaining);
    final student = 'Student #${_log.length + 1}';
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, child) => Scaffold(
        backgroundColor: switch (_phase) {
          Phase.running => _calm,
          Phase.warning => Color.lerp(_calm, _amber, _blink.value),
          Phase.done => Color.lerp(Colors.black, _red, _blink.value),
        },
        body: child,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                _idle ? student : '${_inQa ? 'Q&A' : 'Talk'} · $student',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Expanded(
                child: FittedBox(
                  child: Text(
                    time,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              if (_idle)
                Flexible(child: SingleChildScrollView(child: _setup())),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (_end == null)
                    FilledButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(_idle ? 'Start' : 'Resume'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _pause,
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                    ),
                  if (!_idle) ...[
                    if (!_inQa && _qa > Duration.zero)
                      FilledButton.tonalIcon(
                        onPressed: _startQa,
                        icon: const Icon(Icons.question_answer),
                        label: const Text('Q&A'),
                      )
                    else
                      FilledButton.tonalIcon(
                        onPressed: _nextStudent,
                        icon: const Icon(Icons.skip_next),
                        label: const Text('Next student'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reset'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
