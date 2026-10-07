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
  late final StreamSubscription<List<int>> _ptyOutputSub; // Updated type to match pty.output

  @override
  void initState() {
    super.initState();
    terminal = Terminal(maxLines: 10000);
    
    // Start the PTY process
    pty = Pty.start(
      'sh',
      columns: 80,
      rows: 24,
    );

    // FIXED: 'pty.output' is the correct stream in flutter_pty 0.4.2
    // It emits Uint8List, so we cast it to List<int> and decode it.
    _ptyOutputSub = pty.output.cast<List<int>>().listen((data) {
      terminal.write(utf8.decode(data));
    });

    // Handle user input from xterm back to the PTY
    terminal.onOutput = (data) {
      pty.write(const Utf8Encoder().convert(data));
    };

    // Handle terminal resizing
    terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      pty.resize(height, width);
    };
  }

  @override
  void dispose() {
    _ptyOutputSub.cancel();
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
