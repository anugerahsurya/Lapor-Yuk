import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../state/providers.dart';

/// Brand-coloured summary card: progress ring of filled workdays, a headline
/// sentence, streak pill and three mini stats.
class MonthHero extends StatelessWidget {
  const MonthHero({super.key, required this.month, required this.summary, required this.isCurrent});

  final DateTime month;
  final MonthSummary summary;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = summary;
    final deep = Color.lerp(c.brand, const Color(0xFF0A1230), .35)!;
    final headline = s.workdays == 0
        ? 'Belum ada hari kerja'
        : s.emptyWorkdays == 0
        ? 'Semua hari kerja terisi'
        : '${s.filledWorkdays} dari ${s.workdays} hari kerja terisi';

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: Motion.slow,
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.brand, deep]),
          boxShadow: [BoxShadow(color: c.brand.withValues(alpha: .3), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Stack(
          children: [
            // Soft decorative rings.
            Positioned(right: -40, top: -50, child: _Ring(size: 170, opacity: .09)),
            Positioned(right: 40, bottom: -70, child: _Ring(size: 130, opacity: .06)),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _ProgressRing(value: s.progress),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fmtMonth(month).toUpperCase(),
                              style: context.t.labelSmall!.copyWith(color: Colors.white.withValues(alpha: .7)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              headline,
                              style: context.t.titleLarge!.copyWith(color: Colors.white, height: 1.25, fontSize: 17),
                            ),
                            const SizedBox(height: 10),
                            if (isCurrent)
                              _Pill(
                                icon: Icons.local_fire_department_rounded,
                                iconColor: c.accent,
                                label: s.streak == 0 ? 'Mulai streak hari ini' : 'Streak ${s.streak} hari kerja',
                              )
                            else
                              _Pill(
                                icon: Icons.history_rounded,
                                iconColor: Colors.white,
                                label: s.emptyWorkdays == 0 ? 'Bulan lengkap' : '${s.emptyWorkdays} hari kosong',
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(height: 1, color: Colors.white.withValues(alpha: .14)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _Mini(icon: Icons.task_alt_rounded, value: s.activities, label: 'Kegiatan'),
                      _Mini(
                        icon: Icons.attach_file_rounded,
                        value: s.noEvidence,
                        label: 'Tanpa bukti',
                        warn: s.noEvidence > 0,
                      ),
                      _Mini(
                        icon: Icons.event_busy_rounded,
                        value: s.emptyWorkdays,
                        label: 'Hari kosong',
                        warn: s.emptyWorkdays > 0,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.opacity});
  final double size, opacity;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white.withValues(alpha: opacity), width: 22),
    ),
  );
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: 78,
        height: 78,
        child: CustomPaint(
          painter: _RingPainter(v, context.c.accent),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(v * 100).round()}%',
                  style: context.t.titleLarge!.copyWith(color: Colors.white, fontSize: 19, height: 1),
                ),
                const SizedBox(height: 2),
                Text(
                  'terisi',
                  style: context.t.labelMedium!.copyWith(color: Colors.white.withValues(alpha: .7), fontSize: 10.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.accent);
  final double v;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(4, 4, size.width - 8, size.height - 8);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = Colors.white.withValues(alpha: .16),
    );
    if (v <= 0) return;
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * v.clamp(0, 1),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: [Colors.white, accent, Colors.white],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.accent != accent;
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.iconColor, required this.label});
  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: iconColor),
        const SizedBox(width: 5),
        Text(label, style: context.t.labelMedium!.copyWith(color: Colors.white, fontSize: 11.5)),
      ],
    ),
  );
}

class _Mini extends StatelessWidget {
  const _Mini({required this.icon, required this.value, required this.label, this.warn = false});
  final IconData icon;
  final int value;
  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final accent = context.c.accent;
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: warn ? accent.withValues(alpha: .22) : Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: warn ? accent : Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: value.toDouble()),
                  duration: Motion.slow,
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) =>
                      Text('${v.round()}', style: context.t.titleMedium!.copyWith(color: Colors.white, height: 1.1)),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.t.labelMedium!.copyWith(color: Colors.white.withValues(alpha: .7), fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
