import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthResult {
  final bool success;
  final String? error;
  AuthResult({required this.success, this.error});
}

class AuthService {
  static final AuthService _i = AuthService._internal();
  factory AuthService() => _i;
  AuthService._internal();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  String get displayName {
    final u = _auth.currentUser;
    if (u == null) return '';
    return u.displayName ?? (u.email?.split('@').first ?? 'User');
  }

  String get email => _auth.currentUser?.email ?? '';

  Future<void> init() async {
    // Firebase Auth persists sessions automatically.
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

    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      await cred.user?.updateDisplayName(cleanName);
      await cred.user?.sendEmailVerification();

      await _db.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'username': cleanName,
        'email': cleanEmail,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return AuthResult(success: true);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _friendly(e));
    } catch (e) {
      return AuthResult(success: false, error: 'Something went wrong.');
    }
  }

  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || password.isEmpty) {
      return AuthResult(success: false, error: 'Email and password required');
    }
    try {
      await _auth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      return AuthResult(success: true);
    } on FirebaseAuthException catch (e) {
      return AuthResult(success: false, error: _friendly(e));
    } catch (e) {
      return AuthResult(success: false, error: 'Something went wrong.');
    }
  }

  Future<void> resendVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  Future<void> reload() async {
    await _auth.currentUser?.reload();
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  String _friendly(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account with this email already exists';
      case 'invalid-email':
        return 'That email address is not valid';
      case 'weak-password':
        return 'Password is too weak (min 6 characters)';
      case 'user-not-found':
        return 'No account found with that email';
      case 'wrong-password':
        return 'Incorrect password';
      case 'invalid-credential':
        return 'Incorrect email or password';
      case 'too-many-requests':
        return 'Too many attempts. Try again in a few minutes';
      case 'network-request-failed':
        return 'No internet connection';
      default:
        return e.message ?? 'Authentication failed';
    }
  }
}
