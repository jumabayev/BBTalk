import 'dart:math' as math;
import 'dart:typed_data';

/// Ses deňze goýulýan hakyky wagtly DSP filtrleri.
/// Hemmesi pure Dart, daşky baglylyk ýok. Paket göwrümi ýa sample rate
/// üýtgewsiz galýar — şonuň üçin göni akymly UDP bas-konuş bilen işleýär.

abstract class VoiceEffectProcessor {
  /// `samples` host-endian int16 PCM. Orny-ornuna üýtgedilýär.
  void process(Int16List samples, int sampleRate);
  void reset();
}

/// Effekt ýok — dodaklanman geçip gidýär.
class _PassThrough extends VoiceEffectProcessor {
  @override
  void process(Int16List samples, int sampleRate) {}
  @override
  void reset() {}
}

/// Ring modulator: sinus bilen göni köpelt → klassiki robot sesi.
class RingModProcessor extends VoiceEffectProcessor {
  final double freq;
  final double depth; // 0..1 — 1 = doly, 0 = asyl ses
  double _phase = 0;
  RingModProcessor({this.freq = 100, this.depth = 1});

  @override
  void process(Int16List samples, int sampleRate) {
    final step = 2 * math.pi * freq / sampleRate;
    final d = depth;
    final inv = 1 - d;
    for (int i = 0; i < samples.length; i++) {
      _phase += step;
      if (_phase > 2 * math.pi) _phase -= 2 * math.pi;
      final mod = math.sin(_phase);
      final v = samples[i] * (inv + d * mod);
      samples[i] = _clip16(v);
    }
  }

  @override
  void reset() {
    _phase = 0;
  }
}

/// "Kosmos" — ring-mod + tremolo (amplituda üýtgemesi).
class AlienProcessor extends VoiceEffectProcessor {
  double _ring = 0;
  double _trem = 0;

  @override
  void process(Int16List samples, int sampleRate) {
    final rs = 2 * math.pi * 55 / sampleRate;
    final ts = 2 * math.pi * 4.5 / sampleRate;
    for (int i = 0; i < samples.length; i++) {
      _ring += rs;
      _trem += ts;
      if (_ring > 2 * math.pi) _ring -= 2 * math.pi;
      if (_trem > 2 * math.pi) _trem -= 2 * math.pi;
      final mod = math.sin(_ring);
      final trem = 0.55 + 0.45 * math.sin(_trem);
      samples[i] = _clip16(samples[i] * mod * trem);
    }
  }

  @override
  void reset() {
    _ring = 0;
    _trem = 0;
  }
}

/// Eho — halka buferli delay + feedback.
class EchoProcessor extends VoiceEffectProcessor {
  final int delayMs;
  final double feedback; // 0..0.9
  final double wet; // 0..1
  Int16List _buf = Int16List(0);
  int _idx = 0;

  EchoProcessor({this.delayMs = 220, this.feedback = 0.38, this.wet = 0.55});

  @override
  void process(Int16List samples, int sampleRate) {
    final need = (sampleRate * delayMs / 1000).round();
    if (_buf.length != need) {
      _buf = Int16List(need);
      _idx = 0;
    }
    for (int i = 0; i < samples.length; i++) {
      final delayed = _buf[_idx];
      final dry = samples[i];
      final out = dry + (delayed * wet).round();
      _buf[_idx] = _clip16(dry + delayed * feedback);
      _idx++;
      if (_idx >= _buf.length) _idx = 0;
      samples[i] = _clip16(out.toDouble());
    }
  }

  @override
  void reset() {
    for (int i = 0; i < _buf.length; i++) {
      _buf[i] = 0;
    }
    _idx = 0;
  }
}

/// Megafon — drive + soft clip + ýönekeý highpass.
class MegaphoneProcessor extends VoiceEffectProcessor {
  final double drive;
  double _hpPrevIn = 0;
  double _hpPrevOut = 0;
  MegaphoneProcessor({this.drive = 2.8});

