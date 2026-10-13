import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'story_screen.dart';

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

  late final Stream<List<ChatGroup>>? _groups = ChatService.signedIn ? ChatService.groups() : null;

  @override
  void initState() {
    super.initState();
    if (ChatService.signedIn) {
      _me = ChatService.me();
      ChatService.refreshBadges();
      ChatService.purgeStories();
    }
  }

  Future<void> _answer(ChatGroup g, bool accept) async {
    try {
      await ChatService.answer(g.id, accept);
      if (mounted) toast(context, accept ? 'Bergabung ke ${g.name}' : 'Undangan ditolak');
    } catch (e) {
      if (mounted) toast(context, 'Gagal: $e', icon: Icons.error_outline_rounded);
    }
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
                    const SizedBox(height: 16),
                    _StoryStrip(people: people),
                    const SizedBox(height: 16),
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
                          const _Unread(room: ChatService.publicRoom, onBrand: true),
                          Icon(Icons.chevron_right_rounded, color: c.onBrand),
                        ],
                      ),
                    ).animate().fadeIn(duration: 300.ms).slideY(begin: .1, end: 0),
                    const SizedBox(height: 22),
                    StreamBuilder<List<ChatGroup>>(
                      stream: _groups,
                      builder: (context, gs) {
                        final all = gs.data ?? const <ChatGroup>[];
                        final invited = all.where((g) => !g.joined).toList();
                        final joined = all.where((g) => g.joined).toList();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (invited.isNotEmpty) ...[
                              SectionLabel('Undangan grup · ${invited.length}'),
                              for (final g in invited)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _InviteCard(
                                    group: g,
                                    from: people.where((p) => p.id == g.owner).firstOrNull?.name,
                                    onAnswer: (ok) => _answer(g, ok),
                                  ),
                                ),
                              const SizedBox(height: 14),
                            ],
                            SectionLabel(
                              'Grup · ${joined.length}',
                              trailing: Pressable(
                                onTap: () => Navigator.of(context).push(softRoute(const GroupFormScreen())),
                                child: Text('+ Buat grup', style: context.t.labelLarge!.copyWith(color: c.primary)),
                              ),
                            ),
                            if (joined.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Belum ada grup. Buat grup lalu undang rekan kerja; mereka bisa menerima atau menolak.',
                                  style: context.t.bodySmall,
                                ),
                              ),
                            for (final g in joined)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: AppCard(
                                  onTap: () =>
                                      Navigator.of(context)
                                          .push(softRoute(ChatRoomScreen(room: g.room, title: g.name, group: g))),
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: c.primarySoft,
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: Icon(Icons.group_rounded, color: c.primary),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(child: Text(g.name, style: context.t.titleSmall)),
                                      _Unread(room: g.room),
                                      Icon(Icons.chevron_right_rounded, color: c.muted),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 14),
                          ],
                        );
                      },
                    ),
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
                                _Unread(room: ChatService.dmRoom(p.id)),
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
  const ChatRoomScreen({super.key, required this.room, required this.title, this.avatar, this.group});
  final String room, title;
  final String? avatar;
  final ChatGroup? group;

  @override
  ConsumerState<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

enum _Tick { none, sent, read }

class _ChatRoomScreenState extends ConsumerState<ChatRoomScreen> {
  final _input = TextEditingController();
  final _subs = <StreamSubscription>[];
  List<ChatMessage> _msgs = const [];
  bool _loaded = false;
  Map<String, ChatProfile> _names = const {};
  Map<int, Map<String, String>> _reacts = const {};
  Map<String, DateTime> _reads = const {};
  Set<String> _joined = const {};
  ChatMessage? _replying;
  bool _sending = false;

  bool get _multi => widget.room == ChatService.publicRoom || widget.group != null;
  bool get _receipts => widget.room != ChatService.publicRoom;

  @override
  void initState() {
    super.initState();
    _subs.addAll([
      ChatService.messages(widget.room).listen((m) {
        // Every batch that arrives while the room is open counts as read.
        ChatService.markRead(widget.room);
        setState(() {
          _msgs = m.reversed.toList();
          _loaded = true;
        });
      }),
      ChatService.people().listen((p) => setState(() => _names = {for (final x in p) x.id: x})),
      ChatService.reactions(widget.room).listen((r) => setState(() => _reacts = r)),
      if (_receipts) ChatService.reads(widget.room).listen((r) => setState(() => _reads = r)),
      if (widget.group != null)
        ChatService.members(widget.group!.id).listen(
          (m) => setState(
            () => _joined = {
              for (final x in m)
                if (x.joined) x.userId,
            },
          ),
        ),
    ]);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _input.dispose();
    ChatService.markRead(widget.room);
    super.dispose();
  }

