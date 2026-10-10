import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import '../data/models.dart';
import 'google_account.dart';

class ChatProfile {
  const ChatProfile({required this.id, required this.name, this.unit, this.position, this.avatar});
  final String id;
  final String name;
  final String? unit, position, avatar;

  factory ChatProfile.fromRow(Map<String, dynamic> r) => ChatProfile(
    id: r['id'] as String,
    name: r['name'] as String? ?? 'Pengguna',
    unit: r['unit'] as String?,
    position: r['position'] as String?,
    avatar: r['avatar'] as String?,
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

/// Chat between users who connected their Google account. Supabase holds
/// only chat data (profiles + messages); everything else stays on device.
/// Schema & row-level security: supabase/migrations/*_chat.sql
abstract final class ChatService {
  static const publicRoom = 'umum';
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready || !Env.chatReady) return;
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
    _ready = true;
  }

  static SupabaseClient get _db => Supabase.instance.client;
  static bool get available => _ready;
  static String? get uid => _ready ? _db.auth.currentUser?.id : null;
  static bool get signedIn => uid != null;

  static Future<void> signIn({required Profile profile, required String avatar}) async {
    await init();
    if (!_ready) return;
    if (!signedIn) {
      final token = GoogleAccount.idToken();
      if (token == null) throw StateError('ID token Google tidak tersedia.');
      await _db.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: token);
    }
    await updateProfile(profile: profile, avatar: avatar);
  }

  static Future<void> updateProfile({required Profile profile, required String avatar}) async {
    if (!signedIn) return;
    await _db.from('profiles').upsert({
      'id': uid,
      'name': profile.name.isEmpty ? 'Pengguna' : profile.name,
      'unit': profile.unit,
      'position': profile.position,
      'avatar': avatar,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static Future<void> signOut() async {
    if (_ready && signedIn) await _db.auth.signOut();
  }

  static Stream<List<ChatProfile>> people() => _db
      .from('profiles')
      .stream(primaryKey: ['id'])
      .order('name', ascending: true)
      .map((rows) => rows.map(ChatProfile.fromRow).where((p) => p.id != uid).toList());

  static Stream<List<ChatMessage>> messages(String room) => _db
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('room', room)
      .order('created_at', ascending: true)
      .limit(300)
      .map((rows) => rows.map(ChatMessage.fromRow).toList());

  static Future<void> send(String room, String body) async {
    final text = body.trim();
    if (text.isEmpty) return;
    await _db.from('messages').insert({'room': room, 'body': text.length > 2000 ? text.substring(0, 2000) : text});
  }

  /// Direct-message room id, identical for both participants.
  static String dmRoom(String other) {
    final ids = [uid!, other]..sort();
    return 'dm:${ids[0]}:${ids[1]}';
  }
}
