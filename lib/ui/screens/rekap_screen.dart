import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../services/rekap_pdf.dart';
import '../../state/providers.dart';
import '../sheets/signature_sheet.dart';
import '../widgets/common.dart';

class RekapScreen extends ConsumerStatefulWidget {
  const RekapScreen({super.key});

  @override
  ConsumerState<RekapScreen> createState() => _RekapScreenState();
}

class _RekapScreenState extends ConsumerState<RekapScreen> {
  DateTime _month = monthOf(DateTime.now());
  bool _busy = false;

  Future<void> _export() async {
    final list = ref.read(monthActivitiesProvider(_month));
    final profile = ref.read(settingsProvider).profile;
    final sig = await askSignature(context, name: profile.name);
    if (sig == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await buildRekapPdf(month: _month, activities: list, profile: profile, signaturePng: sig);
      final repo = ref.read(repoProvider);
      if (!await repo.storage.hasPublicAccess()) await repo.storage.requestPublicAccess();
      final path = await repo.storage.saveReport(_month, bytes);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (ctx) => _DoneSheet(path: path, bytes: bytes, month: _month),
      );
    } catch (e) {
      if (mounted) toast(context, 'Gagal membuat rekap: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final list = ref.watch(monthActivitiesProvider(_month));
    final marks = ref.watch(monthMarksProvider(_month));
    final noEv = list.where((a) => a.evidences.isEmpty).length;
    final cont = list.where((a) => a.isContinuationIn(_month)).length;
    final now = monthOf(DateTime.now());

    // Shown as a tab inside the Kinerja module, which owns the header.
    return SafeArea(
      top: false,
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 130),
        physics: const BouncingScrollPhysics(),
        children: [
          // Month switcher
          AppCard(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                IconBtn(icon: Icons.chevron_left_rounded, onTap: () => setState(() => _month = addMonths(_month, -1))),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: Motion.base,
                    transitionBuilder: (w, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: Tween(begin: .9, end: 1.0).animate(a), child: w),
                    ),
                    child: Column(
                      key: ValueKey(_month),
                      children: [
                        Text(bulan[_month.month - 1], style: context.t.titleLarge),
                        Text('${_month.year}', style: context.t.bodySmall),
                      ],
                    ),
                  ),
                ),
                IconBtn(
                  icon: Icons.chevron_right_rounded,
                  onTap: _month.isBefore(now) ? () => setState(() => _month = addMonths(_month, 1)) : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Metric(value: list.length, label: 'Kegiatan', color: c.ink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Metric(value: marks.length, label: 'Hari terisi', color: c.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Metric(value: noEv, label: 'Tanpa bukti', color: noEv > 0 ? c.danger : c.success),
              ),
            ],
          ),
          if (cont > 0) ...[
            const SizedBox(height: 10),
            Tag('$cont kegiatan lanjutan dari bulan sebelumnya', icon: Icons.redo_rounded, color: c.accent),
          ],
          const SizedBox(height: 22),
          const SectionLabel('Pratinjau isi'),
          if (list.isEmpty)
            AppCard(child: Text('Belum ada kegiatan di ${fmtMonth(_month)}.', style: context.t.bodyMedium))
          else
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, a) in list.indexed) ...[
                    if (i > 0) Divider(color: c.line, height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 26,
                            child: Text('${i + 1}', style: context.t.labelLarge!.copyWith(color: c.muted)),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.title, style: context.t.titleSmall),
                                const SizedBox(height: 2),
                                Text(
                                  fmtPeriod(a.start, a.end, short: true) +
                                      (a.isContinuationIn(_month) ? ' · Lanjutan' : ''),
                                  style: context.t.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            a.evidences.isEmpty ? Icons.cancel_rounded : Icons.check_circle_rounded,
                            size: 18,
                            color: a.evidences.isEmpty ? c.danger : c.success,
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: (30 * i.clamp(0, 12)).ms, duration: 250.ms),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 20),
          AppButton(
            label: 'Tanda tangan & unduh PDF',
            icon: Icons.draw_rounded,
            expand: true,
            busy: _busy,
            onTap: list.isEmpty ? null : _export,
          ),
          const SizedBox(height: 10),
          Text(
            'File disimpan ke folder Lapor Yuk/${monthKey(_month)}.',
            textAlign: TextAlign.center,
            style: context.t.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label, required this.color});
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.toDouble()),
          duration: Motion.slow,
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => Text('${v.round()}', style: context.t.headlineMedium!.copyWith(color: color)),
        ),
        Text(label, style: context.t.bodySmall),
      ],
    ),
  );
}

class _DoneSheet extends StatelessWidget {
  const _DoneSheet({required this.path, required this.bytes, required this.month});
  final String path;
  final Uint8List bytes;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final public = path.contains('Lapor Yuk');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: c.success.withValues(alpha: .14), shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, color: c.success, size: 38),
            ).animate().scale(begin: const Offset(.5, .5), duration: 500.ms, curve: Curves.elasticOut),
            const SizedBox(height: 14),
            Text('Rekap ${fmtMonth(month)} siap', style: context.t.headlineSmall),
            const SizedBox(height: 6),
            Text(
              public
                  ? 'Tersimpan di Lapor Yuk/${monthKey(month)}/${path.split('/').last}'
                  : 'Tersimpan di penyimpanan aplikasi.',
              textAlign: TextAlign.center,
              style: context.t.bodySmall,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Bagikan',
                    icon: Icons.ios_share_rounded,
                    style: BtnStyle.ghost,
                    onTap: () => Printing.sharePdf(bytes: bytes, filename: path.split('/').last),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: 'Buka PDF',
                    icon: Icons.open_in_new_rounded,
                    onTap: () => OpenFilex.open(path),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
