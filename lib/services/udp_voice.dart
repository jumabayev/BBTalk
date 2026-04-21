import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../audio_constants.dart';
import 'channel_codec.dart';

/// Başga bir cihazdan gelen paket — ses ýa-da presence heartbeat.
class IncomingVoice {
  final String senderId;
  final String senderName;
  final int avatarIdx;
  final Uint8List pcm;
  final bool endOfTransmission;
  final bool isPresence;

  IncomingVoice({
    required this.senderId,
    required this.senderName,
    required this.avatarIdx,
    required this.pcm,
    required this.endOfTransmission,
    required this.isPresence,
  });
}

/// Paket başlyk flaglary.
class _PktFlags {
  static const int endOfTransmission = 0x01;
  static const int presence = 0x02;
}

/// UDP ýaýlym + AES-GCM şifrelemeli bas-konuş transporty.
///
/// • `reusePort: true` — Android/iOS hot-reload-dan soň "address in use" ýalňyşynyň öňüni alýar.
/// • 255.255.255.255 port broadcast — şol bir LAN-daky ähli BBTalk enjamlaryna ýetirýär.
/// • Şol bir kanaldaky enjamlar üçin şifrelemäniň açary deň gelýär;
///   başga kanal = GCM tag mismatch = paket sessiz taşlanýar.
class UdpVoice {
  RawDatagramSocket? _socket;
  ChannelCodec? _codec;
  final _incoming = StreamController<IncomingVoice>.broadcast();
  int _txSeq = 0;
  final _rng = Random.secure();

  String? _selfUserId;
  InternetAddress _broadcast = InternetAddress('255.255.255.255');

  Stream<IncomingVoice> get incoming => _incoming.stream;
  bool get isBound => _socket != null;
  String get broadcastAddress => _broadcast.address;

  /// Açyk broadcast salgysy — meselem '192.168.1.255'. Boş goýlan bolsa
  /// '255.255.255.255' ulanylýar.
  void setBroadcastAddress(String? address) {
    if (address == null || address.isEmpty) {
      _broadcast = InternetAddress('255.255.255.255');
      return;
    }
    try {
      _broadcast = InternetAddress(address);
    } catch (_) {
      _broadcast = InternetAddress('255.255.255.255');
    }
  }

