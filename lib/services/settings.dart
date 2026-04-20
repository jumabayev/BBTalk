import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/avatars.dart';

/// App sazlamalary. `channel` şifrelemäniň açary; `userId` biziň öýümizde
/// pakediňizi aýyrmak üçin, `name`/`avatarIdx` bolsa başga ulanyjylara
/// görkezmek üçin.
class AppSettings {
  static const _kChannel = 'channel';
  static const _kPort = 'port';
  static const _kName = 'name';
  static const _kAvatar = 'avatarIdx';
  static const _kUserId = 'userId';
  static const _kVibrate = 'vibrate';

  String channel;
  int port;
  String name;
  int avatarIdx;
  final String userId;
  bool vibrate;

  AppSettings({
    required this.channel,
    required this.port,
    required this.name,
    required this.avatarIdx,
    required this.userId,
    required this.vibrate,
  });

  static Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    final rng = Random.secure();

    String userId = p.getString(_kUserId) ?? '';
    if (userId.length != 32) {
      userId = List.generate(
        16,
        (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await p.setString(_kUserId, userId);
    }

    int avatarIdx = p.getInt(_kAvatar) ?? -1;
    if (avatarIdx < 0) {
      avatarIdx = Avatars.random();
      await p.setInt(_kAvatar, avatarIdx);
    }

    String name = (p.getString(_kName) ?? '').trim();
    if (name.isEmpty) {
      name = 'User-${1000 + rng.nextInt(9000)}';
      await p.setString(_kName, name);
    }

    return AppSettings(
      channel: p.getString(_kChannel) ?? 'BBTalk',
      port: p.getInt(_kPort) ?? 9001,
      name: name,
      avatarIdx: avatarIdx,
      userId: userId,
      vibrate: p.getBool(_kVibrate) ?? true,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kChannel, channel.isEmpty ? 'BBTalk' : channel);
    await p.setInt(_kPort, port);
    await p.setString(_kName, name);
    await p.setInt(_kAvatar, avatarIdx);
    await p.setString(_kUserId, userId);
    await p.setBool(_kVibrate, vibrate);
  }
}
