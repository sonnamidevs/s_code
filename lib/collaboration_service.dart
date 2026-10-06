import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class CollabUser {
  final String id;
  final String name;
  final int colorIndex;
  CollabUser({required this.id, required this.name, required this.colorIndex});
}

class CollabMessage {
  final String type;
  final String userId;
  final String userName;
  final String? content;
  final int? cursor;
  final int colorIndex;
  CollabMessage({
    required this.type,
    required this.userId,
    required this.userName,
    this.content,
    this.cursor,
    this.colorIndex = 0,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'userId': userId,
        'userName': userName,
        'content': content,
        'cursor': cursor,
        'colorIndex': colorIndex,
      };

  factory CollabMessage.fromJson(Map<String, dynamic> json) => CollabMessage(
        type: json['type'] as String,
        userId: json['userId'] as String,
        userName: json['userName'] as String,
        content: json['content'] as String?,
        cursor: json['cursor'] as int?,
        colorIndex: json['colorIndex'] as int? ?? 0,
      );
}

class CollaborationService {
  MqttServerClient? _client;
  String? _sessionId;
  String? _userId;
  String? _userName;

  final _messages = StreamController<CollabMessage>.broadcast();
  Stream<CollabMessage> get messages => _messages.stream;

  final _status = StreamController<String>.broadcast();
  Stream<String> get status => _status.stream;

  final Map<String, CollabUser> _users = {};
  Map<String, CollabUser> get users => Map.unmodifiable(_users);

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;
  String? get sessionId => _sessionId;

  static String generateSessionId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<bool> join({required String sessionId, required String userName}) async {
    _sessionId = sessionId.toUpperCase();
    _userName = userName;
    _userId = DateTime.now().millisecondsSinceEpoch.toString() +
        Random().nextInt(9999).toString();

    final clientId = 'pyide_${_userId!}_${Random().nextInt(99999)}';
    final client = MqttServerClient.withPort(
        'broker.hivemq.com', clientId, 8884);
    client.useWebSocket = true;
    client.secure = true;
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.onDisconnected = () => _status.add('disconnected');
    client.onConnected = () => _status.add('connected');

    try {
      _status.add('connecting');
      await client.connect();
    } catch (e) {
      _status.add('error: $e');
      return false;
    }

    _client = client;
    final topic = 'pyide/session/$_sessionId';
    client.subscribe(topic, MqttQos.atLeastOnce);

    client.updates!.listen((events) {
      for (final ev in events) {
        final pub = ev.payload as MqttPublishMessage;
        final payload =
            MqttPublishPayload.bytesToStringAsString(pub.payload.message);
        try {
          final msg = CollabMessage.fromJson(
              jsonDecode(payload) as Map<String, dynamic>);
          if (msg.userId == _userId) continue;
          if (msg.type == 'join') {
            _users[msg.userId] = CollabUser(
                id: msg.userId, name: msg.userName, colorIndex: msg.colorIndex);
          } else if (msg.type == 'leave') {
            _users.remove(msg.userId);
          }
          _messages.add(msg);
        } catch (_) {}
      }
    });

    _publish(CollabMessage(
      type: 'join',
      userId: _userId!,
      userName: _userName!,
      colorIndex: Random().nextInt(6),
    ));

    return true;
  }

  void _publish(CollabMessage msg) {
    if (_client == null || _sessionId == null) return;
    final topic = 'pyide/session/$_sessionId';
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(msg.toJson()));
    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void sendCode(String content) {
    if (_userId == null) return;
    _publish(CollabMessage(
      type: 'code',
      userId: _userId!,
      userName: _userName!,
      content: content,
    ));
  }

  Future<void> leave() async {
    if (_userId != null) {
      _publish(CollabMessage(
          type: 'leave', userId: _userId!, userName: _userName!));
    }
    await Future.delayed(const Duration(milliseconds: 200));
    _client?.disconnect();
    _client = null;
    _sessionId = null;
    _users.clear();
  }

  void dispose() {
    _messages.close();
    _status.close();
    _client?.disconnect();
  }
}
