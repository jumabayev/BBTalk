import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Kanal adyndan çykýan AES-256-GCM açar bilen paketleri şifreleýän/açýan ulgam.
/// Başga kanaldaky paket awtomatiki usulda ret edilýär (MAC barlagy geçenok).
class ChannelCodec {
  final AesGcm _aes;
  final SecretKey _key;

  ChannelCodec._(this._aes, this._key);

  static Future<ChannelCodec> fromChannel(String channel) async {
    final data = utf8.encode('$channel|BBTalk-v1');
    final hash = await Sha256().hash(data);
    return ChannelCodec._(AesGcm.with256bits(), SecretKey(hash.bytes));
  }

  /// Şifrelenen giriş + 16 baýtlyk tag bir baýt-massiwinde gaýdýar.
  Future<Uint8List> encrypt({
    required List<int> plaintext,
    required List<int> aad,
    required List<int> nonce,
  }) async {
    final box = await _aes.encrypt(
      plaintext,
      secretKey: _key,
      nonce: nonce,
      aad: aad,
    );
    final cipher = box.cipherText;
    final tag = box.mac.bytes;
    final out = Uint8List(cipher.length + tag.length);
    out.setRange(0, cipher.length, cipher);
    out.setRange(cipher.length, out.length, tag);
    return out;
  }

  /// cipher+tag birlikde kabul edýär. Täsiz paket bolsa null gaýtarýar.
  Future<Uint8List?> decrypt({
    required Uint8List cipherWithTag,
    required List<int> aad,
    required List<int> nonce,
  }) async {
    if (cipherWithTag.length < 16) return null;
    final cipher = cipherWithTag.sublist(0, cipherWithTag.length - 16);
    final tag = cipherWithTag.sublist(cipherWithTag.length - 16);
    try {
      final box = SecretBox(cipher, nonce: nonce, mac: Mac(tag));
      final pt = await _aes.decrypt(box, secretKey: _key, aad: aad);
      return Uint8List.fromList(pt);
    } catch (_) {
      return null;
    }
  }
}
