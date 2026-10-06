import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

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
        title: const Text('About',
            style: TextStyle(
                fontSize: 13.5,
                color: Color(0xFFCCCCCC),
                fontWeight: FontWeight.w400)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4A9EFF), Color(0xFF3FB950)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4A9EFF).withOpacity(0.3),
                    blurRadius: 22,
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
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFFCCCCCC),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '@Sonnami Devs',
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF4A9EFF),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF202020),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: const [
                  _R('Studio', 'Sonnami Develops'),
                  _R('Country', 'Ghana 🇬🇭'),
                  _R('App', 'PyIDE'),
                  _R('Version', '0.4.0'),
                  _R('Runtime', 'Python 3.14'),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'A mobile Python IDE built from scratch.\nRuns natively on Android.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: Color(0xFF888888),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(color: Color(0xFF2A2A2A)),
            const SizedBox(height: 14),
            const Text(
              '© 2026 Sonnami Develops',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF6A6A6A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _R extends StatelessWidget {
  final String label;
  final String value;
  const _R(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12.5, color: Color(0xFF888888))),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFCCCCCC),
              )),
        ],
      ),
    );
  }
}
