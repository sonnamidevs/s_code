import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/python.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/monokai.dart';
import 'package:flutter_highlight/themes/vs2015.dart';
import 'package:file_picker/file_picker.dart';
import 'settings_screen.dart';
import 'about_screen.dart';
import 'terminal_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PyIDEApp());
}

class PyIDEApp extends StatelessWidget {
  const PyIDEApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PyIDE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4A9EFF),
          surface: Color(0xFF1E1E1E),
          onSurface: Color(0xFFCCCCCC),
        ),
      ),
      home: const MainScaffold(),
    );
  }
}

class EditorTabData {
  String name;
  String content;
  String? path;
  EditorTabData({required this.name, required this.content, this.path});

  Map<String, dynamic> toJson() =>
      {'name': name, 'content': content, 'path': path};

  factory EditorTabData.fromJson(Map<String, dynamic> json) => EditorTabData(
        name: json['name'] as String,
        content: json['content'] as String,
        path: json['path'] as String?,
      );
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold>
    with WidgetsBindingObserver {
  static const MethodChannel _channel =
      MethodChannel('com.sonnamidevs.s_code/native');

  bool _isSetupComplete = false;
  bool _isRunning = false;
  bool _hasError = false;
  String? _nativeLibDir;
  String? _pythonRoot;

  late final CodeController _codeController;
  final FocusNode _editorFocus = FocusNode();
  bool _isAutoIndenting = false;
  bool _showLineNumbers = true;

  final List<EditorTabData> _tabs = [];
  int _activeTab = 0;

  double _fontSize = 13.5;
  String _themeName = 'atom-one-dark';
  double _consoleFraction = 0.30;
  bool _showConsole = true;
  bool _showSpecialKeys = false;
  bool _ctrlActive = false;
  bool _shiftActive = false;
  bool _altActive = false;
  int _sidebarIndex = 0;

  final TextEditingController _outputController = TextEditingController();
  final ScrollController _outputScroll = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const Map<String, Map<String, TextStyle>> _themes = {
    'atom-one-dark': atomOneDarkTheme,
    'atom-one-light': atomOneLightTheme,
    'github': githubTheme,
    'monokai': monokaiTheme,
    'vs2015': vs2015Theme,
  };

  Map<String, TextStyle> get _themeStyles =>
      _themes[_themeName] ?? atomOneDarkTheme;

  static const String _welcomeCode = '''# Welcome to PyIDE

import sys
import platform

def greet(name):
    return f"Hello, {name}!"

class Calculator:
    def add(self, a, b):
        return a + b

print(greet("Android"))
print(f"Python: {sys.version.split()[0]}")
print(f"Platform: {platform.machine()}")

calc = Calculator()
print(f"2 + 3 = {calc.add(2, 3)}")
''';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _codeController = CodeController(text: '', language: python);
    _codeController.addListener(_onControllerChanged);
    _loadPrefs();
    _loadTabs();
    _setupPython();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveTabs();
    }
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _fontSize = p.getDouble('font_size') ?? 13.5;
      _themeName = p.getString('theme') ?? 'atom-one-dark';
      _showLineNumbers = p.getBool('show_line_numbers') ?? true;
    });
  }

  // ============ TAB PERSISTENCE ============
  Future<void> _loadTabs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('tabs_data');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        if (list.isNotEmpty) {
          _tabs.clear();
          for (final item in list) {
            _tabs.add(EditorTabData.fromJson(
                Map<String, dynamic>.from(item as Map)));
          }
          final savedIndex = prefs.getInt('active_tab') ?? 0;
          _activeTab =
              (savedIndex >= 0 && savedIndex < _tabs.length) ? savedIndex : 0;
          _codeController.text = _tabs[_activeTab].content;
          return;
        }
      } catch (_) {}
    }
    _tabs.add(EditorTabData(name: 'main.py', content: _welcomeCode));
    _codeController.text = _welcomeCode;
  }

  Future<void> _saveTabs() async {
    if (_tabs.isEmpty) return;
    _tabs[_activeTab].content = _codeController.text;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'tabs_data', jsonEncode(_tabs.map((t) => t.toJson()).toList()));
    await prefs.setInt('active_tab', _activeTab);
  }

  // ============ AUTO-INDENT ============
  void _onControllerChanged() {
    if (_isAutoIndenting) return;
    final value = _codeController.value;
    final text = value.text;
    final sel = value.selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    final p = sel.baseOffset;
    if (p <= 0 || p > text.length) return;
    if (text[p - 1] != '\n') return;

    final before = text.substring(0, p - 1);
    final lastNl = before.lastIndexOf('\n');
    final prevLine = lastNl == -1 ? before : before.substring(lastNl + 1);
    if (prevLine.trim().isEmpty) return;

    final leading = prevLine.length - prevLine.trimLeft().length;
    var indent = ' ' * leading;
    if (prevLine.trimRight().endsWith(':')) indent += '    ';
    if (indent.isEmpty) return;

    _isAutoIndenting = true;
    try {
      _codeController.value = value.copyWith(
        text: text.substring(0, p) + indent + text.substring(p),
        selection: TextSelection.collapsed(offset: p + indent.length),
        composing: TextRange.empty,
      );
    } finally {
      _isAutoIndenting = false;
    }
  }

  Future<void> _setupPython() async {
    try {
      setState(() => _hasError = false);
      _nativeLibDir = await _channel.invokeMethod('getNativeLibraryDir');
      if (_nativeLibDir == null || _nativeLibDir!.isEmpty) {
        throw Exception('Native dir unavailable');
      }

      final docsDir = await getApplicationDocumentsDirectory();
      _pythonRoot = '${docsDir.path}/python_runtime';
      final root = Directory(_pythonRoot!);

      final wrapper = File('$_nativeLibDir/libpython3-exec.so');
      if (!wrapper.existsSync()) throw Exception('Python wrapper not found');

      final marker = File('${root.path}/.extracted_v7');
      if (!marker.existsSync()) {
        if (root.existsSync()) root.deleteSync(recursive: true);
        await root.create(recursive: true);

        final data = await rootBundle.load('assets/python/python-embed.tar.gz');
        final tmpTar = File('${docsDir.path}/py.tar.gz');
        await tmpTar.writeAsBytes(data.buffer.asUint8List());

        final script = '''
cd "${root.path}"
mkdir -p _tmp
tar -xzf "${tmpTar.path}" -C _tmp
mkdir -p lib
if [ -d "_tmp/stdlib/python3.14" ]; then
  mv "_tmp/stdlib/python3.14" "lib/python3.14"
fi
rm -rf _tmp
''';
        await Process.run('/system/bin/sh', ['-c', script]);
        await tmpTar.delete();

        if (!File('${root.path}/lib/python3.14/encodings/__init__.py')
            .existsSync()) {
          throw Exception('encodings missing');
        }
        await marker.writeAsString('v7');
      }

      setState(() => _isSetupComplete = true);
    } catch (e) {
      setState(() => _hasError = true);
      _append('Setup failed: $e');
    }
  }

  Future<void> _runCode() async {
    if (!_isSetupComplete || _nativeLibDir == null || _pythonRoot == null) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isRunning = true;
      _showConsole = true;
    });

    _append('');
    _append('▶ ${DateTime.now().toString().substring(11, 19)}');
    _append('─' * 40);

    final scriptFile = File('$_pythonRoot/script.py');
    await scriptFile.writeAsString(_codeController.text);

    try {
      final cmd = '''
export PYTHONHOME="$_pythonRoot"
export PYTHONPATH="$_pythonRoot/lib/python3.14"
export LD_LIBRARY_PATH="$_nativeLibDir"
"$_nativeLibDir/libpython3-exec.so" "${scriptFile.path}"
''';
      final result = await Process.run('/bin/sh', ['-c', cmd]);
      if ((result.stdout as String).isNotEmpty) {
        _append(result.stdout as String);
      }
      if ((result.stderr as String).isNotEmpty) {
        _append(result.stderr as String);
      }
      _append('─' * 40);
      _append('[Done] exit ${result.exitCode}');
    } catch (e) {
      _append('Run error: $e');
    } finally {
      setState(() => _isRunning = false);
    }
  }

  void _append(String text) {
    _outputController.text += '$text\n';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_outputScroll.hasClients) {
        _outputScroll.animateTo(
          _outputScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearConsole() => setState(() => _outputController.clear());

  void _insertText(String text) {
    final value = _codeController.value;
    final sel = value.selection;
    if (!sel.isValid) {
      _codeController.text = value.text + text;
      return;
    }
    final newText = value.text.replaceRange(sel.start, sel.end, text);
    _codeController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + text.length),
    );
    _editorFocus.requestFocus();
  }

  void _switchTab(int i) async {
    if (i == _activeTab) return;
    _tabs[_activeTab].content = _codeController.text;
    setState(() => _activeTab = i);
    _codeController.text = _tabs[i].content;
    _saveTabs();
  }

  void _newFile() async {
    _tabs[_activeTab].content = _codeController.text;
    final name = 'untitled_${_tabs.length + 1}.py';
    setState(() {
      _tabs.add(EditorTabData(name: name, content: ''));
      _activeTab = _tabs.length - 1;
    });
    _codeController.text = '';
    _saveTabs();
  }

  void _closeTab(int i) {
    if (_tabs.length == 1) {
      setState(() {
        _tabs[0] = EditorTabData(name: 'untitled.py', content: '');
        _codeController.text = '';
      });
      _saveTabs();
      return;
    }
    setState(() {
      _tabs.removeAt(i);
      if (_activeTab >= _tabs.length) _activeTab = _tabs.length - 1;
      _codeController.text = _tabs[_activeTab].content;
    });
    _saveTabs();
  }

  Future<void> _saveCurrentFile() async {
    _tabs[_activeTab].content = _codeController.text;
    final targetPath =
        _tabs[_activeTab].path ?? '$_pythonRoot/${_tabs[_activeTab].name}';
    await File(targetPath).writeAsString(_tabs[_activeTab].content);
    await _saveTabs();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved ${_tabs[_activeTab].name}',
              style: const TextStyle(fontSize: 13)),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2A2A2A),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Future<void> _openFileFromDevice() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.single.path == null) return;
      final path = result.files.single.path!;
      final content = await File(path).readAsString();
      final name = path.split('/').last;
      _tabs[_activeTab].content = _codeController.text;
      setState(() {
        _tabs.add(EditorTabData(name: name, content: content, path: path));
        _activeTab = _tabs.length - 1;
      });
      _codeController.text = content;
      await _saveTabs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open: $e')),
        );
      }
    }
  }

  void _handleMenu(String v) async {
    switch (v) {
      case 'new':
        _newFile();
        break;
      case 'files':
        _openFileFromDevice();
        break;
      case 'save':
        await _saveCurrentFile();
        break;
      case 'close':
        _closeTab(_activeTab);
        break;
      case 'terminal':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TerminalScreen(
              pythonRoot: _pythonRoot,
              nativeLibDir: _nativeLibDir,
            ),
          ),
        );
        break;
      case 'settings':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SettingsScreen(
              initialFontSize: _fontSize,
              initialTheme: _themeName,
              initialShowLineNumbers: _showLineNumbers,
              onFontSizeChanged: (v) => setState(() => _fontSize = v),
              onThemeChanged: (k) => setState(() => _themeName = k),
              onLineNumbersChanged: (v) =>
                  setState(() => _showLineNumbers = v),
            ),
          ),
        );
        break;
      case 'about':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AboutScreen()),
        );
        break;
      case 'exit':
        await _saveTabs();
        SystemNavigator.pop();
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTabs();
    _codeController.removeListener(_onControllerChanged);
    _codeController.dispose();
    _editorFocus.dispose();
    _outputController.dispose();
    _outputScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      drawer: Drawer(
        backgroundColor: const Color(0xFF1A1A1A),
        width: MediaQuery.of(context).size.width * 0.78,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(14),
            bottomRight: Radius.circular(14),
          ),
        ),
        child: SidebarContent(
          activeIndex: _sidebarIndex,
          onIndexChanged: (i) => setState(() => _sidebarIndex = i),
          files: _tabs.map((t) => t.name).toList(),
          onFileTap: (name) {
            final i = _tabs.indexWhere((t) => t.name == name);
            if (i >= 0) _switchTab(i);
            Navigator.pop(context);
          },
        ),
      ),
      appBar: _appBar(),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _tabsBar(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final total = constraints.maxHeight;
                      final consoleH =
                          (_showConsole ? total * _consoleFraction : 0)
                              .toDouble();
                      final editorH =
                          total - consoleH - (_showConsole ? 10 : 0);
                      return Column(
                        children: [
                          SizedBox(height: editorH, child: _editor()),
                          if (_showConsole) _dragHandle(total),
                          if (_showConsole)
                            SizedBox(height: consoleH, child: _console()),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            if (_showSpecialKeys)
              Positioned(
                left: 0,
                right: 0,
                bottom: viewInsets,
                child: _specialKeysBar(),
              ),
          ],
        ),
      ),
      floatingActionButton: _fab(),
    );
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1A1A1A),
      toolbarHeight: 44,
      elevation: 0,
      leadingWidth: 44,
      leading: IconButton(
        icon: const Icon(Icons.menu, size: 18, color: Color(0xFFAAAAAA)),
        splashRadius: 22,
        padding: EdgeInsets.zero,
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      titleSpacing: 0,
      title: Text(
        _tabs[_activeTab].name,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w400,
          color: Color(0xFFCCCCCC),
          letterSpacing: 0,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined,
              size: 17, color: Color(0xFFAAAAAA)),
          splashRadius: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          onPressed: _saveCurrentFile,
        ),
        IconButton(
          icon: _isRunning
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.7, color: Color(0xFF4A9EFF)),
                )
              : const Icon(Icons.play_arrow_rounded,
                  size: 22, color: Color(0xFF4A9EFF)),
          splashRadius: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          onPressed: _isSetupComplete && !_isRunning ? _runCode : null,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert,
              size: 18, color: Color(0xFFAAAAAA)),
          splashRadius: 22,
          iconSize: 18,
          color: const Color(0xFF252525),
          elevation: 6,
          offset: const Offset(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFF2E2E2E), width: 1),
          ),
          onSelected: _handleMenu,
          itemBuilder: (_) => [
            _mi('new', Icons.note_add_outlined, 'New file'),
            _mi('files', Icons.folder_open_outlined, 'Files'),
            _mi('save', Icons.save_outlined, 'Save'),
            _mi('close', Icons.close, 'Close file'),
            _divider(),
            _mi('terminal', Icons.terminal_outlined, 'Terminal'),
            _divider(),
            _mi('settings', Icons.settings_outlined, 'Settings'),
            _mi('about', Icons.info_outline, 'About'),
            _divider(),
            _mi('exit', Icons.logout_outlined, 'Exit'),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  PopupMenuItem<String> _mi(String v, IconData i, String label) {
    return PopupMenuItem<String>(
      value: v,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(i, size: 16, color: const Color(0xFFAAAAAA)),
          const SizedBox(width: 14),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              color: Color(0xFFCCCCCC),
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuDivider _divider() =>
      const PopupMenuDivider(height: 1, color: Color(0xFF2A2A2A));

  Widget _tabsBar() {
    return Container(
      height: 32,
      color: const Color(0xFF1A1A1A),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        itemCount: _tabs.length,
        itemBuilder: (_, i) {
          final active = i == _activeTab;
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: GestureDetector(
              onTap: () => _switchTab(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF252525)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.description_outlined,
                        size: 12,
                        color: active
                            ? const Color(0xFF4A9EFF)
                            : const Color(0xFF666666)),
                    const SizedBox(width: 6),
                    Text(
                      _tabs[i].name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: active
                            ? const Color(0xFFCCCCCC)
                            : const Color(0xFF7A7A7A),
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _closeTab(i),
                      child: const Icon(Icons.close,
                          size: 12, color: Color(0xFF666666)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _editor() {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: CodeTheme(
        data: CodeThemeData(styles: _themeStyles),
        child: CodeField(
          controller: _codeController,
          focusNode: _editorFocus,
          expands: true,
          wrap: true,
          textStyle: TextStyle(
            fontFamily: 'monospace',
            fontSize: _fontSize,
            height: 1.5,
          ),
          gutterStyle: GutterStyle(
            width: _showLineNumbers ? 36 : 0,
            showLineNumbers: _showLineNumbers,
            showErrors: false,
            showFoldingHandles: false,
            textStyle: TextStyle(
              fontFamily: 'monospace',
              fontSize: _fontSize - 1,
              height: 1.5,
              color: const Color(0xFF5C6370),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dragHandle(double total) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) {
        setState(() {
          _consoleFraction -= d.delta.dy / total;
          _consoleFraction = _consoleFraction.clamp(0.1, 0.85);
        });
      },
      onTap: () {
        setState(() {
          _consoleFraction = _consoleFraction > 0.5 ? 0.25 : 0.75;
        });
      },
      child: Container(
        height: 10,
        color: const Color(0xFF1A1A1A),
        child: Center(
          child: Container(
            width: 30,
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFF444444),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _console() {
    return Container(
      color: const Color(0xFF141414),
      child: Column(
        children: [
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            color: const Color(0xFF1A1A1A),
            child: Row(
              children: [
                _icon(Icons.backspace_outlined, _clearConsole),
                _icon(Icons.keyboard_hide_outlined, () {
                  FocusScope.of(context).unfocus();
                }),
                const Spacer(),
                const Text(
                  'OUTPUT',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6A6A6A),
                  ),
                ),
                const Spacer(),
                _icon(Icons.close, () {
                  setState(() => _showConsole = false);
                }),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _outputController.text.isEmpty
                  ? const Center(
                      child: Text(
                        'Output will appear here',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          color: Color(0xFF5A5A5A),
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      controller: _outputScroll,
                      child: Text(
                        _outputController.text,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          height: 1.5,
                          color: Color(0xFFCCCCCC),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _icon(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 13, color: const Color(0xFFAAAAAA)),
      ),
    );
  }

  Widget _specialKeysBar() {
    final keys = <Map<String, String>>[
      {'label': 'CTRL', 'type': 'mod', 'id': 'ctrl'},
      {'label': 'SHIFT', 'type': 'mod', 'id': 'shift'},
      {'label': 'ALT', 'type': 'mod', 'id': 'alt'},
      {'label': 'TAB', 'type': 'act', 'insert': '    '},
      {'label': '{', 'type': 'sym', 'insert': '{'},
      {'label': '}', 'type': 'sym', 'insert': '}'},
      {'label': '(', 'type': 'sym', 'insert': '('},
      {'label': ')', 'type': 'sym', 'insert': ')'},
      {'label': '[', 'type': 'sym', 'insert': '['},
      {'label': ']', 'type': 'sym', 'insert': ']'},
      {'label': '<', 'type': 'sym', 'insert': '<'},
      {'label': '>', 'type': 'sym', 'insert': '>'},
      {'label': '"', 'type': 'sym', 'insert': '"'},
      {'label': "'", 'type': 'sym', 'insert': "'"},
      {'label': '=', 'type': 'sym', 'insert': '='},
      {'label': '+', 'type': 'sym', 'insert': '+'},
      {'label': '-', 'type': 'sym', 'insert': '-'},
      {'label': '*', 'type': 'sym', 'insert': '*'},
      {'label': '/', 'type': 'sym', 'insert': '/'},
      {'label': '%', 'type': 'sym', 'insert': '%'},
      {'label': '!', 'type': 'sym', 'insert': '!'},
      {'label': '&', 'type': 'sym', 'insert': '&'},
      {'label': '|', 'type': 'sym', 'insert': '|'},
      {'label': ':', 'type': 'sym', 'insert': ':'},
      {'label': ';', 'type': 'sym', 'insert': ';'},
      {'label': '.', 'type': 'sym', 'insert': '.'},
      {'label': ',', 'type': 'sym', 'insert': ','},
      {'label': '?', 'type': 'sym', 'insert': '?'},
      {'label': '#', 'type': 'sym', 'insert': '#'},
      {'label': '@', 'type': 'sym', 'insert': '@'},
      {'label': r'$', 'type': 'sym', 'insert': r'$'},
      {'label': '~', 'type': 'sym', 'insert': '~'},
      {'label': '^', 'type': 'sym', 'insert': '^'},
      {'label': '\\', 'type': 'sym', 'insert': '\\'},
      {'label': '_', 'type': 'sym', 'insert': '_'},
    ];

    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              itemCount: keys.length,
              itemBuilder: (_, i) {
                final k = keys[i];
                final type = k['type']!;
                final id = k['id'];
                final active = (id == 'ctrl' && _ctrlActive) ||
                    (id == 'shift' && _shiftActive) ||
                    (id == 'alt' && _altActive);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: () {
                      if (type == 'mod') {
                        setState(() {
                          if (id == 'ctrl') _ctrlActive = !_ctrlActive;
                          if (id == 'shift') _shiftActive = !_shiftActive;
                          if (id == 'alt') _altActive = !_altActive;
                        });
                      } else {
                        _insertText(k['insert'] ?? '');
                      }
                    },
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF4A9EFF).withOpacity(0.22)
                            : const Color(0xFF252525),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: active
                              ? const Color(0xFF4A9EFF)
                              : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          k['label']!,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: active
                                ? const Color(0xFF4A9EFF)
                                : const Color(0xFFCCCCCC),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          InkWell(
            onTap: () => setState(() => _showSpecialKeys = false),
            child: Container(
              width: 38,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF252525),
                border: Border(left: BorderSide(color: Color(0xFF1A1A1A))),
              ),
              child: const Center(
                child: Icon(Icons.close, size: 14, color: Color(0xFFAAAAAA)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fab() {
    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        setState(() => _showSpecialKeys = !_showSpecialKeys);
      },
      child: FloatingActionButton(
        mini: true,
        backgroundColor: const Color(0xFF252525),
        elevation: 0,
        shape: const CircleBorder(
          side: BorderSide(color: Color(0xFF2E2E2E), width: 1),
        ),
        onPressed: () {
          HapticFeedback.lightImpact();
          setState(() => _showConsole = !_showConsole);
        },
        child: Icon(
          _showConsole
              ? Icons.keyboard_arrow_down
              : Icons.keyboard_arrow_up,
          color: const Color(0xFFAAAAAA),
          size: 20,
        ),
      ),
    );
  }
}

// ================= DRAWER =================
class SidebarContent extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onIndexChanged;
  final List<String> files;
  final ValueChanged<String> onFileTap;

  const SidebarContent({
    super.key,
    required this.activeIndex,
    required this.onIndexChanged,
    required this.files,
    required this.onFileTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          color: const Color(0xFF141414),
          child: Column(
            children: [
              const SizedBox(height: 16),
              _strip(Icons.folder_outlined, 0, 'Files'),
              _strip(Icons.search, 1, 'Search'),
              _strip(Icons.notifications_none, 2, 'Alerts'),
              _strip(Icons.favorite_border, 3, 'Favorites'),
              const Spacer(),
              _strip(Icons.person_outline, 4, 'Profile'),
              const SizedBox(height: 16),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF1A1A1A),
            child: _content(context),
          ),
        ),
      ],
    );
  }

  Widget _strip(IconData icon, int index, String tip) {
    final active = activeIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: tip,
        child: InkWell(
          onTap: () => onIndexChanged(index),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF252525)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: active
                  ? const Color(0xFF4A9EFF)
                  : const Color(0xFF7A7A7A),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    switch (activeIndex) {
      case 0:
        return _filesPanel();
      case 1:
        return _placeholder('SEARCH', Icons.search, 'No search yet.');
      case 2:
        return _placeholder(
            'ALERTS', Icons.notifications_none, 'No notifications.');
      case 3:
        return _placeholder(
            'FAVORITES', Icons.favorite_border, 'No favorites yet.');
      case 4:
        return _profilePanel(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _filesPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 18, 14, 8),
          child: Text('FILES',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7A7A7A),
              )),
        ),
        Expanded(
          child: files.isEmpty
              ? const Center(
                  child: Text('No files open',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFF666666))),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  itemCount: files.length,
                  itemBuilder: (_, i) {
                    final name = files[i];
                    return InkWell(
                      onTap: () => onFileTap(name),
                      borderRadius: BorderRadius.circular(7),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 9),
                        margin: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.description_outlined,
                                size: 15, color: Color(0xFF4A9EFF)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFCCCCCC))),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _placeholder(String title, IconData icon, String msg) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(title,
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF7A7A7A),
                )),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 32, color: const Color(0xFF444444)),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(msg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF7A7A7A))),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _profilePanel(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 18, 14, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('PROFILE',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF7A7A7A),
                )),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF252525),
                    border: Border.all(
                        color: const Color(0xFF303030), width: 1.5),
                  ),
                  child: const Icon(Icons.person_outline,
                      size: 28, color: Color(0xFF6A6A6A)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Not signed in',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFFCCCCCC),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sign in to sync files across devices.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7A7A7A),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4A9EFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sign-in coming soon'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: const Text('Sign in',
                        style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFCCCCCC),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      side: const BorderSide(color: Color(0xFF333333)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Create account coming soon'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: const Text('Create account',
                        style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
