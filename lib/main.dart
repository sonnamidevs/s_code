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
          secondary: Color(0xFF3FB950),
          surface: Color(0xFF252526),
          onSurface: Color(0xFFD4D4D4),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
          centerTitle: false,
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
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  static const MethodChannel _channel =
      MethodChannel('com.sonnamidevs.s_code/native');

  bool _isSetupComplete = false;
  bool _isRunning = false;
  bool _hasError = false;
  String _statusMessage = 'Preparing...';
  String? _nativeLibDir;
  String? _pythonRoot;

  late final CodeController _codeController;
  final FocusNode _editorFocus = FocusNode();
  bool _isAutoIndenting = false;
  bool _showLineNumbers = true;

  final List<EditorTabData> _tabs = [];
  int _activeTab = 0;

  double _fontSize = 13;
  String _themeName = 'atom-one-dark';
  double _consoleFraction = 0.32;
  bool _showConsole = true;
  bool _showSpecialKeys = false;
  bool _ctrlActive = false;
  bool _shiftActive = false;
  bool _altActive = false;
  int _sidebarIndex = 0;
  int _lastHighlightedLine = -1;

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
# A real Python editor for Android.

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
    _codeController = CodeController(text: _welcomeCode, language: python);
    _codeController.addListener(_onControllerChanged);
    _tabs.add(EditorTabData(name: 'main.py', content: _welcomeCode));
    _loadPrefs();
    _setupPython();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _fontSize = p.getDouble('font_size') ?? 13.0;
      _themeName = p.getString('theme') ?? 'atom-one-dark';
      _showLineNumbers = p.getBool('show_line_numbers') ?? true;
    });
  }

  // ================= CONTROLLER LISTENER (auto-indent + line highlight) =====
  void _onControllerChanged() {
    // Line highlight
    final pos = _codeController.selection.baseOffset;
    if (pos >= 0 && pos <= _codeController.text.length) {
      final line =
          '\n'.allMatches(_codeController.text.substring(0, pos)).length;
      if (line != _lastHighlightedLine) {
        _lastHighlightedLine = line;
      }
    }

    // Auto-indent
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

  // ================= PYTHON SETUP =================
  Future<void> _setupPython() async {
    try {
      setState(() {
        _statusMessage = 'Locating...';
        _hasError = false;
      });
      _nativeLibDir = await _channel.invokeMethod('getNativeLibraryDir');
      if (_nativeLibDir == null || _nativeLibDir!.isEmpty) {
        throw Exception('Native library directory unavailable');
      }

      final docsDir = await getApplicationDocumentsDirectory();
      _pythonRoot = '${docsDir.path}/python_runtime';
      final root = Directory(_pythonRoot!);

      final wrapper = File('$_nativeLibDir/libpython3-exec.so');
      if (!wrapper.existsSync()) throw Exception('Python wrapper not found');

      final marker = File('${root.path}/.extracted_v7');
      if (!marker.existsSync()) {
        setState(() => _statusMessage = 'Extracting Python runtime...');
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

        final check =
            File('${root.path}/lib/python3.14/encodings/__init__.py');
        if (!check.existsSync()) {
          throw Exception('encodings missing');
        }
        await marker.writeAsString('v7');
      }

      setState(() {
        _isSetupComplete = true;
        _statusMessage = 'Ready';
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _statusMessage = 'Setup failed';
      });
      _append('Setup failed: $e');
    }
  }

  // ================= RUN =================
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
    _append('▶ ${DateTime.now().toString().substring(11, 19)} — Running');
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
        _append('--- stderr ---');
        _append(result.stderr as String);
      }
      _append('─' * 40);
      _append('Exit ${result.exitCode}  ${result.exitCode == 0 ? "✓" : "✗"}');
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
          duration: const Duration(milliseconds: 200),
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

  // ================= TABS =================
  void _switchTab(int i) {
    if (i == _activeTab) return;
    _tabs[_activeTab].content = _codeController.text;
    setState(() => _activeTab = i);
    _codeController.text = _tabs[i].content;
  }

  void _newFile() {
    _tabs[_activeTab].content = _codeController.text;
    final name = 'untitled_${_tabs.length + 1}.py';
    setState(() {
      _tabs.add(EditorTabData(name: name, content: ''));
      _activeTab = _tabs.length - 1;
    });
    _codeController.text = '';
  }

  void _closeTab(int i) {
    if (_tabs.length == 1) {
      setState(() {
        _tabs[0] = EditorTabData(name: 'untitled.py', content: '');
        _codeController.text = '';
      });
      return;
    }
    setState(() {
      _tabs.removeAt(i);
      if (_activeTab >= _tabs.length) _activeTab = _tabs.length - 1;
      _codeController.text = _tabs[_activeTab].content;
    });
  }

  Future<void> _saveCurrentFile() async {
    _tabs[_activeTab].content = _codeController.text;
    final targetPath = _tabs[_activeTab].path ??
        '$_pythonRoot/${_tabs[_activeTab].name}';
    final f = File(targetPath);
    await f.writeAsString(_tabs[_activeTab].content);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved ${_tabs[_activeTab].name}'),
          duration: const Duration(seconds: 1),
          backgroundColor: const Color(0xFF252526),
        ),
      );
    }
  }

  // ================= OPEN FILE FROM DEVICE =================
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
        _tabs.add(
            EditorTabData(name: name, content: content, path: path));
        _activeTab = _tabs.length - 1;
      });
      _codeController.text = content;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e')),
        );
      }
    }
  }

  // ================= MENU =================
  Future<void> _handleMenu(String v) async {
    switch (v) {
      case 'new':
        _newFile();
        break;
      case 'files':
        await _openFileFromDevice();
        break;
      case 'save':
        await _saveCurrentFile();
        break;
      case 'close':
        _closeTab(_activeTab);
        break;
      case 'terminal':
        _openTerminal();
        break;
      case 'settings':
        _openSettings();
        break;
      case 'about':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AboutScreen()),
        );
        break;
      case 'help':
        _showHelp();
        break;
      case 'exit':
        SystemNavigator.pop();
        break;
    }
  }

  void _openTerminal() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TerminalScreen(
          pythonRoot: _pythonRoot,
          nativeLibDir: _nativeLibDir,
        ),
      ),
    );
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Text('PyIDE — Help',
            style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 15)),
        content: const Text(
          '• Run: ▶ icon in the app bar\n'
          '• Save: pencil icon\n'
          '• Files: tap ⋮ → Files\n'
          '• Terminal: tap ⋮ → Terminal\n'
          '• Resize console: drag the handle\n'
          '• Special keys: long-press the ▲ button\n'
          '• Toggle console: tap the ▲ button',
          style: TextStyle(
              height: 1.6, color: Color(0xFFCCCCCC), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          initialFontSize: _fontSize,
          initialTheme: _themeName,
          initialShowLineNumbers: _showLineNumbers,
          onFontSizeChanged: (v) => setState(() => _fontSize = v),
          onThemeChanged: (k) => setState(() => _themeName = k),
          onLineNumbersChanged: (v) => setState(() => _showLineNumbers = v),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _codeController.removeListener(_onControllerChanged);
    _codeController.dispose();
    _editorFocus.dispose();
    _outputController.dispose();
    _outputScroll.dispose();
    super.dispose();
  }

  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      drawer: Drawer(
        backgroundColor: const Color(0xFF1E1E1E),
        width: MediaQuery.of(context).size.width * 0.82,
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
      appBar: _buildAppBar(),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _buildFileTabs(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final total = constraints.maxHeight;
                      final consoleH = (_showConsole
                              ? total * _consoleFraction
                              : 0)
                          .toDouble();
                      final editorH = total -
                          consoleH -
                          (_showConsole ? 12 : 0);

                      return Column(
                        children: [
                          SizedBox(height: editorH, child: _buildEditor()),
                          if (_showConsole) _buildDragHandle(total),
                          if (_showConsole)
                            SizedBox(
                                height: consoleH, child: _buildConsole()),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            // Special keys — floats above the keyboard
            if (_showSpecialKeys)
              Positioned(
                left: 0,
                right: 0,
                bottom: viewInsets,
                child: _buildSpecialKeysBar(),
              ),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  // ================= APP BAR =================
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1E1E1E),
      toolbarHeight: 48,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: Color(0xFFCCCCCC), size: 20),
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          if (!_isSetupComplete && !_hasError)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: Color(0xFFD29922)),
              ),
            ),
          if (_hasError)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFF85149),
              ),
            ),
          Flexible(
            child: Text(
              _tabs[_activeTab].name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFFD4D4D4),
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined,
              color: Color(0xFFCCCCCC), size: 18),
          onPressed: _saveCurrentFile,
          tooltip: 'Save',
        ),
        IconButton(
          icon: _isRunning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF4A9EFF)),
                )
              : const Icon(Icons.play_arrow_rounded,
                  color: Color(0xFF4A9EFF), size: 24),
          onPressed: _isSetupComplete && !_isRunning ? _runCode : null,
          tooltip: 'Run',
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert,
              color: Color(0xFFCCCCCC), size: 18),
          color: const Color(0xFF2D2D30),
          onSelected: _handleMenu,
          itemBuilder: (_) => const [
            PopupMenuItem(
                value: 'new',
                child: _MenuRow(Icons.add, 'New file')),
            PopupMenuItem(
                value: 'files',
                child: _MenuRow(Icons.folder_open, 'Files')),
            PopupMenuItem(
                value: 'save',
                child: _MenuRow(Icons.save_outlined, 'Save')),
            PopupMenuItem(
                value: 'close',
                child: _MenuRow(Icons.close, 'Close file')),
            PopupMenuDivider(),
            PopupMenuItem(
                value: 'terminal',
                child: _MenuRow(Icons.terminal, 'Terminal')),
            PopupMenuDivider(),
            PopupMenuItem(
                value: 'settings',
                child: _MenuRow(Icons.settings_outlined, 'Settings')),
            PopupMenuItem(
                value: 'about',
                child: _MenuRow(Icons.info_outline, 'About')),
            PopupMenuItem(
                value: 'help',
                child: _MenuRow(Icons.help_outline, 'Help')),
            PopupMenuDivider(),
            PopupMenuItem(
                value: 'exit',
                child: _MenuRow(Icons.logout, 'Exit')),
          ],
        ),
      ],
    );
  }

  // ================= FILE TABS =================
  Widget _buildFileTabs() {
    return Container(
      height: 33,
      color: const Color(0xFF252526),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        itemBuilder: (_, i) {
          final active = i == _activeTab;
          return GestureDetector(
            onTap: () => _switchTab(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF1E1E1E)
                    : const Color(0xFF2D2D30),
                border: Border(
                  bottom: BorderSide(
                    color: active
                        ? const Color(0xFF4A9EFF)
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined,
                      size: 12, color: Color(0xFF4A9EFF)),
                  const SizedBox(width: 6),
                  Text(
                    _tabs[i].name,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: active
                          ? const Color(0xFFD4D4D4)
                          : const Color(0xFF888888),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _closeTab(i),
                    child: const Icon(Icons.close,
                        size: 12, color: Color(0xFF888888)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ================= EDITOR =================
  Widget _buildEditor() {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: CodeTheme(
        data: CodeThemeData(styles: _themeStyles),
        child: CodeField(
          controller: _codeController,
          focusNode: _editorFocus,
          expands: true,
          wrap: false,
          textStyle: TextStyle(
            fontFamily: 'monospace',
            fontSize: _fontSize,
            height: 1.5,
          ),
          gutterStyle: GutterStyle(
            width: _showLineNumbers ? 40 : 0,
            showLineNumbers: _showLineNumbers,
            showErrors: false,
            showFoldingHandles: _showLineNumbers,
            textStyle: TextStyle(
              fontFamily: 'monospace',
              fontSize: _fontSize - 0.5,
              height: 1.5,
              color: const Color(0xFF5C6370),
            ),
          ),
        ),
      ),
    );
  }

  // ================= DRAG HANDLE =================
  Widget _buildDragHandle(double total) {
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
        height: 12,
        color: const Color(0xFF1E1E1E),
        child: Center(
          child: Container(
            width: 40,
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFF5A5A5A),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  // ================= CONSOLE =================
  Widget _buildConsole() {
    return Container(
      color: const Color(0xFF161616),
      child: Column(
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            color: const Color(0xFF252526),
            child: Row(
              children: [
                _smallBtn(
                    Icons.backspace_outlined, 'Clear', _clearConsole),
                _smallBtn(Icons.keyboard_hide_outlined, 'Hide keyboard', () {
                  FocusScope.of(context).unfocus();
                }),
                const Spacer(),
                const Text(
                  'OUTPUT',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF888888),
                  ),
                ),
                const Spacer(),
                _smallBtn(Icons.close, 'Hide console', () {
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
                        'Output will appear here...',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
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
                          fontSize: 11,
                          height: 1.5,
                          color: Color(0xFFD4D4D4),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallBtn(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 14, color: const Color(0xFFCCCCCC)),
        ),
      ),
    );
  }

  // ================= SPECIAL KEYS BAR =================
  Widget _buildSpecialKeysBar() {
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
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFF252526),
        border: Border(
          top: BorderSide(color: const Color(0xFF1E1E1E), width: 1),
        ),
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
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF4A9EFF).withOpacity(0.25)
                            : const Color(0xFF2D2D30),
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
                            fontWeight: FontWeight.w600,
                            color: active
                                ? const Color(0xFF4A9EFF)
                                : const Color(0xFFD4D4D4),
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
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Color(0xFF2D2D30),
                border: Border(
                  left: BorderSide(color: Color(0xFF1E1E1E)),
                ),
              ),
              child: const Center(
                child: Icon(Icons.close,
                    size: 14, color: Color(0xFFCCCCCC)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= FAB =================
  Widget _buildFAB() {
    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        setState(() => _showSpecialKeys = !_showSpecialKeys);
      },
      child: FloatingActionButton(
        mini: true,
        backgroundColor: const Color(0xFF2D2D30),
        elevation: 3,
        onPressed: () {
          HapticFeedback.lightImpact();
          setState(() => _showConsole = !_showConsole);
        },
        child: Icon(
          _showConsole
              ? Icons.keyboard_arrow_down
              : Icons.keyboard_arrow_up,
          color: const Color(0xFFCCCCCC),
        ),
      ),
    );
  }
}

// ================= MENU ROW =================
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuRow(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFFCCCCCC)),
        const SizedBox(width: 12),
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: Color(0xFFD4D4D4))),
      ],
    );
  }
}

