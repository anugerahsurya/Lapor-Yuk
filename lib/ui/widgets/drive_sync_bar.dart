import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/dates.dart';
import '../../core/env.dart';
import '../../core/theme.dart';
import '../../services/location_service.dart';
import '../../state/providers.dart';
import 'common.dart';

/// Per-month "Sinkron ke Google Drive" card.
class DriveSyncBar extends ConsumerWidget {
  const DriveSyncBar({super.key, required this.month, required this.count});
  final DateTime month;
  final int count;

  Future<void> _sync(BuildContext context, WidgetRef ref) async {
    if (!await LocationService.isOnline()) {
      if (context.mounted) toast(context, 'Butuh koneksi internet untuk sinkron', icon: Icons.cloud_off_rounded);
      return;
    }
    try {
      final r = await ref.read(driveSyncProvider.notifier).sync(month);
      if (r == null || !context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 110),
            content: Text('${fmtMonth(month)} tersinkron · ${r.uploaded} berkas baru'),
            action: r.folderLink == null
                ? null
                : SnackBarAction(
                    label: 'Buka',
                    textColor: context.c.accent,
                    onPressed: () => launchUrl(Uri.parse(r.folderLink!), mode: LaunchMode.externalApplication),
                  ),
          ),
        );
    } catch (e) {
      if (context.mounted) toast(context, 'Sinkron gagal: $e', icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final user = ref.watch(googleUserProvider);
    final st = ref.watch(driveSyncProvider);
    final mine = st.busy && sameMonth(st.month!, month);
    final last = ref.read(driveSyncProvider.notifier).lastSynced(month);

    if (!Env.googleReady) return const SizedBox.shrink();

    final subtitle = user == null
        ? 'Hubungkan akun Google di Profil'
        : mine
        ? (st.progress?.label ?? 'Menyiapkan…')
        : last == null
        ? 'Belum pernah disinkron'
        : 'Terakhir ${fmtDateShort(last)} ${fmtTime(last)}';

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(11)),
                child: Icon(
                  mine
                      ? Icons.cloud_sync_rounded
                      : (last == null ? Icons.cloud_upload_rounded : Icons.cloud_done_rounded),
                  color: c.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Google Drive · ${monthKey(month)}', style: context.t.titleSmall),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.t.bodySmall),
                  ],
                ),
              ),
              AppButton(
                label: 'Sinkron',
                icon: Icons.sync_rounded,
                style: BtnStyle.tonal,
                busy: mine,
                onTap: user == null || count == 0 || st.busy ? null : () => _sync(context, ref),
              ),
            ],
          ),
          AnimatedSize(
            duration: Motion.base,
            child: mine && st.progress != null
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: st.progress!.done / st.progress!.total,
                        minHeight: 5,
                        backgroundColor: c.surface2,
                        valueColor: AlwaysStoppedAnimation(c.brand),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
