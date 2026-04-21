import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import '../audio/voice_effects.dart';
import '../audio_constants.dart';

/// Mikrofony PCM16 akym görnüşinde berýän iň pes derejedäki abstraksiýa.
///
/// Goşmaça:
/// • Her paketde RMS dereje hasaplanýar we [onLevel] bilen UI-a ugradylýar.
/// • Islege görä [VoiceEffectProcessor] bilen göni akymda ses üýtgedilýär.
///
/// Zero-copy in-place effekt ulanylanda `asInt16List` view göni PCM baýtlary
/// bilen işleýär. Öz birnäçe Android enjamda `record` paketi Uint8List-i başga
/// buferiň içinde jora däl offset-de goýup bilýär — şol ýagdaý üçin copy+
/// writeback ýoly we doly try/catch bar: her näme bolsa-da asyl PCM sende
/// edilýär, sessiz iýilmäýär.
class AudioCapture {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  VoiceEffectProcessor? _effect;

  bool get isRecording => _sub != null;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<void> start({
    required void Function(Uint8List pcm) onFrame,
    required void Function(double level) onLevel,
    VoiceEffectProcessor? effect,
  }) async {
    await stop();
    _effect = effect;
    _effect?.reset();

    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: AudioConstants.sampleRate,
      numChannels: AudioConstants.channels,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
    ));
    _sub = stream.listen(
      (pcm) {
        if (pcm.isEmpty) {
          onLevel(0);
          onFrame(pcm);
          return;
        }

        final eff = _effect;
        if (eff != null) {
          try {
            _applyEffect(pcm, eff);
          } catch (_) {
            // Effekt näsaz bolsa-da asyl PCM gidýär, sesiň sessiz kesilmeginiň
            // öňi alynýar.
          }
        }

        onLevel(_rms(pcm));
        onFrame(pcm);
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }

  /// Align barlag + fallback bilen effekti goýulýar.
  static void _applyEffect(Uint8List pcm, VoiceEffectProcessor eff) {
    if (pcm.length < 2) return;
    final evenLen = pcm.length & ~1;
    final offset = pcm.offsetInBytes;
    if ((offset & 1) == 0 && (evenLen & 1) == 0) {
      // Zero-copy view — köp ýagdaýda gidýär.
      final view = pcm.buffer.asInt16List(offset, evenLen ~/ 2);
      eff.process(view, AudioConstants.sampleRate);
      return;
    }
    // Align däl: copy → process → writeback.
    final aligned = Uint8List(evenLen);
    aligned.setRange(0, evenLen, pcm);
    final view = aligned.buffer.asInt16List(0, evenLen ~/ 2);
    eff.process(view, AudioConstants.sampleRate);
    pcm.setRange(0, evenLen, aligned);
  }

  /// Alignment-agnostic, aç-açan little-endian RMS.
  static double _rms(Uint8List pcm) {
    if (pcm.length < 2) return 0;
    final count = pcm.length ~/ 2;
    final bd = ByteData.sublistView(pcm);
    double sum = 0;
    for (int i = 0; i < count; i++) {
      final v = bd.getInt16(i * 2, Endian.little).toDouble();
      sum += v * v;
    }
    final rms = math.sqrt(sum / count) / 32768;
    // Pes seslerde hem dýwişli görünsin diýip logarifmik-meňzeş egrilik.
    return math.pow(rms.clamp(0, 1), 0.55).toDouble();
  }
}
