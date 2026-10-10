import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/skp_copy_card.dart';
import 'form_screen.dart';

class DetailScreen extends ConsumerWidget {
  const DetailScreen({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final a = (ref.watch(activitiesProvider).value ?? const []).where((x) => x.id == id).firstOrNull;
    if (a == null) return const Scaffold();
    final months = a.months;
    final folders = a.evidences
        .expand((e) => e.publicPaths)
        .map((pth) => pth.split('/').reversed.skip(1).first)
        .toSet();

    Widget row(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 18, color: c.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.t.bodySmall),
                const SizedBox(height: 2),
                Text(value, style: context.t.titleSmall),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: IconBtn(icon: Icons.arrow_back_rounded, onTap: () => Navigator.pop(context)),
          ),
        ),
        leadingWidth: 60,
        actions: [
          IconBtn(
            icon: Icons.delete_outline_rounded,
            color: c.danger,
            onTap: () async {
              final ok = await confirmSheet(
                context,
                title: 'Hapus kegiatan?',
                message:
                    'Kegiatan beserta ${a.evidences.length} bukti dukung (termasuk salinan di folder Lapor Yuk) akan dihapus permanen.',
                confirm: 'Hapus',
                danger: true,
              );
              if (!ok || !context.mounted) return;
              await ref.read(activitiesProvider.notifier).delete(a);
              if (!context.mounted) return;
              Navigator.pop(context);
              toast(context, 'Kegiatan dihapus', icon: Icons.delete_outline_rounded);
            },
          ),
          const SizedBox(width: 8),
          IconBtn(
            icon: Icons.edit_outlined,
            onTap: () => Navigator.of(context).push(softRoute(FormScreen(editing: a))),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        physics: const BouncingScrollPhysics(),
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final (i, m) in months.indexed)
                Tag(
                  i == 0 ? fmtMonth(m) : '${fmtMonth(m)} · Lanjutan',
                  icon: i == 0 ? Icons.calendar_month_rounded : Icons.redo_rounded,
                  color: i == 0 ? c.primary : c.accent,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(a.title, style: context.t.headlineMedium).animate().fadeIn(duration: 350.ms).slideY(begin: .1, end: 0),
          const SizedBox(height: 18),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              children: [
                row(Icons.event_rounded, 'Periode', fmtPeriod(a.start, a.end)),
                Divider(color: c.line),
                row(Icons.flag_outlined, 'Capaian', a.achievement),
                if (folders.isNotEmpty) ...[
                  Divider(color: c.line),
                  row(Icons.folder_outlined, 'Tersimpan di', folders.map((f) => 'Lapor Yuk/$f').join('\n')),
                ],
              ],
            ),
          ).animate().fadeIn(delay: 80.ms, duration: 350.ms).slideY(begin: .08, end: 0),
          const SizedBox(height: 22),
          const SectionLabel('Salin untuk SKP'),
          SkpCopyCard(activity: a).animate().fadeIn(delay: 140.ms, duration: 350.ms).slideY(begin: .08, end: 0),
          const SizedBox(height: 22),
          SectionLabel('Bukti dukung · ${a.evidences.length}'),
          if (a.evidences.isEmpty)
            AppCard(
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: c.danger),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Belum ada bukti dukung. Tambahkan lewat tombol ubah.', style: context.t.bodyMedium),
                  ),
                ],
              ),
            )
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                for (final (i, e) in a.evidences.indexed)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: EvidenceThumb(evidence: e)),
                      if (e.address != null || e.lat != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            e.address ?? 'Menunggu alamat (offline)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.t.bodySmall,
                          ),
                        ),
                    ],
                  ).animate().fadeIn(delay: (60 * i).ms, duration: 300.ms).scale(begin: const Offset(.94, .94)),
              ],
            ),
        ],
      ),
    );
  }
}
