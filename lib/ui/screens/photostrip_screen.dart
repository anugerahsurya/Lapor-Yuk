import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../services/chat_service.dart';
import '../../services/photostrip_service.dart';
import '../../state/providers.dart';
import '../widgets/activity_card.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';
import 'story_screen.dart';

String _first(String name) => name.trim().split(RegExp(r'\s+')).first;

Widget _face(String? avatar, double size) => ClipOval(
  child: Image.asset(
    avatarAsset(avatars.contains(avatar) ? avatar! : 'sun'),
    width: size,
    height: size,
    fit: BoxFit.cover,
    cacheWidth: (size * 3).round(),
  ),
);

class _StripPainter extends CustomPainter {
  _StripPainter(this.template, this.photos, this.labels, this.title, this.date);
  final int template;
  final List<ui.Image?> photos;
  final List<String> labels;
  final String title;
  final DateTime date;

  @override
  void paint(Canvas canvas, Size size) =>
      paintStrip(canvas, size, template, photos, title: title, date: date, labels: labels);

  @override
  bool shouldRepaint(_StripPainter old) => true;
}

/// Sheet to start a photostrip in [room]: pick a template and (in a group)
/// up to 5 people. [candidates] = people who can be asked (DM: the other
/// person). Opens the session screen once created.
Future<void> startPhotostrip(
  BuildContext context, {
  required String room,
  required String title,
  required List<ChatProfile> candidates,
}) async {
  final dm = room.startsWith('dm:');
  var template = 0;
  final picked = <String>{if (dm) ...candidates.map((p) => p.id)};
  var busy = false;
  final id = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final c = ctx.c;
        final n = picked.length + 1;
        final labels = ['Kamu', for (final p in candidates.where((p) => picked.contains(p.id))) _first(p.name)];
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .88),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Photostrip bareng', style: ctx.t.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Tiap orang mengisi satu kotak pakai kamera masing-masing, maksimal 6 orang. '
                    'Kalau semua sudah foto, hasilnya bisa diunduh sebagai PNG ukuran 4R.',
                    style: ctx.t.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  const SectionLabel('Template'),
                  SizedBox(
                    height: 190,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: stripTemplates.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (_, i) => Pressable(
                        onTap: () => setSheet(() => template = i),
                        child: Column(
                          children: [
                            AnimatedContainer(
                              duration: Motion.fast,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: template == i ? c.brand : c.line, width: 2.5),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 100,
                                  height: 150,
                                  child: CustomPaint(
                                    painter: _StripPainter(i, List.filled(n, null), labels, title, DateTime.now()),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              stripTemplates[i].name,
                              style: ctx.t.labelMedium!.copyWith(color: template == i ? c.primary : c.ink),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SectionLabel('Ajak · $n orang termasuk kamu'),
                  if (dm)
                    Text('Kamu dan ${candidates.isEmpty ? 'temanmu' : candidates.first.name}', style: ctx.t.bodyMedium)
                  else if (candidates.isEmpty)
                    Text('Belum ada anggota lain di grup ini.', style: ctx.t.bodySmall)
                  else
                    for (final p in candidates)
                      CheckboxListTile(
                        value: picked.contains(p.id),
                        contentPadding: EdgeInsets.zero,
                        secondary: _face(p.avatar, 36),
                        title: Text(p.name, style: ctx.t.titleSmall),
                        onChanged: !picked.contains(p.id) && picked.length >= 5
                            ? null
                            : (_) => setSheet(() => picked.contains(p.id) ? picked.remove(p.id) : picked.add(p.id)),
                      ),
                  const SizedBox(height: 14),
                  AppButton(
                    label: picked.isEmpty ? 'Pilih teman dulu' : 'Ajak foto · $n orang',
                    icon: Icons.photo_camera_front_rounded,
                    expand: true,
                    busy: busy,
                    onTap: picked.isEmpty || busy
                        ? null
                        : () async {
                            setSheet(() => busy = true);
                            try {
                              final id = await PhotostripService.create(room, template, picked.toList());
                              if (ctx.mounted) Navigator.pop(ctx, id);
                            } catch (e) {
                              setSheet(() => busy = false);
                              if (ctx.mounted) {
                                toast(ctx, 'Gagal membuat photostrip: $e', icon: Icons.error_outline_rounded);
                              }
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  if (id != null && context.mounted) {
    await Navigator.of(context).push(softRoute(PhotostripScreen(stripId: id, autoShoot: true)));
  }
}

/// One photostrip session: live preview of every box, take my shot, and
/// download the 4R PNG once everyone is in.
class PhotostripScreen extends ConsumerStatefulWidget {
  const PhotostripScreen({super.key, required this.stripId, this.autoShoot = false});
  final int stripId;

  /// Opens the camera right away if I still have to take my shot ("Yuk Foto").
  final bool autoShoot;

  @override
  ConsumerState<PhotostripScreen> createState() => _PhotostripScreenState();
}

class _PhotostripScreenState extends ConsumerState<PhotostripScreen> {
  Photostrip? _strip;
  bool _loaded = false;
  String _title = 'Foto Bareng';
  List<StripMember> _members = const [];
  Map<String, ChatProfile> _people = const {};
  final _images = <String, ui.Image>{};
  final _subs = <StreamSubscription>[];
  bool _shooting = false;
  bool _saving = false;
  bool _autoDone = false;

  String? get _me => ChatService.uid;
  StripMember? get _mine => _members.where((m) => m.userId == _me).firstOrNull;
  bool get _complete => _members.isNotEmpty && _members.every((m) => m.done);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    for (final img in _images.values) {
      img.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await PhotostripService.get(widget.stripId);
      if (s != null && s.room.startsWith('grp:')) {
        final g = await Supabase.instance.client
            .from('groups')
            .select('name')
            .eq('id', s.room.substring(4))
            .maybeSingle();
        _title = g?['name'] as String? ?? _title;
      }
      if (!mounted) return;
      setState(() {
        _strip = s;
        _loaded = true;
      });
      if (s == null) return;
      _subs.addAll([
        PhotostripService.members(s.id).listen(_onMembers),
        ChatService.people().listen((p) => setState(() => _people = {for (final x in p) x.id: x})),
      ]);
    } catch (e) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _onMembers(List<StripMember> m) {
    setState(() => _members = m);
    for (final x in m) {
      final path = x.path;
      if (path == null || _images.containsKey(path)) continue;
      PhotostripService.image(path).then((img) {
        if (mounted) {
          setState(() => _images[path] = img);
        } else {
          img.dispose();
        }
      }, onError: (_) {});
    }
    if (widget.autoShoot && !_autoDone) {
      _autoDone = true;
      if (_mine != null && !_mine!.done) _shoot();
    }
  }

  String _nameOf(String id) => id == _me ? 'Kamu' : (_people[id]?.name ?? 'Pengguna');

  Future<void> _shoot() async {
    if (_shooting) return;
    final path = await Navigator.of(context)
        .push<String>(softRoute(const StoryCameraScreen(capture: true, title: 'Photostrip · fotomu')));
    if (path == null || !mounted) return;
    setState(() => _shooting = true);
    try {
      final jpeg = await compressStory(path);
      await PhotostripService.upload(widget.stripId, jpeg, old: _mine?.path);
      if (mounted) toast(context, _complete ? 'Fotomu masuk' : 'Fotomu masuk, tunggu yang lain ya');
    } catch (e) {
      if (mounted) toast(context, 'Gagal mengunggah: $e', icon: Icons.error_outline_rounded);
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
      if (mounted) setState(() => _shooting = false);
    }
  }

  Future<void> _download() async {
    final s = _strip;
    if (s == null || !_complete) return;
    setState(() => _saving = true);
    try {
      final photos = <ui.Image>[];
      for (final m in _members) {
        photos.add(_images[m.path!] ??= await PhotostripService.image(m.path!));
      }
      final png = await PhotostripService.renderPng(s.template, photos, title: _title, date: s.at);
      final file = await PhotostripService.save(ref.read(repoProvider).storage, png, s.id);
      if (!mounted) return;
      toast(context, 'Tersimpan: $file');
      await OpenFilex.open(file);
    } catch (e) {
      if (mounted) toast(context, 'Gagal mengunduh: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = _strip;
    final mine = _mine;
    final done = _members.where((m) => m.done).length;
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: IconBtn(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
          ),
        ),
        leadingWidth: 60,
        title: Text('Photostrip', style: context.t.titleLarge),
        centerTitle: true,
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : s == null
          ? const Center(
              child: EmptyState(
                icon: Icons.hourglass_bottom_rounded,
                title: 'Photostrip sudah tidak tersedia',
                message: 'Photostrip terhapus otomatis 3 hari setelah dibuat.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: AspectRatio(
                      aspectRatio: stripWidth / stripHeight,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: CustomPaint(
                          painter: _StripPainter(
                            s.template,
                            [for (final m in _members) m.path == null ? null : _images[m.path]],
                            [for (final m in _members) _first(_nameOf(m.userId))],
                            _title,
                            s.at,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'Template ${stripTemplates[s.template.clamp(0, 4)].name} · $done/${_members.length} sudah foto',
                    style: context.t.bodySmall,
                  ),
                ),
                const SizedBox(height: 18),
                if (mine != null && (!mine.done || !_complete))
                  AppButton(
                    label: mine.done ? 'Foto ulang' : 'Yuk Foto',
                    icon: Icons.photo_camera_front_rounded,
                    style: mine.done ? BtnStyle.ghost : BtnStyle.primary,
                    expand: true,
                    busy: _shooting,
                    onTap: _shooting ? null : _shoot,
                  ),
                if (_complete) ...[
                  const SizedBox(height: 10),
                  AppButton(
                    label: 'Unduh PNG 4R',
                    icon: Icons.download_rounded,
                    expand: true,
                    busy: _saving,
                    onTap: _saving ? null : _download,
                  ),
                ],
                const SizedBox(height: 22),
                const SectionLabel('Peserta'),
                for (final m in _members)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _face(_people[m.userId]?.avatar, 38),
                    title: Text(_nameOf(m.userId), style: context.t.titleSmall),
                    subtitle: Text(m.done ? 'Sudah foto' : 'Belum foto', style: context.t.bodySmall),
                    trailing: Icon(
                      m.done ? Icons.check_circle_rounded : Icons.schedule_rounded,
                      color: m.done ? c.success : c.muted,
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Photostrip dan fotonya terhapus otomatis 3 hari setelah dibuat. Unduh sebelum itu.',
                  style: context.t.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
    );
  }
}

/// Invitation bubble in the chat: progress, and "Yuk Foto" for people who
/// still have to take their shot.
class StripBubble extends StatefulWidget {
  const StripBubble({super.key, required this.stripId, required this.mine});
  final int stripId;
  final bool mine;

  @override
  State<StripBubble> createState() => _StripBubbleState();
}

class _StripBubbleState extends State<StripBubble> {
  late final _members = PhotostripService.members(widget.stripId);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = widget.mine ? c.onBrand : c.ink;
    final soft = widget.mine ? Colors.white.withValues(alpha: .75) : c.muted;
    return StreamBuilder<List<StripMember>>(
      stream: _members,
      builder: (context, snap) {
        final m = snap.data ?? const <StripMember>[];
        final done = m.where((x) => x.done).length;
        final me = m.where((x) => x.userId == ChatService.uid).firstOrNull;
        final complete = m.isNotEmpty && done == m.length;
        final gone = snap.hasData && m.isEmpty;
        void open({bool shoot = false}) =>
            Navigator.of(context).push(softRoute(PhotostripScreen(stripId: widget.stripId, autoShoot: shoot)));
        return Container(
          width: 230,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: widget.mine ? Colors.white.withValues(alpha: .14) : c.surface2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.photo_camera_front_rounded, color: fg, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Photostrip bareng', style: context.t.titleSmall!.copyWith(color: fg)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                gone
                    ? 'Sudah tidak tersedia'
                    : complete
                    ? 'Semua sudah foto, siap diunduh'
                    : '$done/${m.length} sudah foto',
                style: context.t.bodySmall!.copyWith(color: soft),
              ),
              if (m.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final x in m)
                      Container(
                        width: 18,
                        height: 24,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: x.done ? (widget.mine ? Colors.white : c.primary) : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: widget.mine ? Colors.white70 : c.line, width: 1.5),
                        ),
                      ),
                  ],
                ),
              ],
              if (!gone) ...[
                const SizedBox(height: 10),
                Pressable(
                  onTap: () => open(shoot: me != null && !me.done),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: widget.mine ? Colors.white : c.brand,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      me != null && !me.done
                          ? 'Yuk Foto'
                          : complete
                          ? 'Lihat & unduh'
                          : 'Lihat',
                      textAlign: TextAlign.center,
                      style: context.t.labelLarge!.copyWith(color: widget.mine ? c.brand : c.onBrand),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
