// Reproduces niraN/lib/core/desktop_feedback.dart's existing 80 ms softCue.
// The Windows notification recording is deliberately not used for navigation.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

void main() {
  const rate = 22050;
  const samples = 1764;
  final data = ByteData(44 + samples * 2);
  final bytes = data.buffer.asUint8List();
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  data.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setRange(8, 16, ascii.encode('WAVEfmt '));
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, ascii.encode('data'));
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    final t = i / rate;
    final attack = math.sin(math.pi / 2 * (t / .004).clamp(0, 1));
    final tail = ((samples - 1 - i) / (rate * .018)).clamp(0.0, 1.0);
    final envelope = attack * attack * math.exp(-t * 52) * tail * tail;
    final phase = 2 * math.pi * (170 * t + 200 / 65 * (1 - math.exp(-65 * t)));
    data.setInt16(
      44 + i * 2,
      (math.sin(phase) * envelope * 5000).round(),
      Endian.little,
    );
  }
  File(
    'android/app/src/main/res/raw/navigation_pop.wav',
  ).writeAsBytesSync(bytes);
}
