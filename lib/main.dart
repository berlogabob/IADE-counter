import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'phase.dart';
import 'session.dart';
import 'sync.dart';

void main() {
  // Route by URL fragment: /host/<token> drives the host, /view/<token> a
  // mirror of it; anything else is today's standalone timer (no Sync).
  final route = Uri.base.fragment;
  final token = route.startsWith('/host/')
      ? route.substring('/host/'.length)
      : route.startsWith('/view/')
      ? route.substring('/view/'.length)
      : null;
  final viewer = route.startsWith('/view/');
  runApp(
    MaterialApp(
      title: 'Defence Timer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: token == null
          ? const TimerPage()
          : TimerPage(sync: Sync(token), viewer: viewer),
    ),
  );
}

class TimerPage extends StatefulWidget {
  const TimerPage({super.key, this.sync, this.viewer = false});

  /// Null for the standalone timer; set for host (push) and viewer (mirror).
  final Sync? sync;

  /// True when mirroring a host's timer rather than running one.
  final bool viewer;

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

  Timer? _sync; // viewer: 1s poll of the host
  Timer? _pushTimer; // host: 5s push while running
  int _rev = -1; // viewer: last snapshot rev applied

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
    _push();
    _pushTimer?.cancel();
    // Push periodically so a viewer recovers mid-run after a refresh.
    _pushTimer = Timer.periodic(const Duration(seconds: 5), (_) => _push());
  }

  void _pause() {
    _ticker?.cancel();
    WakelockPlus.disable();
    _pushTimer?.cancel();
    setState(() {
      _paused = _remaining;
      _end = null;
    });
    _push();
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
    _pushTimer?.cancel();
    _stopEffects();
    setState(() {
      _end = null;
      _paused = null;
      _inQa = false;
    });
    _push();
  }

  /// Serialise the current fields into a [Snapshot] and push it. No-op for a
  /// standalone timer; failures are swallowed so the host keeps running offline.
  void _push() {
    final sync = widget.sync;
    if (sync == null) return;
    final s = Snapshot(
      // ignore: prefer_null_aware_operators - the '?.' form can't carry the '+ offsetMs' addition
      endMs: _end == null ? null : _end!.millisecondsSinceEpoch + sync.offsetMs,
      pausedMs: _paused?.inMilliseconds,
      inQa: _inQa,
      totalMs: _total.inMilliseconds,
      warnMs: _warn.inMilliseconds,
      qaMs: _qa.inMilliseconds,
      student: _log.length + 1,
      log: List<String>.from(_log),
      rev: DateTime.now()
          .millisecondsSinceEpoch, // unique per push, survives host reload
    );
    sync.push(s);
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
  void initState() {
    super.initState();
    if (widget.viewer && widget.sync != null) {
      _startSync();
    } else {
      widget.sync
          ?.poll(); // host: learn the server clock offset before the first push
    }
  }

  /// Viewer: poll the host every second and mirror a new snapshot (rev changed).
  void _startSync() {
    _sync = Timer.periodic(const Duration(seconds: 1), (_) async {
      final s = await widget.sync?.poll();
      if (s == null || s.rev == _rev) return;
      _rev = s.rev;
      setState(() {
        // A new talk/Q&A or a reset ends the previous alert colour and sound.
        if (s.inQa != _inQa || (s.endMs == null && s.pausedMs == null)) {
          _stopEffects();
        }
        _total = Duration(milliseconds: s.totalMs);
        _warn = Duration(milliseconds: s.warnMs);
        _qa = Duration(milliseconds: s.qaMs);
        _inQa = s.inQa;
        _end = s.endMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                s.endMs! - widget.sync!.offsetMs, // server clock -> local clock
              );
        _paused = s.pausedMs == null
            ? null
            : Duration(milliseconds: s.pausedMs!);
        _log
          ..clear()
          ..addAll(s.log);
        if (_end != null || _paused != null) {
          _ticker?.cancel();
          _ticker = Timer.periodic(
            const Duration(milliseconds: 200),
            (_) => _tick(),
          );
          WakelockPlus.enable();
        } else {
          _ticker?.cancel();
          _ticker = null;
          WakelockPlus.disable();
        }
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sync?.cancel();
    _pushTimer?.cancel();
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
    final clock = FittedBox(
      child: Text(
        time,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, child) => Scaffold(
        backgroundColor: switch (_phase) {
          Phase.running => _calm,
          Phase.warning => Color.lerp(_calm, _amber, _blink.value),
          Phase.done => Color.lerp(Colors.black, _red, _blink.value),
        },
        // Setup: one compact block centred both ways, scrolls if it doesn't fit.
        // Running: the clock fills the screen.
        body: (widget.viewer || !_idle)
            ? SizedBox.expand(child: child)
            : Center(child: SingleChildScrollView(child: child)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: (_idle && !widget.viewer)
                ? MainAxisSize.min
                : MainAxisSize.max,
            children: [
              Text(
                _idle ? student : '${_inQa ? 'Q&A' : 'Talk'} · $student',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (widget.viewer || !_idle)
                Expanded(child: clock)
              else
                SizedBox(height: 140, child: clock),
              if (_idle && !widget.viewer) _setup(),
              const SizedBox(height: 16),
              if (widget.viewer) _logBlock(),
              if (!widget.viewer)
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

  /// The host's session log, or nothing when empty. Used standalone and by
  /// viewers (who never see the setup fields or buttons).
  Widget _logBlock() {
    if (_log.isEmpty) return const SizedBox.shrink();
    return Text(_log.join('\n'));
  }
}
