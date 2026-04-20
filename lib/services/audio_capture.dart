import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../audio_constants.dart';

/// Mikrofony PCM16 akym görnüşinde berýän iň pes derejedäki abstraksiýa.
class AudioCapture {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;

  bool get isRecording => _sub != null;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Ses akymyny açýar. [onFrame] her gelen PCM böleginde çagyrylýar.
  Future<void> start({required void Function(Uint8List pcm) onFrame}) async {
    await stop();
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: AudioConstants.sampleRate,
      numChannels: AudioConstants.channels,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
    ));
    _sub = stream.listen(
      onFrame,
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
}
