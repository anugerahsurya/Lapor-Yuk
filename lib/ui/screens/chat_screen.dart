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
/// connected their Google account.
class ChatHomeScreen extends ConsumerStatefulWidget {
  const ChatHomeScreen({super.key, required this.openProfile});
  final VoidCallback openProfile;

  @override
  ConsumerState<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends ConsumerState<ChatHomeScreen> {
  bool _joining = false;

  Future<void> _join() async {
    setState(() => _joining = true);
    try {
      final s = ref.read(settingsProvider);
      await ChatService.signIn(profile: s.profile, avatar: s.avatar);
    } catch (e) {
      if (mounted) toast(context, 'Gagal bergabung: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _joining = false);
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
      ),
      body: !ready
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: EmptyState(
                  icon: Icons.forum_outlined,
                  title: Env.chatReady ? 'Gabung ke chat Lapor Yuk' : 'Chat belum dikonfigurasi',
                  message: Env.chatReady
                      ? 'Namamu, jabatan, dan satker dari Profil akan terlihat oleh pengguna lain. Tidak perlu akun Google.'
                      : 'Build ini belum berisi kunci Supabase.',
                  action: Env.chatReady
                      ? AppButton(label: 'Gabung chat', icon: Icons.login_rounded, busy: _joining, onTap: _join)
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
                    SectionLabel('Pengguna · ${people.length}'),
                    if (snap.connectionState == ConnectionState.waiting)
                      const Center(
                        child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
                      )
                    else if (people.isEmpty)
                      const EmptyState(
                        icon: Icons.person_search_rounded,
                        title: 'Belum ada pengguna lain',
                        message: 'Ajak rekan kerja memasang Lapor Yuk dan menghubungkan Google Drive.',
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
                                _Pic(avatar: p.avatar, size: 44),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p.name, style: context.t.titleSmall),
                                      Text(
                                        [p.position, p.unit].where((e) => (e ?? '').isNotEmpty).join(' · '),
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

class _Pic extends StatelessWidget {
  const _Pic({required this.avatar, required this.size});
  final String? avatar;
  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: Image.asset(
      avatarAsset(avatars.contains(avatar) ? avatar! : 'sun'),
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * 3).round(),
    ),
  );
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
