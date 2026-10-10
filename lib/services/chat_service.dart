import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import '../data/models.dart';

class ChatProfile {
  const ChatProfile({
    required this.id,
    required this.name,
    this.unit,
    this.position,
    this.avatar,
    this.isOnline = false,
    this.lastSeen,
  });
  final String id;
  final String name;
  final String? unit, position, avatar;
  final bool isOnline;
  final DateTime? lastSeen;

  /// Switched on and the app was open recently (heartbeat every 2 minutes).
  bool get onlineNow =>
      isOnline && lastSeen != null && DateTime.now().difference(lastSeen!) < const Duration(minutes: 5);

  factory ChatProfile.fromRow(Map<String, dynamic> r) => ChatProfile(
    id: r['id'] as String,
    name: r['name'] as String? ?? 'Pengguna',
    unit: r['unit'] as String?,
    position: r['position'] as String?,
    avatar: r['avatar'] as String?,
    isOnline: r['is_online'] as bool? ?? false,
    lastSeen: r['last_seen'] == null ? null : DateTime.parse(r['last_seen'] as String).toLocal(),
  );
}

class ChatMessage {
  const ChatMessage({required this.id, required this.room, required this.sender, required this.body, required this.at});
  final int id;
  final String room, sender, body;
  final DateTime at;

  factory ChatMessage.fromRow(Map<String, dynamic> r) => ChatMessage(
    id: r['id'] as int,
    room: r['room'] as String,
    sender: r['sender'] as String,
    body: r['body'] as String,
    at: DateTime.parse(r['created_at'] as String).toLocal(),
  );
}

/// Chat between Lapor Yuk users (anonymous Supabase auth). Supabase holds
/// only chat data (users + chat); everything else stays on device.
/// Schema & row-level security: supabase/migrations/*_chat.sql
abstract final class ChatService {
  static const publicRoom = 'umum';
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready || !Env.chatReady) return;
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
    _ready = true;
    AppLifecycleListener(
      onResume: () => _heartbeat(true),
      onPause: () => _heartbeat(false),
    );
    _heartbeat(true);
  }

  static Timer? _beat;

  /// While the app is in the foreground, keeps users.last_seen fresh so other
  /// devices can tell who is actually online.
  static void _heartbeat(bool on) {
    _beat?.cancel();
    _beat = null;
    if (!on || !signedIn) return;
    _touch();
    _beat = Timer.periodic(const Duration(minutes: 2), (_) => _touch());
  }

  static Future<void> _touch() async {
    if (!signedIn) return;
    try {
      await _db.from('users').update({'last_seen': _now()}).eq('id', uid!);
    } catch (_) {} // offline device: next beat retries
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();

  static SupabaseClient get _db => Supabase.instance.client;
  static bool get available => _ready;
  static String? get uid => _ready ? _db.auth.currentUser?.id : null;
  static bool get signedIn => uid != null;

  /// "Sync": registers this device in the users table with an anonymous
  /// Supabase identity (independent of Google) and pushes the current profile.
  /// The session persists on the device, so the identity stays the same.
  static Future<void> sync({required Profile profile, required String avatar, bool online = true}) async {
    await init();
    if (!_ready) throw StateError('Chat belum dikonfigurasi (SUPABASE_ANON_KEY kosong).');
    if (!signedIn) await _db.auth.signInAnonymously();
    await _db.from('users').upsert({
      'id': uid,
      'name': profile.name.isEmpty ? 'Pengguna' : profile.name,
      'unit': profile.unit,
      'position': profile.position,
      'avatar': avatar,
      'is_online': online,
      'last_seen': _now(),
      'updated_at': _now(),
    });
    _heartbeat(true);
  }

  /// Profile edits re-sync quietly once the device is registered.
  static Future<void> updateProfile({required Profile profile, required String avatar}) async {
    if (!signedIn) return;
    await _db.from('users').update({
      'name': profile.name.isEmpty ? 'Pengguna' : profile.name,
      'unit': profile.unit,
      'position': profile.position,
      'avatar': avatar,
      'updated_at': _now(),
    }).eq('id', uid!);
  }

  static Future<void> setOnline(bool online) async {
    if (!signedIn) return;
    await _db.from('users').update({'is_online': online, 'last_seen': _now()}).eq('id', uid!);
  }

  /// This device's own row (null until the first sync lands).
  static Stream<ChatProfile?> me() => _db
      .from('users')
      .stream(primaryKey: ['id'])
      .eq('id', uid!)
      .map((rows) => rows.isEmpty ? null : ChatProfile.fromRow(rows.first));

  static Future<void> signOut() async {
    _heartbeat(false);
    if (_ready && signedIn) await _db.auth.signOut();
  }

  static Stream<List<ChatProfile>> people() => _db
      .from('users')
      .stream(primaryKey: ['id'])
      .order('name', ascending: true)
      .map((rows) {
        final list = rows.map(ChatProfile.fromRow).where((p) => p.id != uid);
        // Online first, each group still by name.
        return [...list.where((p) => p.onlineNow), ...list.where((p) => !p.onlineNow)];
      });

  static Stream<List<ChatMessage>> messages(String room) => _db
      .from('chat')
      .stream(primaryKey: ['id'])
      .eq('room', room)
      .order('created_at', ascending: true)
      .limit(300)
      .map((rows) => rows.map(ChatMessage.fromRow).toList());

  static Future<void> send(String room, String body) async {
    final text = body.trim();
    if (text.isEmpty) return;
    await _db.from('chat').insert({'room': room, 'body': text.length > 2000 ? text.substring(0, 2000) : text});
  }

  /// Direct-message room id, identical for both participants.
  static String dmRoom(String other) {
    final ids = [uid!, other]..sort();
    return 'dm:${ids[0]}:${ids[1]}';
  }
}
