import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  bool _ctrlActive = false;

  @override
  void initState() {
    super.initState();
    _cwd = widget.pythonRoot ?? '/';
    _write('PyIDE Terminal');
    _write('Type a command and press Enter.');
    _write('');
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

  Map<String, String> _buildEnv() {
    const systemPath =
        '/system/bin:/system/xbin:/vendor/bin:/product/bin';

    final env = <String, String>{
      'PATH': systemPath,
      'HOME': '/',
      'TERM': 'xterm-256color',
      'LANG': 'en_US.UTF-8',
    };

    if (widget.pythonRoot != null && widget.nativeLibDir != null) {
      env['PYTHONHOME'] = widget.pythonRoot!;
      env['PYTHONPATH'] = '${widget.pythonRoot}/lib/python3.14';
      env['LD_LIBRARY_PATH'] = widget.nativeLibDir!;
      env['PATH'] =
          '${widget.pythonRoot}/bin:${widget.nativeLibDir}:$systemPath';
    }

    return env;
  }

  Future<void> _runCommand(String raw) async {
    final cmd = raw.trim();
    if (cmd.isEmpty) {
      _write('\$');
      return;
    }

    setState(() => _isRunning = true);
    _write('\$ $cmd');

    if (cmd == 'cd' || cmd.startsWith('cd ')) {
      final parts = cmd.split(' ');
      final target = parts.length > 1 ? parts.sublist(1).join(' ') : '/';
      final newPath = target.startsWith('/') ? target : '$_cwd/$target';
      final dir = Directory(newPath);
      if (await dir.exists()) {
        try {
          _cwd = dir.resolveSymbolicLinksSync();
        } catch (_) {
          _cwd = newPath;
        }
      } else {
        _write('cd: no such directory: $target');
      }
      setState(() => _isRunning = false);
      return;
    }

    if (cmd == 'clear') {
      setState(() {
        _historyController.clear();
        _isRunning = false;
      });
      return;
    }

    try {
      final result = await Process.run(
        '/system/bin/sh',
        ['-c', cmd],
        workingDirectory: _cwd,
        environment: _buildEnv(),
        includeParentEnvironment: true,
      );

      final out = (result.stdout as String).trimRight();
      final err = (result.stderr as String).trimRight();

      if (out.isNotEmpty) _write(out);
      if (err.isNotEmpty) _write(err);
      if (out.isEmpty && err.isEmpty && result.exitCode != 0) {
        _write('[exit ${result.exitCode}]');
      }
    } catch (e) {
      _write('Error: $e');
    } finally {
      setState(() => _isRunning = false);
    }
  }

  void _insertKey(String text) {
    final sel = _inputController.selection;
    final value = _inputController.text;
    if (!sel.isValid) {
      _inputController.text = value + text;
      _inputController.selection =
          TextSelection.collapsed(offset: _inputController.text.length);
      return;
    }
    final newText = value.replaceRange(sel.start, sel.end, text);
    _inputController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + text.length),
    );
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
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E0E),
        elevation: 0,
        toolbarHeight: 44,
        iconTheme:
            const IconThemeData(color: Color(0xFFAAAAAA), size: 18),
        title: const Text('Terminal',
            style: TextStyle(
                fontSize: 13.5,
                color: Color(0xFFCCCCCC),
                fontWeight: FontWeight.w400)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => setState(() => _historyController.clear()),
          ),
        ],
      ),
      body: Column(
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
                    fontSize: 12.5,
                    height: 1.45,
                    color: Color(0xFFCCCCCC),
                  ),
                ),
              ),
            ),
          ),
          Container(
            height: 40,
            color: const Color(0xFF0E0E0E),
            child: Row(
              children: [
                _key('ESC', () => _insertKey('\u001b')),
                _key('TAB', () => _insertKey('    ')),
                _modKey('CTRL', _ctrlActive, () {
                  setState(() => _ctrlActive = !_ctrlActive);
                }),
                _modKey('ALT', false, () {}),
                _key('-', () => _insertKey('-')),
                _key('/', () => _insertKey('/')),
                _key('|', () => _insertKey('|')),
                _key('~', () => _insertKey('~')),
                _key('<', () => _insertKey('<')),
                _key('>', () => _insertKey('>')),
              ],
            ),
          ),
          Container(
            color: const Color(0xFF0E0E0E),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '\$',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3FB950),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    focusNode: _inputFocus,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Color(0xFFCCCCCC),
                    ),
                    cursorColor: const Color(0xFF3FB950),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10),
                    ),
                    onSubmitted: (v) {
                      _inputController.clear();
                      _runCommand(v);
                    },
                  ),
                ),
                if (_isRunning)
                  const Padding(
                    padding: EdgeInsets.all(6),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.7,
                          color: Color(0xFF3FB950)),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.arrow_upward,
                        size: 18, color: Color(0xFF3FB950)),
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
    );
  }

  Widget _key(String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFFCCCCCC),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modKey(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF3FB950).withOpacity(0.25)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: active
                    ? const Color(0xFF3FB950)
                    : const Color(0xFFAAAAAA),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