  Future<void> start({
    required int port,
    required ChannelCodec codec,
    required String selfUserId,
    String? broadcastAddress,
  }) async {
    await stop();
    _codec = codec;
    _selfUserId = selfUserId;
    setBroadcastAddress(broadcastAddress);

    final s = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
      reusePort: _canReusePort(),
    );
    s.broadcastEnabled = true;
    s.readEventsEnabled = true;
    _socket = s;
    s.listen(_onEvent, onError: (_) {}, cancelOnError: false);
  }

  bool _canReusePort() {
    // POSIX platformalarda (Android, iOS, macOS, Linux) goldanýar.
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isLinux;
  }

  Future<void> stop() async {
    final s = _socket;
    _socket = null;
    s?.close();
  }

  Future<void> setCodec(ChannelCodec codec) async {
    _codec = codec;
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final s = _socket;
    if (s == null) return;
    while (true) {
      final pkt = s.receive();
      if (pkt == null) return;
      _handle(pkt);
    }
  }

  Future<void> _handle(Datagram dg) async {
    final data = dg.data;
    if (data.length < 8 + 12 + 16) return; // header+nonce+tag min
    if (data[0] != AudioConstants.magic[0] ||
        data[1] != AudioConstants.magic[1] ||
        data[2] != AudioConstants.magic[2] ||
        data[3] != AudioConstants.magic[3]) {
      return;
    }
    if (data[4] != 2) return; // version
    final flags = data[5];
    final header = data.sublist(0, 8);
    final nonce = data.sublist(8, 20);
    final cipher = data.sublist(20);

    final codec = _codec;
    if (codec == null) return;
    final pt = await codec.decrypt(
      cipherWithTag: cipher,
      aad: header,
      nonce: nonce,
    );
    if (pt == null) return; // başga kanal / bozulan
    if (pt.length < 18) return;

    final senderId = _bytesToHex(pt.sublist(0, 16));
    if (senderId == _selfUserId) return; // öz sesimizi diňlemäýäris

    final nameLen = pt[16];
    if (pt.length < 17 + nameLen + 1) return;
    final name = utf8.decode(pt.sublist(17, 17 + nameLen),
        allowMalformed: true);
    final avatarIdx = pt[17 + nameLen];
    // .sublist çärýek Uint8List-i owrdip berýär — ikinji copy gerek däl.
    final pcm = pt.sublist(18 + nameLen);

    _incoming.add(IncomingVoice(
      senderId: senderId,
      senderName: name,
      avatarIdx: avatarIdx,
      pcm: pcm,
      endOfTransmission: (flags & _PktFlags.endOfTransmission) != 0,
      isPresence: (flags & _PktFlags.presence) != 0,
    ));
  }

  /// PCM böleginiň iberilmegi. Uly PCM bolsa birnäçe UDP paketine bölünýär.
  Future<void> sendVoice({
    required int port,
    required Uint8List pcm,
    required String userId,
    required String name,
    required int avatarIdx,
    bool endOfTransmission = false,
  }) async {
    final s = _socket;
    final codec = _codec;
    if (s == null || codec == null) return;

    final userIdBytes = _hexToBytes(userId);
    if (userIdBytes.length != 16) return;

    final safeName = name.length > 63 ? name.substring(0, 63) : name;
    final nameBytes = utf8.encode(safeName);
    if (nameBytes.length > 255) return;

    const maxPayload = AudioConstants.maxFramePayload;
    int offset = 0;
    final total = pcm.length;
    final sendAtLeastOnce = total == 0 && endOfTransmission;

    do {
      final chunkLen = (total - offset).clamp(0, maxPayload);
      final isLast = offset + chunkLen >= total;
      final flags =
          (endOfTransmission && isLast) ? _PktFlags.endOfTransmission : 0;
      final seq = (_txSeq++) & 0xFFFF;

      final plaintext = Uint8List(
        16 + 1 + nameBytes.length + 1 + chunkLen,
      );
      plaintext.setRange(0, 16, userIdBytes);
      plaintext[16] = nameBytes.length;
      plaintext.setRange(17, 17 + nameBytes.length, nameBytes);
      plaintext[17 + nameBytes.length] = avatarIdx & 0xFF;
      if (chunkLen > 0) {
        plaintext.setRange(
          18 + nameBytes.length,
          plaintext.length,
          pcm,
          offset,
        );
      }

      final nonce = Uint8List.fromList(
        List<int>.generate(12, (_) => _rng.nextInt(256)),
      );

      final header = Uint8List(8);
      header[0] = AudioConstants.magic[0];
      header[1] = AudioConstants.magic[1];
      header[2] = AudioConstants.magic[2];
      header[3] = AudioConstants.magic[3];
      header[4] = 2;
      header[5] = flags;
      header[6] = seq & 0xFF;
      header[7] = (seq >> 8) & 0xFF;

      final cipher = await codec.encrypt(
        plaintext: plaintext,
        aad: header,
        nonce: nonce,
      );

      final pkt = Uint8List(8 + 12 + cipher.length);
      pkt.setRange(0, 8, header);
      pkt.setRange(8, 20, nonce);
      pkt.setRange(20, pkt.length, cipher);

      s.send(pkt, _broadcast, port);

      offset += chunkLen;
      if (sendAtLeastOnce) break;
    } while (offset < total);
  }

  /// Kanalda "men bardan" diýip bir paket iberýär (ses ýok, diňe kimligim).
  Future<void> sendPresence({
    required int port,
    required String userId,
    required String name,
    required int avatarIdx,
  }) async {
    final s = _socket;
    final codec = _codec;
    if (s == null || codec == null) return;

    final userIdBytes = _hexToBytes(userId);
    if (userIdBytes.length != 16) return;

    final safeName = name.length > 63 ? name.substring(0, 63) : name;
    final nameBytes = utf8.encode(safeName);
    if (nameBytes.length > 255) return;

    final plaintext = Uint8List(16 + 1 + nameBytes.length + 1);
    plaintext.setRange(0, 16, userIdBytes);
    plaintext[16] = nameBytes.length;
    plaintext.setRange(17, 17 + nameBytes.length, nameBytes);
    plaintext[17 + nameBytes.length] = avatarIdx & 0xFF;

    final nonce = Uint8List.fromList(
      List<int>.generate(12, (_) => _rng.nextInt(256)),
    );

    final seq = (_txSeq++) & 0xFFFF;
    final header = Uint8List(8);
    header[0] = AudioConstants.magic[0];
    header[1] = AudioConstants.magic[1];
    header[2] = AudioConstants.magic[2];
    header[3] = AudioConstants.magic[3];
    header[4] = 2;
    header[5] = _PktFlags.presence;
    header[6] = seq & 0xFF;
    header[7] = (seq >> 8) & 0xFF;

    final cipher = await codec.encrypt(
      plaintext: plaintext,
      aad: header,
      nonce: nonce,
    );

    final pkt = Uint8List(8 + 12 + cipher.length);
    pkt.setRange(0, 8, header);
    pkt.setRange(8, 20, nonce);
    pkt.setRange(20, pkt.length, cipher);

    s.send(pkt, _broadcast, port);
  }

  Future<void> dispose() async {
    await stop();
    await _incoming.close();
  }

  // --- helpers ---
  static String _bytesToHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static Uint8List _hexToBytes(String hex) {
    if (hex.length.isOdd) return Uint8List(0);
    final out = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}
