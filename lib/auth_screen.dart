import 'package:flutter/material.dart';
import 'auth_service.dart';

class AuthScreen extends StatefulWidget {
  final VoidCallback onSignedIn;
  const AuthScreen({super.key, required this.onSignedIn});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _signInEmailCtrl = TextEditingController();
  final _signInPasswordCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() => _error = null));
  }

  Future<void> _signUp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await AuthService().signUp(
      username: _nameCtrl.text,
      email: _emailCtrl.text,
      password: _passwordCtrl.text,
    );
    setState(() => _loading = false);
    if (r.success) {
      widget.onSignedIn();
    } else {
      setState(() => _error = r.error);
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await AuthService().signIn(
      email: _signInEmailCtrl.text,
      password: _signInPasswordCtrl.text,
    );
    setState(() => _loading = false);
    if (r.success) {
      widget.onSignedIn();
    } else {
      setState(() => _error = r.error);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _signInEmailCtrl.dispose();
    _signInPasswordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF4A9EFF), Color(0xFF3FB950)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4A9EFF).withOpacity(0.3),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.terminal,
                          size: 36, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'PyIDE',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFCCCCCC),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Python IDE for Android',
                    style: TextStyle(
                        fontSize: 12.5, color: Color(0xFF7A7A7A)),
                  ),
                  const SizedBox(height: 30),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF202020),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabs,
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: const Color(0xFF4A9EFF),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicatorPadding: const EdgeInsets.all(4),
                      labelColor: Colors.white,
                      unselectedLabelColor: const Color(0xFF888888),
                      labelStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(height: 40, text: 'Sign In'),
                        Tab(height: 40, text: 'Sign Up'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 260,
                    child: TabBarView(
                      controller: _tabs,
                      children: [_signInForm(), _signUpForm()],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B6B).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFFFF6B6B).withOpacity(0.4)),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFFF6B6B)),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text(
                    'Your data stays on your device.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF666666)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _signInForm() {
    return Column(
      children: [
        _field(_signInEmailCtrl, 'Email', Icons.email_outlined),
        const SizedBox(height: 10),
        _field(_signInPasswordCtrl, 'Password', Icons.lock_outline,
            obscure: true),
        const SizedBox(height: 20),
        _submitButton('Sign In', _signIn),
      ],
    );
  }

  Widget _signUpForm() {
    return Column(
      children: [
        _field(_nameCtrl, 'Username', Icons.person_outline),
        const SizedBox(height: 10),
        _field(_emailCtrl, 'Email', Icons.email_outlined),
        const SizedBox(height: 10),
        _field(_passwordCtrl, 'Password (min 6 chars)', Icons.lock_outline,
            obscure: true),
        const SizedBox(height: 20),
        _submitButton('Create Account', _signUp),
      ],
    );
  }

  Widget _submitButton(String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _loading ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF3FB950),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 1.8, color: Colors.white),
              )
            : Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, IconData icon,
      {bool obscure = false}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      style: const TextStyle(fontSize: 13.5, color: Color(0xFFCCCCCC)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF5A5A5A)),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF888888)),
        filled: true,
        fillColor: const Color(0xFF202020),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF4A9EFF), width: 1.2),
        ),
      ),
    );
  }
}
