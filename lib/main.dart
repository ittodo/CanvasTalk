import "package:flutter/material.dart";

import "src/app_shell.dart";
import "src/state/app_controller.dart";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CanvasTalkApp());
}

class CanvasTalkApp extends StatefulWidget {
  const CanvasTalkApp({super.key});

  @override
  State<CanvasTalkApp> createState() => _CanvasTalkAppState();
}

class _CanvasTalkAppState extends State<CanvasTalkApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "CanvasTalk",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A7A57)),
      ),
      home: AppShell(controller: _controller),
    );
  }
}
