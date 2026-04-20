import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/avatars.dart';
import '../services/audio_capture.dart';
import '../services/audio_player.dart';
import '../services/channel_codec.dart';
import '../services/settings.dart';
import '../services/udp_voice.dart';
import 'settings_screen.dart';

class PttScreen extends StatefulWidget {
  final AppSettings settings;
  const PttScreen({super.key, required this.settings});

  @override
  State<PttScreen> createState() => _PttScreenState();
}

enum _Status { idle, transmitting, receiving }

class _Peer {
  final String id;
  String name;
  int avatarIdx;
  DateTime lastSeen;
  _Peer({
    required this.id,
    required this.name,
    required this.avatarIdx,
    required this.lastSeen,
  });
}

const _presenceInterval = Duration(seconds: 3);
const _presenceTimeout = Duration(seconds: 10);

class _PttScreenState extends State<PttScreen> with WidgetsBindingObserver {
  final _udp = UdpVoice();
  final _capture = AudioCapture();
  final _player = AudioPlayer();

  StreamSubscription<IncomingVoice>? _inSub;
  Timer? _rxTimer;
  Timer? _presenceTimer;
  Timer? _cleanupTimer;
  String? _ownIp;
  _Status _status = _Status.idle;
  String? _currentSpeakerId;
  final Map<String, _Peer> _online = {};
  String? _error;
  bool _micPermissionDenied = false;
  bool _starting = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _start();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    _inSub?.cancel();
    _rxTimer?.cancel();
    _presenceTimer?.cancel();
    _cleanupTimer?.cancel();
    _udp.dispose();
    _capture.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        setState(() {
          _micPermissionDenied = true;
          _starting = false;
        });
        return;
      }
      await _player.init();
      final codec = await ChannelCodec.fromChannel(widget.settings.channel);
      await _udp.start(
        port: widget.settings.port,
        codec: codec,
        selfUserId: widget.settings.userId,
      );
      _inSub = _udp.incoming.listen(_onIncoming);
      try {
        final info = NetworkInfo();
        _ownIp = await info.getWifiIP();
      } catch (_) {}

      // Ilkinji presence dessine ugradylýar, soň wagtlaýyn gaýtalanýar.
      _sendPresence();
      _presenceTimer?.cancel();
      _presenceTimer = Timer.periodic(_presenceInterval, (_) => _sendPresence());
      _cleanupTimer?.cancel();
      _cleanupTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final cutoff = DateTime.now().subtract(_presenceTimeout);
        final before = _online.length;
        _online.removeWhere((_, p) => p.lastSeen.isBefore(cutoff));
        final speakerGone = _currentSpeakerId != null &&
            !_online.containsKey(_currentSpeakerId);
        if (mounted && (before != _online.length || speakerGone)) {
          setState(() {
            if (speakerGone) _currentSpeakerId = null;
          });
        }
      });

      if (mounted) {
        setState(() {
          _starting = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _starting = false;
        });
      }
    }
  }

  void _sendPresence() {
    _udp.sendPresence(
      port: widget.settings.port,
      userId: widget.settings.userId,
      name: widget.settings.name,
      avatarIdx: widget.settings.avatarIdx,
    );
  }

  void _onIncoming(IncomingVoice v) {
    // Online sanawyny täzele (her gelen paket — ses hem bolsa, presence hem bolsa).
    final existed = _online.containsKey(v.senderId);
    final peer = _online.putIfAbsent(
      v.senderId,
      () => _Peer(
        id: v.senderId,
        name: v.senderName,
        avatarIdx: v.avatarIdx,
        lastSeen: DateTime.now(),
      ),
    );
    peer
      ..name = v.senderName
      ..avatarIdx = v.avatarIdx
      ..lastSeen = DateTime.now();

    if (v.isPresence) {
      if (!existed && mounted) setState(() {});
      return; // presence-da ses ýok, diňe kimligi täzelendi
    }

    _player.feedPcm(v.pcm);

    if (_status != _Status.transmitting) {
      setState(() {
        _status = _Status.receiving;
        _currentSpeakerId = v.senderId;
      });
    } else if (!existed && mounted) {
      setState(() {}); // täze peer peýda boldy
    }

    _rxTimer?.cancel();
    _rxTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (_status == _Status.receiving) {
        setState(() {
          _status = _Status.idle;
          _currentSpeakerId = null;
        });
      }
    });
  }

  Future<void> _startTx() async {
    if (_status == _Status.transmitting || _starting) return;
    if (widget.settings.vibrate) HapticFeedback.mediumImpact();
    setState(() => _status = _Status.transmitting);
    try {
      await _capture.start(onFrame: (pcm) {
        _udp.sendVoice(
          port: widget.settings.port,
          pcm: pcm,
          userId: widget.settings.userId,
          name: widget.settings.name,
          avatarIdx: widget.settings.avatarIdx,
        );
      });
    } catch (e) {
      setState(() {
        _status = _Status.idle;
        _error = e.toString();
      });
    }
  }

  Future<void> _stopTx() async {
    if (_status != _Status.transmitting) return;
    await _capture.stop();
    await _udp.sendVoice(
      port: widget.settings.port,
      pcm: Uint8List(0),
      userId: widget.settings.userId,
      name: widget.settings.name,
      avatarIdx: widget.settings.avatarIdx,
      endOfTransmission: true,
    );
    if (mounted) setState(() => _status = _Status.idle);
  }

  Future<void> _openSettings() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(settings: widget.settings),
      ),
    );
    if (changed == true) {
      await _inSub?.cancel();
      await _udp.stop();
      _presenceTimer?.cancel();
      _cleanupTimer?.cancel();
      setState(() {
        _starting = true;
        _currentSpeakerId = null;
        _online.clear();
        _status = _Status.idle;
      });
      await _start();
    }
  }

  _Peer? get _currentSpeaker =>
      _currentSpeakerId == null ? null : _online[_currentSpeakerId];

  Color get _statusColor {
    switch (_status) {
      case _Status.transmitting:
        return const Color(0xFFE53935);
      case _Status.receiving:
        final sp = _currentSpeaker;
        return sp != null
            ? Color(Avatars.get(sp.avatarIdx).color)
            : const Color(0xFF43A047);
      case _Status.idle:
        return const Color(0xFF546E7A);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_micPermissionDenied) {
      return Scaffold(
        appBar: AppBar(title: const Text('BBTalk')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.mic_off, size: 80, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text(
                  'Mikrofona rugsat gerek.\nSazlamalardan rugsady açyp gaýtadan açyň.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => openAppSettings(),
                  child: const Text('Sazlamalary aç'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final btnSize = (size.shortestSide * 0.6).clamp(200.0, 360.0);
    final myAvatar = Avatars.get(widget.settings.avatarIdx);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Color(myAvatar.color),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(myAvatar.emoji, style: const TextStyle(fontSize: 18)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.settings.name,
                      style: const TextStyle(fontSize: 16)),
                  Text(
                    '# ${widget.settings.channel}',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            _InfoBar(ownIp: _ownIp, port: widget.settings.port),
            const SizedBox(height: 6),
            _OnlineHeader(online: _online.length + 1),
            _OnlineRow(
              peers: _online.values.toList(),
              speakingId: _currentSpeakerId,
              myAvatarIdx: widget.settings.avatarIdx,
              myName: widget.settings.name,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('⚠ $_error',
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SpeakerBanner(
                      status: _status,
                      speaker: _currentSpeaker,
                      onlineCount: _online.length + 1,
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTapDown: (_) => _startTx(),
                      onTapUp: (_) => _stopTx(),
                      onTapCancel: _stopTx,
                      onLongPressStart: (_) => _startTx(),
                      onLongPressEnd: (_) => _stopTx(),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: btnSize,
                        height: btnSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _statusColor,
                          boxShadow: [
                            BoxShadow(
                              color: _statusColor.withValues(alpha: 0.5),
                              blurRadius: _status == _Status.idle ? 16 : 40,
                              spreadRadius: _status == _Status.idle ? 2 : 8,
                            ),
                          ],
                        ),
                        child: Center(
                          child: _status == _Status.receiving &&
                                  _currentSpeaker != null
                              ? Text(
                                  Avatars.get(_currentSpeaker!.avatarIdx).emoji,
                                  style: TextStyle(fontSize: btnSize * 0.5),
                                )
                              : Icon(
                                  _status == _Status.transmitting
                                      ? Icons.mic
                                      : Icons.radio_button_checked,
                                  color: Colors.white,
                                  size: btnSize * 0.45,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _status == _Status.transmitting
                          ? 'GEPLEÝÄR — goýber → dine'
                          : 'Basyp sakla → gürle',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: _status == _Status.transmitting
                            ? const Color(0xFFE53935)
                            : Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBar extends StatelessWidget {
  final String? ownIp;
  final int port;
  const _InfoBar({required this.ownIp, required this.port});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi, size: 16, color: Colors.black54),
          const SizedBox(width: 6),
          Text(
            ownIp ?? (Platform.isIOS ? 'Wi-Fi barla' : '—'),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const Spacer(),
          Icon(Icons.lock, size: 14, color: Colors.green.shade700),
          const SizedBox(width: 4),
          const Text(
            'şifrelenen',
            style: TextStyle(fontSize: 11, color: Colors.black45),
          ),
          const SizedBox(width: 10),
          Text(
            ':$port',
            style: const TextStyle(
                fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SpeakerBanner extends StatelessWidget {
  final _Status status;
  final _Peer? speaker;
  final int onlineCount; // özümizi goşup
  const _SpeakerBanner({
    required this.status,
    required this.speaker,
    required this.onlineCount,
  });

  @override
  Widget build(BuildContext context) {
    if (status == _Status.receiving && speaker != null) {
      final a = Avatars.get(speaker!.avatarIdx);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Color(a.color).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Color(a.color), width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(a.emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Text(
              speaker!.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(a.color),
              ),
            ),
            const SizedBox(width: 8),
            const Text('🔊', style: TextStyle(fontSize: 18)),
          ],
        ),
      );
    }
    final txt = status == _Status.transmitting
        ? '🎙 Sen gepleýärsiň'
        : (onlineCount <= 1
            ? 'Başga hiç kim ýok — garaşylýar'
            : '$onlineCount adam online — hiç kim gepleýänok');
    return Text(
      txt,
      style: TextStyle(
        fontSize: 15,
        color: Colors.black.withValues(alpha: 0.6),
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _OnlineHeader extends StatelessWidget {
  final int online;
  const _OnlineHeader({required this.online});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF43A047),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'KANALDA $online ADAM',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kanaldaky ähli online ulanyjylaryň avatarlary.
/// Häzir gepleýäniň daşynda pulsing halka emele getirýär.
class _OnlineRow extends StatelessWidget {
  final List<_Peer> peers;
  final String? speakingId;
  final int myAvatarIdx;
  final String myName;
  const _OnlineRow({
    required this.peers,
    required this.speakingId,
    required this.myAvatarIdx,
    required this.myName,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...peers]..sort((a, b) => a.name.compareTo(b.name));
    return SizedBox(
      height: 78,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _OnlineChip(
            emoji: Avatars.get(myAvatarIdx).emoji,
            color: Avatars.get(myAvatarIdx).color,
            name: '$myName (sen)',
            speaking: false,
            dim: true,
          ),
          const SizedBox(width: 8),
          if (sorted.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22, horizontal: 8),
              child: Text(
                'Başga hiç kim ýok',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
            )
          else
            for (final p in sorted) ...[
              _OnlineChip(
                emoji: Avatars.get(p.avatarIdx).emoji,
                color: Avatars.get(p.avatarIdx).color,
                name: p.name,
                speaking: p.id == speakingId,
                dim: false,
              ),
              const SizedBox(width: 8),
            ],
        ],
      ),
    );
  }
}

class _OnlineChip extends StatelessWidget {
  final String emoji;
  final int color;
  final String name;
  final bool speaking;
  final bool dim;
  const _OnlineChip({
    required this.emoji,
    required this.color,
    required this.name,
    required this.speaking,
    required this.dim,
  });

  @override
  Widget build(BuildContext context) {
    final c = Color(color);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: dim ? c.withValues(alpha: 0.45) : c,
            shape: BoxShape.circle,
            border: Border.all(
              color: speaking ? const Color(0xFF43A047) : Colors.transparent,
              width: 3,
            ),
            boxShadow: speaking
                ? [
                    BoxShadow(
                      color: const Color(0xFF43A047).withValues(alpha: 0.55),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(emoji, style: const TextStyle(fontSize: 26)),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 68,
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: speaking ? FontWeight.w700 : FontWeight.w500,
              color: speaking ? const Color(0xFF2E7D32) : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
