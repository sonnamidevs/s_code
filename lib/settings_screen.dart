import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

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

  // Same themes as main.dart
  static const Map<String, String> _themeNames = {
    'atom-one-dark': 'Atom One Dark',
    'atom-one-light': 'Atom One Light',
    'github': 'GitHub',
    'monokai': 'Monokai',
    'vs2015': 'VS 2015',
  };

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

  // === Cross-Version Android Permission Handling ===
  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // 1. Try Android 11+ All Files Access
    if (await Permission.manageExternalStorage.isGranted) return true;
    var status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;

    // 2. Fallback for Android 6-10 (Legacy Storage)
    status = await Permission.storage.request();
    if (status.isGranted) return true;

    return false;
  }

  Future<void> _pickFolder() async {
    final granted = await _requestStoragePermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage permission denied. Cannot access external folders.'),
            backgroundColor: Color(0xFF2C2C2C),
          ),
        );
      }
      return;
    }

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
          // ============ EDITOR SETTINGS ============
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Text('EDITOR', style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w600, color: Color(0xFF7A7A7A))),
          ),
          
          // Font Size Slider
          ListTile(
            title: const Text('Font Size', style: TextStyle(fontSize: 14, color: Color(0xFFCCCCCC))),
            subtitle: Text('${_fontSize.toStringAsFixed(1)} pt', style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
            trailing: SizedBox(
              width: 140,
              child: Slider(
                value: _fontSize,
                min: 10,
                max: 24,
                divisions: 28,
                activeColor: const Color(0xFF4A9EFF),
                inactiveColor: const Color(0xFF303030),
                onChanged: (val) {
                  setState(() => _fontSize = val);
                  widget.onFontSizeChanged(val);
                },
              ),
            ),
          ),

          // Line Numbers Toggle
          SwitchListTile(
            title: const Text('Show Line Numbers', style: TextStyle(fontSize: 14, color: Color(0xFFCCCCCC))),
            subtitle: const Text('Display line numbers in the editor gutter', style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
            value: _showLineNumbers,
            activeColor: const Color(0xFF4A9EFF),
            onChanged: (val) {
              setState(() => _showLineNumbers = val);
              widget.onLineNumbersChanged(val);
            },
          ),

          // Theme Picker
          ListTile(
            title: const Text('Editor Theme', style: TextStyle(fontSize: 14, color: Color(0xFFCCCCCC))),
            subtitle: Text(_themeNames[_themeName] ?? _themeName, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
            trailing: const Icon(Icons.color_lens_outlined, color: Color(0xFF4A9EFF)),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF252525),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  title: const Text('Choose Theme', style: TextStyle(fontSize: 15, color: Color(0xFFCCCCCC))),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _themeNames.entries.map((e) {
                      return RadioListTile<String>(
                        title: Text(e.value, style: const TextStyle(fontSize: 13, color: Color(0xFFCCCCCC))),
                        value: e.key,
                        groupValue: _themeName,
                        activeColor: const Color(0xFF4A9EFF),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _themeName = val);
                            widget.onThemeChanged(val);
                            Navigator.pop(ctx);
                          }
                        },
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),

          const Divider(color: Color(0xFF2A2A2A), height: 30),

          // ============ STORAGE SETTINGS ============
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('FILE STORAGE', style: TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w600, color: Color(0xFF7A7A7A))),
          ),
          const ListTile(
            title: Text('File Storage', style: TextStyle(fontSize: 14, color: Color(0xFFCCCCCC))),
            subtitle: Text('Choose where your Python files are saved', style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
          ),
          SwitchListTile(
            title: const Text('Use External Storage', style: TextStyle(fontSize: 14, color: Color(0xFFCCCCCC))),
            subtitle: const Text('Save to device storage (requires permission)', style: TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
            value: _useExternal,
            activeColor: const Color(0xFF4A9EFF),
            onChanged: (val) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('use_external_storage', val);
              setState(() => _useExternal = val);
              if (val) _pickFolder();
            },
          ),
          if (_useExternal)
            ListTile(
              title: const Text('External Folder Path', style: TextStyle(fontSize: 14, color: Color(0xFFCCCCCC))),
              subtitle: Text(_externalPath.isEmpty ? 'Tap to select folder' : _externalPath, style: const TextStyle(fontSize: 12, color: Color(0xFF7A7A7A))),
              trailing: const Icon(Icons.folder_open, color: Color(0xFF4A9EFF)),
              onTap: _pickFolder,
            ),
        ],
      ),
    );
  }
}
