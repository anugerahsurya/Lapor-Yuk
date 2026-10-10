import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/env.dart';
import '../../core/theme.dart';
import '../../services/chat_service.dart';
import '../../state/providers.dart';
import '../widgets/activity_card.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';

/// Rooms: "Ruang Umum" for everyone + direct messages with other users who
/// synced their device. "Sync" registers this device in the users table;
/// the Online switch controls whether others see it as online.
class ChatHomeScreen extends ConsumerStatefulWidget {
  const ChatHomeScreen({super.key, required this.openProfile});
  final VoidCallback openProfile;

  @override
  ConsumerState<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends ConsumerState<ChatHomeScreen> {
  bool _syncing = false;
  Stream<ChatProfile?>? _me;

  @override
  void initState() {
    super.initState();
    if (ChatService.signedIn) _me = ChatService.me();
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final s = ref.read(settingsProvider);
      await ChatService.sync(profile: s.profile, avatar: s.avatar);
      _me = ChatService.me(); // fresh stream: an older one may predate the row
      if (mounted) toast(context, 'Tersinkron. Kamu terdaftar di chat.', icon: Icons.cloud_done_rounded);
    } catch (e) {
      if (mounted) toast(context, 'Gagal sinkron: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _setOnline(bool on) async {
    try {
      await ChatService.setOnline(on);
      if (mounted) setState(() => _me = ChatService.me());
    } catch (e) {
      if (mounted) toast(context, 'Gagal mengubah status: $e', icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ready = Env.chatReady && ChatService.signedIn;

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: IconBtn(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
          ),
        ),
        leadingWidth: 60,
        title: Text('Chat', style: context.t.titleLarge),
        centerTitle: true,
        actions: [
          if (ready)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconBtn(icon: Icons.sync_rounded, tooltip: 'Sync profil', onTap: _syncing ? null : _sync),
            ),
        ],
      ),
      body: !ready
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: EmptyState(
                  icon: Icons.forum_outlined,
                  title: Env.chatReady ? 'Sync untuk mulai chat' : 'Chat belum dikonfigurasi',
                  message: Env.chatReady
                      ? 'Perangkat ini akan terdaftar sebagai pengguna. Namamu, jabatan, dan satker dari Profil terlihat oleh pengguna lain. Tidak perlu akun Google.'
                      : 'Build ini belum berisi kunci Supabase.',
                  action: Env.chatReady
                      ? AppButton(label: 'Sync & online', icon: Icons.sync_rounded, busy: _syncing, onTap: _sync)
                      : null,
                ),
              ),
            )
          : StreamBuilder<List<ChatProfile>>(
              stream: ChatService.people(),
              builder: (context, snap) {
                final people = snap.data ?? const <ChatProfile>[];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  children: [
                    _OnlineCard(me: _me, onChanged: _setOnline),
                    const SizedBox(height: 12),
                    AppCard(
                      onTap: () =>
                          Navigator.of(context)
                              .push(softRoute(const ChatRoomScreen(room: ChatService.publicRoom, title: 'Ruang Umum'))),
                      color: c.brand,
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .16),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(Icons.groups_rounded, color: c.onBrand),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Ruang Umum', style: context.t.titleMedium!.copyWith(color: c.onBrand)),
                                Text(
                                  'Ngobrol dengan semua pengguna Lapor Yuk',
                                  style: context.t.bodySmall!.copyWith(color: Colors.white.withValues(alpha: .75)),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded, color: c.onBrand),
                        ],
                      ),
                    ).animate().fadeIn(duration: 300.ms).slideY(begin: .1, end: 0),
                    const SizedBox(height: 22),
                    SectionLabel(
                      'Pengguna · ${people.length}'
                      '${people.any((p) => p.onlineNow) ? ' · ${people.where((p) => p.onlineNow).length} online' : ''}',
                    ),
                    if (snap.connectionState == ConnectionState.waiting)
                      const Center(
                        child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
                      )
                    else if (people.isEmpty)
                      const EmptyState(
                        icon: Icons.person_search_rounded,
                        title: 'Belum ada pengguna lain',
                        message: 'Ajak rekan kerja memasang Lapor Yuk lalu menekan Sync di menu Chat.',
                      )
                    else
                      for (final (i, p) in people.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppCard(
                            onTap: () => Navigator.of(context).push(
                              softRoute(
                                ChatRoomScreen(room: ChatService.dmRoom(p.id), title: p.name, avatar: p.avatar),
                              ),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                _Pic(avatar: p.avatar, size: 44, online: p.onlineNow),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p.name, style: context.t.titleSmall),
                                      Text(
                                        [
                                          p.onlineNow ? 'Online' : _seen(p.lastSeen),
                                          p.position,
                                          p.unit,
                                        ].where((e) => (e ?? '').isNotEmpty).join(' · '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.t.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chat_bubble_outline_rounded, color: c.muted, size: 20),
                              ],
                            ),
                          ),
                        ).animate().fadeIn(delay: (30 * i.clamp(0, 10)).ms, duration: 250.ms),
                  ],
                );
              },
            ),
    );
  }
}

