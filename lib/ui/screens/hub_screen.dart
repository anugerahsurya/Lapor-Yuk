import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/quotes.dart';
import '../../core/theme.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../services/chat_service.dart';
import '../../state/providers.dart';
import '../sheets/todo_sheet.dart';
import '../widgets/common.dart';
import '../widgets/sky_header.dart';
import 'camera_screen.dart';
import 'chat_screen.dart';
import 'photos_screen.dart';
import 'todo_screen.dart';

/// Home: living meadow, daily quote, feature hub and a "today" digest.
class HubScreen extends ConsumerWidget {
  const HubScreen({
    super.key,
    required this.openKinerja,
    required this.openTodo,
    required this.openProfile,
    required this.onReport,
  });

  final void Function(int tab) openKinerja;
  final VoidCallback openTodo;
  final VoidCallback openProfile;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final summary = ref.watch(monthSummaryProvider(monthOf(now)));
    final todayTodos = ref.watch(todayTodosProvider);
    final photos = ref.watch(looseProvider).value?.length ?? 0;
    final todayActs = ref.watch(dayActivitiesProvider(dateOnly(now)));

    var i = 0;
    Widget enter(Widget w) => w.animate().fadeIn(delay: (60 * i++).ms, duration: 420.ms).slideY(begin: .12, end: 0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SkyHeader(height: 280, onAvatarTap: openProfile)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 130),
            sliver: SliverList.list(
              children: [
                enter(const _QuoteCard()),
                const _UpdateBanner(),
                const SizedBox(height: 22),
                enter(const SectionLabel('Fitur')),
                enter(
                  Row(
                    children: [
                      Expanded(
                        child: _FeatureCard(
                          filled: true,
                          icon: Icons.insights_rounded,
                          title: 'Kinerja',
                          subtitle: summary.workdays == 0
                              ? 'Lapor CKP'
                              : '${summary.filledWorkdays}/${summary.workdays} hari kerja terisi',
                          progress: summary.progress,
                          onTap: () => openKinerja(0),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FeatureCard(
                          icon: Icons.checklist_rounded,
                          title: 'To Do',
                          subtitle: todayTodos.isEmpty ? 'Tidak ada tenggat' : '${todayTodos.length} tugas hari ini',
                          onTap: openTodo,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                enter(
                  Row(
                    children: [
                      _MiniFeature(
                        icon: Icons.photo_camera_rounded,
                        label: 'Kamera',
                        onTap: () => Navigator.of(context).push(softRoute(const CameraScreen(quick: true))),
                      ),
                      _MiniFeature(
                        icon: Icons.photo_library_rounded,
                        label: 'Foto',
                        badge: photos,
                        onTap: () => Navigator.of(context).push(softRoute(const PhotosScreen())),
                      ),
                      _MiniFeature(icon: Icons.picture_as_pdf_rounded, label: 'Rekap', onTap: () => openKinerja(2)),
                      ListenableBuilder(
                        listenable: Listenable.merge([
                          ChatService.unread,
                          ChatService.invites,
                          ChatService.friendRequests,
                        ]),
                        builder: (context, _) => _MiniFeature(
                          icon: Icons.forum_rounded,
                          label: 'Chat',
                          badge: ChatService.badge,
                          onTap: () => Navigator.of(context).push(softRoute(ChatHomeScreen(openProfile: openProfile))),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                enter(SectionLabel('Hari ini · ${fmtDay(now)}')),
                enter(_CkpToday(count: todayActs.length, weekend: now.weekday >= 6, onReport: onReport)),
                const SizedBox(height: 10),
                if (todayTodos.isEmpty)
                  enter(
                    AppCard(
                      onTap: () => openTodoSheet(context, due: dateOnly(now)),
                      child: Row(
                        children: [
                          Icon(Icons.add_task_rounded, color: context.c.primary),
                          const SizedBox(width: 12),
                          Expanded(child: Text('Tambah tugas untuk hari ini', style: context.t.titleSmall)),
                          Icon(Icons.add_rounded, color: context.c.muted),
                        ],
                      ),
                    ),
                  )
                else ...[
                  for (final t in todayTodos.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: enter(TodoTile(key: ValueKey(t.id), todo: t, compact: true)),
                    ),
                  if (todayTodos.length > 3)
                    Center(
                      child: Pressable(
                        onTap: openTodo,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            'Lihat ${todayTodos.length - 3} tugas lainnya',
                            style: context.t.labelLarge!.copyWith(color: context.c.primary),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteCard extends ConsumerStatefulWidget {
  const _QuoteCard();

  @override
  ConsumerState<_QuoteCard> createState() => _QuoteCardState();
}

class _QuoteCardState extends ConsumerState<_QuoteCard> {
  int _offset = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final q = quoteOfDay(ref.watch(clockProvider).value ?? DateTime.now(), offset: _offset);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '“',
            style: TextStyle(fontFamily: kFont, fontSize: 54, height: .9, fontWeight: FontWeight.w800, color: c.brand),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: Motion.base,
              transitionBuilder: (w, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, .15), end: Offset.zero).animate(a),
                  child: w,
                ),
              ),
              child: Column(
                key: ValueKey(q.text),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('QUOTE HARI INI', style: context.t.labelSmall!.copyWith(color: c.muted)),
                  const SizedBox(height: 6),
                  Text(q.text, style: context.t.titleMedium!.copyWith(height: 1.4)),
                  const SizedBox(height: 8),
                  Text('— ${q.by}', style: context.t.labelMedium!.copyWith(color: c.primary)),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Quote lain',
            onPressed: () => setState(() => _offset++),
            icon: Icon(Icons.autorenew_rounded, color: c.muted, size: 20),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.filled = false,
    this.progress,
  });

  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final bool filled;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = filled ? c.onBrand : c.ink;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.slow,
        height: 148,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: filled
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.brand, Color.lerp(c.brand, const Color(0xFF0A1230), .35)!],
                )
              : null,
          color: filled ? null : c.surface,
          borderRadius: BorderRadius.circular(22),
          border: filled ? null : Border.all(color: c.line),
          boxShadow: filled
              ? [BoxShadow(color: c.brand.withValues(alpha: .28), blurRadius: 18, offset: const Offset(0, 8))]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: filled ? Colors.white.withValues(alpha: .16) : c.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: filled ? c.onBrand : c.primary, size: 21),
                ),
                const Spacer(),
                Icon(Icons.arrow_outward_rounded, size: 18, color: fg.withValues(alpha: .6)),
              ],
            ),
            const Spacer(),
            Text(title, style: context.t.titleLarge!.copyWith(color: fg)),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.bodySmall!.copyWith(color: filled ? Colors.white.withValues(alpha: .75) : c.muted),
            ),
            if (progress != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress!),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 5,
                    backgroundColor: Colors.white.withValues(alpha: .2),
                    valueColor: AlwaysStoppedAnimation(c.accent),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniFeature extends StatelessWidget {
  const _MiniFeature({required this.icon, required this.label, required this.onTap, this.badge = 0});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Expanded(
      child: Pressable(
        onTap: onTap,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: c.line),
                  ),
                  child: Icon(icon, color: c.primary, size: 24),
                ),
                if (badge > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.bg, width: 2),
                      ),
                      child: Text(
                        '$badge',
                        style: context.t.labelMedium!.copyWith(color: const Color(0xFF111A33), fontSize: 10.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(label, style: context.t.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _CkpToday extends StatelessWidget {
  const _CkpToday({required this.count, required this.weekend, required this.onReport});
  final int count;
  final bool weekend;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (icon, color, title, sub) = count > 0
        ? (Icons.verified_rounded, c.success, '$count kegiatan tercatat', 'Laporan CKP hari ini sudah aman.')
        : weekend
        ? (
            Icons.weekend_rounded,
            c.primary,
            'Hari libur',
            'Sabtu & Minggu tidak dihitung hari kerja. Selamat istirahat.',
          )
        : (Icons.pending_actions_rounded, c.accent, 'Belum ada kegiatan', 'Catat kegiatan hari ini untuk CKP.');
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.t.titleSmall),
                Text(sub, style: context.t.bodySmall),
              ],
            ),
          ),
          if (count == 0 && !weekend) AppButton(label: 'Lapor', style: BtnStyle.tonal, onTap: onReport),
        ],
      ),
    );
  }
}

/// Shows on Beranda when a newer APK is on the download page. Dismissible per
/// version so it does not nag after the user has seen it.
class _UpdateBanner extends ConsumerStatefulWidget {
  const _UpdateBanner();

  @override
  ConsumerState<_UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<_UpdateBanner> {
  int? _dismissed;

  @override
  Widget build(BuildContext context) {
    final up = ref.watch(updateProvider).value;
    if (up == null || up.versionCode == _dismissed) return const SizedBox.shrink();
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        color: c.brand,
        child: Row(
          children: [
            Icon(Icons.system_update_rounded, color: c.onBrand),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pembaruan tersedia · ${up.versionName}',
                    style: context.t.titleSmall!.copyWith(color: c.onBrand),
                  ),
                  if (up.notes.isNotEmpty)
                    Text(
                      up.notes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.t.bodySmall!.copyWith(color: Colors.white.withValues(alpha: .8)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Pressable(
                  onTap: up.url.isEmpty
                      ? null
                      : () => launchUrl(Uri.parse(up.url), mode: LaunchMode.externalApplication),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Text('Unduh', style: context.t.labelLarge!.copyWith(color: c.brand)),
                  ),
                ),
                Pressable(
                  onTap: () => setState(() => _dismissed = up.versionCode),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Nanti',
                      style: context.t.labelMedium!.copyWith(color: Colors.white.withValues(alpha: .8)),
                    ),
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
