import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

class CollabUser {
  final String id;
  final String name;
  final int colorIndex;
  CollabUser({required this.id, required this.name, required this.colorIndex});
}

class CollaborationService {
  static final CollaborationService _i = CollaborationService._internal();
  factory CollaborationService() => _i;
  CollaborationService._internal();

  final _db = FirebaseFirestore.instance;

  String? _sessionId;
  StreamSubscription? _sessionSub;
  StreamSubscription? _usersSub;
  Timer? _presenceTimer;

  final _codeStream = StreamController<String>.broadcast();
  Stream<String> get codeStream => _codeStream.stream;

  final _usersStream = StreamController<Map<String, CollabUser>>.broadcast();
  Stream<Map<String, CollabUser>> get usersStream => _usersStream.stream;

  final _statusStream = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusStream.stream;

  String? get sessionId => _sessionId;
  bool get isConnected => _sessionId != null;

  static String generateSessionId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<bool> createSession() async {
    final id = generateSessionId();
    final user = AuthService().currentUser;
    if (user == null) return false;

    try {
      final color = Random().nextInt(6);
      await _db.collection('sessions').doc(id).set({
        'ownerId': user.uid,
        'ownerName': AuthService().displayName,
        'code': '# New collaboration session\n# Start typing here...\n\n',
        'codeVersion': 1,
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdate': FieldValue.serverTimestamp(),
      });
      await _db
          .collection('sessions')
          .doc(id)
          .collection('users')
          .doc(user.uid)
          .set({
        'name': AuthService().displayName,
        'colorIndex': color,
        'lastSeen': FieldValue.serverTimestamp(),
      });
      await _subscribe(id);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> joinSession(String id) async {
    id = id.trim().toUpperCase();
    if (id.length != 6) return false;
    final user = AuthService().currentUser;
    if (user == null) return false;

    try {
      final doc = await _db.collection('sessions').doc(id).get();
      if (!doc.exists) return false;

      final color = Random().nextInt(6);
      await _db
          .collection('sessions')
          .doc(id)
          .collection('users')
          .doc(user.uid)
          .set({
        'name': AuthService().displayName,
        'colorIndex': color,
        'lastSeen': FieldValue.serverTimestamp(),
      });
      await _subscribe(id);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> _subscribe(String id) async {
    _sessionId = id;

    // Listen to session code
    _sessionSub = _db.collection('sessions').doc(id).snapshots().listen(
      (snap) {
        final data = snap.data();
        if (data == null) return;
        final code = data['code'] as String? ?? '';
        _codeStream.add(code);
      },
      onError: (_) => _statusStream.add('error'),
    );

    // Listen to users
    _usersSub = _db
        .collection('sessions')
        .doc(id)
        .collection('users')
        .snapshots()
        .listen((snap) {
      final map = <String, CollabUser>{};
      for (final d in snap.docs) {
        final data = d.data();
        map[d.id] = CollabUser(
          id: d.id,
          name: data['name'] as String? ?? 'User',
          colorIndex: data['colorIndex'] as int? ?? 0,
        );
      }
      _usersStream.add(map);
    });

    // Heartbeat — update lastSeen every 15s
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _updatePresence();
    });

    _statusStream.add('connected');
  }

  Future<void> _updatePresence() async {
    final id = _sessionId;
    final user = AuthService().currentUser;
    if (id == null || user == null) return;
    try {
      await _db
          .collection('sessions')
          .doc(id)
          .collection('users')
          .doc(user.uid)
          .update({'lastSeen': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  /// Push the current editor content to Firestore.
  Future<void> sendCode(String content) async {
    final id = _sessionId;
    if (id == null) return;
    try {
      await _db.collection('sessions').doc(id).update({
        'code': content,
        'lastUpdate': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> leave() async {
    final id = _sessionId;
    final user = AuthService().currentUser;
    _presenceTimer?.cancel();
    await _sessionSub?.cancel();
    await _usersSub?.cancel();
    _sessionSub = null;
    _usersSub = null;
    if (id != null && user != null) {
      try {
        await _db
            .collection('sessions')
            .doc(id)
            .collection('users')
            .doc(user.uid)
            .delete();
      } catch (_) {}
    }
    _sessionId = null;
    _statusStream.add('disconnected');
  }

  void dispose() {
    _presenceTimer?.cancel();
    _sessionSub?.cancel();
    _usersSub?.cancel();
    _codeStream.close();
    _usersStream.close();
    _statusStream.close();
  }
}
