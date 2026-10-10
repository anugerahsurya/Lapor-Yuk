import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import 'common.dart';

/// The three things every SKP entry needs, each one tap away from the
/// clipboard: activity, achievement sentence and the Drive evidence link.
class SkpCopyCard extends ConsumerWidget {
  const SkpCopyCard({super.key, required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final a = activity;
    final links = ref.watch(driveLinksProvider).value ?? const {};
    // One link per month the activity appears in (lanjutan → several).
    final monthLinks = {
      for (final m in a.months)
        if (links['${a.id}|${monthKey(m)}'] != null) m: links['${a.id}|${monthKey(m)}']!,
    };
    final mainLink = monthLinks.values.isEmpty ? null : monthLinks.values.first;

    void copy(String text, String what) {
      Clipboard.setData(ClipboardData(text: text));
      HapticFeedback.lightImpact();
      toast(context, '$what disalin', icon: Icons.content_copy_rounded);
    }

    Widget row(String label, String value, {String? copyText, bool link = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.t.labelSmall!.copyWith(color: c.muted)),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: link ? 1 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.bodyMedium!.copyWith(color: link ? c.primary : c.ink),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconBtn(
            icon: Icons.content_copy_rounded,
            onTap: copyText == null ? null : () => copy(copyText, label[0] + label.substring(1).toLowerCase()),
          ),
        ],
      ),
    );

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row('KEGIATAN', a.title, copyText: a.title),
          Divider(color: c.line),
          row('CAPAIAN', a.achievement, copyText: a.achievement),
          Divider(color: c.line),
          if (monthLinks.isEmpty)
            row('BUKTI DUKUNG', 'Sinkron bulan ini ke Google Drive untuk mendapatkan link')
          else
            for (final e in monthLinks.entries)
              row(
                monthLinks.length > 1 ? 'BUKTI DUKUNG · ${fmtMonth(e.key).toUpperCase()}' : 'BUKTI DUKUNG',
                e.value,
                copyText: e.value,
                link: true,
              ),
          const SizedBox(height: 10),
          AppButton(
            label: 'Salin semua',
            icon: Icons.copy_all_rounded,
            expand: true,
            onTap: () => copy(
              [a.title, a.achievement, ?mainLink].join('\n'),
              'Kegiatan, capaian${mainLink == null ? '' : ' & link'}',
            ),
          ),
        ],
      ),
    );
  }
}
