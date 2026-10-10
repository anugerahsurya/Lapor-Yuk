import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import '../widgets/activity_card.dart';
import '../widgets/common.dart';
import '../widgets/drive_sync_bar.dart';
import 'detail_screen.dart';

/// Month pager listing all activities that touch the chosen month.
class ActivitiesScreen extends ConsumerStatefulWidget {
  const ActivitiesScreen({super.key});

  @override
  ConsumerState<ActivitiesScreen> createState() => _ActivitiesScreenState();
}

class _ActivitiesScreenState extends ConsumerState<ActivitiesScreen> {
  DateTime _month = monthOf(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final list = ref.watch(monthActivitiesProvider(_month));
    final all = ref.watch(activitiesProvider).value ?? const [];

    // Current month back to the oldest month that has data (min. 6 months).
    var oldest = addMonths(monthOf(now), -5);
    for (final a in all) {
      if (monthOf(a.start).isBefore(oldest)) oldest = monthOf(a.start);
    }
    final months = <DateTime>[];
    for (var m = monthOf(now); !m.isBefore(oldest); m = addMonths(m, -1)) {
      months.add(m);
    }

    // Shown as a tab inside the Kinerja module, which owns the header.
    return SafeArea(
      top: false,
      bottom: false,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 64,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: months.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final m = months[i];
                  final n = all.where((a) => a.touchesMonth(m)).length;
                  return _MonthChip(
                    month: m,
                    count: n,
                    active: sameMonth(m, _month),
                    onTap: () => setState(() => _month = m),
                  );
                },
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            sliver: SliverToBoxAdapter(
              child: DriveSyncBar(month: _month, count: list.length),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            sliver: SliverToBoxAdapter(child: SectionLabel('${fmtMonth(_month)} · ${list.length} kegiatan')),
          ),
          if (list.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.inbox_outlined,
                title: 'Belum ada kegiatan',
                message: 'Tekan tombol + di bawah untuk melaporkan kegiatan.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => ActivityCard(
                  key: ValueKey('${list[i].id}-$_month'),
                  activity: list[i],
                  month: _month,
                  onTap: () => Navigator.of(context).push(softRoute(DetailScreen(id: list[i].id!))),
                ).animate().fadeIn(delay: (35 * i.clamp(0, 10)).ms, duration: 320.ms).slideY(begin: .12, end: 0),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 130)),
        ],
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  const _MonthChip({required this.month, required this.count, required this.active, required this.onTap});

  final DateTime month;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.base,
        curve: Motion.ease,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.brand : c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? c.brand : c.line),
        ),
        child: Row(
          children: [
            Text(
              '${bulanPendek[month.month - 1]} ${month.year}',
              style: context.t.labelLarge!.copyWith(color: active ? c.onBrand : c.ink, fontSize: 13.5),
            ),
            if (count > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: active ? c.accent : c.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: context.t.labelMedium!.copyWith(color: active ? const Color(0xFF111A33) : c.primary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
