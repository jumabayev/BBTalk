import 'package:flutter/material.dart';

import 'screens/ptt_screen.dart';
import 'services/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(BBTalkApp(settings: settings));
}

class BBTalkApp extends StatelessWidget {
  final AppSettings settings;
  const BBTalkApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BBTalk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE53935),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: PttScreen(settings: settings),
    );
  }
}
