import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'admin.dart';
import 'phase.dart';
import 'session.dart';
import 'sync.dart';
import 'wheel.dart';

void main() {
  // Route by URL fragment: /admin opens the admin page, /host/<edit>[/<notes>]
  // [/<read>] drives the host, /view/<read> a mirror of it; anything else is
  // the standalone timer (no Sync). parseRoute rejects a non-alphanumeric
  // token segment and falls back to standalone for the whole route.
  final parsed = parseRoute(Uri.base.fragment);
  runApp(
    MaterialApp(
      title: 'Defence Timer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: parsed.role == 'admin'
          ? const AdminPage()
          : TimerPage(
              sync: parsed.tokens.isNotEmpty ? Sync(parsed.tokens[0]) : null,
              notesSync: parsed.tokens.length > 1
                  ? Sync(parsed.tokens[1])
                  : null,
              readToken: parsed.tokens.length > 2 ? parsed.tokens[2] : null,
              viewer: parsed.role == 'viewer',
            ),
    ),
  );
}

class TimerPage extends StatefulWidget {
  const TimerPage({
    super.key,
    this.sync,
    this.notesSync,
    this.readToken,
    this.viewer = false,
  });

  /// Null for the standalone timer; set for host (push) and viewer (mirror).
  final Sync? sync;

  /// Null unless the host URL carries a second notes share token.
  final Sync? notesSync;

  /// The read-only (viewer) share token when the host URL carried a third
  /// segment; the viewer URL uses this in preference to the edit token.
  final String? readToken;

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
  Timer? _notesTimer; // host: 2s debounce before writing notes
  Timer? _repaint; // sync mode: repaint so overlays follow the server clock
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

  final _rosterCtl = TextEditingController();
  final _notesCtl = TextEditingController();
  List<Group> _groups = [];
  int _gi = 0; // current group index
  int _si = 0; // current student index within the group
  bool _finished = false; // past the last group's last student
  Map<String, String> _notes = {}; // group name -> note text
  int? _startDelta; // host: start +/- minutes for the current student

  // Roulette and break both live only in the snapshot timestamps; every
  // screen derives what to show from them, so no extra state to mirror.
  final TextEditingController _breakCtl = TextEditingController(text: '10');
  int? _spinAtMs; // host: server ms the spin started
  int _spinWinner = 0; // host: group index the wheel stopped on
  int? _breakEndMs; // host: server ms the break ends

  bool get _idle => _end == null && _paused == null;
  Duration get _limit => _inQa ? _qa : _total;

  // The break overlay wins over the wheel when both are live.
  bool get _breakActive => _breakEndMs != null;

  // The wheel is live while its spin+hold window is open and there are enough
  // groups to make a wheel. Everything is derived from [spinAtMs].
  bool get _wheelActive {
    if (_spinAtMs == null || _groups.length < 2) return false;
    final elapsed = widget.sync!.nowMs() - _spinAtMs!;
    return elapsed >= 0 &&
        elapsed <= spinMs.inMilliseconds + holdMs.inMilliseconds;
  }

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

  /// Host only: show a QR (and the URL) a viewer can scan to mirror this timer.
  void _shareLink() {
    final url = Uri.base
        .replace(fragment: '/view/${widget.readToken ?? widget.sync!.token}')
        .toString();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Viewer link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(data: url, backgroundColor: Colors.white, size: 260),
            SelectableText(url),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              _copy(url);
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.content_copy),
            label: const Text('Copy link'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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
      // Parse the roster only before the first student; later starts keep
      // the position that _nextStudent advanced to.
      if (_log.isEmpty) {
        _groups = parseRoster(_rosterCtl.text);
        _gi = 0;
        _si = 0;
        _finished = false;
      }
      // First student of a group: record the start offset against its plan.
      _startDelta = _groups.isNotEmpty && _si == 0 && !_finished
          ? startDelta(_groups[_gi].planned, DateTime.now())
          : null;
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
    _log.add(_logLine(_log.length + 1, talk, _total, qa));
    _startDelta = null;
    if (_groups.isNotEmpty) {
      _si++;
      if (_si >= _maxStudents(_groups[_gi])) {
        _gi++;
        _si = 0;
      }
      // Past the last group's last student: stay idle, show 'All done'.
      if (_gi >= _groups.length) {
        _finished = true;
        _gi = _groups.length - 1;
        _si = _maxStudents(_groups[_gi]) - 1;
      }
    }
    _reset();
  }

