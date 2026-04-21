/// Mikrofon/dynamik üçin paýlanýan sazlamalar.
class AudioConstants {
  /// 16 kHz — ses akymy LAN-da jitter-e has çydamly. 24 kHz-de
  /// her paket 40 ms ses saklap, WiFi jitter-i ortasynda ýitgi aç-açan
  /// eşidilýärdi. Bu aralykda 16 kHz ses hili walkie-talkie üçin kem däl.
  static const int sampleRate = 16000;
  static const int channels = 1;
  static const int bitsPerSample = 16;

  /// 1024 baýt = 512 sample = 32 ms ses (16 kHz mono). MTU-dan örän pes,
  /// IP fragmentlenmezligini üpjün edýär. Az wagt = az boşluk ýitgisinde.
  static const int maxFramePayload = 1024;

  /// UDP paket başlygy: magic + flags + reserved + seq
  static const int headerSize = 8;
  static const List<int> magic = [0x42, 0x42, 0x54, 0x4B]; // 'BBTK'
}