  @override
  void process(Int16List samples, int sampleRate) {
    // 1-pol highpass ~500 Hz — "teneke" tonallygy berýär.
    final rc = 1.0 / (2 * math.pi * 500);
    final dt = 1.0 / sampleRate;
    final a = rc / (rc + dt);

    for (int i = 0; i < samples.length; i++) {
      final x = samples[i] / 32768.0 * drive;
      final clipped = _softClip(x);
      final y = a * (_hpPrevOut + clipped - _hpPrevIn);
      _hpPrevIn = clipped;
      _hpPrevOut = y;
      samples[i] = _clip16(y * 28000);
    }
  }

  @override
  void reset() {
    _hpPrevIn = 0;
    _hpPrevOut = 0;
  }
}

/// Radio — bandpass 300-3400 Hz + ýumşak drive, stansiýa sesi.
class RadioProcessor extends VoiceEffectProcessor {
  double _lpPrev = 0;
  double _hpPrevIn = 0;
  double _hpPrevOut = 0;

  @override
  void process(Int16List samples, int sampleRate) {
    final lpA = (2 * math.pi * 3000) /
        (2 * math.pi * 3000 + sampleRate.toDouble());
    final rc = 1.0 / (2 * math.pi * 350);
    final dt = 1.0 / sampleRate;
    final hpA = rc / (rc + dt);

    for (int i = 0; i < samples.length; i++) {
      double x = samples[i] / 32768.0;
      // Lowpass (tweeter-siz)
      _lpPrev = _lpPrev + lpA * (x - _lpPrev);
      // Highpass (subsonic aýyr)
      final hp = hpA * (_hpPrevOut + _lpPrev - _hpPrevIn);
      _hpPrevIn = _lpPrev;
      _hpPrevOut = hp;
      // Ýumşak drive
      final y = _softClip(hp * 1.8);
      samples[i] = _clip16(y * 24000);
    }
  }

  @override
  void reset() {
    _lpPrev = 0;
    _hpPrevIn = 0;
    _hpPrevOut = 0;
  }
}

/// Bit-crusher — "kompýuter döwük ses".
class BitCrushProcessor extends VoiceEffectProcessor {
  final int bits; // 4-8 arasy gowy eşidilýär
  BitCrushProcessor({this.bits = 6});

  @override
  void process(Int16List samples, int sampleRate) {
    final steps = 1 << (bits - 1);
    for (int i = 0; i < samples.length; i++) {
      final q = (samples[i] / 32768.0 * steps).round() / steps;
      samples[i] = _clip16(q * 32767);
    }
  }

  @override
  void reset() {}
}

// --- helpers ---

double _softClip(double x) {
  if (x > 1) return 1;
  if (x < -1) return -1;
  return x * (1.5 - 0.5 * x * x);
}

int _clip16(num v) {
  if (v > 32767) return 32767;
  if (v < -32768) return -32768;
  return v.toInt();
}

// --- effekt sanawy UI üçin ---

enum VoiceEffect {
  none('Hiç', '🎤'),
  robot('Robot', '🤖'),
  alien('Kosmos', '👽'),
  echo('Eho', '🎭'),
  megaphone('Megafon', '📢'),
  radio('Stansiýa', '📻'),
  bitcrush('Döwük', '💾');

  final String label;
  final String emoji;
  const VoiceEffect(this.label, this.emoji);

  VoiceEffectProcessor createProcessor() {
    switch (this) {
      case VoiceEffect.none:
        return _PassThrough();
      case VoiceEffect.robot:
        return RingModProcessor(freq: 100);
      case VoiceEffect.alien:
        return AlienProcessor();
      case VoiceEffect.echo:
        return EchoProcessor();
      case VoiceEffect.megaphone:
        return MegaphoneProcessor();
      case VoiceEffect.radio:
        return RadioProcessor();
      case VoiceEffect.bitcrush:
        return BitCrushProcessor();
    }
  }

  static VoiceEffect fromIndex(int idx) {
    if (idx < 0 || idx >= VoiceEffect.values.length) return VoiceEffect.none;
    return VoiceEffect.values[idx];
  }
}
