/// Mikrofon/dynamik üçin paýlanýan sazlamalar.
class AudioConstants {
  /// 24 kHz — 16 kHz-den has arassa ses, ýöne WhatsApp-dan az bant-ini
  /// ulanýar (~48 KB/s). 48 kHz bolsa has gowy-da bant-ini iki esse edýär,
  /// walkie-talkie üçin gerek däl.
  static const int sampleRate = 24000;
  static const int channels = 1;
  static const int bitsPerSample = 16;

  /// Bir UDP paketinde iberilýän PCM baýt mukdarynyň ýokary çägi.
  /// 1920 baýt = 960 sample = 40 ms ses (24 kHz mono). MTU-dan örän pes,
  /// IP fragmentlenmezligini üpjün edýär. Az-az paket = az jitter.
  static const int maxFramePayload = 1920;

  /// UDP paket başlygy: magic + flags + reserved + seq
  static const int headerSize = 8;
  static const List<int> magic = [0x42, 0x42, 0x54, 0x4B]; // 'BBTK'
}
