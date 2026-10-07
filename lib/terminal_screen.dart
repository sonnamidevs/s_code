import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import 'package:flutter_pty/flutter_pty.dart';

class TerminalScreen extends StatefulWidget {
  final String? pythonRoot;
  final String? nativeLibDir;

  const TerminalScreen({Key? key, this.pythonRoot, this.nativeLibDir}) : super(key: key);

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final Terminal terminal;
  late final Pty pty;
  late final StreamSubscription<String> _stdoutSub;

  @override
  void initState() {
    super.initState();
    terminal = Terminal(maxLines: 10000);
    pty = Pty.start(
      'sh',
      columns: 80,
      rows: 24,
    );

    _stdoutSub = pty.stdout.transform(utf8.decoder).listen((data) {
      terminal.write(data);
    });

    terminal.onOutput = (data) {
      pty.write(const Utf8Encoder().convert(data));
    };

    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      pty.resize(height, width);
    };
  }

  @override
  void dispose() {
    _stdoutSub.cancel();
    pty.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Terminal'),
        backgroundColor: const Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
      ),
      body: TerminalView(
        terminal,
        controller: TerminalController(),
        textStyle: const TerminalStyle(
          fontFamily: 'monospace',
          fontSize: 14,
        ),
      ),
    );
  }
}
