import 'package:flutter/material.dart';
import 'ui/controllers/companion_controller.dart';
import 'ui/screens/companion_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MirroringCompanionApp());
}

class MirroringCompanionApp extends StatefulWidget {
  const MirroringCompanionApp({super.key});

  @override
  State<MirroringCompanionApp> createState() => _MirroringCompanionAppState();
}

class _MirroringCompanionAppState extends State<MirroringCompanionApp> {
  late final CompanionController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CompanionController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mirroring',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorSchemeSeed: const Color(0xFF3B82F6),
      ),
      home: CompanionHomeScreen(controller: _controller),
    );
  }
}
