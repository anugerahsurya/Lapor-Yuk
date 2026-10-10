import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../widgets/activity_card.dart';
import '../widgets/common.dart';
import '../widgets/month_calendar.dart';
import '../widgets/month_hero.dart';
import 'camera_screen.dart';
import 'detail_screen.dart';
import 'photos_screen.dart';

/// "Ringkasan" tab of the Kinerja module: month hero, quick actions,
/// calendar and the selected day's activities.
class KinerjaOverview extends ConsumerStatefulWidget {
  const KinerjaOverview({super.key, required this.onReport});

  final void Function([DateTime? day]) onReport;

  @override
  ConsumerState<KinerjaOverview> createState() => _KinerjaOverviewState();
}

class _KinerjaOverviewState extends ConsumerState<KinerjaOverview> {
  DateTime _month = monthOf(DateTime.now());
  DateTime _day = dateOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final marks = ref.watch(monthMarksProvider(_month));
    final dayActs = ref.watch(dayActivitiesProvider(_day));
    final window = reportWindow(now);
    final canReportDay = inWindow(_day, now);
    final weekend = _day.weekday >= 6;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 130),
      physics: const BouncingScrollPhysics(),
      children: [
        MonthHero(
          month: _month,
          summary: ref.watch(monthSummaryProvider(_month)),
          isCurrent: sameMonth(_month, now),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: .15, end: 0),
        const SizedBox(height: 12),
        _QuickActions(
          photos: ref.watch(looseProvider).value?.length ?? 0,
          onReport: () => widget.onReport(),
        ).animate().fadeIn(delay: 40.ms, duration: 400.ms).slideY(begin: .15, end: 0),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: MonthCalendar(
            month: _month,
            marks: marks,
            selected: _day,
            maxMonth: monthOf(now),
            onMonthChanged: (m) => setState(() {
              _month = m;
              _day = sameMonth(m, now) ? dateOnly(now) : DateTime(m.year, m.month, 1);
            }),
            onDayTap: (d) => setState(() => _day = d),
            isEnabled: (d) => !d.isAfter(window.max),
          ),
        ).animate().fadeIn(delay: 80.ms, duration: 400.ms).slideY(begin: .1, end: 0),
        const SizedBox(height: 22),
        SectionLabel(
          sameDay(_day, now) ? 'Hari ini · ${fmtDateShort(_day)}' : '${fmtDay(_day)} · ${fmtDateShort(_day)}',
          trailing: canReportDay
              ? Pressable(
                  onTap: () => widget.onReport(_day),
                  child: Text('+ Lapor tanggal ini', style: context.t.labelMedium!.copyWith(color: c.primary)),
                )
              : null,
        ),
        AnimatedSwitcher(
          duration: Motion.base,
          child: Column(
            key: ValueKey('$_day-${dayActs.length}-${dayActs.map((e) => e.updatedAt).join()}'),
            children: dayActs.isEmpty
                ? [
                    EmptyState(
                      icon: weekend ? Icons.weekend_outlined : Icons.event_available_outlined,
                      title: weekend ? '${fmtDay(_day)}, hari libur' : 'Belum ada kegiatan',
                      message: weekend
                          ? 'Sabtu dan Minggu libur, tidak dihitung hari kerja. Tetap bisa lapor kalau ada kegiatan.'
                          : canReportDay
                          ? 'Tanggal ini masih kosong. Laporkan kegiatanmu selagi masih bisa.'
                          : 'Tanggal ini di luar batas pelaporan (maks. 1 bulan ke belakang).',
                    ),
                  ]
                : [
                    for (final (i, a) in dayActs.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ActivityCard(
                          activity: a,
                          month: monthOf(_day),
                          onTap: () => Navigator.of(context).push(softRoute(DetailScreen(id: a.id!))),
                        ).animate().fadeIn(delay: (40 * i).ms, duration: 300.ms).slideX(begin: .05, end: 0),
                      ),
                  ],
          ),
        ),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.photos, required this.onReport});
  final int photos;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget tile({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool filled = false,
      int badge = 0,
    }) => Expanded(
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.slow,
          height: 78,
          decoration: BoxDecoration(
            color: filled ? c.brand : c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: filled ? c.brand : c.line),
            boxShadow: filled
                ? [BoxShadow(color: c.brand.withValues(alpha: .28), blurRadius: 16, offset: const Offset(0, 6))]
                : null,
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 24, color: filled ? c.onBrand : c.primary),
                    const SizedBox(height: 6),
                    Text(label, style: context.t.labelMedium!.copyWith(color: filled ? c.onBrand : c.ink)),
                  ],
                ),
              ),
              if (badge > 0)
                Positioned(
                  top: 8,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      '$badge',
                      style: context.t.labelMedium!.copyWith(color: const Color(0xFF111A33), fontSize: 11),
                    ),
                  ).animate(key: ValueKey(badge)).scale(duration: 300.ms, curve: Curves.easeOutBack),
                ),
            ],
          ),
        ),
      ),
    );
    return Row(
      children: [
        tile(icon: Icons.post_add_rounded, label: 'Lapor', onTap: onReport, filled: true),
        const SizedBox(width: 10),
        tile(
          icon: Icons.photo_camera_rounded,
          label: 'Kamera cepat',
          onTap: () => Navigator.of(context).push(softRoute(const CameraScreen(quick: true))),
        ),
        const SizedBox(width: 10),
        tile(
          icon: Icons.photo_library_rounded,
          label: 'Foto tersimpan',
          badge: photos,
          onTap: () => Navigator.of(context).push(softRoute(const PhotosScreen())),
        ),
      ],
    );
  }
}