String? _seen(DateTime? at) {
  if (at == null) return null;
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 60) return 'Aktif ${d.inMinutes.clamp(1, 59)} mnt lalu';
  if (d.inHours < 24) return 'Aktif ${d.inHours} jam lalu';
  return 'Aktif ${fmtDateShort(at)}';
}

/// This device's own Online/Offline switch.
class _OnlineCard extends StatelessWidget {
  const _OnlineCard({required this.me, required this.onChanged});
  final Stream<ChatProfile?>? me;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return StreamBuilder<ChatProfile?>(
      stream: me,
      builder: (context, snap) {
        final on = snap.data?.isOnline ?? false;
        return AppCard(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: on ? c.success : c.muted, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(on ? 'Kamu online' : 'Kamu offline', style: context.t.titleSmall),
                    Text(
                      on ? 'Pengguna lain melihatmu sedang aktif' : 'Kamu tetap bisa membaca dan mengirim pesan',
                      style: context.t.bodySmall,
                    ),
                  ],
                ),
              ),
              Switch(value: on, onChanged: snap.data != null ? onChanged : null),
            ],
          ),
        );
      },
    );
  }
}

class _Pic extends StatelessWidget {
  const _Pic({required this.avatar, required this.size, this.online = false});
  final String? avatar;
  final double size;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final pic = ClipOval(
      child: Image.asset(
        avatarAsset(avatars.contains(avatar) ? avatar! : 'sun'),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
      ),
    );
    if (!online) return pic;
    final dot = size * .28;
    return Stack(
      children: [
        pic,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(
              color: context.c.success,
              shape: BoxShape.circle,
              border: Border.all(color: context.c.surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class ChatRoomScreen extends ConsumerStatefulWidget {
  const ChatRoomScreen({super.key, required this.room, required this.title, this.avatar});
  final String room, title;
  final String? avatar;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final _input = TextEditingController();
  late final Stream<List<ChatMessage>> _stream = ChatService.messages(widget.room);
  late final Stream<List<ChatProfile>> _people = ChatService.people();
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ChatService.send(widget.room, text);
      _input.clear();
    } catch (e) {
      if (mounted) toast(context, 'Gagal mengirim: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final me = ChatService.uid;
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: IconBtn(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
          ),
        ),
        leadingWidth: 60,
        titleSpacing: 4,
        title: Row(
          children: [
            if (widget.room == ChatService.publicRoom)
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(11)),
                child: Icon(Icons.groups_rounded, color: c.onBrand, size: 20),
              )
            else
              _Pic(avatar: widget.avatar, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.title, style: context.t.titleMedium, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<ChatProfile>>(
        stream: _people,
        builder: (context, peopleSnap) {
          final names = {for (final p in peopleSnap.data ?? const <ChatProfile>[]) p.id: p};
          return StreamBuilder<List<ChatMessage>>(
            stream: _stream,
            builder: (context, snap) {
              final msgs = (snap.data ?? const <ChatMessage>[]).reversed.toList();
              return Column(
                children: [
                  Expanded(
                    child: msgs.isEmpty
                        ? Center(
                            child: EmptyState(
                              icon: Icons.waving_hand_outlined,
                              title: snap.connectionState == ConnectionState.waiting ? 'Memuat…' : 'Belum ada pesan',
                              message: 'Mulai obrolan dengan sapaan singkat.',
                            ),
                          )
                        : ListView.builder(
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                            itemCount: msgs.length,
                            itemBuilder: (_, i) {
                              final m = msgs[i];
                              final mine = m.sender == me;
                              final older = i + 1 < msgs.length ? msgs[i + 1] : null;
                              final newDay = older == null || !sameDay(older.at, m.at);
                              final showName =
                                  !mine &&
                                  widget.room == ChatService.publicRoom &&
                                  (older == null || older.sender != m.sender);
                              return Column(
                                children: [
                                  if (newDay)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      child: Tag(sameDay(m.at, DateTime.now()) ? 'Hari ini' : fmtDateShort(m.at)),
                                    ),
                                  _Bubble(message: m, mine: mine, name: showName ? names[m.sender]?.name : null),
                                ],
                              );
                            },
                          ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _input,
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(hintText: 'Tulis pesan…'),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Pressable(
                            onTap: _sending ? null : _send,
                            scale: .85,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
                              child: _sending
                                  ? Padding(
                                      padding: const EdgeInsets.all(15),
                                      child: CircularProgressIndicator(strokeWidth: 2, color: c.onBrand),
                                    )
                                  : Icon(Icons.send_rounded, color: c.onBrand, size: 21),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine, this.name});
  final ChatMessage message;
  final bool mine;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .76),
        margin: EdgeInsets.only(top: name != null ? 8 : 3),
        padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
        decoration: BoxDecoration(
          color: mine ? c.brand : c.surface,
          border: mine ? null : Border.all(color: c.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 6),
            bottomRight: Radius.circular(mine ? 6 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (name != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(name!, style: context.t.labelMedium!.copyWith(color: c.primary)),
              ),
            Text(message.body, style: context.t.bodyMedium!.copyWith(color: mine ? c.onBrand : c.ink)),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                fmtTime(message.at),
                style: context.t.labelSmall!.copyWith(
                  color: mine ? Colors.white.withValues(alpha: .7) : c.muted,
                  fontSize: 10,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: .2, end: 0);
  }
}
