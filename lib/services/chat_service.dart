import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import '../core/sensitive.dart';
import '../data/models.dart';
import 'reminder_service.dart';

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
  const ChatMessage({
    required this.id,
    required this.room,
    required this.sender,
    required this.body,
    required this.at,
    this.replyTo,
    this.storyPath,
    this.photoId,
    this.voicePath,
    this.voiceSecs,
    this.stripId,
  });
  final int id;
  final String room, sender, body;
  final DateTime at;
  final int? replyTo;

  /// Set when this message replies to a story.
  final String? storyPath;

  /// Photo attached to this message; null once it is purged (after 2 days).
  final int? photoId;

  /// Voice note; [voicePath] goes null after 3 days ("VN kedaluwarsa").
  final String? voicePath;
  final int? voiceSecs;

  /// Photostrip invitation ("Yuk foto bareng!").
  final int? stripId;

  factory ChatMessage.fromRow(Map<String, dynamic> r) => ChatMessage(
    id: r['id'] as int,
    room: r['room'] as String,
    sender: r['sender'] as String,
    body: r['body'] as String,
    at: DateTime.parse(r['created_at'] as String).toLocal(),
    replyTo: r['reply_to'] as int?,
    storyPath: r['story_path'] as String?,
    photoId: r['photo_id'] as int?,
    voicePath: r['voice_path'] as String?,
    voiceSecs: (r['voice_secs'] as num?)?.toInt(),
    stripId: r['strip_id'] as int?,
  );
}

/// Written as escapes: the reaction set is data, kept out of the source text.
const reactionEmojis = ['\u{1F44D}', '\u{2764}\u{FE0F}', '\u{1F602}', '\u{1F62E}', '\u{1F622}', '\u{1F64F}'];

class ChatGroup {
  const ChatGroup({required this.id, required this.name, required this.owner, required this.joined, this.photo});
  final String id, name, owner;

  /// Storage path in the group_photos bucket.
  final String? photo;

  /// false = invitation still waiting for an answer.
  final bool joined;

  String get room => 'grp:$id';
}

class GroupMember {
  const GroupMember({required this.userId, required this.joined});
  final String userId;
  final bool joined;
}

/// One friendship/request row seen from my side.
class Connection {
  const Connection({required this.requester, required this.addressee, required this.status, required this.me});
  final String requester, addressee, status, me;

  String get other => requester == me ? addressee : requester;
  bool get accepted => status == 'accepted';

  /// A pending request someone sent to me (I decide).
  bool get incoming => status == 'pending' && addressee == me;

  /// A pending request I sent, waiting for them.
  bool get outgoing => status == 'pending' && requester == me;
}

class Story {
  const Story({required this.id, required this.author, required this.url, required this.at, this.path, this.caption});
  final int id;
  final String author, url;
  final String? path, caption;
  final DateTime at;
}

/// Chat between Lapor Yuk users (anonymous Supabase auth). Supabase holds
/// only chat data (users, chat, groups, stories); everything else stays on device.
/// Schema & row-level security: supabase/migrations/*.sql
abstract final class ChatService {
  static const publicRoom = 'umum';
  static const storyBucket = 'stories';
  static bool _ready = false;

  /// Unread messages per room, and pending group invitations. Drive the
  /// badges on the hub Chat button and in the chat list.
  static final unread = ValueNotifier<Map<String, int>>(const {});
  static final invites = ValueNotifier<int>(0);
  static final friendRequests = ValueNotifier<int>(0);
  static RealtimeChannel? _live;
  static Timer? _debounce;
  static Timer? _seenTimer;

  static Future<void> init() async {
    if (_ready || !Env.chatReady) return;
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
    _ready = true;
    AppLifecycleListener(
      onResume: () {
        _heartbeat(true);
        refreshBadges();
      },
      onPause: () => _heartbeat(false),
    );
    _heartbeat(true);
    _listen();
  }

  static int get badge => unread.value.values.fold(0, (a, b) => a + b) + invites.value + friendRequests.value;

