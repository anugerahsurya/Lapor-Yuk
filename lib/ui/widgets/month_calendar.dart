import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import 'common.dart';

/// Calendar used by both the dashboard (marks) and the date picker
/// (selection/range + disabled days). Month changes slide horizontally.
class MonthCalendar extends StatefulWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.onMonthChanged,
    required this.onDayTap,
    this.marks = const {},
    this.selected,
    this.rangeStart,
    this.rangeEnd,
    this.isEnabled,
    this.minMonth,
    this.maxMonth,
  });

  final DateTime month;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDayTap;
  final Map<int, int> marks;
  final DateTime? selected;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final bool Function(DateTime)? isEnabled;
  final DateTime? minMonth;
  final DateTime? maxMonth;

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  int _dir = 1;

  bool get _canPrev => widget.minMonth == null || addMonths(widget.month, -1).compareTo(monthOf(widget.minMonth!)) >= 0;
  bool get _canNext => widget.maxMonth == null || addMonths(widget.month, 1).compareTo(monthOf(widget.maxMonth!)) <= 0;

  void _go(int d) {
    setState(() => _dir = d);
    widget.onMonthChanged(addMonths(widget.month, d));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            AnimatedSwitcher(
              duration: Motion.base,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, .4), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              child: Text(fmtMonth(widget.month), key: ValueKey(widget.month), style: context.t.titleLarge),
            ),
            const Spacer(),
            IconBtn(icon: Icons.chevron_left_rounded, onTap: _canPrev ? () => _go(-1) : null),
            const SizedBox(width: 8),
            IconBtn(icon: Icons.chevron_right_rounded, onTap: _canNext ? () => _go(1) : null),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    hariPendek[i],
                    style: context.t.labelMedium!.copyWith(color: i >= 5 ? c.danger.withValues(alpha: .8) : c.muted),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -200 && _canNext) _go(1);
            if (v > 200 && _canPrev) _go(-1);
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topCenter, children: [...prev, ?cur]),
            transitionBuilder: (child, a) {
              final incoming = child.key == ValueKey(widget.month);
              final off = Offset((incoming ? .25 : -.25) * _dir, 0);
              return FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: off, end: Offset.zero).animate(a),
                  child: child,
                ),
              );
            },
            child: _Grid(key: ValueKey(widget.month), w: widget),
          ),
        ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({super.key, required this.w});
  final MonthCalendar w;

  @override
  Widget build(BuildContext context) {
    final m = w.month;
    final lead = DateTime(m.year, m.month, 1).weekday - 1;
    final days = daysInMonth(m);
    final rows = ((lead + days) / 7).ceil();
    final today = dateOnly(DateTime.now());
    return Column(
      children: [
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final d = r * 7 + col - lead + 1;
                      if (d < 1 || d > days) return const SizedBox(height: 48);
                      final date = DateTime(m.year, m.month, d);
                      return _Day(
                        date: date,
                        today: sameDay(date, today),
                        marks: w.marks[d] ?? 0,
                        enabled: w.isEnabled?.call(date) ?? true,
                        selected:
                            (w.selected != null && sameDay(date, w.selected!)) ||
                            (w.rangeStart != null && sameDay(date, w.rangeStart!)) ||
                            (w.rangeEnd != null && sameDay(date, w.rangeEnd!)),
                        inRange:
                            w.rangeStart != null &&
                            w.rangeEnd != null &&
                            date.isAfter(w.rangeStart!) &&
                            date.isBefore(w.rangeEnd!),
                        rangeEdge: w.rangeStart != null && w.rangeEnd != null && !sameDay(w.rangeStart!, w.rangeEnd!)
                            ? (sameDay(date, w.rangeStart!) ? -1 : (sameDay(date, w.rangeEnd!) ? 1 : 0))
                            : 0,
                        onTap: () => w.onDayTap(date),
                      );
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.date,
    required this.today,
    required this.marks,
    required this.enabled,
    required this.selected,
    required this.inRange,
    required this.rangeEdge,
    required this.onTap,
  });

  final DateTime date;
  final bool today, enabled, selected, inRange;
  final int marks;
  final int rangeEdge; // -1 start, 1 end, 0 none
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final weekend = date.weekday >= 6; // Sabtu & Minggu libur
    final fg = selected
        ? c.onBrand
        : !enabled
        ? c.muted.withValues(alpha: .35)
        : weekend
        ? c.danger
        : c.ink;
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (inRange || rangeEdge != 0)
            Positioned.fill(
              top: 5,
              bottom: 5,
              child: FractionallySizedBox(
                alignment: rangeEdge == -1 ? Alignment.centerRight : Alignment.centerLeft,
                widthFactor: rangeEdge == 0 ? 1 : .5,
                child: ColoredBox(color: c.primarySoft),
              ),
            ),
          Pressable(
            onTap: enabled ? onTap : null,
            scale: .85,
            child: AnimatedContainer(
              duration: Motion.base,
              curve: Motion.ease,
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected
                    ? c.brand
                    : (marks > 0 && enabled ? c.primarySoft.withValues(alpha: .55) : Colors.transparent),
                shape: BoxShape.circle,
                border: today && !selected ? Border.all(color: c.accent, width: 2) : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    '${date.day}',
                    style: context.t.titleSmall!.copyWith(
                      color: fg,
                      fontWeight: today || selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  if (marks > 0)
                    Positioned(
                      bottom: 4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < marks.clamp(1, 3); i++)
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(color: selected ? c.accent : c.primary, shape: BoxShape.circle),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
