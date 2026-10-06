import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_service.dart';
import 'collaboration_service.dart';

class CollaborationScreen extends StatefulWidget {
  final Function(String content)? onContentReceived;
  const CollaborationScreen({super.key, this.onContentReceived});

  @override
  State<CollaborationScreen> createState() => _CollaborationScreenState();
}

class _CollaborationScreenState extends State<CollaborationScreen> {
  final _service = CollaborationService();
  final _sessionController = TextEditingController();

  bool _isConnecting = false;
  Map<String, CollabUser> _users = {};
  String? _mySessionId;

  @override
  void initState() {
    super.initState();
    _service.usersStream.listen((users) {
      if (mounted) setState(() => _users = users);
    });
    _service.codeStream.listen((code) {
      if (widget.onContentReceived != null) {
        widget.onContentReceived!(code);
      }
    });
  }

  Future<void> _host() async {
    setState(() => _isConnecting = true);
    final ok = await _service.createSession();
    if (!mounted) return;
    setState(() {
      _isConnecting = false;
      _mySessionId = _service.sessionId;
    });
    if (ok) {
      _sessionController.text = _mySessionId ?? '';
      _snack('Session created: ${_mySessionId}');
    } else {
      _snack('Failed to create session. Check your connection.');
    }
  }

  Future<void> _join() async {
    final id = _sessionController.text.trim().toUpperCase();
    if (id.length != 6) {
      _snack('Enter a valid 6-character code');
      return;
    }
    setState(() => _isConnecting = true);
    final ok = await _service.joinSession(id);
    if (!mounted) return;
    setState(() {
      _isConnecting = false;
      _mySessionId = ok ? _service.sessionId : null;
    });
    if (ok) {
      _snack('Joined session $id');
    } else {
      _snack('Session not found');
    }
  }

  Future<void> _leave() async {
    await _service.leave();
    if (!mounted) return;
    setState(() {
      _users = {};
      _mySessionId = null;
      _sessionController.clear();
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 13)),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      backgroundColor: const Color(0xFF252525),
    ));
  }

  @override
  void dispose() {
    _sessionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _mySessionId != null;
    final myUid = AuthService().currentUser?.uid;
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        toolbarHeight: 44,
        iconTheme: const IconThemeData(color: Color(0xFFAAAAAA), size: 18),
        title: const Text('Collaborate',
            style: TextStyle(
                fontSize: 14,
                color: Color(0xFFCCCCCC),
                fontWeight: FontWeight.w400)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: connected
                    ? const Color(0xFF3FB950).withOpacity(0.1)
                    : const Color(0xFF252525),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: connected
                      ? const Color(0xFF3FB950).withOpacity(0.4)
                      : const Color(0xFF2A2A2A),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: connected
                          ? const Color(0xFF3FB950)
                          : const Color(0xFF666666),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      connected
                          ? 'Connected · ${_users.length} collaborator${_users.length == 1 ? '' : 's'}'
                          : 'Not connected',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: connected
                            ? const Color(0xFF3FB950)
                            : const Color(0xFF888888),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Session code',
                style: TextStyle(fontSize: 11, color: Color(0xFF7A7A7A))),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sessionController,
                    enabled: !connected,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 6,
                    style: const TextStyle(
                      fontSize: 18,
                      letterSpacing: 6,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFCCCCCC),
                    ),
                    decoration: _inputDec('ABC123').copyWith(counterText: ''),
                  ),
                ),
                const SizedBox(width: 8),
                if (connected)
                  IconButton(
                    icon: const Icon(Icons.copy,
                        size: 20, color: Color(0xFF4A9EFF)),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: _mySessionId ?? ''));
                      _snack('Code copied');
                    },
                  ),
              ],
            ),
            const SizedBox(height: 24),
            if (!connected) ...[
              FilledButton.icon(
                onPressed: _isConnecting ? null : _host,
                icon: _isConnecting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.6, color: Colors.white),
                      )
                    : const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Create new session',
                    style: TextStyle(fontSize: 13.5)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4A9EFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _isConnecting ? null : _join,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Join existing session',
                    style: TextStyle(fontSize: 13.5)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFCCCCCC),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: const BorderSide(color: Color(0xFF333333)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                ),
              ),
            ] else
              OutlinedButton.icon(
                onPressed: _leave,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Leave session',
                    style: TextStyle(fontSize: 13.5)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6B6B),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: const BorderSide(color: Color(0xFFFF6B6B)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                ),
              ),
            if (connected) ...[
              const SizedBox(height: 30),
              const Text('Collaborators',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7A7A7A))),
              const SizedBox(height: 10),
              ..._users.values.map((u) {
                final isMe = u.id == myUid;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 9),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252525),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _userColor(u.colorIndex),
                        ),
                        child: Center(
                          child: Text(
                            u.name.isNotEmpty
                                ? u.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(u.name,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFFCCCCCC))),
                      if (isMe) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A9EFF).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('You',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF4A9EFF),
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Color _userColor(int i) {
    const colors = [
      Color(0xFF4A9EFF),
      Color(0xFF3FB950),
      Color(0xFFFFB84D),
      Color(0xFFE56BFF),
      Color(0xFFFF6B6B),
      Color(0xFF4DD0E1),
    ];
    return colors[i % colors.length];
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF5A5A5A)),
        filled: true,
        fillColor: const Color(0xFF252525),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: Color(0xFF4A9EFF), width: 1.2),
        ),
      );
}
