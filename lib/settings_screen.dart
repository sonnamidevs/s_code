import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  final double initialFontSize;
  final String initialTheme;
  final bool initialShowLineNumbers;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<String> onThemeChanged;
  final ValueChanged<bool> onLineNumbersChanged;

  const SettingsScreen({
    Key? key,
    required this.initialFontSize,
    required this.initialTheme,
    required this.initialShowLineNumbers,
    required this.onFontSizeChanged,
    required this.onThemeChanged,
    required this.onLineNumbersChanged,
  }) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _fontSize;
  late String _themeName;
  late bool _showLineNumbers;
  bool _useExternal = false;
  String _externalPath = '';

  @override
  void initState() {
    super.initState();
    _fontSize = widget.initialFontSize;
    _themeName = widget.initialTheme;
    _showLineNumbers = widget.initialShowLineNumbers;
    _loadStorageSettings();
  }

  Future<void> _loadStorageSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useExternal = prefs.getBool('use_external_storage') ?? false;
      _externalPath = prefs.getString('external_storage_path') ?? '';
    });
  }

  Future<void> _pickFolder() async {
    String? path = await FilePicker.platform.getDirectoryPath();
    if (path != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('external_storage_path', path);
      setState(() => _externalPath = path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          const ListTile(
            title: Text('File Storage', style: TextStyle(fontSize: 14, color: Color(0xFFCCCCCC))),
            subtitle: Text('Choose where your Python files are saved', style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
          ),
          SwitchListTile(
            title: const Text('Use External Storage', style: TextStyle(fontSize: 14, color: Color(0xFFCCCCCC))),
            subtitle: const Text('Save files to your device storage instead of the sandbox', style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
            value: _useExternal,
            onChanged: (val) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('use_external_storage', val);
              setState(() => _useExternal = val);
            },
          ),
          if (_useExternal)
            ListTile(
              title: const Text('External Folder Path', style: TextStyle(fontSize: 14, color: Color(0xFFCCCCCC))),
              subtitle: Text(_externalPath.isEmpty ? 'Not selected (using default)' : _externalPath, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
              trailing: const Icon(Icons.folder_open, color: Color(0xFF4A9EFF)),
              onTap: _pickFolder,
            ),
          const Divider(color: Color(0xFF2A2A2A)),
          // Add your existing font size, theme, and line number settings here
        ],
      ),
    );
  }
}
