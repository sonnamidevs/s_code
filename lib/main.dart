import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/python.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';

// ================= APP ENTRY =================
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PrideApp());
}

class PrideApp extends StatelessWidget {
  const PrideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pride',
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
          centerTitle: true,
        ),
      ),
      home: const MainScaffold(),
    );
  }
}

// ================= DATA MODELS =================
class EditorTabData {
  String name;
  String content;
  EditorTabData({required this.name, required this.content});
}

// ================= MAIN SCAFFOLD =================
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  // Runtime
  static const MethodChannel _channel =
      MethodChannel('com.sonnamidevs.s_code/native');
  bool _isSetupComplete = false;
  bool _isRunning = false;
  String _status = 'Preparing runtime...';
  String? _nativeLibDir;
  String? _pythonRoot;

  // Editor
  late final CodeController _codeController;
  final FocusNode _editorFocus = FocusNode();
  bool _isAutoIndenting = false;

  // Tabs
  final List<EditorTabData> _tabs = [];
  int _activeTab = 0;

  // UI state
  double _fontSize = 14;
  bool _showConsole = true;
  bool _showToolbar = true;
  int _sidebarIndex = 0;

  // Console
  final TextEditingController _outputController = TextEditingController();
  final ScrollController _outputScroll = ScrollController();

  // Sidebar drawer key
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const String _welcomeCode = '''# Welcome to Pride
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
    _codeController.addListener(_onCodeChanged);
    _tabs.add(EditorTabData(name: 'main.py', content: _welcomeCode));
    _loadFontSize();
    _setupPython();
  }

  Future<void> _loadFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    final size = prefs.getDouble('font_size') ?? 14.0;
    if (mounted) setState(() => _fontSize = size);
  }

  Future<void> _saveFontSize(double size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('font_size', size);
  }

  // ================= AUTO-INDENT =================
  void _onCodeChanged() {
    if (_isAutoIndenting) return;

    final value = _codeController.value;
    final text = value.text;
    final sel = value.selection;

    if (!sel.isValid || !sel.isCollapsed) return;
    final pos = sel.baseOffset;
    if (pos <= 0 || pos > text.length) return;
    if (text[pos - 1] != '\n') return;

    final before = text.substring(0, pos - 1);
    final lastNl = before.lastIndexOf('\n');
    final prevLine =
        lastNl == -1 ? before : before.substring(lastNl + 1);

    if (prevLine.trim().isEmpty) return;

    final leading = prevLine.length - prevLine.trimLeft().length;
    var indent = ' ' * leading;

    if (prevLine.trimRight().endsWith(':')) {
      indent += '    ';
    }

    if (indent.isEmpty) return;

    _isAutoIndenting = true;
    try {
      _codeController.value = value.copyWith(
        text: text.substring(0, pos) + indent + text.substring(pos),
        selection:
            TextSelection.collapsed(offset: pos + indent.length),
        composing: TextRange.empty,
      );
    } finally {
      _isAutoIndenting = false;
    }
  }

  // ================= PYTHON SETUP =================
  Future<void> _setupPython() async {
    try {
      setState(() => _status = 'Locating native directory...');
      _nativeLibDir = await _channel.invokeMethod('getNativeLibraryDir');
      if (_nativeLibDir == null || _nativeLibDir!.isEmpty) {
        throw Exception('Could not determine native library directory.');
      }

      final docsDir = await getApplicationDocumentsDirectory();
      _pythonRoot = '${docsDir.path}/python_runtime';
      final root = Directory(_pythonRoot!);

      final wrapper = File('$_nativeLibDir/libpython3-exec.so');
      if (!wrapper.existsSync()) {
        throw Exception('Python wrapper not found.');
      }

      final marker = File('${root.path}/.extracted_v7');
      if (!marker.existsSync()) {
        setState(() => _status = 'Extracting Python runtime...');
        if (root.existsSync()) root.deleteSync(recursive: true);
        await root.create(recursive: true);

        final data =
            await rootBundle.load('assets/python/python-embed.tar.gz');
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
          throw Exception('encodings module missing');
        }
        await marker.writeAsString('v7');
      }

      setState(() {
        _isSetupComplete = true;
        _status = 'Ready';
      });
    } catch (e) {
      _append('Setup failed: $e');
      setState(() => _status = 'Setup failed');
    }
  }

  // ================= RUN CODE =================
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
    _append('─' * 44);

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
      _append('─' * 44);
      _append(
          'Exit ${result.exitCode}  ${result.exitCode == 0 ? "✓" : "✗"}');
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

  // ================= TAB MANAGEMENT =================
  void _switchTab(int i) {
    if (i == _activeTab) return;
    _tabs[_activeTab].content = _codeController.text;
    setState(() => _activeTab = i);
    _codeController.text = _tabs[i].content;
  }

  void _newFile() {
    final name = 'untitled_${_tabs.length + 1}.py';
    _tabs[_activeTab].content = _codeController.text;
    setState(() {
      _tabs.add(EditorTabData(name: name, content: ''));
      _activeTab = _tabs.length - 1;
    });
    _codeController.text = '';
  }

  void _closeTab(int i) {
    if (_tabs.length == 1) {
      _newFile();
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
    final f = File('$_pythonRoot/${_tabs[_activeTab].name}');
    await f.writeAsString(_tabs[_activeTab].content);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved ${_tabs[_activeTab].name}')),
      );
    }
  }

  // ================= MENU =================
  Future<void> _handleMenu(String value) async {
    switch (value) {
      case 'new':
        _newFile();
        break;
      case 'save':
        await _saveCurrentFile();
        break;
      case 'saveas':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save As coming soon')),
        );
        break;
      case 'files':
        setState(() => _sidebarIndex = 0);
        _scaffoldKey.currentState?.openDrawer();
        break;
      case 'close':
        _closeTab(_activeTab);
        break;
      case 'recent':
        _showRecentFiles();
        break;
      case 'find':
        _showFindDialog();
        break;
      case 'console':
        setState(() => _showConsole = !_showConsole);
        break;
      case 'terminal':
        _showTerminalPlaceholder();
        break;
      case 'settings':
        _openSettings();
        break;
      case 'help':
        _showHelp();
        break;
      case 'exit':
        _showExitConfirm();
        break;
    }
  }

  void _showRecentFiles() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF252526),
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recent Files',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ..._tabs.map((t) => ListTile(
                  leading: const Icon(Icons.description_outlined,
                      size: 20, color: Color(0xFF4A9EFF)),
                  title: Text(t.name),
                  onTap: () {
                    Navigator.pop(context);
                    _switchTab(_tabs.indexOf(t));
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showFindDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Text('Find'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search in file...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final query = controller.text;
              if (query.isNotEmpty) {
                final idx = _codeController.text.indexOf(query);
                if (idx >= 0) {
                  _codeController.selection = TextSelection(
                    baseOffset: idx,
                    extentOffset: idx + query.length,
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Not found')),
                  );
                }
              }
              Navigator.pop(context);
            },
            child: const Text('Find'),
          ),
        ],
      ),
    );
  }

  void _showTerminalPlaceholder() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Interactive terminal coming in a future update'),
      ),
    );
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Text('Pride — Help'),
        content: const SingleChildScrollView(
          child: Text(
            'Shortcuts:\n\n'
            '• Run: tap the ▶ icon in the app bar\n'
            '• Clear console: 🧹 icon in the app bar\n'
            '• Auto-indent: press Enter after a line ending with :\n'
            '• Font size: three-dot menu → Settings\n'
            '• File tabs: tap to switch, ✕ to close\n\n'
            'Tips:\n'
            '• Python 3.14 runs on-device\n'
            '• No internet required after install\n'
            '• Save files to keep them between sessions',
            style: TextStyle(height: 1.5),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showExitConfirm() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF252526),
        title: const Text('Exit Pride?'),
        content: const Text('Any unsaved changes will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              SystemNavigator.pop();
            },
            child: const Text('Exit'),
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
          fontSize: _fontSize,
          onFontSizeChanged: (v) {
            setState(() => _fontSize = v);
            _saveFontSize(v);
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    _editorFocus.dispose();
    _outputController.dispose();
    _outputScroll.dispose();
    super.dispose();
  }

  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        backgroundColor: const Color(0xFF1E1E1E),
        width: MediaQuery.of(context).size.width * 0.85,
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
      body: Column(
        children: [
          _buildStatusBar(),
          _buildFileTabs(),
          Expanded(
            flex: 3,
            child: _buildEditor(),
          ),
          if (_showConsole) ...[
            _buildActionRow(),
            Expanded(
              flex: 2,
              child: _buildConsole(),
            ),
          ],
        ],
      ),
      floatingActionButton: _buildFloatingButton(),
    );
  }

  // ================= APP BAR =================
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1E1E1E),
      leading: IconButton(
        icon: const Icon(Icons.menu, color: Color(0xFFCCCCCC)),
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      title: Text(
        _tabs[_activeTab].name,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFFCCCCCC),
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: Color(0xFFCCCCCC)),
          onPressed: _saveCurrentFile,
          tooltip: 'Save',
        ),
        IconButton(
          icon: _isRunning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF4A9EFF)),
                )
              : const Icon(Icons.play_arrow_rounded,
                  color: Color(0xFF4A9EFF), size: 26),
          onPressed: _isSetupComplete && !_isRunning ? _runCode : null,
          tooltip: 'Run',
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Color(0xFFCCCCCC)),
          color: const Color(0xFF2D2D30),
          onSelected: _handleMenu,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'new', child: _MenuRow(Icons.add, 'New file')),
            PopupMenuItem(
                value: 'save', child: _MenuRow(Icons.save_outlined, 'Save')),
            PopupMenuItem(
                value: 'saveas',
                child: _MenuRow(Icons.save_as_outlined, 'Save as')),
            PopupMenuItem(
                value: 'files',
                child: _MenuRow(Icons.folder_outlined, 'Files')),
            PopupMenuItem(
                value: 'close',
                child: _MenuRow(Icons.close, 'Close file')),
            PopupMenuItem(
                value: 'recent',
                child: _MenuRow(Icons.history, 'Open recent')),
            PopupMenuItem(
                value: 'find',
                child: _MenuRow(Icons.search, 'Find file')),
            PopupMenuItem(
                value: 'console',
                child: _MenuRow(Icons.terminal, 'Console')),
            PopupMenuItem(
                value: 'terminal',
                child: _MenuRow(Icons.code, 'Terminal')),
            PopupMenuItem(
                value: 'settings',
                child: _MenuRow(Icons.settings_outlined, 'Settings')),
            PopupMenuItem(
                value: 'help',
                child: _MenuRow(Icons.help_outline, 'Help')),
            PopupMenuItem(
                value: 'exit', child: _MenuRow(Icons.logout, 'Exit')),
          ],
        ),
      ],
    );
  }

  // ================= STATUS BAR =================
  Widget _buildStatusBar() {
    Color c;
    IconData icon;
    if (_isSetupComplete) {
      c = const Color(0xFF3FB950);
      icon = Icons.check_circle_outline;
    } else if (_status == 'Setup failed') {
      c = const Color(0xFFF85149);
      icon = Icons.error_outline;
    } else {
      c = const Color(0xFFD29922);
      icon = Icons.hourglass_top;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFF161616),
      child: Row(
        children: [
          Icon(icon, color: c, size: 13),
          const SizedBox(width: 8),
          Text(
            _status,
            style: TextStyle(fontSize: 11, color: c),
          ),
          const Spacer(),
          Text(
            'Python 3.14',
            style: TextStyle(
              fontSize: 11,
              color: const Color(0xFF888888),
            ),
          ),
        ],
      ),
    );
  }

  // ================= FILE TABS =================
  Widget _buildFileTabs() {
    return Container(
      height: 38,
      color: const Color(0xFF252526),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        itemBuilder: (_, i) {
          final active = i == _activeTab;
          return GestureDetector(
            onTap: () => _switchTab(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
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
                      size: 14, color: Color(0xFF4A9EFF)),
                  const SizedBox(width: 8),
                  Text(
                    _tabs[i].name,
                    style: TextStyle(
                      fontSize: 13,
                      color: active
                          ? const Color(0xFFD4D4D4)
                          : const Color(0xFF888888),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _closeTab(i),
                    child: const Icon(Icons.close,
                        size: 14, color: Color(0xFF888888)),
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
        data: CodeThemeData(styles: atomOneDarkTheme),
        child: CodeField(
          controller: _codeController,
          focusNode: _editorFocus,
          textStyle: TextStyle(
            fontFamily: 'monospace',
            fontSize: _fontSize,
            height: 1.5,
          ),
          gutterStyle: GutterStyle(
            width: 46,
            showLineNumbers: true,
            showErrors: false,
            showFoldingHandles: true,
            textStyle: TextStyle(
              fontFamily: 'monospace',
              fontSize: _fontSize,
              height: 1.5,
              color: const Color(0xFF5C6370),
            ),
          ),
        ),
      ),
    );
  }

  // ================= ACTION ROW =================
  Widget _buildActionRow() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFF252526),
      child: Row(
        children: [
          _toolbarIcon(Icons.backspace_outlined, 'Clear console', _clearConsole),
          const SizedBox(width: 4),
          _toolbarIcon(Icons.keyboard_hide_outlined, 'Hide keyboard', () {
            FocusScope.of(context).unfocus();
          }),
          const Spacer(),
          const Text(
            'Output',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              color: Color(0xFF888888),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbarIcon(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: const Color(0xFFCCCCCC)),
        ),
      ),
    );
  }

  // ================= CONSOLE =================
  Widget _buildConsole() {
    return Container(
      color: const Color(0xFF161616),
      padding: const EdgeInsets.all(12),
      width: double.infinity,
      child: _outputController.text.isEmpty
          ? const Center(
              child: Text(
                'Output will appear here...',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
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
                  fontSize: 12,
                  height: 1.5,
                  color: Color(0xFFD4D4D4),
                ),
              ),
            ),
    );
  }

  // ================= FLOATING BUTTON =================
  Widget _buildFloatingButton() {
    return FloatingActionButton(
      mini: true,
      backgroundColor: const Color(0xFF2D2D30),
      elevation: 4,
      onPressed: () {
        setState(() => _showToolbar = !_showToolbar);
      },
      child: const Icon(Icons.keyboard_arrow_up,
          color: Color(0xFFCCCCCC)),
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
        Icon(icon, size: 18, color: const Color(0xFFCCCCCC)),
        const SizedBox(width: 14),
        Text(label,
            style: const TextStyle(fontSize: 14, color: Color(0xFFD4D4D4))),
      ],
    );
  }
}

// ================= SIDEBAR (DRAWER) =================
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
        // Icon strip
        Container(
          width: 56,
          color: const Color(0xFF181818),
          child: Column(
            children: [
              const SizedBox(height: 40),
              _stripIcon(Icons.folder_outlined, 0, 'Files'),
              _stripIcon(Icons.search, 1, 'Search'),
              _stripIcon(Icons.notifications_none, 2, 'Notifications'),
              _stripIcon(Icons.favorite_border, 3, 'Favorites'),
              _stripIcon(Icons.person_outline, 4, 'About'),
            ],
          ),
        ),
        // Content
        Expanded(
          child: Container(
            color: const Color(0xFF1E1E1E),
            child: _buildContent(context),
          ),
        ),
      ],
    );
  }

  Widget _stripIcon(IconData icon, int index, String tooltip) {
    final active = activeIndex == index;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onIndexChanged(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: active ? const Color(0xFF4A9EFF) : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: active ? const Color(0xFFD4D4D4) : const Color(0xFF6A6A6A),
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
        return _placeholderPanel('Search', Icons.search,
            'Search across files coming soon.');
      case 2:
        return _placeholderPanel('Notifications', Icons.notifications_none,
            'No new notifications.');
      case 3:
        return _placeholderPanel(
            'Favorites', Icons.favorite_border, 'No favorites yet.');
      case 4:
        return _aboutPanel(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _filesPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text(
            'FILES',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF888888),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: files
                .map((f) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.description_outlined,
                          size: 18, color: Color(0xFF4A9EFF)),
                      title: Text(f,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFFD4D4D4))),
                      onTap: () => onFileTap(f),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _placeholderPanel(String title, IconData icon, String message) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF888888),
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 42, color: const Color(0xFF444444)),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF888888)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _aboutPanel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text(
            'ABOUT',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF888888),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4A9EFF), Color(0xFF3FB950)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4A9EFF).withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'BN',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Bismark Nana Konadu',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD4D4D4),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '@Sonnami Devs',
                  style: TextStyle(
                    fontSize: 13,
                    color: const Color(0xFF4A9EFF),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252526),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF3A3A3A), width: 1),
                  ),
                  child: Column(
                    children: const [
                      _InfoRow(label: 'Studio', value: 'Sonnami Develops'),
                      _InfoRow(label: 'Country', value: 'Ghana 🇬🇭'),
                      _InfoRow(label: 'App', value: 'Pride IDE'),
                      _InfoRow(label: 'Version', value: '0.2.0'),
                      _InfoRow(label: 'Runtime', value: 'Python 3.14'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Built with care in Ghana.\nPride runs Python natively on Android.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: Color(0xFF888888),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF888888)),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFD4D4D4),
            ),
          ),
        ],
      ),
    );
  }
}

// ================= SETTINGS SCREEN =================
class SettingsScreen extends StatefulWidget {
  final double fontSize;
  final ValueChanged<double> onFontSizeChanged;

  const SettingsScreen({
    super.key,
    required this.fontSize,
    required this.onFontSizeChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _size;

  @override
  void initState() {
    super.initState();
    _size = widget.fontSize;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Settings'),
        iconTheme: const IconThemeData(color: Color(0xFFD4D4D4)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'EDITOR',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF252526),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Font size',
                        style: TextStyle(
                            fontSize: 14, color: Color(0xFFD4D4D4))),
                    const Spacer(),
                    Text(
                      '${_size.toStringAsFixed(0)} pt',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4A9EFF),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _size,
                  min: 10,
                  max: 28,
                  divisions: 18,
                  activeColor: const Color(0xFF4A9EFF),
                  inactiveColor: const Color(0xFF3A3A3A),
                  onChanged: (v) {
                    setState(() => _size = v);
                    widget.onFontSizeChanged(v);
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Preview:',
                  style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'def greet(name):\n    return f"Hello, {name}!"',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: _size,
                      height: 1.5,
                      color: const Color(0xFFD4D4D4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Center(
            child: Text(
              'Pride IDE · Sonnami Develops',
              style: TextStyle(
                fontSize: 11,
                color: const Color(0xFF5A5A5A),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