// ================= SIDEBAR =================
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
          width: 50,
          color: const Color(0xFF181818),
          child: Column(
            children: [
              const SizedBox(height: 30),
              _strip(Icons.folder_outlined, 0, 'Files'),
              _strip(Icons.search, 1, 'Search'),
              _strip(Icons.notifications_none, 2, 'Alerts'),
              _strip(Icons.favorite_border, 3, 'Favorites'),
              _strip(Icons.person_outline, 4, 'Profile'),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF1E1E1E),
            child: _buildContent(context),
          ),
        ),
      ],
    );
  }

  Widget _strip(IconData icon, int index, String tip) {
    final active = activeIndex == index;
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: () => onIndexChanged(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: active
                    ? const Color(0xFF4A9EFF)
                    : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Icon(
            icon,
            size: 19,
            color: active
                ? const Color(0xFFD4D4D4)
                : const Color(0xFF6A6A6A),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (activeIndex) {
      case 0:
        return _filesPanel();
      case 1:
        return _placeholder(
            'SEARCH', Icons.search, 'Search across files coming soon.');
      case 2:
        return _placeholder(
            'ALERTS', Icons.notifications_none, 'No new notifications.');
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
          padding: EdgeInsets.fromLTRB(14, 20, 14, 10),
          child: Text('FILES',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF888888),
              )),
        ),
        Expanded(
          child: files.isEmpty
              ? const Center(
                  child: Text('No files open',
                      style: TextStyle(
                          fontSize: 11.5, color: Color(0xFF666666))),
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: files
                      .map((f) => ListTile(
                            dense: true,
                            visualDensity:
                                const VisualDensity(vertical: -3),
                            leading: const Icon(
                                Icons.description_outlined,
                                size: 16,
                                color: Color(0xFF4A9EFF)),
                            title: Text(f,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFD4D4D4))),
                            onTap: () => onFileTap(f),
                          ))
                      .toList(),
                ),
        ),
      ],
    );
  }

  Widget _placeholder(String title, IconData icon, String msg) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(title,
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF888888),
                )),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 36, color: const Color(0xFF444444)),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(msg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11.5, color: Color(0xFF888888))),
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
          padding: EdgeInsets.fromLTRB(14, 20, 14, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('PROFILE',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF888888),
                )),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2D2D30),
                    border: Border.all(
                        color: const Color(0xFF3A3A3A), width: 1.5),
                  ),
                  child: const Icon(Icons.person_outline,
                      size: 30, color: Color(0xFF6A6A6A)),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Not signed in',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFFD4D4D4),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Sign in to sync your files across devices.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF888888),
                    height: 1.5,
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
                            content: Text('Sign-in coming soon')),
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
                      side: const BorderSide(color: Color(0xFF3A3A3A)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Create account coming soon')),
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
