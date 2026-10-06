import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppNotification {
  final String title;
  final String body;
  final IconData icon;
  final DateTime timestamp;
  final String type;
  
  AppNotification({
    required this.title,
    required this.body,
    required this.icon,
    required this.timestamp,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'timestamp': timestamp.toIso8601String(),
        'type': type,
      };

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        title: j['title'] as String,
        body: j['body'] as String,
        icon: Icons.notifications,
        timestamp: DateTime.parse(j['timestamp'] as String),
        type: j['type'] as String,
      );
}

class NotificationService {
  static final NotificationService _i = NotificationService._internal();
  factory NotificationService() => _i;
  NotificationService._internal();

  static const String _key = 'in_app_notifications';
  static const int _maxItems = 30;

  final _stream = StreamController<List<AppNotification>>.broadcast();
  Stream<List<AppNotification>> get stream => _stream.stream;

  List<AppNotification> _items = [];

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _items = list
            .map((e) =>
                AppNotification.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {}
    }
    _stream.add(_items);
  }

  Future<void> push({
    required String title,
    required String body,
    required String type,
    IconData icon = Icons.notifications_outlined,
  }) async {
    final n = AppNotification(
      title: title,
      body: body,
      icon: icon,
      timestamp: DateTime.now(),
      type: type,
    );
    _items.insert(0, n);
    if (_items.length > _maxItems) _items = _items.sublist(0, _maxItems);
    _stream.add(_items);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(_items.map((e) => e.toJson()).toList()));
  }

  Future<void> clear() async {
    _items = [];
    _stream.add(_items);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  List<AppNotification> get items => List.unmodifiable(_items);
}
