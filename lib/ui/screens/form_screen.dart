import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../sheets/date_sheet.dart';
import '../widgets/common.dart';
import 'camera_screen.dart';
import 'photos_screen.dart';

class FormScreen extends ConsumerStatefulWidget {
  const FormScreen({super.key, this.initialDay, this.editing, this.initialEvidences = const []});

  final DateTime? initialDay;
  final Activity? editing;

  /// Saved quick-camera photos to attach from the start.
  final List<Evidence> initialEvidences;

  @override
  ConsumerState<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends ConsumerState<FormScreen> {
  late final _title = TextEditingController(text: widget.editing?.title ?? '');
  late final _ach = TextEditingController(text: widget.editing?.achievement ?? defaultAchievement(''));
  late bool _autoAch =
      widget.editing == null || widget.editing!.achievement == defaultAchievement(widget.editing!.title);
  late bool _range = widget.editing?.isRange ?? false;
  late DateTime? _start = widget.editing?.start ?? _initialDay();
  late DateTime? _end = widget.editing?.end ?? _start;
  late final List<Evidence> _evidences = [...?widget.editing?.evidences, ...widget.initialEvidences];
  final List<Evidence> _removed = [];
  bool _saving = false;
  bool _submitted = false;
  bool _dirty = false;

  DateTime? _initialDay() {
    final d = widget.initialDay ?? DateTime.now();
    return inWindow(d, DateTime.now()) ? dateOnly(d) : null;
  }

  @override
  void initState() {
    super.initState();
    _title.addListener(() {
      _dirty = true;
      if (_autoAch) _ach.text = defaultAchievement(_title.text);
      if (_submitted) setState(() {});
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _ach.dispose();
    super.dispose();
  }

  bool get _datesUnchanged => widget.editing != null && _start == widget.editing!.start && _end == widget.editing!.end;

  String? get _titleError => _title.text.trim().isEmpty ? 'Kegiatan wajib diisi' : null;

  String? get _periodError {
    if (_start == null || _end == null) return 'Pilih periode kegiatan';
    if (_end!.isBefore(_start!)) return 'Tanggal selesai sebelum tanggal mulai';
    if (_datesUnchanged) return null;
    final now = DateTime.now();
    if (_end!.isAfter(dateOnly(now))) return 'Tidak boleh melewati hari ini';
    if (!inWindow(_start!, now)) return 'Maksimal 1 bulan ke belakang (${fmtDateShort(reportWindow(now).min)})';
    return null;
  }

  Future<void> _pickPeriod() async {
    final r = await pickPeriod(context, range: _range, start: _start, end: _end);
    if (r == null) return;
    setState(() {
      _start = r.$1;
      _end = r.$2;
      _dirty = true;
    });
  }

  Future<void> _addCamera() async {
    final ev = await Navigator.of(context).push<Evidence>(softRoute(const CameraScreen()));
    if (ev == null) return;
    setState(() {
      _evidences.add(ev);
      _dirty = true;
    });
  }

  Future<void> _addGallery() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;
    final storage = ref.read(repoProvider).storage;
    for (final x in picked) {
      final ext = p.extension(x.path).replaceFirst('.', '').toLowerCase();
      final dest = storage.newStagingPath(ext.isEmpty ? 'jpg' : ext);
      await x.saveTo(dest);
      _evidences.add(Evidence(kind: EvidenceKind.image, name: x.name, masterPath: dest, capturedAt: DateTime.now()));
    }
    setState(() => _dirty = true);
  }

  Future<void> _addPdf() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
    if (files.isEmpty) return;
    final storage = ref.read(repoProvider).storage;
    for (final f in files) {
      final dest = storage.newStagingPath('pdf');
      await f.xFile.saveTo(dest);
      _evidences.add(Evidence(kind: EvidenceKind.pdf, name: f.name, masterPath: dest, capturedAt: DateTime.now()));
    }
    setState(() => _dirty = true);
  }

  Future<void> _addSaved() async {
    final picked = await pickSavedPhotos(context, exclude: {for (final e in _evidences) ?e.id});
    if (picked == null || picked.isEmpty) return;
    setState(() {
      _evidences.addAll(picked);
      _dirty = true;
    });
  }

  void _remove(Evidence e) {
    setState(() {
      _evidences.remove(e);
      if (e.id != null && e.activityId == null) {
        // A saved quick-camera photo: just detach, it stays in "Foto tersimpan".
      } else if (e.id != null) {
        _removed.add(e);
      } else {
        ref.read(repoProvider).storage.deleteAll([e.masterPath, e.rawPath]);
      }
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (_titleError != null || _periodError != null) {
      toast(context, _titleError ?? _periodError!, icon: Icons.error_outline_rounded);
      return;
    }
    final storage = ref.read(repoProvider).storage;
    if (_evidences.isNotEmpty && !await storage.hasPublicAccess()) {
      if (!mounted) return;
      final ok = await confirmSheet(
        context,
        title: 'Izinkan akses folder',
        message:
            'Agar bukti dukung juga tersimpan di folder "Lapor Yuk/${monthKey(_start!)}" pada memori HP, aktifkan "Izinkan akses untuk mengelola semua file" untuk Lapor Yuk.',
        confirm: 'Buka pengaturan',
      );
      if (ok) await storage.requestPublicAccess();
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final a = Activity(
        id: widget.editing?.id,
        title: _title.text.trim().replaceAll(RegExp(r'\s+'), ' '),
        achievement: _ach.text.trim(),
        start: _start!,
        end: _end!,
        createdAt: widget.editing?.createdAt ?? now,
        updatedAt: now,
      );
      await ref.read(activitiesProvider.notifier).save(a, evidences: _evidences, removed: _removed);
      if (!mounted) return;
      final cont = a.months.length > 1 ? ' · tercatat di ${a.months.length} bulan' : '';
      Navigator.pop(context, true);
      toast(context, (widget.editing == null ? 'Kegiatan tersimpan' : 'Perubahan tersimpan') + cont);
    } catch (e) {
      if (mounted) toast(context, 'Gagal menyimpan: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discard() async {
    if (!_dirty) return Navigator.pop(context);
    final ok = await confirmSheet(
      context,
      title: 'Buang perubahan?',
      message: 'Isian yang belum disimpan akan hilang.',
      confirm: 'Buang',
      danger: true,
    );
    if (!ok || !mounted) return;
    await ref
        .read(repoProvider)
        .storage
        .deleteAll(_evidences.where((e) => e.id == null).expand((e) => [e.masterPath, e.rawPath]));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final List<DateTime> months = _start != null && _end != null && !_end!.isBefore(_start!)
        ? monthsBetween(_start!, _end!)
        : const <DateTime>[];
    int i = 0;
    Widget enter(Widget w) => w.animate().fadeIn(delay: (50 * i++).ms, duration: 350.ms).slideY(begin: .08, end: 0);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _discard();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Center(
              child: IconBtn(icon: Icons.close_rounded, onTap: _discard),
            ),
          ),
          leadingWidth: 60,
          title: Text(widget.editing == null ? 'Lapor kegiatan' : 'Ubah kegiatan', style: context.t.titleLarge),
          centerTitle: true,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          physics: const BouncingScrollPhysics(),
          children: [
            enter(const SectionLabel('Kegiatan')),
            enter(
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 4,
                style: context.t.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Contoh: Pengawasan Ujian Kompetensi',
                  errorText: _submitted ? _titleError : null,
                ),
              ),
            ),
            const SizedBox(height: 22),
            enter(
              SectionLabel(
                'Capaian',
                trailing: AnimatedSwitcher(
                  duration: Motion.fast,
                  child: _autoAch
                      ? Tag('Otomatis', key: const ValueKey(1), icon: Icons.auto_awesome_rounded, color: c.success)
                      : Pressable(
                          key: const ValueKey(2),
                          onTap: () => setState(() {
                            _autoAch = true;
                            _ach.text = defaultAchievement(_title.text);
                          }),
                          child: Tag('Kembalikan format', icon: Icons.refresh_rounded, color: c.primary),
                        ),
                ),
              ),
            ),
            enter(
              TextField(
                controller: _ach,
                minLines: 2,
                maxLines: 5,
                style: context.t.bodyMedium,
                onChanged: (_) => setState(() {
                  _autoAch = false;
                  _dirty = true;
                }),
                decoration: const InputDecoration(),
              ),
            ),
            const SizedBox(height: 22),
            enter(const SectionLabel('Periode')),
            enter(
              _Segmented(
                value: _range,
                onChanged: (v) => setState(() {
                  _range = v;
                  if (!v && _start != null) _end = _start;
                  if (v && _start != null && _end == _start) _end = null;
                  _dirty = true;
                }),
              ),
            ),
            const SizedBox(height: 10),
            enter(
              _PeriodField(
                start: _start,
                end: _end,
                range: _range,
                error: _submitted ? _periodError : null,
                onTap: _pickPeriod,
              ),
            ),
            AnimatedSize(
              duration: Motion.base,
              curve: Motion.ease,
              child: months.length > 1
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.accent.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.redo_rounded, size: 18, color: c.accent),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Melewati ${months.length} bulan. Kegiatan akan tercatat di ${months.map(fmtMonth).join(' & ')}, '
                                'dengan tanda "Lanjutan" di bulan berikutnya.',
                                style: context.t.bodySmall!.copyWith(color: c.ink),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 22),
            enter(
              SectionLabel('Bukti dukung', trailing: Text('${_evidences.length} berkas', style: context.t.bodySmall)),
            ),
            enter(
              Row(
                children: [
                  Expanded(
                    child: _SourceTile(
                      icon: Icons.photo_camera_rounded,
                      label: 'Kamera',
                      primary: true,
                      onTap: _addCamera,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SourceTile(icon: Icons.photo_library_rounded, label: 'Galeri', onTap: _addGallery),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SourceTile(icon: Icons.picture_as_pdf_rounded, label: 'PDF', onTap: _addPdf),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SourceTile(icon: Icons.photo_camera_back_rounded, label: 'Tersimpan', onTap: _addSaved),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSize(
              duration: Motion.base,
              curve: Motion.ease,
              alignment: Alignment.topCenter,
              child: _evidences.isEmpty
                  ? const SizedBox(width: double.infinity)
                  : GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      children: [
                        for (final e in _evidences)
                          EvidenceThumb(key: ObjectKey(e), evidence: e, onRemove: () => _remove(e))
                              .animate()
                              .scale(begin: const Offset(.8, .8), duration: 300.ms, curve: Curves.easeOutBack)
                              .fadeIn(),
                      ],
                    ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: AppButton(
            label: widget.editing == null ? 'Simpan laporan' : 'Simpan perubahan',
            icon: Icons.check_rounded,
            expand: true,
            busy: _saving,
            onTap: _save,
          ),
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget seg(String label, bool v) => Expanded(
      child: Pressable(
        onTap: () => onChanged(v),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          child: AnimatedDefaultTextStyle(
            duration: Motion.fast,
            style: context.t.labelLarge!.copyWith(color: value == v ? c.ink : c.muted, fontSize: 13.5),
            child: Text(label),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(14)),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: Motion.base,
            curve: Motion.ease,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: .5,
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: .06), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
              ),
            ),
          ),
          Row(children: [seg('Tanggal tunggal', false), seg('Rentang tanggal', true)]),
        ],
      ),
    );
  }
}

class _PeriodField extends StatelessWidget {
  const _PeriodField({
    required this.start,
    required this.end,
    required this.range,
    required this.error,
    required this.onTap,
  });
  final DateTime? start, end;
  final bool range;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final has = start != null && end != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Pressable(
          onTap: onTap,
          scale: .98,
          child: AnimatedContainer(
            duration: Motion.base,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: error != null ? c.danger : c.line),
            ),
            child: Row(
              children: [
                Icon(range ? Icons.date_range_rounded : Icons.event_rounded, color: c.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        has ? fmtPeriod(start!, end!) : (range ? 'Pilih rentang tanggal' : 'Pilih tanggal'),
                        style: context.t.titleSmall!.copyWith(color: has ? c.ink : c.muted),
                      ),
                      if (has)
                        Text(
                          sameDay(start!, end!)
                              ? fmtDay(start!)
                              : '${end!.difference(start!).inDays + 1} hari · ${fmtDay(start!)} – ${fmtDay(end!)}',
                          style: context.t.bodySmall,
                        ),
                    ],
                  ),
                ),
                Icon(Icons.expand_more_rounded, color: c.muted),
              ],
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(error!, style: context.t.bodySmall!.copyWith(color: c.danger)),
          ).animate().shakeX(hz: 4, amount: 3, duration: 300.ms),
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.icon, required this.label, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 84,
        decoration: BoxDecoration(
          color: primary ? c.brand : c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: primary ? c.brand : c.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: primary ? c.onBrand : c.primary, size: 24),
            const SizedBox(height: 6),
            Text(label, style: context.t.labelMedium!.copyWith(color: primary ? c.onBrand : c.ink)),
          ],
        ),
      ),
    );
  }
}

class EvidenceThumb extends StatelessWidget {
  const EvidenceThumb({super.key, required this.evidence, this.onRemove});
  final Evidence evidence;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final e = evidence;
    return Pressable(
      onTap: () => OpenFilex.open(e.masterPath),
      scale: .95,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (e.isImage)
              Image.file(
                File(e.masterPath),
                fit: BoxFit.cover,
                cacheWidth: 360,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: c.surface2,
                  child: Icon(Icons.broken_image_outlined, color: c.muted),
                ),
              )
            else
              Container(
                color: c.surface2,
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.picture_as_pdf_rounded, color: c.danger, size: 26),
                    const Spacer(),
                    Text(
                      e.name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.labelMedium!.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
            if (e.kind == EvidenceKind.camera)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        e.addressPending ? Icons.cloud_off_rounded : Icons.place_rounded,
                        size: 11,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        e.addressPending ? 'offline' : 'geotag',
                        style: const TextStyle(
                          fontFamily: kFont,
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (onRemove != null)
              Positioned(
                right: 6,
                top: 6,
                child: Pressable(
                  onTap: onRemove,
                  scale: .8,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
