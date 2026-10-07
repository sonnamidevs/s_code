import 'dart:async';
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
import 'package:firebase_core/firebase_core.dart';
import 'auth_service.dart';
import 'auth_screen.dart';
import 'settings_screen.dart';
import 'about_screen.dart';
import 'terminal_screen.dart';
import 'collaboration_service.dart';
import 'collaboration_screen.dart';
import 'file_sync_service.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await AuthService().init();
  await NotificationService().init();
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
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF2C2C2C),
          contentTextStyle: TextStyle(color: Colors.white, fontSize: 13),
          actionTextColor: Color(0xFF4A9EFF),
          behavior: SnackBarBehavior.floating,
          elevation: 6.0,
        ),
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
  Process? _currentProcess;

  // === [MODIFIED] Buffers and Timer for smooth infinite loop output ===
  Timer? _consoleTimer;
  final StringBuffer _consoleBuffer = StringBuffer();

  String? _nativeLibDir;
  String? _pythonRoot;

  late final CodeController _codeController;
  final FocusNode _editorFocus = FocusNode();
  final ScrollController _editorScrollController = ScrollController();
  
  bool _isAutoIndenting = false;
  bool _isApplyingRemote = false;
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

  // Search
  final _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _searchResults = [];

  final TextEditingController _outputController = TextEditingController();
  final ScrollController _outputScroll = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final _collab = CollaborationService();

  bool _signInPromptShownThisSession = false;
  int _lastSyncedTabHash = 0;

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
    _initApp();

    _collab.codeStream.listen((code) {
      if (!_collab.isConnected) return;
      if (_codeController.text == code) return;
      _isApplyingRemote = true;
      final sel = _codeController.selection;
      _codeController.text = code;
      if (sel.isValid && sel.baseOffset <= code.length) {
        _codeController.selection = sel;
      }
      _isApplyingRemote = false;
    });

    _collab.usersStream.listen((users) {
      final myUid = AuthService().currentUser?.uid;
      for (final u in users.values) {
        if (u.id != myUid) {
          NotificationService().push(
            title: '${u.name} joined',
            body: 'A collaborator is now editing with you.',
            type: 'collab_join',
            icon: Icons.person_add_outlined,
          );
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 8), _maybeSignInPrompt);
    });
  }

  Future<void> _initApp() async {
    await _loadTabs();
    if (AuthService().isSignedIn) {
      final remote = await FileSyncService().fetchTabs();
      if (remote != null && remote.isNotEmpty) {
        final local = _tabs.map((t) => t.toJson()).toList();
        if (_tabsCountHash(remote) != _tabsCountHash(local)) {
          if (mounted) {
            setState(() {
              _tabs.clear();
              for (final item in remote) {
                _tabs.add(EditorTabData.fromJson(item));
              }
              if (_activeTab >= _tabs.length) _activeTab = 0;
              _codeController.text = _tabs[_activeTab].content;
            });
            NotificationService().push(
              title: 'Files synced',
              body: 'Your files were loaded from the cloud.',
              type: 'file_sync',
              icon: Icons.cloud_done_outlined,
            );
          }
        }
      }
    }
    _setupPython();
  }

  int _tabsCountHash(List<Map<String, dynamic>> tabs) {
    int h = tabs.length;
    for (final t in tabs) {
      h = h * 31 + (t['name'] as String).hashCode;
    }
    return h;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveTabs();
      _syncToCloud();
    }
  }

  Future<void> _syncToCloud() async {
    if (!AuthService().isSignedIn) return;
    if (_tabs.isEmpty) return;
    _tabs[_activeTab].content = _codeController.text;
    await FileSyncService().uploadTabs(_tabs.map((t) => t.toJson()).toList());
  }

  Future<void> _maybeSignInPrompt() async {
    if (!mounted) return;
    if (AuthService().isSignedIn) return;
    if (_signInPromptShownThisSession) return;

    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt('signin_prompt_last') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < const Duration(days: 3).inMilliseconds) return;
    await prefs.setInt('signin_prompt_last', now);
    _signInPromptShownThisSession = true;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Sign in to sync files and collaborate in real time →',
          style: TextStyle(fontSize: 13),
        ),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF252525),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'Sign In',
          textColor: const Color(0xFF4A9EFF),
          onPressed: _openSignIn,
        ),
      ),
    );
  }

  void _openSignIn() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AuthScreen(
          allowSkip: true,
          onSignedIn: () async {
            Navigator.pop(context);
            setState(() {});
            await _syncToCloud();
            final remote = await FileSyncService().fetchTabs();
            if (remote != null && remote.isNotEmpty && mounted) {
              setState(() {
                _tabs.clear();
                for (final item in remote) {
                  _tabs.add(EditorTabData.fromJson(item));
                }
                if (_activeTab >= _tabs.length) _activeTab = 0;
                _codeController.text = _tabs[_activeTab].content;
              });
            }
            if (!mounted) return;
            NotificationService().push(
              title: 'Welcome, ${AuthService().displayName}!',
              body: 'Your files are now syncing across devices.',
              type: 'signed_in',
              icon: Icons.check_circle_outline,
            );
          },
        ),
      ),
    );
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

  void _onControllerChanged() {
    if (_collab.isConnected && !_isApplyingRemote) {
      _collab.sendCode(_codeController.text);
      _collab.sendCursor(_codeController.selection.baseOffset);
    }
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

  // ============ SEARCH ============
  void _runSearch(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    final results = <Map<String, dynamic>>[];
    for (int t = 0; t < _tabs.length; t++) {
      final tab = _tabs[t];
      final content = (t == _activeTab) ? _codeController.text : tab.content;
      final lines = content.split('\n');
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.toLowerCase().contains(query)) {
          results.add({
            'tabIndex': t,
            'tabName': tab.name,
            'line': i + 1,
            'content': line.trim(),
          });
        }
      }
    }
    setState(() => _searchResults = results);
  }

  void _jumpToResult(Map<String, dynamic> r) {
    final t = r['tabIndex'] as int;
    if (t != _activeTab) _switchTab(t);
    final line = r['line'] as int;
    final text = _codeController.text;
    final lines = text.split('\n');
    int offset = 0;
    for (int i = 0; i < line - 1 && i < lines.length; i++) {
      offset += lines[i].length + 1;
    }
    _codeController.selection = TextSelection.collapsed(offset: offset);
    _editorFocus.requestFocus();
    Navigator.pop(context);
  }

  Future<void> _setupPython() async {
    try {
      _nativeLibDir = await _channel.invokeMethod('getNativeLibraryDir');
      if (_nativeLibDir == null || _nativeLibDir!.isEmpty) {
        throw Exception('Native dir unavailable');
      }

      final docsDir = await getApplicationDocumentsDirectory();
      _pythonRoot = '${docsDir.path}/python_runtime';
      final root = Directory(_pythonRoot!);

      final wrapper = File('$_nativeLibDir/libpython3-exec.so');
      if (!wrapper.existsSync()) throw Exception('Python wrapper not found');

      final marker = File('${root.path}/.extracted_v8');
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
if [ -d "_tmp/lib" ]; then
  cp _tmp/lib/*.so* lib/ 2>/dev/null || true
fi
rm -rf _tmp
mkdir -p lib
cp "${_nativeLibDir}"/*.so lib/ 2>/dev/null || true
cd lib
[ -f libz.so ] && ln -sf libz.so libz.so.1
[ -f libssl.so ] && ln -sf libssl.so libssl.so.3
[ -f libcrypto.so ] && ln -sf libcrypto.so libcrypto.so.3
[ -f libsqlite3.so ] && ln -sf libsqlite3.so libsqlite3.so.0
[ -f libffi.so ] && ln -sf libffi.so libffi.so.8
[ -f libbz2.so ] && ln -sf libbz2.so libbz2.so.1.0
[ -f liblzma.so ] && ln -sf liblzma.so liblzma.so.5
[ -f libexpat.so ] && ln -sf libexpat.so libexpat.so.1
[ -f libreadline.so ] && ln -sf libreadline.so libreadline.so.8
[ -f libncursesw.so ] && ln -sf libncursesw.so libncursesw.so.6
[ -f libtinfo.so ] && ln -sf libtinfo.so libtinfo.so.6
''';
        await Process.run('/system/bin/sh', ['-c', script]);
        await tmpTar.delete();

        if (!File('${root.path}/lib/python3.14/encodings/__init__.py')
            .existsSync()) {
          throw Exception('encodings missing');
        }
        await marker.writeAsString('v8');
      }

      setState(() => _isSetupComplete = true);
    } catch (e) {
      _consoleBuffer.writeln('Setup failed: $e');
      if (mounted) setState(() => _outputController.text = _consoleBuffer.toString());
    }
  }

  Map<String, String> _runEnv() {
    return {
      'PYTHONHOME': _pythonRoot ?? '',
      'PYTHONPATH': '${_pythonRoot}/lib/python3.14',
      'LD_LIBRARY_PATH': '${_pythonRoot}/lib:${_nativeLibDir ?? ''}',
    };
  }

  Future<String> _getSaveDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final useExternal = prefs.getBool('use_external_storage') ?? false;

    if (useExternal) {
      final path = prefs.getString('external_storage_path');
      if (path != null && path.isNotEmpty && await Directory(path).exists()) {
        return path;
      }
    }

    final appDir = await getApplicationDocumentsDirectory();
    final homeDir = Directory('${appDir.path}/home');
    if (!await homeDir.exists()) {
      await homeDir.create(recursive: true);
    }
    return homeDir.path;
  }

  // ============ RUN CODE (LIVE STREAM FIX) ============
  Future<void> _runCode() async {
    if (!_isSetupComplete || _nativeLibDir == null || _pythonRoot == null) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isRunning = true;
      _showConsole = true;
    });

    _consoleBuffer.clear();
    _consoleBuffer.writeln('');
    _consoleBuffer.writeln('▶ ${DateTime.now().toString().substring(11, 19)}');
    _consoleBuffer.writeln('─' * 40);

    // Timer updates the UI every 100ms instead of thousands of times per second
    _consoleTimer?.cancel();
    _consoleTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        setState(() {
          _outputController.text = _consoleBuffer.toString();
        });
        _scrollToBottom();
      }
    });

    final dir = await _getSaveDirectory();
    final scriptFile = File('$dir/script.py');
    await scriptFile.writeAsString(_codeController.text);

    try {
      final cmd = '"$_nativeLibDir/libpython3-exec.so" "${scriptFile.path}"';
      _currentProcess = await Process.start(
        '/system/bin/sh',
        ['-c', cmd],
        environment: _runEnv(),
        includeParentEnvironment: true,
      );

      _currentProcess!.stdout.transform(utf8.decoder).listen((data) {
        _consoleBuffer.write(data);
      });

      _currentProcess!.stderr.transform(utf8.decoder).listen((data) {
        _consoleBuffer.write(data);
      });

      final exitCode = await _currentProcess!.exitCode;
      _consoleTimer?.cancel();
      if (mounted) {
        _consoleBuffer.writeln('─' * 40);
        _consoleBuffer.writeln('[Done] exit $exitCode');
        setState(() {
          _outputController.text = _consoleBuffer.toString();
          _isRunning = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      _consoleTimer?.cancel();
      if (mounted) {
        _consoleBuffer.writeln('Run error: $e');
        setState(() {
          _outputController.text = _consoleBuffer.toString();
          _isRunning = false;
        });
      }
    }
  }

  void _stopCode() {
    _consoleTimer?.cancel();
    _currentProcess?.kill();
    setState(() => _isRunning = false);
    _consoleBuffer.writeln('Process stopped by user');
    setState(() {
      _outputController.text = _consoleBuffer.toString();
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_outputScroll.hasClients) {
        _outputScroll.animateTo(_outputScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut);
      }
    });
  }

  void _clearConsole() {
    _consoleBuffer.clear();
    setState(() => _outputController.clear());
  }

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
    _syncToCloud();
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
    _syncToCloud();
  }

  void _closeTab(int i) {
    if (_tabs.length == 1) {
      setState(() {
        _tabs[0] = EditorTabData(name: 'untitled.py', content: '');
        _codeController.text = '';
      });
      _saveTabs();
      _syncToCloud();
      return;
    }
    setState(() {
      _tabs.removeAt(i);
      if (_activeTab >= _tabs.length) _activeTab = _tabs.length - 1;
      _codeController.text = _tabs[_activeTab].content;
    });
    _saveTabs();
    _syncToCloud();
  }

  // ============ SAVE FILE WITH DIALOG ============
  Future<void> _saveCurrentFile() async {
    _tabs[_activeTab].content = _codeController.text;
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252525),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Save File', style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 16)),
        content: const Text('Choose where to save this file:', style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final dir = await _getSaveDirectory();
              final path = '${dir}/${_tabs[_activeTab].name}';
              await _writeFile(path);
            },
            child: const Text('Sandbox (Home)', style: TextStyle(color: Color(0xFF4A9EFF))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final path = await FilePicker.platform.saveFile(
                dialogTitle: 'Save to device',
                fileName: _tabs[_activeTab].name,
                type: FileType.any,
              );
              if (path != null) {
                await _writeFile(path);
              }
            },
            child: const Text('Device Storage', style: TextStyle(color: Color(0xFF4A9EFF))),
          ),
        ],
      ),
    );
  }

  Future<void> _writeFile(String path) async {
    try {
      final file = File(path);
      await file.writeAsString(_tabs[_activeTab].content);
      _tabs[_activeTab].path = path;
      _tabs[_activeTab].name = path.split('/').last;
      await _saveTabs();
      await _syncToCloud();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${_tabs[_activeTab].name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  Future<void> _openFileFromDevice() async {
    try {
      final dir = await _getSaveDirectory();
      final result = await FilePicker.platform.pickFiles(
        initialDirectory: dir,
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
      await _syncToCloud();
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
      case 'new': _newFile(); break;
      case 'files': _openFileFromDevice(); break;
      case 'save': await _saveCurrentFile(); break;
      case 'close': _closeTab(_activeTab); break;
      case 'search':
        setState(() => _sidebarIndex = 1);
        _scaffoldKey.currentState?.openDrawer();
        break;
      case 'notifications':
        setState(() => _sidebarIndex = 2);
        _scaffoldKey.currentState?.openDrawer();
        break;
      case 'collab':
        if (!AuthService().isSignedIn) {
          _showSignInRequiredDialog();
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CollaborationScreen(
              onContentReceived: (content) {
                _isApplyingRemote = true;
                final sel = _codeController.selection;
                _codeController.text = content;
                if (sel.isValid && sel.baseOffset <= content.length) {
                  _codeController.selection = sel;
                }
                _isApplyingRemote = false;
              },
            ),
          ),
        );
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
              onLineNumbersChanged: (v) => setState(() => _showLineNumbers = v),
            ),
          ),
        );
        break;
      case 'about':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()));
        break;
      case 'signin': _openSignIn(); break;
      case 'signout':
        await AuthService().signOut();
        if (mounted) setState(() {});
        break;
      case 'exit':
        await _saveTabs();
        await _syncToCloud();
        SystemNavigator.pop();
        break;
    }
  }

  void _showSignInRequiredDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF252525),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.group_add_outlined, size: 20, color: Color(0xFF4A9EFF)),
            SizedBox(width: 10),
            Text('Sign in required', style: TextStyle(fontSize: 15, color: Color(0xFFCCCCCC))),
          ],
        ),
        content: const Text(
          'Sign in to sync files across devices and collaborate in real time.',
          style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFFAAAAAA)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later', style: TextStyle(color: Color(0xFF888888))),
          ),
          FilledButton(
            onPressed: () { Navigator.pop(ctx); _openSignIn(); },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4A9EFF), foregroundColor: Colors.white),
            child: const Text('Sign In'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTabs();
    _consoleTimer?.cancel(); // Fix: Cancel timer to prevent memory leak
    _codeController.removeListener(_onControllerChanged);
    _codeController.dispose();
    _editorFocus.dispose();
    _editorScrollController.dispose();
    _outputController.dispose();
    _outputScroll.dispose();
    _searchController.dispose();
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
        width: MediaQuery.of(context).size.width * 0.82,
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
          searchController: _searchController,
          searchQuery: _searchQuery,
          searchResults: _searchResults,
          onSearchChanged: (q) { _searchQuery = q; _runSearch(q); },
          onResultTap: _jumpToResult,
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
                      final consoleH = (_showConsole ? total * _consoleFraction : 0).toDouble();
                      final editorH = total - consoleH - (_showConsole ? 10 : 0);
                      return Column(
                        children: [
                          SizedBox(height: editorH, child: _editor()),
                          if (_showConsole) _dragHandle(total),
                          if (_showConsole) SizedBox(height: consoleH, child: _console()),
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
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w400, color: Color(0xFFCCCCCC)),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 17, color: Color(0xFFAAAAAA)),
          splashRadius: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          onPressed: _saveCurrentFile,
        ),
        IconButton(
          icon: _isRunning
              ? const Icon(Icons.stop_rounded, size: 22, color: Colors.redAccent)
              : const Icon(Icons.play_arrow_rounded, size: 22, color: Color(0xFF4A9EFF)),
          splashRadius: 22,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          onPressed: _isSetupComplete ? (_isRunning ? _stopCode : _runCode) : null,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFFAAAAAA)),
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
          itemBuilder: (_) {
            final signed = AuthService().isSignedIn;
            return [
              _mi('new', Icons.note_add_outlined, 'New file'),
              _mi('files', Icons.folder_open_outlined, 'Files'),
              _mi('save', Icons.save_outlined, 'Save'),
              _mi('close', Icons.close, 'Close file'),
              _divider(),
              _mi('search', Icons.search, 'Search'),
              _mi('notifications', Icons.notifications_none, 'Notifications'),
              _divider(),
              _mi('collab', Icons.group_add_outlined, 'Collaborate'),
              _mi('terminal', Icons.terminal_outlined, 'Terminal'),
              _divider(),
              _mi('settings', Icons.settings_outlined, 'Settings'),
              _mi('about', Icons.info_outline, 'About'),
              _divider(),
              if (!signed) _mi('signin', Icons.login, 'Sign in')
              else _mi('signout', Icons.person_remove_outlined, 'Sign out'),
              _mi('exit', Icons.logout_outlined, 'Exit'),
            ];
          },
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
          Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w400, color: Color(0xFFCCCCCC))),
        ],
      ),
    );
  }

  PopupMenuDivider _divider() => const PopupMenuDivider(height: 1, color: Color(0xFF2A2A2A));

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
                  color: active ? const Color(0xFF252525) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.description_outlined, size: 12, color: active ? const Color(0xFF4A9EFF) : const Color(0xFF666666)),
                    const SizedBox(width: 6),
                    Text(_tabs[i].name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: active ? const Color(0xFFCCCCCC) : const Color(0xFF7A7A7A))),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _closeTab(i),
                      child: const Icon(Icons.close, size: 12, color: Color(0xFF666666)),
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
    final lineCount = '\n'.allMatches(_codeController.text).length + 1;
    final digits = lineCount.toString().length;
    
    double gutterWidth = 60;
    double gutterFontSize = 12;
    
    if (digits == 4) {
      gutterWidth = 72;
      gutterFontSize = 11;
    } else if (digits >= 5) {
      gutterWidth = 84;
      gutterFontSize = 9.5;
    }

    return Container(
      color: const Color(0xFF1E1E1E),
      child: CodeTheme(
        data: CodeThemeData(styles: _themeStyles),
        child: GestureDetector(
          onVerticalDragUpdate: (details) {
            if (_editorScrollController.hasClients) {
              _editorScrollController.jumpTo(
                (_editorScrollController.offset - details.delta.dy)
                    .clamp(0.0, _editorScrollController.position.maxScrollExtent),
              );
            }
          },
          child: CodeField(
            controller: _codeController,
            focusNode: _editorFocus,
            expands: false,
            wrap: true,
            // This gives the extra space at the bottom so you can scroll past the last line
            padding: const EdgeInsets.only(bottom: 300, top: 8, left: 4, right: 4),
            scrollController: _editorScrollController,
            textStyle: TextStyle(
              fontFamily: 'monospace',
              fontSize: _fontSize,
              height: 1.5,
            ),
            gutterStyle: GutterStyle(
              width: gutterWidth,
              showLineNumbers: _showLineNumbers,
              showErrors: false,
              showFoldingHandles: false,
              textStyle: TextStyle(
                fontFamily: 'monospace',
                fontSize: gutterFontSize,
                height: 1.5,
                color: const Color(0xFF5C6370),
              ),
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
                _icon(Icons.keyboard_hide_outlined, () => FocusScope.of(context).unfocus()),
                const Spacer(),
                const Text('OUTPUT', style: TextStyle(fontSize: 10, letterSpacing: 1.4, fontWeight: FontWeight.w500, color: Color(0xFF6A6A6A))),
                const Spacer(),
                _icon(Icons.close, () => setState(() => _showConsole = false)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _outputController.text.isEmpty
                  ? const Center(
                      child: Text('Output will appear here', style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Color(0xFF5A5A5A))),
                    )
                  : SingleChildScrollView(
                      controller: _outputScroll,
                      child: Text(
                        _outputController.text,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.5, color: Color(0xFFCCCCCC)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFF4A9EFF).withOpacity(0.22) : const Color(0xFF252525),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: active ? const Color(0xFF4A9EFF) : Colors.transparent,
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
                            color: active ? const Color(0xFF4A9EFF) : const Color(0xFFCCCCCC),
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
          _showConsole ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
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
  final TextEditingController searchController;
  final String searchQuery;
  final List<Map<String, dynamic>> searchResults;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Map<String, dynamic>> onResultTap;

  const SidebarContent({
    super.key,
    required this.activeIndex,
    required this.onIndexChanged,
    required this.files,
    required this.onFileTap,
    required this.searchController,
    required this.searchQuery,
    required this.searchResults,
    required this.onSearchChanged,
    required this.onResultTap,
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
              const SizedBox(height: 14),
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
              color: active ? const Color(0xFF252525) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: active ? const Color(0xFF4A9EFF) : const Color(0xFF7A7A7A),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    switch (activeIndex) {
      case 0: return _filesPanel();
      case 1: return _searchPanel();
      case 2: return _notificationsPanel();
      case 3: return _placeholder('FAVORITES', Icons.favorite_border, 'No favorites yet.');
      case 4: return _profilePanel(context);
      default: return const SizedBox.shrink();
    }
  }

  Widget _filesPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 18, 14, 8),
          child: Text('FILES', style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w600, color: Color(0xFF7A7A7A))),
        ),
        Expanded(
          child: files.isEmpty
              ? const Center(child: Text('No files open', style: TextStyle(fontSize: 12, color: Color(0xFF666666))))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  itemCount: files.length,
                  itemBuilder: (_, i) {
                    final name = files[i];
                    return InkWell(
                      onTap: () => onFileTap(name),
                      borderRadius: BorderRadius.circular(7),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        margin: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.description_outlined, size: 15, color: Color(0xFF4A9EFF)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Color(0xFFCCCCCC)))),
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

  Widget _searchPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 18, 14, 8),
          child: Text('SEARCH', style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w600, color: Color(0xFF7A7A7A))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            style: const TextStyle(fontSize: 13, color: Color(0xFFCCCCCC)),
            decoration: InputDecoration(
              hintText: 'Search in all files...',
              hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF5A5A5A)),
              prefixIcon: const Icon(Icons.search, size: 16, color: Color(0xFF888888)),
              filled: true,
              fillColor: const Color(0xFF202020),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (searchQuery.isEmpty)
          const Expanded(child: Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('Type to search across all open files.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF666666))))))
        else if (searchResults.isEmpty)
          const Expanded(child: Center(child: Text('No matches', style: TextStyle(fontSize: 12, color: Color(0xFF666666)))))
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              itemCount: searchResults.length,
              itemBuilder: (_, i) {
                final r = searchResults[i];
                return InkWell(
                  onTap: () => onResultTap(r),
                  borderRadius: BorderRadius.circular(7),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(color: const Color(0xFF202020), borderRadius: BorderRadius.circular(7)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.description_outlined, size: 12, color: Color(0xFF4A9EFF)),
                            const SizedBox(width: 6),
                            Expanded(child: Text('${r['tabName']}:${r['line']}', style: const TextStyle(fontSize: 11, color: Color(0xFF888888), fontWeight: FontWeight.w500))),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(r['content'] as String, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Color(0xFFCCCCCC), fontFamily: 'monospace')),
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

  Widget _notificationsPanel() {
    return StreamBuilder<List<AppNotification>>(
      stream: NotificationService().stream,
      initialData: NotificationService().items,
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];
        return Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(14, 18, 14, 8),
                    child: Text('NOTIFICATIONS', style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w600, color: Color(0xFF7A7A7A))),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFF7A7A7A)),
                  onPressed: () => NotificationService().clear(),
                ),
              ],
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('No notifications', style: TextStyle(fontSize: 12, color: Color(0xFF666666))))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final n = items[i];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(color: const Color(0xFF202020), borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(n.icon, size: 16, color: const Color(0xFF4A9EFF)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(n.title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFCCCCCC))),
                                    const SizedBox(height: 3),
                                    Text(n.body, style: const TextStyle(fontSize: 11.5, color: Color(0xFFAAAAAA), height: 1.4)),
                                    const SizedBox(height: 4),
                                    Text(_timeAgo(n.timestamp), style: const TextStyle(fontSize: 10, color: Color(0xFF666666))),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _placeholder(String title, IconData icon, String msg) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
          child: Align(alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w600, color: Color(0xFF7A7A7A)))),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 32, color: const Color(0xFF444444)),
                const SizedBox(height: 10),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A)))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _profilePanel(BuildContext context) {
    final signed = AuthService().isSignedIn;
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 18, 14, 8),
          child: Align(alignment: Alignment.centerLeft, child: Text('PROFILE', style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w600, color: Color(0xFF7A7A7A)))),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
            child: signed ? _signedInProfile(context) : _signedOutProfile(context),
          ),
        ),
      ],
    );
  }

  Widget _signedInProfile(BuildContext context) {
    final verified = AuthService().isEmailVerified;
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF4A9EFF), Color(0xFF3FB950)])),
          child: Center(
            child: Text(
              AuthService().displayName.isNotEmpty ? AuthService().displayName[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(AuthService().displayName, style: const TextStyle(fontSize: 14, color: Color(0xFFCCCCCC), fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(AuthService().email, style: const TextStyle(fontSize: 11.5, color: Color(0xFF7A7A7A))),
        const SizedBox(height: 16),
        if (!verified)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: const Color(0xFFD29922).withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFD29922).withOpacity(0.4))),
            child: Column(
              children: [
                const Text('Email not verified', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFD29922))),
                const SizedBox(height: 4),
                const Text('Check your inbox and click the verification link.', style: TextStyle(fontSize: 11.5, color: Color(0xFFAAAAAA), height: 1.4)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      await AuthService().resendVerification();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification email sent')));
                      }
                    },
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFD29922), side: const BorderSide(color: Color(0xFFD29922)), padding: const EdgeInsets.symmetric(vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                    child: const Text('Resend', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF202020), borderRadius: BorderRadius.circular(10)),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Signed in', style: TextStyle(fontSize: 11, color: Color(0xFF7A7A7A))),
              SizedBox(height: 4),
              Text('Files sync automatically. Collaborate anytime.', style: TextStyle(fontSize: 12, color: Color(0xFFAAAAAA), height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _signedOutProfile(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF252525), border: Border.all(color: const Color(0xFF303030), width: 1.5)),
          child: const Icon(Icons.person_outline, size: 28, color: Color(0xFF6A6A6A)),
        ),
        const SizedBox(height: 12),
        const Text('Not signed in', style: TextStyle(fontSize: 13, color: Color(0xFFCCCCCC), fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        const Text('Sign in to sync files and collaborate in real time.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A), height: 1.4)),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4A9EFF), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(context),
            child: const Text('Sign in', style: TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }
}
