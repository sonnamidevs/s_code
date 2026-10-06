import 'dart:io';
import 'package:flutter/material.dart';

class TerminalScreen extends StatefulWidget {
  final String? pythonRoot;
  final String? nativeLibDir;

  const TerminalScreen({super.key, this.pythonRoot, this.nativeLibDir});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _inputCtrl = TextEditingController();
  final _historyCtrl = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();

  late String _cwd;
  bool _isRunning = false;
  bool _ctrlActive = false;
  bool _altActive = false;

  final List<String> _commandHistory = [];
  int _historyIndex = -1;

  @override
  void initState() {
    super.initState();
    _cwd = widget.pythonRoot ?? '/';
    _print('Welcome to PyIDE Terminal');
    _print('');
    _print('Type "help" for available commands.');
    _print('Type "pip install <package>" to install Python packages.');
    _print('');
  }

  void _print(String text) {
    _historyCtrl.text += '$text\n';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut);
      }
    });
  }

  String get _prompt {
    final path = _cwd.replaceFirst(widget.pythonRoot ?? '~', '~');
    return '$path \$';
  }

  Map<String, String> _env() {
    const systemPath = '/system/bin:/system/xbin:/vendor/bin:/product/bin';
    final env = <String, String>{
      'PATH': systemPath,
      'HOME': widget.pythonRoot ?? '/',
      'TERM': 'xterm-256color',
      'LANG': 'en_US.UTF-8',
      'PS1': _prompt,
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
    if (cmd.isEmpty) return;

    _commandHistory.insert(0, cmd);
    _historyIndex = -1;

    _print('${_prompt} $cmd');
    setState(() => _isRunning = true);

    if (cmd == 'cd' || cmd.startsWith('cd ')) {
      final target = cmd.length > 3 ? cmd.substring(3).trim() : '/';
      final newPath = target.startsWith('/') ? target : '$_cwd/$target';
      final dir = Directory(newPath);
      if (await dir.exists()) {
        try {
          _cwd = dir.resolveSymbolicLinksSync();
        } catch (_) {
          _cwd = newPath;
        }
      } else {
        _print('cd: no such directory: $target');
      }
      setState(() => _isRunning = false);
      return;
    }

    if (cmd == 'clear') {
      setState(() {
        _historyCtrl.clear();
        _isRunning = false;
      });
      return;
    }

    if (cmd == 'help') {
      _print('Available commands:');
      _print('  ls, cd, pwd, cat, mkdir, rm, echo');
      _print('  pip install <package>');
      _print('  python <file.py>');
      _print('  clear');
      setState(() => _isRunning = false);
      return;
    }

    String actualCmd = cmd;
    if (cmd == 'pip' || cmd.startsWith('pip ')) {
      final py = '${widget.pythonRoot}/lib/python3.14';
      final pythonBin = widget.nativeLibDir != null
          ? '${widget.nativeLibDir}/libpython3-exec.so'
          : 'python3';
      final args = cmd.length > 3 ? cmd.substring(3).trim() : '';
      final envStr = widget.nativeLibDir != null
          ? 'PYTHONHOME="${widget.pythonRoot}" PYTHONPATH="$py" LD_LIBRARY_PATH="${widget.nativeLibDir}" '
          : '';
      actualCmd = '$envStr"$pythonBin" -m pip $args';
    }

    try {
      final result = await Process.run(
        '/system/bin/sh',
        ['-c', actualCmd],
        workingDirectory: _cwd,
        environment: _env(),
        includeParentEnvironment: true,
      );

      final out = (result.stdout as String).trimRight();
      final err = (result.stderr as String).trimRight();

      if (out.isNotEmpty) _print(out);
      if (err.isNotEmpty) {
        if (!err.contains('Broken pipe')) _print(err);
      }
      if (out.isEmpty && err.isEmpty && result.exitCode != 0) {
        _print('[exit ${result.exitCode}]');
      }
    } catch (e) {
      _print('Error: $e');
    } finally {
      setState(() => _isRunning = false);
    }
  }

  void _historyUp() {
    if (_commandHistory.isEmpty) return;
    if (_historyIndex < _commandHistory.length - 1) _historyIndex++;
    _inputCtrl.text = _commandHistory[_historyIndex];
    _inputCtrl.selection =
        TextSelection.collapsed(offset: _inputCtrl.text.length);
  }

  void _historyDown() {
    if (_historyIndex > 0) {
      _historyIndex--;
      _inputCtrl.text = _commandHistory[_historyIndex];
    } else {
      _historyIndex = -1;
      _inputCtrl.clear();
    }
    _inputCtrl.selection =
        TextSelection.collapsed(offset: _inputCtrl.text.length);
  }

  void _insert(String text) {
    final sel = _inputCtrl.selection;
    final value = _inputCtrl.text;
    if (!sel.isValid) {
      _inputCtrl.text = value + text;
      _inputCtrl.selection =
          TextSelection.collapsed(offset: _inputCtrl.text.length);
      return;
    }
    final newText = value.replaceRange(sel.start, sel.end, text);
    _inputCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + text.length),
    );
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _historyCtrl.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        toolbarHeight: 44,
        iconTheme: const IconThemeData(color: Color(0xFFAAAAAA), size: 18),
        title: const Text('Terminal',
            style: TextStyle(
                fontSize: 13.5,
                color: Color(0xFFCCCCCC),
                fontWeight: FontWeight.w400)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => setState(() => _historyCtrl.clear()),
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
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                  child: SelectableText(
                    _historyCtrl.text,
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
            _keyRow(),
            _inputRow(),
          ],
        ),
      ),
    );
  }

  Widget _keyRow() {
    return Container(
      height: 38,
      color: const Color(0xFF0A0A0A),
      child: Row(
        children: [
          _k('ESC', () => _insert('\u001b')),
          _k('TAB', () => _insert('    ')),
          _m('CTRL', _ctrlActive,
              () => setState(() => _ctrlActive = !_ctrlActive)),
          _m('ALT', _altActive, () => setState(() => _altActive = !_altActive)),
          _k('↑', _historyUp),
          _k('↓', _historyDown),
          _k('←', () => _insert('\u001b[D')),
          _k('→', () => _insert('\u001b[C')),
          _k('/', () => _insert('/')),
          _k('-', () => _insert('-')),
          _k('|', () => _insert('|')),
          _k('~', () => _insert('~')),
        ],
      ),
    );
  }

  Widget _k(String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              color: Color(0xFFCCCCCC),
            ),
          ),
        ),
      ),
    );
  }

  Widget _m(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color:
                    active ? const Color(0xFF3FB950) : const Color(0xFFAAAAAA),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputRow() {
    return Container(
      color: const Color(0xFF0A0A0A),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      child: Row(
        children: [
          Text(
            _prompt,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3FB950),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              focusNode: _inputFocus,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                color: Color(0xFFCCCCCC),
              ),
              cursorColor: const Color(0xFF3FB950),
              cursorWidth: 8,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
              onSubmitted: (v) {
                _inputCtrl.clear();
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
                    strokeWidth: 1.6, color: Color(0xFF3FB950)),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.keyboard_return,
                  size: 20, color: Color(0xFF3FB950)),
              onPressed: () {
                final v = _inputCtrl.text;
                _inputCtrl.clear();
                _runCommand(v);
              },
            ),
        ],
      ),
    );
  }
}
