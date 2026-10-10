import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/sky.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';
import 'avatar.dart';
import 'sky.dart';

/// The living meadow header with greeting, sitting on a rounded sheet lip.
class SkyHeader extends ConsumerWidget {
  const SkyHeader({super.key, this.height = 300, this.onAvatarTap});

  static const sheetLip = 30.0;
  final double height;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final sky = ref.watch(skyProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final profile = ref.watch(settingsProvider.select((s) => s.profile));
    final top = MediaQuery.paddingOf(context).top;
    final weekend = now.weekday >= 6;

    return SizedBox(
      height: height + top,
      child: Stack(
        children: [
          Positioned.fill(
            child: SkyView(
              state: sky,
              ground: sheetLip,
              child: Padding(
                padding: EdgeInsets.fromLTRB(22, top + 18, 22, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _SkyChip(sky: sky, now: now),
                        if (weekend) ...[
                          const SizedBox(width: 8),
                          const _Chip(icon: Icons.weekend_rounded, label: 'Libur'),
                        ],
                        const Spacer(),
                        GestureDetector(
                          onTap: onAvatarTap,
                          child: Avatar(size: 42, ring: Colors.white.withValues(alpha: .55)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Selamat ${sky.phase.label.toLowerCase()},',
                      style: context.t.titleMedium!.copyWith(color: Colors.white.withValues(alpha: .85)),
                    ).animate().fadeIn(duration: 500.ms).slideY(begin: .3, end: 0, curve: Curves.easeOutCubic),
                    Text(profile.firstName, style: context.t.displaySmall!.copyWith(color: Colors.white))
                        .animate()
                        .fadeIn(delay: 80.ms, duration: 500.ms)
                        .slideY(begin: .3, end: 0, curve: Curves.easeOutCubic),
                    const SizedBox(height: 4),
                    Text(
                      fmtFullDate(now),
                      style: context.t.bodyMedium!.copyWith(color: Colors.white.withValues(alpha: .8)),
                    ).animate().fadeIn(delay: 160.ms, duration: 500.ms),
                  ],
                ),
              ),
            ),
          ),
          // Rounded top of the content sheet, sitting on the hills.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: sheetLip,
            child: AnimatedContainer(
              duration: Motion.slow,
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(sheetLip)),
              ),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkyChip extends StatelessWidget {
  const _SkyChip({required this.sky, required this.now});
  final SkyState sky;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final icon = switch (sky.phase) {
      SkyPhase.pagi => Icons.wb_twilight_rounded,
      SkyPhase.siang => Icons.wb_sunny_rounded,
      SkyPhase.sore => Icons.wb_twilight_rounded,
      SkyPhase.malam => Icons.nightlight_round,
    };
    return _Chip(icon: icon, label: '${sky.phase.label} · ${fmtTime(now)}');
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: .22)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.white),
        const SizedBox(width: 6),
        Text(label, style: context.t.labelMedium!.copyWith(color: Colors.white)),
      ],
    ),
  );
}