  String _nameOf(String id) => id == ChatService.uid ? 'Kamu' : (_names[id]?.name ?? 'Pengguna');

  /// Other people in this room who have opened it since [m] was sent.
  List<String> _readers(ChatMessage m) => [
    for (final e in _reads.entries)
      if (e.key != ChatService.uid && !e.value.isBefore(m.at) && (widget.group == null || _joined.contains(e.key)))
        e.key,
  ];

  _Tick _tick(ChatMessage m) {
    if (m.sender != ChatService.uid) return _Tick.none;
    if (!_receipts) return _Tick.sent;
    final others = widget.group == null ? 1 : _joined.length - 1;
    return others > 0 && _readers(m).length >= others ? _Tick.read : _Tick.sent;
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ChatService.send(widget.room, text, replyTo: _replying?.id);
      _input.clear();
      if (mounted) setState(() => _replying = null);
    } catch (e) {
      if (mounted) toast(context, 'Gagal mengirim: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _react(ChatMessage m, String emoji) async {
    try {
      await ChatService.react(m, emoji, current: _reacts[m.id]?[ChatService.uid]);
    } catch (e) {
      if (mounted) toast(context, 'Gagal memberi reaksi: $e', icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _actions(ChatMessage m) async {
    HapticFeedback.mediumImpact();
    final mine = m.sender == ChatService.uid;
    final current = _reacts[m.id]?[ChatService.uid];
    final pick = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final e in reactionEmojis)
                    Pressable(
                      onTap: () => Navigator.pop(ctx, 'r:$e'),
                      scale: .8,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: e == current ? ctx.c.primarySoft : null,
                          shape: BoxShape.circle,
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Balas'),
              onTap: () => Navigator.pop(ctx, 'reply'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Salin'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            if (mine && widget.group != null)
              ListTile(
                leading: const Icon(Icons.done_all_rounded),
                title: const Text('Dibaca oleh'),
                onTap: () => Navigator.pop(ctx, 'info'),
              ),
            if (mine)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: ctx.c.danger),
                title: Text('Hapus untuk semua', style: TextStyle(color: ctx.c.danger)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (pick == null || !mounted) return;
    if (pick.startsWith('r:')) {
      await _react(m, pick.substring(2));
    } else if (pick == 'reply') {
      setState(() => _replying = m);
    } else if (pick == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.body));
      if (mounted) toast(context, 'Pesan disalin');
    } else if (pick == 'info') {
      _readInfo(m);
    } else if (pick == 'delete') {
      final ok = await confirmSheet(
        context,
        title: 'Hapus pesan?',
        message: 'Pesan hilang untuk semua orang di ruang ini.',
        confirm: 'Hapus',
        danger: true,
      );
      if (!ok) return;
      try {
        await ChatService.deleteMessage(m.id);
      } catch (e) {
        if (mounted) toast(context, 'Gagal menghapus: $e', icon: Icons.error_outline_rounded);
      }
    }
  }

  void _readInfo(ChatMessage m) {
    final read = _readers(m);
    final unread = _joined.where((u) => u != ChatService.uid && !read.contains(u)).toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            SectionLabel('Dibaca · ${read.length}'),
            for (final u in read)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _Pic(avatar: _names[u]?.avatar, size: 36),
                title: Text(_nameOf(u)),
                trailing: Text(fmtTime(_reads[u]!), style: ctx.t.bodySmall),
              ),
            if (unread.isNotEmpty) ...[
              const SizedBox(height: 8),
              SectionLabel('Belum dibaca · ${unread.length}'),
              for (final u in unread)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _Pic(avatar: _names[u]?.avatar, size: 36),
                  title: Text(_nameOf(u)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final me = ChatService.uid;
    final byId = {for (final m in _msgs) m.id: m};
    final reply = _replying;
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
            if (_multi)
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(11)),
                child: Icon(
                  widget.group != null ? Icons.group_rounded : Icons.groups_rounded,
                  color: c.onBrand,
                  size: 20,
                ),
              )
            else
              _Pic(avatar: widget.avatar, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.title, style: context.t.titleMedium, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          if (widget.group != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconBtn(
                icon: Icons.info_outline_rounded,
                tooltip: 'Info grup',
                onTap: () => Navigator.of(context).push(softRoute(GroupInfoScreen(group: widget.group!))),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _msgs.isEmpty
                ? Center(
                    child: EmptyState(
                      icon: Icons.waving_hand_outlined,
                      title: _loaded ? 'Belum ada pesan' : 'Memuat…',
                      message: 'Mulai obrolan dengan sapaan singkat.',
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) {
                      final m = _msgs[i];
                      final mine = m.sender == me;
                      final older = i + 1 < _msgs.length ? _msgs[i + 1] : null;
                      final newDay = older == null || !sameDay(older.at, m.at);
                      final showName = !mine && _multi && (newDay || older.sender != m.sender);
                      final quoted = m.replyTo == null ? null : byId[m.replyTo];
                      return Column(
                        children: [
                          if (newDay)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Tag(sameDay(m.at, DateTime.now()) ? 'Hari ini' : fmtDateShort(m.at)),
                            ),
                          _Bubble(
                            key: ValueKey(m.id),
                            message: m,
                            mine: mine,
                            sender: showName ? (_names[m.sender] ?? _unknown) : null,
                            quote: m.replyTo == null
                                ? null
                                : (
                                    quoted == null ? 'Pesan' : _nameOf(quoted.sender),
                                    quoted?.body ?? 'Pesan sudah dihapus atau terlalu lama',
                                  ),
                            reactions: _reacts[m.id] ?? const {},
                            tick: _tick(m),
                            onLongPress: () => _actions(m),
                            onReact: (e) => _react(m, e),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (reply != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border(left: BorderSide(color: c.brand, width: 3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Membalas ${_nameOf(reply.sender)}',
                          style: context.t.labelMedium!.copyWith(color: c.primary),
                        ),
                        Text(reply.body, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.t.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _replying = null),
                    icon: Icon(Icons.close_rounded, color: c.muted, size: 20),
                  ),
                ],
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
      ),
    );
  }
}

// Sender who already left / hasn't synced since: still label the bubble.
const _unknown = ChatProfile(id: '', name: 'Pengguna');

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.message,
    required this.mine,
    required this.reactions,
    required this.tick,
    required this.onLongPress,
    required this.onReact,
    this.sender,
    this.quote,
  });
  final ChatMessage message;
  final bool mine;

  /// Set on the first bubble of each run in Ruang Umum / groups: shows the
  /// sender's avatar and name above the bubble.
  final ChatProfile? sender;

  /// (name, text) of the message this one replies to.
  final (String, String)? quote;
  final Map<String, String> reactions;
  final _Tick tick;
  final VoidCallback onLongPress;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = mine ? c.onBrand : c.ink;
    final soft = mine ? Colors.white.withValues(alpha: .7) : c.muted;
    final q = quote;
    final story = message.storyPath;
    final bubble = GestureDetector(
      onLongPress: onLongPress,
      onDoubleTap: () => onReact(reactionEmojis[1]),
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .76),
        padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
        decoration: BoxDecoration(
          color: mine ? c.brand : c.surface,
          border: mine ? null : Border.all(color: c.line),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(sender != null ? 6 : 18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 6),
            bottomRight: Radius.circular(mine ? 6 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (story != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        ChatService.storyUrl(story),
                        width: 36,
                        height: 48,
                        fit: BoxFit.cover,
                        cacheWidth: 108,
                        errorBuilder: (_, _, _) => Container(
                          width: 36,
                          height: 48,
                          color: Colors.black12,
                          child: Icon(Icons.hourglass_bottom_rounded, size: 16, color: soft),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('Membalas story', style: context.t.labelSmall!.copyWith(color: soft)),
                  ],
                ),
              ),
            if (q != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                decoration: BoxDecoration(
                  color: mine ? Colors.white.withValues(alpha: .14) : c.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border(left: BorderSide(color: mine ? Colors.white : c.primary, width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(q.$1, style: context.t.labelSmall!.copyWith(color: mine ? Colors.white : c.primary)),
                    Text(
                      q.$2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall!.copyWith(color: soft),
                    ),
                  ],
                ),
              ),
            Text(message.body, style: context.t.bodyMedium!.copyWith(color: fg)),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fmtTime(message.at),
                    style: context.t.labelSmall!.copyWith(color: soft, fontSize: 10, letterSpacing: 0),
                  ),
                  if (tick != _Tick.none) ...[
                    const SizedBox(width: 3),
                    Icon(
                      tick == _Tick.read ? Icons.done_all_rounded : Icons.done_rounded,
                      size: 14,
                      color: tick == _Tick.read ? c.accent : soft,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final counts = <String, int>{};
    for (final e in reactions.values) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
    final myReaction = reactions[ChatService.uid];
    final withReactions = counts.isEmpty
        ? bubble
        : Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              bubble,
              Transform.translate(
                offset: const Offset(0, -4),
                child: Wrap(
                  spacing: 4,
                  children: [
                    for (final e in counts.entries)
                      Pressable(
                        onTap: () => onReact(e.key),
                        scale: .9,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: e.key == myReaction ? c.primarySoft : c.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: e.key == myReaction ? c.primary : c.line),
                          ),
                          child: Text(
                            e.value > 1 ? '${e.key} ${e.value}' : e.key,
                            style: context.t.labelSmall!.copyWith(fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );

    final s = sender;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: s == null
          ? Padding(padding: const EdgeInsets.only(top: 3), child: withReactions)
          : Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Pic(avatar: s.avatar, size: 20),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .62),
                        child: Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.labelMedium!.copyWith(color: c.primary, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if ((s.position ?? '').isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            s.position!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.labelSmall!.copyWith(color: c.muted, fontSize: 10.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  withReactions,
                ],
              ),
            ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: .2, end: 0);
  }
}

class _Unread extends StatelessWidget {
  const _Unread({required this.room, this.onBrand = false});
  final String room;
  final bool onBrand;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: ChatService.unread,
      builder: (context, map, _) {
        final n = map[room] ?? 0;
        if (n == 0) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: onBrand ? Colors.white : context.c.brand,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            n > 99 ? '99+' : '$n',
            style: context.t.labelMedium!.copyWith(color: onBrand ? context.c.brand : context.c.onBrand, fontSize: 11),
          ),
        );
      },
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.group, required this.onAnswer, this.from});
  final ChatGroup group;
  final String? from;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mail_outline_rounded, color: c.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name, style: context.t.titleSmall),
                    Text(from == null ? 'Kamu diundang ke grup ini' : '$from mengundangmu', style: context.t.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppButton(label: 'Tolak', style: BtnStyle.ghost, onTap: () => onAnswer(false)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(label: 'Terima', icon: Icons.check_rounded, onTap: () => onAnswer(true)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Own story first ("+" to add), then everyone else with an active story.
class _StoryStrip extends StatefulWidget {
  const _StoryStrip({required this.people});
  final List<ChatProfile> people;

  @override
  State<_StoryStrip> createState() => _StoryStripState();
}

class _StoryStripState extends State<_StoryStrip> {
  final _stories = ChatService.stories();
  final _me = ChatService.me();
  Set<int> _seen = const {};
  StreamSubscription<Set<int>>? _seenSub;

  @override
  void initState() {
    super.initState();
    _seenSub = ChatService.viewed().listen((v) => setState(() => _seen = v));
  }

  @override
  void dispose() {
    _seenSub?.cancel();
    super.dispose();
  }

  bool _isSeen(Story s) => _seen.contains(s.id);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final people = widget.people;
    return StreamBuilder<List<Story>>(
      stream: _stories,
      builder: (context, snap) {
        final all = snap.data ?? const <Story>[];
        final byAuthor = <String, List<Story>>{};
        for (final s in all.reversed) {
          byAuthor.putIfAbsent(s.author, () => []).add(s); // oldest first, like a timeline
        }
        final me = ChatService.uid;
        final mine = byAuthor.remove(me) ?? const <Story>[];
        final names = {for (final p in people) p.id: p};

        Widget item({required String label, String? avatar, required bool ring, Widget? add, VoidCallback? onTap}) {
          return Pressable(
            onTap: onTap,
            child: SizedBox(
              width: 70,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: ring ? c.brand : c.line, width: 2.5),
                        ),
                        child: _Pic(avatar: avatar, size: 54),
                      ),
                      if (add != null) Positioned(right: -2, bottom: -2, child: add),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.labelSmall!.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
          );
        }

        void open(List<Story> list, ChatProfile? p) => Navigator.of(context)
            .push(softRoute(StoryViewer(stories: list, name: p?.name ?? 'Pengguna', avatar: p?.avatar, people: names)));
        // People with something unseen come first.
        final others = byAuthor.entries.toList()
          ..sort((a, b) => (a.value.every(_isSeen) ? 1 : 0) - (b.value.every(_isSeen) ? 1 : 0));

        return SizedBox(
          height: 92,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              StreamBuilder<ChatProfile?>(
                stream: _me,
                builder: (context, meSnap) => item(
                  label: 'Story kamu',
                  avatar: meSnap.data?.avatar,
                  ring: mine.isNotEmpty,
                  onTap: () => mine.isEmpty
                      ? Navigator.of(context).push(softRoute(const StoryCameraScreen()))
                      : open(mine, meSnap.data),
                  add: Pressable(
                    onTap: () => Navigator.of(context).push(softRoute(const StoryCameraScreen())),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: c.brand,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.bg, width: 2),
                      ),
                      child: Icon(Icons.add_rounded, size: 14, color: c.onBrand),
                    ),
                  ),
                ),
              ),
              for (final e in others)
                item(
                  label: names[e.key]?.name ?? 'Pengguna',
                  avatar: names[e.key]?.avatar,
                  ring: !e.value.every(_isSeen),
                  onTap: () => open(e.value, names[e.key]),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Checklist of synced users; used when creating a group and when inviting
/// more people later.
class _PeoplePicker extends StatelessWidget {
  const _PeoplePicker({required this.people, required this.picked, required this.onToggle});
  final List<ChatProfile> people;
  final Set<String> picked;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return const EmptyState(
        icon: Icons.person_search_rounded,
        title: 'Tidak ada yang bisa diundang',
        message: 'Pengguna lain harus menekan Sync di menu Chat dulu.',
      );
    }
    return Column(
      children: [
        for (final p in people)
          CheckboxListTile(
            value: picked.contains(p.id),
            onChanged: (_) => onToggle(p.id),
            contentPadding: EdgeInsets.zero,
            secondary: _Pic(avatar: p.avatar, size: 40, online: p.onlineNow),
            title: Text(p.name, style: context.t.titleSmall),
            subtitle: Text(
              [p.position, p.unit].where((e) => (e ?? '').isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodySmall,
            ),
          ),
      ],
    );
  }
}

class GroupFormScreen extends StatefulWidget {
  const GroupFormScreen({super.key});

  @override
  State<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends State<GroupFormScreen> {
  final _name = TextEditingController();
  final _picked = <String>{};
  final _people = ChatService.people();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      toast(context, 'Isi nama grup dulu', icon: Icons.info_outline_rounded);
      return;
    }
    setState(() => _saving = true);
    try {
      await ChatService.createGroup(name, _picked.toList());
      if (!mounted) return;
      toast(
        context,
        _picked.isEmpty ? 'Grup dibuat' : 'Grup dibuat. ${_picked.length} undangan terkirim, menunggu diterima.',
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, 'Gagal membuat grup: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: IconBtn(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
          ),
        ),
        leadingWidth: 60,
        title: Text('Grup baru', style: context.t.titleLarge),
        centerTitle: true,
      ),
      body: StreamBuilder<List<ChatProfile>>(
        stream: _people,
        builder: (context, snap) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            TextField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Nama grup, mis. Tim Statistik Sosial'),
            ),
            const SizedBox(height: 8),
            SectionLabel('Undang anggota${_picked.isEmpty ? '' : ' · ${_picked.length} dipilih'}'),
            Text('Yang diundang akan melihat undangan dan bisa menerima atau menolak.', style: context.t.bodySmall),
            const SizedBox(height: 6),
            if (snap.connectionState == ConnectionState.waiting)
              const Center(
                child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
              )
            else
              _PeoplePicker(
                people: snap.data ?? const [],
                picked: _picked,
                onToggle: (id) => setState(() => _picked.contains(id) ? _picked.remove(id) : _picked.add(id)),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: AppButton(
            label: 'Buat grup',
            icon: Icons.group_add_rounded,
            busy: _saving,
            expand: true,
            onTap: _save,
          ),
        ),
      ),
    );
  }
}

class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({super.key, required this.group});
  final ChatGroup group;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late final _members = ChatService.members(widget.group.id);
  final _people = ChatService.people();

  bool get _owner => widget.group.owner == ChatService.uid;

  Future<void> _invite(List<ChatProfile> candidates) async {
    final picked = <String>{};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Undang ke ${widget.group.name}', style: ctx.t.titleMedium),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _PeoplePicker(
                      people: candidates,
                      picked: picked,
                      onToggle: (id) => setSheet(() => picked.contains(id) ? picked.remove(id) : picked.add(id)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: AppButton(
                    label: picked.isEmpty ? 'Pilih orang' : 'Kirim ${picked.length} undangan',
                    expand: true,
                    onTap: picked.isEmpty ? null : () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ChatService.invite(widget.group.id, picked.toList());
      if (mounted) toast(context, '${picked.length} undangan terkirim');
    } catch (e) {
      if (mounted) toast(context, 'Gagal mengundang: $e', icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _remove(ChatProfile p, bool joined) async {
    final ok = await confirmSheet(
      context,
      title: joined ? 'Keluarkan ${p.name}?' : 'Batalkan undangan?',
      message: joined ? 'Dia tidak bisa lagi membaca pesan grup ini.' : 'Undangan untuk ${p.name} dibatalkan.',
      confirm: joined ? 'Keluarkan' : 'Batalkan',
      danger: true,
    );
    if (!ok) return;
    try {
      await ChatService.removeMember(widget.group.id, p.id);
    } catch (e) {
      if (mounted) toast(context, 'Gagal: $e', icon: Icons.error_outline_rounded);
    }
  }

  Future<void> _leave() async {
    final ok = await confirmSheet(
      context,
      title: _owner ? 'Hapus grup?' : 'Keluar dari grup?',
      message: _owner
          ? 'Grup dan semua anggotanya dihapus. Pesan lama tidak bisa dibuka lagi.'
          : 'Kamu perlu diundang lagi untuk bergabung kembali.',
      confirm: _owner ? 'Hapus grup' : 'Keluar',
      danger: true,
    );
    if (!ok) return;
    try {
      if (_owner) {
        await ChatService.deleteGroup(widget.group.id);
      } else {
        await ChatService.removeMember(widget.group.id);
      }
      if (!mounted) return;
      Navigator.of(context)
        ..pop()
        ..pop();
    } catch (e) {
      if (mounted) toast(context, 'Gagal: $e', icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
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
        title: Text(widget.group.name, style: context.t.titleLarge, overflow: TextOverflow.ellipsis),
        centerTitle: true,
      ),
      body: StreamBuilder<List<ChatProfile>>(
        stream: _people,
        builder: (context, ps) {
          final people = {for (final p in ps.data ?? const <ChatProfile>[]) p.id: p};
          return StreamBuilder<List<GroupMember>>(
            stream: _members,
            builder: (context, ms) {
              final members = ms.data ?? const <GroupMember>[];
              final inGroup = members.map((m) => m.userId).toSet();
              final joined = members.where((m) => m.joined).toList();
              final waiting = members.where((m) => !m.joined).toList();

              Widget row(GroupMember m) {
                final p = m.userId == me
                    ? const ChatProfile(id: '', name: 'Kamu')
                    : (people[m.userId] ?? ChatProfile(id: m.userId, name: 'Pengguna'));
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _Pic(avatar: p.avatar, size: 40, online: p.onlineNow),
                  title: Text(p.name, style: context.t.titleSmall),
                  subtitle: Text(
                    m.userId == widget.group.owner ? 'Pembuat grup' : (m.joined ? 'Anggota' : 'Menunggu jawaban'),
                    style: context.t.bodySmall,
                  ),
                  trailing: _owner && m.userId != me
                      ? IconButton(
                          tooltip: m.joined ? 'Keluarkan' : 'Batalkan undangan',
                          icon: const Icon(Icons.person_remove_outlined),
                          onPressed: () => _remove(p, m.joined),
                        )
                      : null,
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  AppButton(
                    label: 'Undang anggota',
                    icon: Icons.person_add_alt_rounded,
                    style: BtnStyle.tonal,
                    expand: true,
                    onTap: () => _invite(people.values.where((p) => !inGroup.contains(p.id)).toList()),
                  ),
                  const SizedBox(height: 18),
                  SectionLabel('Anggota · ${joined.length}'),
                  for (final m in joined) row(m),
                  if (waiting.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SectionLabel('Diundang · ${waiting.length}'),
                    for (final m in waiting) row(m),
                  ],
                  const SizedBox(height: 24),
                  AppButton(
                    label: _owner ? 'Hapus grup' : 'Keluar dari grup',
                    icon: Icons.logout_rounded,
                    style: BtnStyle.danger,
                    expand: true,
                    onTap: _leave,
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
