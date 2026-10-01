// Generates assets/warn.wav and assets/final.wav. Run: dart run tool/gen_beeps.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const rate = 44100;

/// One sine tone with a short fade in/out to avoid clicks.
List<int> tone(double hz, double seconds, double amp) {
  final n = (rate * seconds).round();
  final fade = rate * 0.02;
  return List.generate(n, (i) {
    final env = min(1.0, min(i, n - i) / fade);
    return (sin(2 * pi * hz * i / rate) * amp * env * 32767).round();
  });
}

List<int> silence(double seconds) => List.filled((rate * seconds).round(), 0);

void writeWav(String path, List<int> samples) {
  final data = Int16List.fromList(samples).buffer.asUint8List();
  final h = ByteData(44);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      h.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, 36 + data.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little); // PCM
  h.setUint16(22, 1, Endian.little); // mono
  h.setUint32(24, rate, Endian.little);
  h.setUint32(28, rate * 2, Endian.little);
  h.setUint16(32, 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  h.setUint32(40, data.length, Endian.little);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync([...h.buffer.asUint8List(), ...data]);
}

void main() {
  // Gentle: two soft, low notes.
  writeWav('assets/warn.wav', [
    ...tone(660, 0.25, 0.25),
    ...silence(0.08),
    ...tone(880, 0.35, 0.25),
  ]);

  // Final: three groups of three loud beeps.
  final group = [
    for (var i = 0; i < 3; i++) ...[...tone(990, 0.3, 0.9), ...silence(0.15)],
  ];
  writeWav('assets/final.wav', [
    for (var i = 0; i < 3; i++) ...[...group, ...silence(0.5)],
  ]);
}
