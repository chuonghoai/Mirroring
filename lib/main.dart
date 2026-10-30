import 'package:flutter/material.dart';
import 'ui/controllers/mirroring_controller.dart';
import 'ui/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MirroringApp());
}

class MirroringApp extends StatefulWidget {
  const MirroringApp({super.key});

  @override
  State<MirroringApp> createState() => _MirroringAppState();
}

class _MirroringAppState extends State<MirroringApp> with WidgetsBindingObserver {
  late final MirroringController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MirroringController();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _controller.cleanup();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mirroring',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFF2563EB),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorSchemeSeed: const Color(0xFF3B82F6),
        fontFamily: 'Segoe UI',
      ),
      home: HomeScreen(controller: _controller),
    );
  }
}
