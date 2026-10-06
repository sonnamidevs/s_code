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
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        toolbarHeight: 44,
        iconTheme:
            const IconThemeData(color: Color(0xFFAAAAAA), size: 18),
        title: const Text('Settings',
            style: TextStyle(
                fontSize: 13.5,
                color: Color(0xFFCCCCCC),
                fontWeight: FontWeight.w400)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: [
          _hdr('EDITOR'),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.text_fields,
                        size: 15, color: Color(0xFF4A9EFF)),
                    const SizedBox(width: 10),
                    const Text('Font size',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFFCCCCCC))),
                    const Spacer(),
                    Text('${_size.toStringAsFixed(1)} pt',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF4A9EFF),
                        )),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: _size,
                    min: 9,
                    max: 24,
                    divisions: 30,
                    activeColor: const Color(0xFF4A9EFF),
                    inactiveColor: const Color(0xFF2A2A2A),
                    onChanged: (v) {
                      setState(() => _size = v);
                      widget.onFontSizeChanged(v);
                      _persist();
                    },
                  ),
                ),
                const Divider(color: Color(0xFF2A2A2A), height: 20),
                Row(
                  children: [
                    const Icon(Icons.format_list_numbered,
                        size: 15, color: Color(0xFF4A9EFF)),
                    const SizedBox(width: 10),
                    const Text('Line numbers',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFFCCCCCC))),
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
          _hdr('THEME'),
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
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: active
                                  ? const Color(0xFF4A9EFF)
                                  : const Color(0xFF3A3A3A),
                              width: 1.8,
                            ),
                          ),
                          child: active
                              ? const Center(
                                  child: Icon(Icons.check,
                                      size: 10, color: Color(0xFF4A9EFF)),
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Text(t['name']!,
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFFCCCCCC))),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          _hdr('ABOUT'),
          _card(
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 15, color: Color(0xFF4A9EFF)),
                    const SizedBox(width: 10),
                    const Text('About PyIDE',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFFCCCCCC))),
                    const Spacer(),
                    const Icon(Icons.chevron_right,
                        size: 18, color: Color(0xFF6A6A6A)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hdr(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 18, 0, 8),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF7A7A7A),
          ),
        ),
      );

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding ?? const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF202020),
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      );
}
