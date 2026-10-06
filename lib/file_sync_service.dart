import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

class FileSyncService {
  static final FileSyncService _i = FileSyncService._internal();
  factory FileSyncService() => _i;
  FileSyncService._internal();

  final _db = FirebaseFirestore.instance;

  bool get isEnabled => AuthService().isSignedIn;

  /// Upload local tabs to Firestore. Called when user signs in.
  Future<void> uploadTabs(List<Map<String, dynamic>> tabs) async {
    if (!isEnabled) return;
    final uid = AuthService().currentUser!.uid;
    try {
      await _db.collection('users').doc(uid).collection('files').doc('all').set({
        'tabs': tabs,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Fetch tabs from Firestore. Returns null if none found.
  Future<List<Map<String, dynamic>>?> fetchTabs() async {
    if (!isEnabled) return null;
    final uid = AuthService().currentUser!.uid;
    try {
      final doc = await _db
          .collection('users')
          .doc(uid)
          .collection('files')
          .doc('all')
          .get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      final tabs = data['tabs'] as List?;
      if (tabs == null) return null;
      return tabs.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return null;
    }
  }

  /// Real-time stream of this user's tabs.
  Stream<List<Map<String, dynamic>>> tabsStream() {
    if (!isEnabled) return const Stream.empty();
    final uid = AuthService().currentUser!.uid;
    return _db
        .collection('users')
        .doc(uid)
        .collection('files')
        .doc('all')
        .snapshots()
        .map((snap) {
      final data = snap.data();
      if (data == null) return [];
      final tabs = data['tabs'] as List?;
      if (tabs == null) return [];
      return tabs.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    });
  }
}
