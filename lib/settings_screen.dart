import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'about_screen.dart';

class SettingsScreen extends StatefulWidget {
  final double initialFontSize;
  final String initialTheme;
  final bool initialShowLineNumbers;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<String> onThemeChanged;
  final ValueChanged<bool> onLineNumbersChanged;

  const SettingsScreen({
    super.key,
    required this.initialFontSize,
    required this.initialTheme,
    required this.initialShowLineNumbers,
    required this.onFontSizeChanged,
    required this.onThemeChanged,
    required this.onLineNumbersChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _size;
  late String _theme;
  late bool _showLineNumbers;

  static const List<Map<String, String>> _themeOptions = [
    {'key': 'atom-one-dark', 'name': 'Atom One Dark'},
    {'key': 'atom-one-light', 'name': 'Atom One Light'},
    {'key': 'github', 'name': 'GitHub'},
    {'key': 'monokai', 'name': 'Monokai'},
    {'key': 'vs2015', 'name': 'VS 2015'},
  ];

  @override
  void initState() {
    super.initState();
    _size = widget.initialFontSize;
    _theme = widget.initialTheme;
    _showLineNumbers = widget.initialShowLineNumbers;
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('font_size', _size);
    await p.setString('theme', _theme);
    await p.setBool('show_line_numbers', _showLineNumbers);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        iconTheme: const IconThemeData(color: Color(0xFFD4D4D4)),
        title: const Text('Settings',
            style: TextStyle(fontSize: 16, color: Color(0xFFD4D4D4))),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _sectionHeader('EDITOR'),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.text_fields,
                        size: 18, color: Color(0xFF4A9EFF)),
                    const SizedBox(width: 10),
                    const Text('Font size',
                        style: TextStyle(fontSize: 14, color: Color(0xFFD4D4D4))),
                    const Spacer(),
                    Text('${_size.toStringAsFixed(0)} pt',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4A9EFF),
                        )),
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
                    _persist();
                  },
                ),
                const Divider(color: Color(0xFF2D2D30), height: 24),
                Row(
                  children: [
                    const Icon(Icons.format_list_numbered,
                        size: 18, color: Color(0xFF4A9EFF)),
                    const SizedBox(width: 10),
                    const Text('Show line numbers',
                        style: TextStyle(fontSize: 14, color: Color(0xFFD4D4D4))),
                    const Spacer(),
                    Switch(
                      value: _showLineNumbers,
                      activeColor: const Color(0xFF4A9EFF),
                      onChanged: (v) {
                        setState(() => _showLineNumbers = v);
                        widget.onLineNumbersChanged(v);
                        _persist();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          _sectionHeader('THEME'),
          _card(
            padding: EdgeInsets.zero,
            child: Column(
              children: _themeOptions.map((t) {
                final active = _theme == t['key'];
                return InkWell(
                  onTap: () {
                    setState(() => _theme = t['key']!);
                    widget.onThemeChanged(t['key']!);
                    _persist();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: active
                                  ? const Color(0xFF4A9EFF)
                                  : const Color(0xFF3A3A3A),
                              width: 2,
                            ),
                          ),
                          child: active
                              ? const Center(
                                  child: Icon(Icons.check,
                                      size: 12, color: Color(0xFF4A9EFF)),
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Text(t['name']!,
                            style: const TextStyle(
                                fontSize: 14, color: Color(0xFFD4D4D4))),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          _sectionHeader('ABOUT'),
          _card(
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 18, color: Color(0xFF4A9EFF)),
                    const SizedBox(width: 10),
                    const Text('About PyIDE',
                        style: TextStyle(fontSize: 14, color: Color(0xFFD4D4D4))),
                    const Spacer(),
                    const Icon(Icons.chevron_right,
                        size: 20, color: Color(0xFF6A6A6A)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
          Center(
            child: Text(
              'PyIDE · Sonnami Develops · v0.2.0',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF5A5A5A),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 0, 10),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
            color: Color(0xFF888888),
          ),
        ),
      );

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF252526),
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      );
}
