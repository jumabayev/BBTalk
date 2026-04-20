import 'dart:typed_data';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

import '../audio_constants.dart';

/// Gelýän PCM-i dynamige feed edip duran ýönekeý jitter-buferli pleýer.
class AudioPlayer {
  bool _setupDone = false;

  Future<void> init() async {
    if (_setupDone) return;
    await FlutterPcmSound.setLogLevel(LogLevel.error);
    // playAndRecord — mikrofon bilen deňzaman işlemäge rugsat berýär.
    await FlutterPcmSound.setup(
      sampleRate: AudioConstants.sampleRate,
      channelCount: AudioConstants.channels,
      iosAudioCategory: IosAudioCategory.playAndRecord,
    );
    // Feed callbackini boş goýsak hem bolýar — biz eliň bilen feed edýäris.
    FlutterPcmSound.setFeedCallback((_) {});
    _setupDone = true;
  }

  /// 16-bit PCM (host endian, Android/iOS-da little endian) baýtlary nobata salýar.
  Future<void> feedPcm(Uint8List pcmLe) async {
    if (!_setupDone || pcmLe.isEmpty) return;
    // Record paketi hem PCM16 host endian berýär, şol görnüşde geçýäris.
    final bd = ByteData.view(
      pcmLe.buffer,
      pcmLe.offsetInBytes,
      pcmLe.lengthInBytes,
    );
    await FlutterPcmSound.feed(PcmArrayInt16(bytes: bd));
    FlutterPcmSound.start();
  }

  Future<void> dispose() async {
    if (!_setupDone) return;
    _setupDone = false;
    try {
      await FlutterPcmSound.release();
    } catch (_) {}
  }
}
