/// Mikrofon/dynamik üçin paýlanýan sazlamalar.
class AudioConstants {
  static const int sampleRate = 16000;
  static const int channels = 1;
  static const int bitsPerSample = 16;

  /// Bir UDP paketinde iberilýän PCM baýt mukdarynyň ýokary çägi.
  /// 1024 baýt = 512 sample = 32 ms ses (16 kHz mono). MTU-dan örän pes,
  /// IP fragmentlenmezligini üpjün edýär.
  static const int maxFramePayload = 1024;

  /// UDP paket başlygy: magic + flags + reserved + seq
  static const int headerSize = 8;
  static const List<int> magic = [0x42, 0x42, 0x54, 0x4B]; // 'BBTK'
}
