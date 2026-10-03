import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _outputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  static const MethodChannel _channel =
      MethodChannel('com.sonnamidevs.s_code/native');

  bool _isSetupComplete = false;
  bool _isRunning = false;
  String _status = 'Preparing runtime...';

  String? _nativeLibDir;
  String? _pythonStdlibDir;

  @override
  void initState() {
    super.initState();
    _setupPython();
  }

  Future<void> _setupPython() async {
    try {
      setState(() => _status = 'Locating native directory...');
      _nativeLibDir = await _channel.invokeMethod('getNativeLibraryDir');

      if (_nativeLibDir == null || _nativeLibDir!.isEmpty) {
        throw Exception('Could not determine native library directory.');
      }

      final docsDir = await getApplicationDocumentsDirectory();
      _pythonStdlibDir = '${docsDir.path}/stdlib_extracted';
      final stdlibDir = Directory(_pythonStdlibDir!);

      // Check the wrapper binary is present
      final wrapper = File('$_nativeLibDir/libpython3-exec.so');
      if (!wrapper.existsSync()) {
        throw Exception(
            'Python wrapper not found in native library directory. Check jniLibs.');
      }

      // Check the real Python shared library is present
      final pyLibFiles = Directory(_nativeLibDir!)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('libpython3.') && f.path.endsWith('.so'))
          .toList();
      if (pyLibFiles.isEmpty) {
        throw Exception(
            'libpython3.x.so not found in native library directory. Check jniLibs.');
      }

      final versionMarker = File('${stdlibDir.path}/.extracted_v5');
      if (!versionMarker.existsSync()) {
        setState(() => _status = 'Extracting Python standard library...');
        if (stdlibDir.existsSync()) stdlibDir.deleteSync(recursive: true);
        await stdlibDir.create(recursive: true);

        final data = await rootBundle.load('assets/python/python-embed.tar.gz');
        final tmpTar = File('${docsDir.path}/py.tar.gz');
        await tmpTar.writeAsBytes(data.buffer.asUint8List());

        final result = await Process.run(
          '/system/bin/sh',
          [
            '-c',
            'cd "${stdlibDir.path}" && tar -xzf "${tmpTar.path}" stdlib lib'
          ],
        );

        if (result.exitCode != 0) {
          _append('Tar extraction error: ${result.stderr}');
        }
        await tmpTar.delete();
        await versionMarker.writeAsString('v5');
      }

      setState(() {
        _isSetupComplete = true;
        _status = 'Ready';
      });
      _append('Runtime ready.');
      _append('Native lib dir: $_nativeLibDir');
      _append('Python wrapper: ${wrapper.path}');
      _append(
          'Python libs: ${pyLibFiles.map((f) => f.path.split('/').last).join(', ')}');
      _append('Stdlib: $_pythonStdlibDir');
    } catch (e, st) {
      _append('Setup failed: $e');
      _append(st.toString());
      setState(() => _status = 'Setup failed');
    }
  }

  Future<void> _runHello() async {
    if (!_isSetupComplete || _nativeLibDir == null || _pythonStdlibDir == null) {
      return;
    }

    setState(() {
      _isRunning = true;
      _outputController.clear();
    });

    _append('>>> Running hello.py');
    _append('');

    final scriptFile = File('$_pythonStdlibDir/hello.py');
    await scriptFile.writeAsString('''
print("Hello from Python on Android!")
print("-" * 30)
import sys
print(f"Python version: {sys.version}")
print("S Code prototype: working.")
''');

    try {
      // Run the wrapper with LD_LIBRARY_PATH pointing at native lib dir
      // so it can find libpython3.14.so, libcrypto, etc.
      final cmd = '''
export PYTHONHOME="$_pythonStdlibDir/stdlib"
export PYTHONPATH="$_pythonStdlibDir/stdlib"
export LD_LIBRARY_PATH="$_nativeLibDir"
"$_nativeLibDir/libpython3-exec.so" "${scriptFile.path}"
''';

      final result = await Process.run('/system/bin/sh', ['-c', cmd]);

      _append('exit code: ${result.exitCode}');
      _append('');
      if ((result.stdout as String).isNotEmpty) {
        _append(result.stdout as String);
      }
      if ((result.stderr as String).isNotEmpty) {
        _append('--- stderr ---');
        _append(result.stderr as String);
      }
    } catch (e) {
      _append('Run error: $e');
    } finally {
      setState(() => _isRunning = false);
    }
  }

  void _append(String text) {
    _outputController.text += '$text\n';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _outputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('S Code')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusBanner(),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isSetupComplete && !_isRunning ? _runHello : null,
              icon: _isRunning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF0D1117),
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(_isRunning ? 'Running...' : 'Run hello.py'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3FB950),
                foregroundColor: const Color(0xFF0D1117),
                disabledBackgroundColor: const Color(0xFF30363D),
                disabledForegroundColor: const Color(0xFF8B949E),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'OUTPUT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: Color(0xFF8B949E),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildConsole()),
          ],
        ),
      ),
    );
  }

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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _status,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsole() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF010409),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Text(
          _outputController.text.isEmpty
              ? 'Output will appear here...'
              : _outputController.text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.5,
            color: _outputController.text.isEmpty
                ? const Color(0xFF484F58)
                : const Color(0xFFE6EDF3),
          ),
        ),
      ),
    );
  }
}
