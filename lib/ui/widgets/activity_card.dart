import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import 'common.dart';

class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.activity, required this.onTap, this.month});

  final Activity activity;
  final VoidCallback onTap;

  /// When given, a "Lanjutan" tag is shown if the activity started earlier.
  final DateTime? month;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final a = activity;
    final photos = a.evidences.where((e) => e.isImage).length;
    final docs = a.evidences.length - photos;
    final pending = a.evidences.any((e) => e.addressPending);
    final cont = month != null && a.isContinuationIn(month!);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DateBadge(start: a.start, end: a.end),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.t.titleMedium),
                const SizedBox(height: 4),
                Text(fmtPeriod(a.start, a.end, short: true), style: context.t.bodySmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (cont) Tag('Lanjutan', icon: Icons.redo_rounded, color: c.accent),
                    if (a.evidences.isEmpty) Tag('Belum ada bukti', icon: Icons.error_outline_rounded, color: c.danger),
                    if (photos > 0) Tag('$photos foto', icon: Icons.photo_outlined, color: c.primary),
                    if (docs > 0) Tag('$docs PDF', icon: Icons.description_outlined, color: c.primary),
                    if (pending) Tag('Alamat menunggu', icon: Icons.cloud_off_rounded),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 6),
            child: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.start, required this.end});
  final DateTime start, end;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final range = !sameDay(start, end);
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Text(
            bulanPendek[start.month - 1].toUpperCase(),
            style: context.t.labelSmall!.copyWith(color: c.muted, fontSize: 10),
          ),
          Text('${start.day}', style: context.t.headlineSmall!.copyWith(height: 1.1)),
          if (range)
            Text(
              '→ ${end.day}${end.month != start.month ? ' ${bulanPendek[end.month - 1]}' : ''}',
              style: context.t.labelMedium!.copyWith(color: c.primary, fontSize: 10.5),
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: c.surface2, shape: BoxShape.circle),
            child: Icon(icon, color: c.muted, size: 28),
          ),
          const SizedBox(height: 14),
          Text(title, style: context.t.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(message, style: context.t.bodySmall, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
