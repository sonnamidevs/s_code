import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

class CollabUser {
  final String id;
  final String name;
  final int colorIndex;
  final int cursorPos;
  CollabUser({
    required this.id,
    required this.name,
    required this.colorIndex,
    required this.cursorPos,
  });
}

class RemoteCursor {
  final String userId;
  final String name;
  final int position;
  final int colorIndex;
  RemoteCursor({
    required this.userId,
    required this.name,
    required this.position,
    required this.colorIndex,
  });
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
  Timer? _codeDebounce;
  Timer? _cursorDebounce; // <-- THIS WAS MISSING

  final _codeStream = StreamController<String>.broadcast();
  Stream<String> get codeStream => _codeStream.stream;

  final _usersStream = StreamController<Map<String, CollabUser>>.broadcast();
  Stream<Map<String, CollabUser>> get usersStream => _usersStream.stream;

  final _cursorsStream = StreamController<List<RemoteCursor>>.broadcast();
  Stream<List<RemoteCursor>> get cursorsStream => _cursorsStream.stream;

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
      await _db.collection('sessions').doc(id).set({
        'ownerId': user.uid,
        'ownerName': AuthService().displayName,
        'code': '# Collaboration session\n# Start typing...\n',
        'codeVersion': 1,
        'createdAt': FieldValue.serverTimestamp(),
        'lastUpdate': FieldValue.serverTimestamp(),
        'activeUsers': 1,
      });
      await _registerUser(id);
      await _subscribe(id);
      return true;
    } catch (_) {
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
      await _registerUser(id);
      await _subscribe(id);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _registerUser(String id) async {
    final user = AuthService().currentUser;
    if (user == null) return;
    await _db
        .collection('sessions')
        .doc(id)
        .collection('users')
        .doc(user.uid)
        .set({
      'name': AuthService().displayName,
      'colorIndex': Random().nextInt(6),
      'cursorPos': 0,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _subscribe(String id) async {
    _sessionId = id;

    _sessionSub = _db.collection('sessions').doc(id).snapshots().listen((snap) {
      final data = snap.data();
      if (data == null) return;
      final code = data['code'] as String? ?? '';
      _codeStream.add(code);
    });

    _usersSub = _db
        .collection('sessions')
        .doc(id)
        .collection('users')
        .snapshots()
        .listen((snap) {
      final users = <String, CollabUser>{};
      final cursors = <RemoteCursor>[];
      final myUid = AuthService().currentUser?.uid;
      for (final d in snap.docs) {
        final data = d.data();
        final u = CollabUser(
          id: d.id,
          name: data['name'] as String? ?? 'User',
          colorIndex: data['colorIndex'] as int? ?? 0,
          cursorPos: data['cursorPos'] as int? ?? 0,
        );
        users[d.id] = u;
        if (d.id != myUid) {
          cursors.add(RemoteCursor(
            userId: d.id,
            name: u.name,
            position: u.cursorPos,
            colorIndex: u.colorIndex,
          ));
        }
      }
      _usersStream.add(users);
      _cursorsStream.add(cursors);
    });

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

  void sendCode(String content) {
    _codeDebounce?.cancel();
    _codeDebounce = Timer(const Duration(milliseconds: 400), () async {
      final id = _sessionId;
      if (id == null) return;
      try {
        await _db.collection('sessions').doc(id).update({
          'code': content,
          'lastUpdate': FieldValue.serverTimestamp(),
          'codeVersion': FieldValue.increment(1),
        });
      } catch (_) {}
    });
  }

  // --- THIS WAS MISSING ---
  void sendCursor(int position) {
    _cursorDebounce?.cancel();
    _cursorDebounce = Timer(const Duration(milliseconds: 250), () async {
      final id = _sessionId;
      final user = AuthService().currentUser;
      if (id == null || user == null) return;
      try {
        await _db
            .collection('sessions')
            .doc(id)
            .collection('users')
            .doc(user.uid)
            .update({'cursorPos': position});
      } catch (_) {}
    });
  }
  // ------------------------

  Future<void> leave() async {
    final id = _sessionId;
    final user = AuthService().currentUser;
    _presenceTimer?.cancel();
    _codeDebounce?.cancel();
    _cursorDebounce?.cancel();
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
    _codeDebounce?.cancel();
    _cursorDebounce?.cancel();
    _sessionSub?.cancel();
    _usersSub?.cancel();
    _codeStream.close();
    _usersStream.close();
    _cursorsStream.close();
    _statusStream.close();
  }
}
