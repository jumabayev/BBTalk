import 'package:flutter/material.dart';

import '../models/avatars.dart';
import '../services/settings.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _channel;
  late TextEditingController _port;
  late TextEditingController _name;
  late int _avatarIdx;
  late bool _vibrate;

  @override
  void initState() {
    super.initState();
    _channel = TextEditingController(text: widget.settings.channel);
    _port = TextEditingController(text: widget.settings.port.toString());
    _name = TextEditingController(text: widget.settings.name);
    _avatarIdx = widget.settings.avatarIdx;
    _vibrate = widget.settings.vibrate;
  }

  @override
  void dispose() {
    _channel.dispose();
    _port.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final port = int.tryParse(_port.text.trim()) ?? 9001;
    final ch = _channel.text.trim();
    widget.settings
      ..channel = ch.isEmpty ? 'BBTalk' : ch
      ..port = port
      ..name = _name.text.trim().isEmpty ? 'User' : _name.text.trim()
      ..avatarIdx = _avatarIdx
      ..vibrate = _vibrate;
    await widget.settings.save();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sazlamalar')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionLabel('KIM BOLJAK'),
          const SizedBox(height: 8),
          _AvatarPicker(
            selected: _avatarIdx,
            onSelect: (i) => setState(() => _avatarIdx = i),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Meniň adym',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            maxLength: 30,
          ),
          const SizedBox(height: 12),
          const _SectionLabel('KANAL (GIZLI SÖZ)'),
          const SizedBox(height: 8),
          TextField(
            controller: _channel,
            decoration: const InputDecoration(
              labelText: 'Kanal ady',
              helperText:
                  'Şol bir kanaldaky ähli enjamlar biri-birini eşidýär. Başga kanaldakylar eşidip bilmeýär.',
              helperMaxLines: 3,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock),
            ),
          ),
          const SizedBox(height: 20),
          ExpansionTile(
            title: const Text('Ösen sazlamalar'),
            childrenPadding: const EdgeInsets.all(8),
            children: [
              TextField(
                controller: _port,
                decoration: const InputDecoration(
                  labelText: 'UDP port',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Basanda yrgyldama'),
                value: _vibrate,
                onChanged: (v) => setState(() => _vibrate = v),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Ýatda sakla'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Colors.black54,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  const _AvatarPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: Avatars.list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final a = Avatars.get(i);
          final isSel = i == selected;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Color(a.color),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSel ? Colors.black : Colors.transparent,
                  width: 3,
                ),
                boxShadow: isSel
                    ? [
                        BoxShadow(
                          color: Color(a.color).withValues(alpha: 0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(a.emoji, style: const TextStyle(fontSize: 32)),
              ),
            ),
          );
        },
      ),
    );
  }
}
