import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/month_calendar.dart';

/// Picks a single date or a range inside the reporting window
/// (one month back .. today). Days outside are disabled.
Future<(DateTime, DateTime)?> pickPeriod(BuildContext context, {required bool range, DateTime? start, DateTime? end}) {
  return showModalBottomSheet<(DateTime, DateTime)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PeriodSheet(range: range, start: start, end: end),
  );
}

class _PeriodSheet extends StatefulWidget {
  const _PeriodSheet({required this.range, this.start, this.end});
  final bool range;
  final DateTime? start, end;

  @override
  State<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends State<_PeriodSheet> {
  final _w = reportWindow(DateTime.now());
  late DateTime? _start = _valid(widget.start);
  late DateTime? _end = widget.range ? _valid(widget.end) : _start;
  late DateTime _month = monthOf(_start ?? _w.max);

  DateTime? _valid(DateTime? d) => d != null && inWindow(d, DateTime.now()) ? d : null;

  void _tap(DateTime d) {
    setState(() {
      if (!widget.range) {
        _start = _end = d;
      } else if (_start == null || _end != null) {
        _start = d;
        _end = null;
      } else if (d.isBefore(_start!)) {
        _start = d;
      } else {
        _end = d;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final ready = _start != null && _end != null;
    final hint = !widget.range
        ? 'Pilih tanggal kegiatan'
        : _start == null
        ? 'Pilih tanggal mulai'
        : _end == null
        ? 'Sekarang pilih tanggal selesai'
        : fmtPeriod(_start!, _end!);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.range ? 'Rentang periode' : 'Tanggal kegiatan', style: context.t.headlineSmall),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: Motion.fast,
              child: Text(
                hint,
                key: ValueKey(hint),
                style: context.t.bodyMedium!.copyWith(color: c.muted),
              ),
            ),
            const SizedBox(height: 16),
            MonthCalendar(
              month: _month,
              minMonth: _w.min,
              maxMonth: _w.max,
              onMonthChanged: (m) => setState(() => _month = m),
              onDayTap: _tap,
              selected: widget.range ? null : _start,
              rangeStart: widget.range ? _start : null,
              rangeEnd: widget.range ? _end : null,
              isEnabled: (d) => inWindow(d, DateTime.now()),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: c.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pelaporan hanya untuk ${fmtDateShort(_w.min)} – ${fmtDateShort(_w.max)}.',
                      style: context.t.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Gunakan periode ini',
              expand: true,
              onTap: ready ? () => Navigator.pop(context, (_start!, _end!)) : null,
            ),
          ],
        ),
      ),
    );
  }
}
