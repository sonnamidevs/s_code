import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppUser {
  final String id;
  final String username;
  final String email;
  final DateTime createdAt;

  AppUser({
    required this.id,
    required this.username,
    required this.email,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'email': email,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        username: j['username'] as String,
        email: j['email'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class AuthResult {
  final bool success;
  final String? error;
  final AppUser? user;
  AuthResult({required this.success, this.error, this.user});
}

class AuthService {
  static final AuthService _i = AuthService._internal();
  factory AuthService() => _i;
  AuthService._internal();

  static const String _usersKey = 'auth_users';
  static const String _sessionKey = 'auth_session';

  AppUser? _current;
  AppUser? get currentUser => _current;
  bool get isSignedIn => _current != null;

  String _hash(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_sessionKey);
    if (id == null) return;
    final users = await _loadUsers();
    final match = users.firstWhere(
      (u) => u.id == id,
      orElse: () => AppUser(id: '', username: '', email: '', createdAt: DateTime.now()),
    );
    if (match.id.isNotEmpty) _current = match;
  }

  Future<List<AppUser>> _loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_usersKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => AppUser.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, String>> _loadPasswords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_usersKey}_pwd');
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveUsers(List<AppUser> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _usersKey, jsonEncode(users.map((u) => u.toJson()).toList()));
  }

  Future<void> _savePasswords(Map<String, String> passwords) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_usersKey}_pwd', jsonEncode(passwords));
  }

  Future<AuthResult> signUp({
    required String username,
    required String email,
    required String password,
  }) async {
    final cleanName = username.trim();
    final cleanEmail = email.trim().toLowerCase();

    if (cleanName.length < 2) {
      return AuthResult(success: false, error: 'Name must be at least 2 characters');
    }
    if (!cleanEmail.contains('@') || !cleanEmail.contains('.')) {
      return AuthResult(success: false, error: 'Enter a valid email');
    }
    if (password.length < 6) {
      return AuthResult(success: false, error: 'Password must be at least 6 characters');
    }

    final users = await _loadUsers();
    if (users.any((u) => u.email == cleanEmail)) {
      return AuthResult(success: false, error: 'An account with this email already exists');
    }

    final user = AppUser(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      username: cleanName,
      email: cleanEmail,
      createdAt: DateTime.now(),
    );

    users.add(user);
    await _saveUsers(users);

    final passwords = await _loadPasswords();
    passwords[user.id] = _hash(password);
    await _savePasswords(passwords);

    _current = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, user.id);

    return AuthResult(success: true, user: user);
  }

  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || password.isEmpty) {
      return AuthResult(success: false, error: 'Email and password required');
    }

    final users = await _loadUsers();
    final match = users.firstWhere(
      (u) => u.email == cleanEmail,
      orElse: () => AppUser(id: '', username: '', email: '', createdAt: DateTime.now()),
    );
    if (match.id.isEmpty) {
      return AuthResult(success: false, error: 'No account found with that email');
    }

    final passwords = await _loadPasswords();
    if (passwords[match.id] != _hash(password)) {
      return AuthResult(success: false, error: 'Incorrect password');
    }

    _current = match;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, match.id);

    return AuthResult(success: true, user: match);
  }

  Future<void> signOut() async {
    _current = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }
}
