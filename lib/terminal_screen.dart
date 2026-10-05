import 'dart:io';
import 'package:flutter/material.dart';

class TerminalScreen extends StatefulWidget {
  final String? pythonRoot;
  final String? nativeLibDir;

  const TerminalScreen({
    super.key,
    this.pythonRoot,
    this.nativeLibDir,
  });

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _historyController = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _inputFocus = FocusNode();

  late String _cwd;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _cwd = widget.pythonRoot ?? '/';
    _write('PyIDE Terminal');
    _write('Working directory: $_cwd');
    _write('Type a command and press Enter.');
    _write('─' * 40);
  }

  void _write(String text) {
    _historyController.text += '$text\n';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _runCommand(String raw) async {
    final cmd = raw.trim();
    if (cmd.isEmpty) return;

    setState(() => _isRunning = true);
    _write('\$ $cmd');

    // Built-in: cd
    if (cmd == 'cd' || cmd.startsWith('cd ')) {
      final parts = cmd.split(' ');
      final target = parts.length > 1 ? parts.sublist(1).join(' ') : '/';
      final newPath = target.startsWith('/')
          ? target
          : '$_cwd/$target';
      final dir = Directory(newPath);
      if (await dir.exists()) {
        try {
          _cwd = dir.resolveSymbolicLinksSync();
          _write('Changed to $_cwd');
        } catch (_) {
          _cwd = newPath;
          _write('Changed to $_cwd');
        }
      } else {
        _write('cd: no such directory: $target');
      }
      setState(() => _isRunning = false);
      return;
    }

    // Built-in: clear
    if (cmd == 'clear') {
      setState(() {
        _historyController.clear();
        _isRunning = false;
      });
      return;
    }

    // Everything else: run in a shell
    try {
      final env = <String, String>{
        'HOME': Platform.environment['HOME'] ?? '/',
        'PATH': '/system/bin:/system/xbin',
        'TERM': 'xterm-256color',
      };
      if (widget.pythonRoot != null && widget.nativeLibDir != null) {
        env['PYTHONHOME'] = widget.pythonRoot!;
        env['PYTHONPATH'] = '${widget.pythonRoot}/lib/python3.14';
        env['LD_LIBRARY_PATH'] = widget.nativeLibDir!;
        env['PATH'] =
            '${widget.pythonRoot}/bin:${widget.nativeLibDir}:\${PATH}';
      }

      final result = await Process.run(
        '/system/bin/sh',
        ['-c', cmd],
        workingDirectory: _cwd,
        environment: env,
      );

      final out = (result.stdout as String).trimRight();
      final err = (result.stderr as String).trimRight();

      if (out.isNotEmpty) _write(out);
      if (err.isNotEmpty) _write(err);
      if (out.isEmpty && err.isEmpty && result.exitCode != 0) {
        _write('[exit code ${result.exitCode}]');
      }
    } catch (e) {
      _write('Error: $e');
    } finally {
      setState(() => _isRunning = false);
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _historyController.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF161616),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        iconTheme: const IconThemeData(color: Color(0xFFD4D4D4)),
        title: const Text('Terminal',
            style: TextStyle(fontSize: 15, color: Color(0xFFD4D4D4))),
        actions: [
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined,
                color: Color(0xFFCCCCCC), size: 18),
            onPressed: () {
              setState(() => _historyController.clear());
            },
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward,
                color: Color(0xFFCCCCCC), size: 18),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _inputFocus.requestFocus(),
                behavior: HitTestBehavior.opaque,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    _historyController.text,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.5,
                      color: Color(0xFFD4D4D4),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              color: const Color(0xFF252526),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '\$',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: const Color(0xFF3FB950),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      focusNode: _inputFocus,
                      autofocus: false,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        color: Color(0xFFD4D4D4),
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: 'type a command…',
                        hintStyle: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          color: Color(0xFF5A5A5A),
                        ),
                      ),
                      onSubmitted: (v) {
                        _inputController.clear();
                        _runCommand(v);
                      },
                    ),
                  ),
                  if (_isRunning)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF4A9EFF)),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.send,
                          size: 16, color: Color(0xFF4A9EFF)),
                      onPressed: () {
                        final v = _inputController.text;
                        _inputController.clear();
                        _runCommand(v);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
