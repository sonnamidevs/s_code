import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        iconTheme: const IconThemeData(color: Color(0xFFD4D4D4)),
        title: const Text('About',
            style: TextStyle(fontSize: 16, color: Color(0xFFD4D4D4))),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4A9EFF), Color(0xFF3FB950)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4A9EFF).withOpacity(0.35),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'BN',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Bismark Nana Konadu',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFFD4D4D4),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '@Sonnami Devs',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF4A9EFF),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 30),
            _infoCard(children: const [
              _Row(label: 'Studio', value: 'Sonnami Develops'),
              _Row(label: 'Country', value: 'Ghana 🇬🇭'),
              _Row(label: 'App', value: 'PyIDE'),
              _Row(label: 'Version', value: '0.2.0'),
              _Row(label: 'Engine', value: 'Flutter'),
              _Row(label: 'Runtime', value: 'Python 3.14'),
            ]),
            const SizedBox(height: 26),
            const Text(
              'PyIDE is a mobile Python IDE built from scratch.\n'
              'No internet required. Runs natively on Android.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Color(0xFF888888),
              ),
            ),
            const SizedBox(height: 30),
            const Divider(color: Color(0xFF2D2D30)),
            const SizedBox(height: 20),
            const Text(
              'Built with care in Ghana.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF6A6A6A),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '© 2026 Sonnami Develops',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF5A5A5A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard({required List<Widget> children}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF252526),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: children),
      );
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF888888))),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFD4D4D4),
              )),
        ],
      ),
    );
  }
}
