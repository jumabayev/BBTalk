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

class _Speaker {
  final String id;
  String name;
  int avatarIdx;
  DateTime lastSeen;
  _Speaker({required this.id, required this.name, required this.avatarIdx, required this.lastSeen});
}

class _PttScreenState extends State<PttScreen> with WidgetsBindingObserver {
  final _udp = UdpVoice();
  final _capture = AudioCapture();
  final _player = AudioPlayer();

  StreamSubscription<IncomingVoice>? _inSub;
  Timer? _rxTimer;
  String? _ownIp;
  _Status _status = _Status.idle;
  _Speaker? _currentSpeaker;
  final Map<String, _Speaker> _recentSpeakers = {};
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

  void _onIncoming(IncomingVoice v) {
    _player.feedPcm(v.pcm);
    final sp = _recentSpeakers.putIfAbsent(
      v.senderId,
      () => _Speaker(
        id: v.senderId,
        name: v.senderName,
        avatarIdx: v.avatarIdx,
        lastSeen: DateTime.now(),
      ),
    );
    sp
      ..name = v.senderName
      ..avatarIdx = v.avatarIdx
      ..lastSeen = DateTime.now();

    if (_status != _Status.transmitting) {
      setState(() {
        _status = _Status.receiving;
        _currentSpeaker = sp;
      });
    }
    _rxTimer?.cancel();
    _rxTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (_status == _Status.receiving) {
        setState(() {
          _status = _Status.idle;
          _currentSpeaker = null;
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
      setState(() {
        _starting = true;
        _currentSpeaker = null;
        _status = _Status.idle;
      });
      await _start();
    }
  }

  Color get _statusColor {
    switch (_status) {
      case _Status.transmitting:
        return const Color(0xFFE53935);
      case _Status.receiving:
        return _currentSpeaker != null
            ? Color(Avatars.get(_currentSpeaker!.avatarIdx).color)
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
                    ),
                    const SizedBox(height: 24),
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
  final _Speaker? speaker;
  const _SpeakerBanner({required this.status, required this.speaker});

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
        : 'Diňleýär — hiç kim gepläňok';
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
