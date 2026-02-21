import "package:flutter/material.dart";

import "src/app_shell.dart";
import "src/state/app_controller.dart";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AsciiPaintApp());
}

class AsciiPaintApp extends StatefulWidget {
  const AsciiPaintApp({super.key});

  @override
  State<AsciiPaintApp> createState() => _AsciiPaintAppState();
}

class _AsciiPaintAppState extends State<AsciiPaintApp> {
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
      title: "AsciiPaint",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A7A57)),
      ),
      home: AppShell(controller: _controller),
    );
  }
}
