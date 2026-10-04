import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/python.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';

// ================= APP ENTRY =================
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SCodeApp());
}

class SCodeApp extends StatelessWidget {
  const SCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'S Code',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF58A6FF),
          secondary: Color(0xFF3FB950),
          surface: Color(0xFF161B22),
          onSurface: Color(0xFFE6EDF3),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161B22),
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ================= HOME SCREEN =================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Runtime state
  static const MethodChannel _channel =
      MethodChannel('com.sonnamidevs.s_code/native');

  bool _isSetupComplete = false;
  bool _isRunning = false;
  String _status = 'Preparing runtime...';

  String? _nativeLibDir;
  String? _pythonRoot;

  // Editor state
  late final CodeController _codeController;

  // Console state
  final TextEditingController _outputController = TextEditingController();
  final ScrollController _outputScrollController = ScrollController();

  static const String _welcomeCode = '''# Welcome to S Code
# A real Python editor for Android.

import sys
import platform

def greet(name):
    return f"Hello, {name}!"

print(greet("Android"))
print(f"Python: {sys.version.split()[0]}")
print(f"Platform: {platform.machine()}")
''';

  @override
  void initState() {
    super.initState();
    _codeController = CodeController(
      text: _welcomeCode,
      language: python,
    );
    _setupPython();
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
        throw Exception('Python wrapper not found in native library directory.');
      }

      final versionMarker = File('${root.path}/.extracted_v7');
      if (!versionMarker.existsSync()) {
        setState(() => _status = 'Extracting Python runtime...');
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

        final encodingsCheck =
            File('${root.path}/lib/python3.14/encodings/__init__.py');
        if (!encodingsCheck.existsSync()) {
          throw Exception('encodings module missing after extraction');
        }

        await versionMarker.writeAsString('v7');
      }

      setState(() {
        _isSetupComplete = true;
        _status = 'Ready';
      });
    } catch (e, st) {
      _append('Setup failed: $e');
      _append(st.toString());
      setState(() => _status = 'Setup failed');
    }
  }

  // ================= RUN CODE =================
  Future<void> _runCode() async {
    if (!_isSetupComplete || _nativeLibDir == null || _pythonRoot == null) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isRunning = true);

    _append('');
    _append('▶ ${DateTime.now().toString().substring(11, 19)} — Running');
    _append('─' * 40);

    // Save the editor content to a file
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
      _append(
          'Exit code: ${result.exitCode}  ${result.exitCode == 0 ? "✓" : "✗"}');
    } catch (e) {
      _append('Run error: $e');
    } finally {
      setState(() => _isRunning = false);
    }
  }

  // ================= CONSOLE HELPERS =================
  void _append(String text) {
    _outputController.text += '$text\n';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_outputScrollController.hasClients) {
        _outputScrollController.animateTo(
          _outputScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearConsole() {
    setState(() {
      _outputController.clear();
    });
  }

  // ================= DISPOSE =================
  @override
  void dispose() {
    _codeController.dispose();
    _outputController.dispose();
    _outputScrollController.dispose();
    super.dispose();
  }

  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'S Code',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'Clear console',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: _clearConsole,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusBanner(),
          Expanded(
            flex: 3,
            child: _buildEditor(),
          ),
          _buildActionBar(),
          Expanded(
            flex: 2,
            child: _buildConsole(),
          ),
        ],
      ),
    );
  }

  // ================= STATUS BANNER =================
  Widget _buildStatusBanner() {
    Color color;
    IconData icon;

    if (_isSetupComplete) {
      color = const Color(0xFF3FB950);
      icon = Icons.check_circle_outline;
    } else if (_status == 'Setup failed') {
      color = const Color(0xFFF85149);
      icon = Icons.error_outline;
    } else {
      color = const Color(0xFFD29922);
      icon = Icons.hourglass_top;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border(
          bottom: BorderSide(color: color.withOpacity(0.2), width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _status,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= EDITOR =================
  Widget _buildEditor() {
    return Container(
      color: const Color(0xFF282C34),
      child: CodeTheme(
        data: CodeThemeData(styles: atomOneDarkTheme),
        child: CodeField(
          controller: _codeController,
          textStyle: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            height: 1.5,
          ),
          gutterStyle: const GutterStyle(
            width: 50,
            showLineNumbers: true,
            showErrors: false,
            showFoldingHandles: true,
            textStyle: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              height: 1.5,
              color: Color(0xFF5C6370),
            ),
          ),
        ),
      ),
    );
  }

  // ================= ACTION BAR =================
  Widget _buildActionBar() {
    return Container(
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: _isSetupComplete && !_isRunning ? _runCode : null,
            icon: _isRunning
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF0D1117),
                    ),
                  )
                : const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text(_isRunning ? 'Running...' : 'Run'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3FB950),
              foregroundColor: const Color(0xFF0D1117),
              disabledBackgroundColor: const Color(0xFF30363D),
              disabledForegroundColor: const Color(0xFF8B949E),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 10),
          TextButton.icon(
            onPressed: _clearConsole,
            icon: const Icon(Icons.backspace_outlined, size: 18),
            label: const Text('Clear'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8B949E),
            ),
          ),
          const Spacer(),
          const Text(
            'Python 3.14',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF8B949E),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ================= CONSOLE =================
  Widget _buildConsole() {
    return Container(
      color: const Color(0xFF010409),
      padding: const EdgeInsets.all(12),
      child: _outputController.text.isEmpty
          ? const Center(
              child: Text(
                'Output will appear here...',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Color(0xFF484F58),
                ),
              ),
            )
          : SingleChildScrollView(
              controller: _outputScrollController,
              child: Text(
                _outputController.text,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFFE6EDF3),
                ),
              ),
            ),
    );
  }
}
