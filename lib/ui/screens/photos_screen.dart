import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../widgets/activity_card.dart';
import '../widgets/common.dart';
import 'camera_screen.dart';
import 'detail_screen.dart';
import 'form_screen.dart';

/// Gallery of every photo in the app: quick-camera photos plus image evidence
/// from each activity, grouped by capture date.
class PhotosScreen extends ConsumerWidget {
  const PhotosScreen({super.key});

  Future<void> _actions(BuildContext context, WidgetRef ref, GalleryPhoto g) async {
    final e = g.evidence;
    final a = g.activity;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(e.masterPath), width: 54, height: 72, fit: BoxFit.cover, cacheWidth: 160),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${fmtFullDate(e.capturedAt)} · ${fmtTime(e.capturedAt)}', style: ctx.t.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          a != null ? a.title : (e.address ?? 'Alamat menunggu sinyal'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: ctx.t.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (a == null)
                AppButton(
                  label: 'Buat laporan dengan foto ini',
                  icon: Icons.post_add_rounded,
                  expand: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(softRoute(FormScreen(initialDay: e.capturedAt, initialEvidences: [e])));
                  },
                )
              else
                AppButton(
                  label: 'Buka kegiatan',
                  icon: Icons.assignment_outlined,
                  expand: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(softRoute(DetailScreen(id: a.id!)));
                  },
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Lihat',
                      icon: Icons.open_in_full_rounded,
                      style: BtnStyle.ghost,
                      onTap: () => OpenFilex.open(e.masterPath),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButton(
                      label: 'Hapus',
                      icon: Icons.delete_outline_rounded,
                      style: BtnStyle.danger,
                      // A photo attached to an activity is removed from the
                      // report form, not here, to keep the achievement intact.
                      onTap: a != null
                          ? null
                          : () async {
                              final ok = await confirmSheet(
                                ctx,
                                title: 'Hapus foto?',
                                message: 'Foto juga dihapus dari folder Lapor Yuk.',
                                confirm: 'Hapus',
                                danger: true,
                              );
                              if (!ok) return;
                              await ref.read(repoProvider).deleteEvidence(e);
                              ref.invalidate(looseProvider);
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                    ),
                  ),
                ],
              ),
              if (a != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Foto ini melekat pada kegiatan. Hapus dari halaman kegiatan bila perlu.',
                    style: ctx.t.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(galleryProvider).value ?? const <GalleryPhoto>[];
    final loose = photos.where((g) => g.activity == null).length;
    final groups = <DateTime, List<GalleryPhoto>>{};
    for (final g in photos) {
      groups.putIfAbsent(dateOnly(g.evidence.capturedAt), () => []).add(g);
    }
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: IconBtn(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
          ),
        ),
        leadingWidth: 60,
        title: Text('Foto tersimpan', style: context.t.titleLarge),
        centerTitle: true,
        actions: [
          IconBtn(
            icon: Icons.photo_camera_rounded,
            bg: context.c.brand,
            color: context.c.onBrand,
            onTap: () => Navigator.of(context).push(softRoute(const CameraScreen(quick: true))),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: photos.isEmpty
          ? const Center(
              child: EmptyState(
                icon: Icons.photo_camera_back_outlined,
                title: 'Belum ada foto',
                message: 'Foto dari Kamera cepat dan bukti gambar kegiatan muncul di sini.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              physics: const BouncingScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${photos.length} foto'
                    '${loose > 0 ? ' · $loose belum dilampirkan' : ''}',
                    style: context.t.bodySmall,
                  ),
                ),
                for (final entry in groups.entries) ...[
                  SectionLabel('${fmtDay(entry.key)}, ${fmtDateShort(entry.key)}'),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 3 / 4,
                    children: [
                      for (final (i, g) in entry.value.indexed)
                        Pressable(
                          onTap: () => _actions(context, ref, g),
                          scale: .95,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(File(g.evidence.masterPath), fit: BoxFit.cover, cacheWidth: 300),
                                if (g.activity == null)
                                  Positioned(
                                    right: 6,
                                    top: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: context.c.accent,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'Baru',
                                        style: TextStyle(
                                          fontFamily: kFont,
                                          color: Color(0xFF111A33),
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  left: 6,
                                  bottom: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      fmtTime(g.evidence.capturedAt),
                                      style: const TextStyle(
                                        fontFamily: kFont,
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ).animate().fadeIn(delay: (30 * i).ms, duration: 250.ms).scale(begin: const Offset(.92, .92)),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
              ],
            ),
    );
  }
}

/// Multi-select sheet used by the report form to attach saved photos.
Future<List<Evidence>?> pickSavedPhotos(BuildContext context, {required Set<int> exclude}) {
  return showModalBottomSheet<List<Evidence>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PickSheet(exclude: exclude),
  );
}

class _PickSheet extends ConsumerStatefulWidget {
  const _PickSheet({required this.exclude});
  final Set<int> exclude;

  @override
  ConsumerState<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends ConsumerState<_PickSheet> {
  final _sel = <int>{};

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final photos = (ref.watch(looseProvider).value ?? const <Evidence>[])
        .where((e) => !widget.exclude.contains(e.id))
        .toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Foto tersimpan', style: context.t.headlineSmall),
              const SizedBox(height: 4),
              Text('Pilih foto dari Kamera cepat untuk dilampirkan.', style: context.t.bodySmall),
              const SizedBox(height: 14),
              if (photos.isEmpty)
                const EmptyState(
                  icon: Icons.photo_camera_back_outlined,
                  title: 'Belum ada foto tersimpan',
                  message: 'Gunakan Kamera cepat di Beranda.',
                )
              else
                Flexible(
                  child: GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 3 / 4,
                    children: [
                      for (final e in photos)
                        Pressable(
                          onTap: () => setState(() => _sel.contains(e.id) ? _sel.remove(e.id) : _sel.add(e.id!)),
                          scale: .94,
                          child: AnimatedContainer(
                            duration: Motion.fast,
                            padding: EdgeInsets.all(_sel.contains(e.id) ? 4 : 0),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _sel.contains(e.id) ? c.brand : Colors.transparent, width: 2.5),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.file(File(e.masterPath), fit: BoxFit.cover, cacheWidth: 300),
                                  Positioned(
                                    right: 6,
                                    top: 6,
                                    child: AnimatedScale(
                                      scale: _sel.contains(e.id) ? 1 : 0,
                                      duration: Motion.base,
                                      curve: Motion.spring,
                                      child: Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
                                        child: Icon(Icons.check_rounded, size: 15, color: c.onBrand),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              AppButton(
                label: _sel.isEmpty ? 'Pilih foto' : 'Lampirkan ${_sel.length} foto',
                expand: true,
                onTap: _sel.isEmpty
                    ? null
                    : () => Navigator.pop(context, photos.where((e) => _sel.contains(e.id)).toList()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