  /// At least one so a group with no listed students still counts as one slot.
  int _maxStudents(Group g) => g.students.isEmpty ? 1 : g.students.length;

  /// The current student's name within [group], or 'Student #n' when the roster
  /// listed fewer students than are being presented.
  String _studentNameInGroup() {
    if (_groups.isEmpty) return 'Student #${_log.length + 1}';
    final group = _groups[_gi];
    return (_si >= 0 && _si < group.students.length)
        ? group.students[_si]
        : 'Student #${_log.length + 1}';
  }

  /// The host's log line, prefixed with `'<group> · <student>'` when a roster
  /// is loaded, with the start offset appended for the group's first student.
  String _logLine(int num, Duration talk, Duration total, Duration qa) {
    final base = logLine(num, talk, total, qa);
    if (_groups.isEmpty) return base;
    final group = _groups[_gi];
    final line = '${group.name} · $_studentNameInGroup()  $base';
    final d = _startDelta;
    if (d == null) return line;
    if (d == 0) return '$line start on time';
    return d > 0 ? '$line start +$d min' : '$line start -${-d} min';
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
    _ensureRepaint(); // back to 250 ms now that the wheel is done
    _push();
  }

  /// Repaint periodically while sync is active so the overlays follow the
  /// server clock. Faster while the wheel spins, so its animation stays smooth.
  void _ensureRepaint() {
    if (widget.sync == null) return;
    final interval = _spinAtMs != null
        ? const Duration(milliseconds: 50)
        : const Duration(milliseconds: 250);
    _repaint?.cancel();
    _repaint = Timer.periodic(interval, (_) => setState(() {}));
  }

  /// Host: spin the roulette. Picks a random winner, stamps the start, and
  /// pushes the snapshot; the wheel animates from the timestamps everywhere.
  void _spin() {
    if (!_idle || _groups.length < 2) return;
    _spinWinner = Random().nextInt(_groups.length);
    _spinAtMs = widget.sync!.nowMs();
    _gi = _spinWinner;
    _si = 0;
    _push();
    _ensureRepaint();
  }

  /// Host: offer to start a break via a minutes dialog.
  void _breakDialog() {
    if (!_idle) return;
    _breakCtl.text = '10';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Break'),
        content: _field(_breakCtl, 'Break length'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              _breakStart();
              Navigator.of(context).pop();
            },
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  /// Host: set the break's end timestamp and push it.
  void _breakStart() {
    if (!_idle) return;
    final minutes = _minutes(_breakCtl.text);
    if (minutes == null) {
      _snack('Check the break time');
      return;
    }
    _breakEndMs = widget.sync!.nowMs() + minutes.inMilliseconds;
    _push();
    _ensureRepaint();
  }

  /// Host: end the break so the overlay disappears everywhere.
  void _endBreak() {
    _breakEndMs = null;
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
      groups: List<Group>.from(_groups),
      gi: _gi,
      finished: _finished,
      si: _si,
      spinAtMs: _spinAtMs,
      spinWinner: _spinWinner,
      breakEndMs: _breakEndMs,
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
      _restore(); // host: learn the server clock offset and resume a reloaded session
      _loadNotes(); // host: load notes for the current share
    }
    _ensureRepaint(); // repaint so overlays follow the server clock
  }