  static void _listen() {
    if (!signedIn || _live != null) return;
    void later(_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), refreshBadges);
    }

    _live = _db
        .channel('badges')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat',
          callback: (p) {
            later(p);
            _notify(p.newRecord);
            // Tells senders the message reached this phone (two grey ticks).
            if (p.newRecord['sender'] != uid) {
              _seenTimer?.cancel();
              _seenTimer = Timer(const Duration(seconds: 1), _touch);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'group_members',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid!),
          callback: later,
        )
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'connections', callback: later)
        .subscribe();
    refreshBadges();
  }

  /// Room currently on screen; no notification for its messages.
  static String? openRoom;
  static final _names = <String, String>{};

  /// Local notification for a new message. Rides on the realtime channel, so
  /// it only fires while the app process is alive (foreground or recently
  /// backgrounded); push with the app closed would need FCM.
  static Future<void> _notify(Map<String, dynamic> r) async {
    final room = r['room'] as String?;
    final sender = r['sender'] as String?;
    if (room == null || sender == null || sender == uid || room == openRoom) return;
    try {
      Future<String> name(String table, String id, String fallback) async {
        if (_names[id] case final n?) return n;
        final row = await _db.from(table).select('name').eq('id', id).maybeSingle();
        return _names[id] = row?['name'] as String? ?? fallback;
      }

      final who = await name('users', sender, 'Pengguna');
      final text = r['strip_id'] != null
          ? 'Mengajak foto bareng'
          : r['photo_id'] != null
          ? 'Mengirim foto'
          : r['voice_path'] != null
          ? 'Mengirim pesan suara'
          : r['body'] as String? ?? '';
      final (title, body) = room == publicRoom
          ? ('Ruang Umum', '$who: $text')
          : room.startsWith('grp:')
          ? (await name('groups', room.substring(4), 'Grup'), '$who: $text')
          : (who, text);
      await ReminderService.chat(room.hashCode & 0x7fffffff, title, maskSensitive(body));
    } catch (_) {}
  }

  static Future<void> refreshBadges() async {
    if (!signedIn) return;
    try {
      final rows = await _db.rpc('unread_counts') as List;
      unread.value = {for (final r in rows) r['room'] as String: (r['n'] as num).toInt()};
      final inv = await _db.from('group_members').select('group_id').eq('user_id', uid!).eq('status', 'invited');
      invites.value = inv.length;
      final req = await _db.from('connections').select('requester').eq('addressee', uid!).eq('status', 'pending');
      friendRequests.value = req.length;
    } catch (_) {} // offline: keep the last known numbers
  }

  static Future<void> markRead(String room) async {
    if (!signedIn) return;
    if ((unread.value[room] ?? 0) > 0) unread.value = {...unread.value}..remove(room);
    try {
      await _db.rpc('mark_read', params: {'r': room});
    } catch (_) {}
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
    _listen();
  }

  /// Profile edits re-sync quietly once the device is registered.
  static Future<void> updateProfile({required Profile profile, required String avatar}) async {
    if (!signedIn) return;
    await _db
        .from('users')
        .update({
          'name': profile.name.isEmpty ? 'Pengguna' : profile.name,
          'unit': profile.unit,
          'position': profile.position,
          'avatar': avatar,
          'updated_at': _now(),
        })
        .eq('id', uid!);
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
    await _live?.unsubscribe();
    _live = null;
    unread.value = const {};
    invites.value = 0;
    friendRequests.value = 0;
    if (_ready && signedIn) await _db.auth.signOut();
  }

  static Stream<List<ChatProfile>> people() =>
      _db.from('users').stream(primaryKey: ['id']).order('name', ascending: true).map((rows) {
        final list = rows.map(ChatProfile.fromRow).where((p) => p.id != uid);
        // Online first, each group still by name.
        return [...list.where((p) => p.onlineNow), ...list.where((p) => !p.onlineNow)];
      });

  /// My connection rows (RLS returns only those involving me). Realtime, so
  /// the friends list and request badges update live.
  static Stream<List<Connection>> connections() => _db
      .from('connections')
      .stream(primaryKey: ['requester', 'addressee'])
      .map(
        (rows) => [
          for (final r in rows)
            Connection(
              requester: r['requester'] as String,
              addressee: r['addressee'] as String,
              status: r['status'] as String,
              me: uid ?? '',
            ),
        ],
      );

  /// Accepted friends as profiles (people() filtered by the connection list).
  static Stream<List<ChatProfile>> friendProfiles() {
    final ctrl = StreamController<List<ChatProfile>>();
    List<ChatProfile>? ppl;
    Set<String>? ids;
    void emit() {
      if (ppl != null && ids != null) {
        ctrl.add([
          for (final p in ppl!)
            if (ids!.contains(p.id)) p,
        ]);
      }
    }

    final a = people().listen((v) {
      ppl = v;
      emit();
    });
    final b = connections().listen((v) {
      ids = {for (final x in v.where((e) => e.accepted)) x.other};
      emit();
    });
    ctrl.onCancel = () async {
      await a.cancel();
      await b.cancel();
    };
    return ctrl.stream;
  }

  static Future<String> requestConnect(String other) async =>
      await _db.rpc('request_connection', params: {'other': other}) as String;

  static Future<void> respondConnect(String other, bool accept) =>
      _db.rpc('respond_connection', params: {'other': other, 'accept': accept});

  static Future<void> removeConnect(String other) => _db.rpc('remove_connection', params: {'other': other});

  static Stream<List<ChatMessage>> messages(String room) => _db
      .from('chat')
      .stream(primaryKey: ['id'])
      .eq('room', room)
      .order('created_at', ascending: true)
      .limit(300)
      .map((rows) => rows.map(ChatMessage.fromRow).toList());

  static Future<void> send(String room, String body, {int? replyTo, String? storyPath}) async {
    final text = body.trim();
    if (text.isEmpty) return;
    await _db.from('chat').insert({
      'room': room,
      'body': text.length > 2000 ? text.substring(0, 2000) : text,
      'reply_to': ?replyTo,
      'story_path': ?storyPath,
    });
  }

  static Future<void> deleteMessage(int id) => _db.from('chat').delete().eq('id', id);

  static const photoBucket = 'chat_media';
  static const voiceBucket = 'chat_voice';

  /// Photo lifetime in the chat; the database hides it after this too.
  static const photoLife = Duration(days: 2);

  /// Sends a photo that stays in the room for [photoLife]. [jpeg] must already be compressed.
  static Future<void> sendPhoto(String room, Uint8List jpeg, {String? caption, int? replyTo}) async {
    final path = '${uid!}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _db.storage
        .from(photoBucket)
        .uploadBinary(path, jpeg, fileOptions: const FileOptions(contentType: 'image/jpeg'));
    final row = await _db.from('chat_photos').insert({'room': room, 'path': path}).select().single();
    final text = caption?.trim() ?? '';
    await _db.from('chat').insert({
      'room': room,
      'body': text.isEmpty ? 'Foto' : text,
      'photo_id': row['id'],
      'reply_to': ?replyTo,
    });
  }

  /// Public URL of a photo still within [photoLife], or null once it expired.
  static Future<String?> photoUrl(int photoId) async {
    final r = await _db.from('chat_photos').select('path').eq('id', photoId).maybeSingle();
    final path = r?['path'] as String?;
    return path == null ? null : _db.storage.from(photoBucket).getPublicUrl(path);
  }

  static Future<void> sendVoice(String room, String filePath, int seconds, {int? replyTo}) async {
    final bytes = await File(filePath).readAsBytes();
    final path = '${uid!}/${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _db.storage
        .from(voiceBucket)
        .uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'audio/mp4'));
    await _db.from('chat').insert({
      'room': room,
      'body': 'Pesan suara',
      'voice_path': path,
      'voice_secs': seconds,
      'reply_to': ?replyTo,
    });
  }

  static String voiceUrl(String path) => _db.storage.from(voiceBucket).getPublicUrl(path);

  /// Removes expired ephemeral photos (>2 days) and voice notes (>3 days).
  static Future<void> purgeChatMedia() async {
    if (!signedIn) return;
    try {
      final photos = (await _db.rpc('purge_chat_photos') as List).cast<String>();
      if (photos.isNotEmpty) await _db.storage.from(photoBucket).remove(photos);
    } catch (_) {}
    try {
      final voices = (await _db.rpc('purge_voice') as List).cast<String>();
      if (voices.isNotEmpty) await _db.storage.from(voiceBucket).remove(voices);
    } catch (_) {}
  }

  /// message id -> {user id: emoji}
  static Stream<Map<int, Map<String, String>>> reactions(String room) =>
      _db.from('chat_reactions').stream(primaryKey: ['message_id', 'user_id']).eq('room', room).map((rows) {
        final out = <int, Map<String, String>>{};
        for (final r in rows) {
          (out[r['message_id'] as int] ??= {})[r['user_id'] as String] = r['emoji'] as String;
        }
        return out;
      });

  /// Same emoji again removes the reaction; another emoji replaces it.
  static Future<void> react(ChatMessage m, String emoji, {String? current}) async {
    final q = _db.from('chat_reactions');
    if (current == emoji) {
      await q.delete().eq('message_id', m.id).eq('user_id', uid!);
    } else {
      await q.upsert({'message_id': m.id, 'user_id': uid, 'room': m.room, 'emoji': emoji});
    }
  }

  /// user id -> when they last opened [room] (DM and group rooms only).
  static Stream<Map<String, DateTime>> reads(String room) => _db
      .from('chat_reads')
      .stream(primaryKey: ['user_id', 'room'])
      .eq('room', room)
      .map((rows) => {for (final r in rows) r['user_id'] as String: DateTime.parse(r['read_at'] as String).toLocal()});

  /// Direct-message room id, identical for both participants.
  static String dmRoom(String other) {
    final ids = [uid!, other]..sort();
    return 'dm:${ids[0]}:${ids[1]}';
  }

  /// Groups this device belongs to or is invited to. Group names are fetched
  /// on every membership change: realtime would not deliver the row of a
  /// group created before the invitation arrived.
  static Stream<List<ChatGroup>> groups() =>
      _db.from('group_members').stream(primaryKey: ['group_id', 'user_id']).eq('user_id', uid!).asyncMap((rows) async {
        if (rows.isEmpty) return const <ChatGroup>[];
        final joined = {for (final r in rows) r['group_id'] as String: r['status'] == 'member'};
        final gs = await _db
            .from('groups')
            .select('id, name, owner, photo')
            .inFilter('id', joined.keys.toList())
            .order('name');
        return [
          for (final g in gs)
            ChatGroup(
              id: g['id'] as String,
              name: g['name'] as String,
              owner: g['owner'] as String,
              joined: joined[g['id']] ?? false,
              photo: g['photo'] as String?,
            ),
        ];
      });

  static Stream<List<GroupMember>> members(String groupId) => _db
      .from('group_members')
      .stream(primaryKey: ['group_id', 'user_id'])
      .eq('group_id', groupId)
      .map(
        (rows) => [for (final r in rows) GroupMember(userId: r['user_id'] as String, joined: r['status'] == 'member')],
      );

  static Future<String> createGroup(String name, List<String> invitees) async {
    final id = await _db.rpc('create_group', params: {'group_name': name.trim(), 'invitees': invitees});
    return id as String;
  }

  static Future<void> invite(String groupId, List<String> users) async {
    if (users.isEmpty) return;
    await _db
        .from('group_members')
        .upsert(
          [
            for (final u in users) {'group_id': groupId, 'user_id': u, 'status': 'invited', 'invited_by': uid},
          ],
          onConflict: 'group_id,user_id',
          ignoreDuplicates: true,
        );
  }

  /// Accept or decline an invitation.
  static Future<void> answer(String groupId, bool accept) async {
    final q = _db.from('group_members');
    if (accept) {
      await q.update({'status': 'member'}).eq('group_id', groupId).eq('user_id', uid!);
    } else {
      await q.delete().eq('group_id', groupId).eq('user_id', uid!);
    }
    await refreshBadges();
  }

  /// Leave a group, or (as its owner) remove someone else.
  static Future<void> removeMember(String groupId, [String? user]) =>
      _db.from('group_members').delete().eq('group_id', groupId).eq('user_id', user ?? uid!);

  static Future<void> renameGroup(String groupId, String name) =>
      _db.from('groups').update({'name': name.trim()}).eq('id', groupId);

  static Future<void> deleteGroup(String groupId) => _db.from('groups').delete().eq('id', groupId);

  static const groupPhotoBucket = 'group_photos';

  static String groupPhotoUrl(String path) => _db.storage.from(groupPhotoBucket).getPublicUrl(path);

  /// Owner only. [jpeg] must already be compressed (bucket limit 300 KB).
  /// Returns the new path; the previous file is removed.
  static Future<String> setGroupPhoto(String groupId, Uint8List jpeg, {String? old}) async {
    final path = '$groupId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _db.storage
        .from(groupPhotoBucket)
        .uploadBinary(path, jpeg, fileOptions: const FileOptions(contentType: 'image/jpeg'));
    await _db.from('groups').update({'photo': path}).eq('id', groupId);
    if (old != null) {
      try {
        await _db.storage.from(groupPhotoBucket).remove([old]);
      } catch (_) {}
    }
    return path;
  }

  static Stream<List<Story>> stories() =>
      _db.from('stories').stream(primaryKey: ['id']).order('created_at', ascending: false).map((rows) {
        final now = DateTime.now();
        return [
          for (final r in rows)
            if (DateTime.parse(r['expires_at'] as String).isAfter(now))
              Story(
                id: r['id'] as int,
                author: r['author'] as String,
                path: r['path'] as String,
                url: _db.storage.from(storyBucket).getPublicUrl(r['path'] as String),
                caption: r['caption'] as String?,
                at: DateTime.parse(r['created_at'] as String).toLocal(),
              ),
        ];
      });

  /// [jpeg] must already be compressed (bucket limit 1 MB).
  static Future<void> postStory(Uint8List jpeg, {String? caption}) async {
    final path = '${uid!}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _db.storage
        .from(storyBucket)
        .uploadBinary(path, jpeg, fileOptions: const FileOptions(contentType: 'image/jpeg'));
    final text = caption?.trim() ?? '';
    await _db.from('stories').insert({
      'path': path,
      'caption': text.isEmpty ? null : text,
      'size_kb': (jpeg.length / 1024).ceil(),
    });
  }

  static String storyUrl(String path) => _db.storage.from(storyBucket).getPublicUrl(path);

  static Future<void> markViewed(Story s) async {
    if (s.author == uid) return;
    try {
      await _db
          .from('story_views')
          .upsert({'story_id': s.id, 'viewer': uid}, onConflict: 'story_id,viewer', ignoreDuplicates: true);
    } catch (_) {}
  }

  /// Story ids this device has already seen, to grey out their ring.
  static Stream<Set<int>> viewed() => _db
      .from('story_views')
      .stream(primaryKey: ['story_id', 'viewer'])
      .eq('viewer', uid!)
      .map((rows) => {for (final r in rows) r['story_id'] as int});

  /// Who saw one of my stories, newest first.
  static Stream<List<(String, DateTime)>> viewers(int storyId) => _db
      .from('story_views')
      .stream(primaryKey: ['story_id', 'viewer'])
      .eq('story_id', storyId)
      .order('viewed_at')
      .map(
        (rows) => [for (final r in rows) (r['viewer'] as String, DateTime.parse(r['viewed_at'] as String).toLocal())],
      );

  static Future<void> deleteStory(Story s) async {
    await _db.from('stories').delete().eq('id', s.id);
    if (s.path != null) await _db.storage.from(storyBucket).remove([s.path!]);
  }

  /// Rows past 24 hours are removed in the database; their files are removed
  /// here because SQL cannot delete Storage objects.
  static Future<void> purgeStories() async {
    if (!signedIn) return;
    try {
      final paths = (await _db.rpc('purge_stories') as List).cast<String>();
      if (paths.isNotEmpty) await _db.storage.from(storyBucket).remove(paths);
    } catch (_) {}
  }
}
