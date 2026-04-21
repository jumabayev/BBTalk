import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import '../audio/voice_effects.dart';
import '../audio_constants.dart';

/// Mikrofony PCM16 akym görnüşinde berýän iň pes derejedäki abstraksiýa.
///
/// Goşmaça:
/// • Her paketde RMS dereje hasaplanýar we [onLevel] bilen UI-a ugradylýar
///   (0..1 aralykda — düwmäniň töwereginde galyşyk animasiýa üçin).
/// • Islege görä [VoiceEffectProcessor] bilen göni akymda ses üýtgedilýär.
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
        // int16 göz arkaly PCM-iň üstünden işleýäris (copy ýok).
        final samples = pcm.buffer.asInt16List(
          pcm.offsetInBytes,
          pcm.lengthInBytes ~/ 2,
        );

        final eff = _effect;
        if (eff != null) {
          eff.process(samples, AudioConstants.sampleRate);
        }

        onLevel(_rms(samples));
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

  static double _rms(Int16List s) {
    if (s.isEmpty) return 0;
    double sum = 0;
    for (int i = 0; i < s.length; i++) {
      final v = s[i].toDouble();
      sum += v * v;
    }
    final rms = math.sqrt(sum / s.length) / 32768;
    // Ses RMS-i adatça logarifmik — pes ýerde has diri görkezmek üçin
    // ýumşak kubine galdyrýarys.
    return math.pow(rms.clamp(0, 1), 0.55).toDouble();
  }
}