  /// Host only: after a page reload, resume from the last pushed snapshot so the
  /// roster, position, log and running timer survive. Skipped when the share is
  /// empty or the host already started something while the request was in flight.
  Future<void> _restore() async {
    final s = await widget.sync?.poll(); // also sets the server clock offset
    if (s == null || s.totalMs <= 0 || !mounted) return;
    if (!_idle || _log.isNotEmpty || _groups.isNotEmpty) return;
    setState(() {
      _total = Duration(milliseconds: s.totalMs);
      _warn = Duration(milliseconds: s.warnMs);
      _qa = Duration(milliseconds: s.qaMs);
      _totalCtl.text = (_total.inSeconds / 60).toString();
      _warnCtl.text = (_warn.inSeconds / 60).toString();
      _qaCtl.text = (_qa.inSeconds / 60).toString();
      _inQa = s.inQa;
      _groups = List<Group>.from(s.groups);
      _gi = s.gi;
      _si = s.si;
      _finished = s.finished;
      _log
        ..clear()
        ..addAll(s.log);
      _spinAtMs = s.spinAtMs;
      _spinWinner = s.spinWinner;
      _breakEndMs = s.breakEndMs;
      _paused = s.pausedMs == null ? null : Duration(milliseconds: s.pausedMs!);
      // shortcut: talk time before a Q&A is not stored, so a reload during Q&A
      // logs it as 0; store it in the snapshot if that matters.
      _talkTaken = Duration.zero;
    });
    if (s.endMs != null) {
      _run(Duration(milliseconds: s.endMs! - widget.sync!.nowMs()));
    }
  }

