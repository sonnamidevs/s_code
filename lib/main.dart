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

  bool _isSetupComplete = false;
  bool _isRunning = false;
  String _status = 'Preparing runtime...';

  String? _pythonRoot;
  String? _pythonBin;

  // Bump this when extraction logic changes to force re-extraction
  static const String _extractVersion = 'v2';

  @override
  void initState() {
    super.initState();
    _setupPython();
  }

  Future<void> _setupPython() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      _pythonRoot = '${docsDir.path}/pyenv';
      _pythonBin = '$_pythonRoot/bin/python3';

      final root = Directory(_pythonRoot!);
      final versionFile = File('$_pythonRoot/.$_extractVersion');

      // Force re-extraction if version marker is missing
      if (!versionFile.existsSync()) {
        if (root.existsSync()) {
          setState(() => _status = 'Cleaning old runtime...');
          root.deleteSync(recursive: true);
        }

        setState(() => _status = 'Extracting Python runtime...');
        await root.create(recursive: true);

        // Extract the tar.gz
        final data = await rootBundle.load('assets/python/python-embed.tar.gz');
        final tmpTar = File('$_pythonRoot/py.tar.gz');
        await tmpTar.writeAsBytes(data.buffer.asUint8List());

        setState(() => _status = 'Unpacking runtime (be patient)...');

        // Use -p to preserve permissions from the archive
        final extract = await Process.run(
          '/system/bin/sh',
          ['-c', 'cd "$_pythonRoot" && tar -xpf py.tar.gz'],
        );
        _append('tar exit: ${extract.exitCode}');
        if ((extract.stderr as String).isNotEmpty) {
          _append('tar err: ${extract.stderr}');
        }
        await tmpTar.delete();

        // Fix permissions explicitly via sh
        setState(() => _status = 'Setting permissions...');
        final chmod = await Process.run(
          '/system/bin/sh',
          [
            '-c',
            'chmod -R 755 "$_pythonRoot/bin" "$_pythonRoot/lib" 2>&1'
          ],
        );
        _append('chmod exit: ${chmod.exitCode}');
        if ((chmod.stdout as String).isNotEmpty) {
          _append('chmod out: ${chmod.stdout}');
        }
        if ((chmod.stderr as String).isNotEmpty) {
          _append('chmod err: ${chmod.stderr}');
        }

        // Ensure python3 itself is executable
        await Process.run(
          '/system/bin/sh',
          ['-c', 'chmod 755 "$_pythonBin" 2>&1'],
        );

        // Verify: list the bin folder
        final ls = await Process.run(
          '/system/bin/sh',
          ['-c', 'ls -la "$_pythonRoot/bin"'],
        );
        _append('--- bin listing ---');
        _append(ls.stdout as String);

        await versionFile.writeAsString(_extractVersion);
      } else {
        _append('Runtime already extracted ($_extractVersion).');
      }

      setState(() {
        _isSetupComplete = true;
        _status = 'Ready';
      });
      _append('Python runtime ready at:');
      _append(_pythonRoot!);
    } catch (e, st) {
      _append('Setup failed: $e');
      _append(st.toString());
      setState(() => _status = 'Setup failed');
    }
  }

  Future<void> _runHello() async {
    if (!_isSetupComplete || _pythonBin == null) return;

    setState(() {
      _isRunning = true;
      _outputController.clear();
    });

    _append('>>> Running hello.py');
    _append('');

    final scriptFile = File('$_pythonRoot/hello.py');
    await scriptFile.writeAsString('''
print("Hello from Python on Android!")
print("-" * 30)
for i in range(1, 6):
    print(f"Line {i}")
print("-" * 30)
print("S Code prototype: working.")
''');

    try {
      // Run through sh with proper env variables
      final cmd = '''
export PYTHONHOME="$_pythonRoot"
export PYTHONPATH="$_pythonRoot/stdlib"
export LD_LIBRARY_PATH="$_pythonRoot/lib"
"$_pythonBin" "${scriptFile.path}"
''';

      final result = await Process.run(
        '/system/bin/sh',
        ['-c', cmd],
      );

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
      appBar: AppBar(
        title: const Text('S Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reinstall runtime',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Reinstall runtime?'),
                  content: const Text('This re-extracts Python. Takes ~30s.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Reinstall'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                final root = Directory(_pythonRoot!);
                if (root.existsSync()) root.deleteSync(recursive: true);
                setState(() {
                  _isSetupComplete = false;
                  _status = 'Reinstalling...';
                });
                _setupPython();
              }
            },
          ),
        ],
      ),
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
              label: Text(
                _isRunning ? 'Running...' : 'Run hello.py',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
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