  /// Host only: decode the notes share (group name -> text) into memory.
  /// Bad JSON is ignored; without a notes token the notes live in memory only.
  Future<void> _loadNotes() async {
    final raw = await widget.notesSync?.getText();
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        setState(() {
          _notes = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        });
      }
    } catch (_) {
      // ignore bad JSON
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
        _groups = List<Group>.from(s.groups);
        _gi = s.gi;
        _finished = s.finished;
        _si = s.si;
        _spinAtMs = s.spinAtMs;
        _spinWinner = s.spinWinner;
        _breakEndMs = s.breakEndMs;
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
    _repaint?.cancel();
    _pushTimer?.cancel();
    _notesTimer?.cancel();
    _blink.dispose();
    _player.dispose();
    _totalCtl.dispose();
    _warnCtl.dispose();
    _qaCtl.dispose();
    _rosterCtl.dispose();
    _notesCtl.dispose();
    _breakCtl.dispose();
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
      SizedBox(
        width: 320,
        child: TextField(
          controller: _rosterCtl,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            labelText: 'Roster (one group per line)',
            helperText: '14:30 Group A: Ana, Rui — time and names optional',
          ),
        ),
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
              onPressed: () => _copy(_fullLog()),
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
    final student = _finished
        ? 'All done'
        : _groups.isEmpty
        ? 'Student #${_log.length + 1}'
        : '${_groups[_gi].name} · ${_studentNameInGroup()}';
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
        // Running: the clock fills the screen. The roulette/break overlays sit
        // on top of all of it while they are live.
        body: _stack(
          (widget.viewer || !_idle)
              ? SizedBox.expand(child: child)
              : Center(child: SingleChildScrollView(child: child)),
        ),
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
                    if (widget.sync != null)
                      TextButton.icon(
                        onPressed: _shareLink,
                        icon: const Icon(Icons.qr_code),
                        label: const Text('Viewer link'),
                      ),
                    if (widget.sync != null)
                      FilledButton.icon(
                        onPressed: (_idle && _groups.length >= 2 && !_finished)
                            ? _spin
                            : null,
                        icon: const Icon(Icons.casino),
                        label: const Text('Spin'),
                      ),
                    if (widget.sync != null)
                      OutlinedButton.icon(
                        onPressed: _idle ? _breakDialog : null,
                        icon: const Icon(Icons.free_breakfast),
                        label: const Text('Break'),
                      ),
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
              if (!widget.viewer && _groups.isNotEmpty) _notesTile(),
            ],
          ),
        ),
      ),
    );
  }

  /// The whole body with the wheel/break overlay on top while either is live.
  Widget _stack(Widget content) {
    final overlays = <Widget>[];
    if (_breakActive) {
      overlays.add(_breakOverlay());
    } else if (_wheelActive) {
      overlays.add(_wheelOverlay());
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        ...overlays.map((o) => Positioned.fill(child: o)),
      ],
    );
  }

  /// The spinning wheel, shown while its spin+hold window is open.
  Widget _wheelOverlay() => Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final elapsed = widget.sync!.nowMs() - _spinAtMs!;
      final spinning = elapsed < spinMs.inMilliseconds;
      return Container(
        color: Colors.black.withValues(alpha: 0.9),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = min(constraints.maxWidth, constraints.maxHeight);
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomPaint(
                    size: Size(side * 0.8, side * 0.8),
                    painter: WheelPainter(
                      labels: _groups.map((g) => g.name).toList(),
                      angle: wheelAngle(
                        _groups.length,
                        _spinWinner,
                        elapsed / spinMs.inMilliseconds,
                      ),
                      colourA: theme.colorScheme.primary,
                      colourB: theme.colorScheme.tertiary,
                    ),
                  ),
                  if (!spinning)
                    Padding(
                      padding: EdgeInsets.only(top: side * 0.08),
                      child: Text(
                        _groups[_spinWinner].name,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: side * 0.1,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );
    },
  );

  /// The break countdown, shown while a break is running. Fills the screen and
  /// turns red once past its end (overtime).
  Widget _breakOverlay() => Builder(
    builder: (context) {
      final remaining = Duration(
        milliseconds: _breakEndMs! - widget.sync!.nowMs(),
      );
      final overtime = remaining <= Duration.zero;
      return Container(
        color: _calm,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = min(constraints.maxWidth, constraints.maxHeight);
            return Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Break',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: side * 0.08,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        FittedBox(
                          child: Text(
                            formatRemaining(remaining),
                            style: TextStyle(
                              color: overtime ? Colors.red : Colors.white,
                              fontSize: side * 0.2,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!widget.viewer)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 40),
                    child: FilledButton.icon(
                      onPressed: _endBreak,
                      icon: const Icon(Icons.stop),
                      label: const Text('End break'),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    },
  );

  /// The host's session log, or nothing when empty. Used standalone and by
  /// viewers (who never see the setup fields or buttons).
  Widget _logBlock() {
    if (_log.isEmpty) return const SizedBox.shrink();
    return Text(_log.join('\n'));
  }

  /// The host's log plus the current group's notes, for 'Copy log'.
  String _fullLog() {
    var text = _log.join('\n');
    if (_groups.isNotEmpty) {
      final group = _groups[_gi];
      final note = _notes[group.name];
      if (note != null && note.isNotEmpty) {
        text = '$text\nNotes (${group.name}): $note';
      }
    }
    return text;
  }

  /// Host-only notes editor: one ExpansionTile bound to the current group's
  /// note. Without a notes token the notes live in memory only.
  Widget _notesTile() {
    final group = _groups[_gi];
    if (_notesCtl.text != (_notes[group.name] ?? '')) {
      _notesCtl.text = _notes[group.name] ?? '';
    }
    return ExpansionTile(
      title: const Text('Notes'),
      children: [
        TextField(
          controller: _notesCtl,
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(labelText: 'Notes for ${group.name}'),
          onChanged: (value) => _onNotesChanged(group.name, value),
        ),
      ],
    );
  }

  /// Host only: remember the current group's note and, debounced 2 s, write the
  /// whole map to the notes share. Without a notes token it stays in memory.
  void _onNotesChanged(String groupName, String value) {
    setState(() => _notes[groupName] = value);
    _notesTimer?.cancel();
    _notesTimer = Timer(const Duration(seconds: 2), () {
      widget.notesSync?.putText(jsonEncode(_notes));
    });
  }
}
