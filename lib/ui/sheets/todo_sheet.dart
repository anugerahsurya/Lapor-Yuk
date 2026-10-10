import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/todo.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

/// Next Monday–Friday after [from] (Sabtu & Minggu libur).
DateTime nextWorkday(DateTime from) {
  var d = dateOnly(from).add(const Duration(days: 1));
  while (d.weekday >= 6) {
    d = d.add(const Duration(days: 1));
  }
  return d;
}

Future<void> openTodoSheet(BuildContext context, {Todo? todo, DateTime? due}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TodoSheet(todo: todo, due: due),
  );
}

class _TodoSheet extends ConsumerStatefulWidget {
  const _TodoSheet({this.todo, this.due});
  final Todo? todo;
  final DateTime? due;

  @override
  ConsumerState<_TodoSheet> createState() => _TodoSheetState();
}

class _TodoSheetState extends ConsumerState<_TodoSheet> {
  late final _title = TextEditingController(text: widget.todo?.title ?? '');
  late final _note = TextEditingController(text: widget.todo?.note ?? '');
  late DateTime? _due = widget.todo?.due ?? widget.due;
  late int? _minutes = widget.todo?.dueMinutes;
  late bool _important = widget.todo?.important ?? false;
  bool _showNote = false;

  @override
  void initState() {
    super.initState();
    _showNote = _note.text.isNotEmpty;
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final base = widget.todo ?? Todo(title: title, createdAt: DateTime.now());
    final t = base.copyWith(
      title: title,
      note: _note.text.trim(),
      due: _due,
      clearDue: _due == null,
      dueMinutes: _minutes,
      clearTime: _minutes == null,
      important: _important,
    );
    await ref.read(todosProvider.notifier).save(t);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final today = dateOnly(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    final work = nextWorkday(today);

    Widget chip(String label, bool active, VoidCallback onTap, {IconData? icon}) => Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: active ? c.brand : c.surface2, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 15, color: active ? c.onBrand : c.muted), const SizedBox(width: 5)],
            Text(label, style: context.t.labelMedium!.copyWith(color: active ? c.onBrand : c.ink)),
          ],
        ),
      ),
    );

    final custom = _due != null && !sameDay(_due!, today) && !sameDay(_due!, tomorrow) && !sameDay(_due!, work);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.todo == null ? 'Tugas baru' : 'Ubah tugas', style: context.t.headlineSmall),
                ),
                Pressable(
                  onTap: () => setState(() => _important = !_important),
                  scale: .8,
                  child: AnimatedSwitcher(
                    duration: Motion.base,
                    transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
                    child: Icon(
                      _important ? Icons.star_rounded : Icons.star_outline_rounded,
                      key: ValueKey(_important),
                      color: _important ? c.accent : c.muted,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              autofocus: widget.todo == null,
              textCapitalization: TextCapitalization.sentences,
              style: context.t.titleMedium,
              decoration: const InputDecoration(hintText: 'Mau mengerjakan apa?'),
              onSubmitted: (_) => _save(),
            ),
            AnimatedSize(
              duration: Motion.base,
              child: _showNote
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: TextField(
                        controller: _note,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(hintText: 'Catatan (opsional)'),
                      ),
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Pressable(
                          onTap: () => setState(() => _showNote = true),
                          child: Text('+ Tambah catatan', style: context.t.labelMedium!.copyWith(color: c.primary)),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 18),
            const SectionLabel('Tenggat'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                chip(
                  'Tanpa',
                  _due == null,
                  () => setState(() {
                    _due = null;
                    _minutes = null;
                  }),
                ),
                chip('Hari ini', _due != null && sameDay(_due!, today), () => setState(() => _due = today)),
                chip('Besok', _due != null && sameDay(_due!, tomorrow), () => setState(() => _due = tomorrow)),
                if (!sameDay(work, tomorrow))
                  chip(
                    'Hari kerja berikutnya (${hariPendek[work.weekday - 1]})',
                    _due != null && sameDay(_due!, work),
                    () => setState(() => _due = work),
                  ),
                chip(custom ? fmtDateShort(_due!) : 'Pilih tanggal', custom, () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _due ?? today,
                    firstDate: today.subtract(const Duration(days: 365)),
                    lastDate: today.add(const Duration(days: 365 * 3)),
                    helpText: 'Tenggat tugas',
                  );
                  if (d != null) setState(() => _due = d);
                }, icon: Icons.event_rounded),
              ],
            ),
            AnimatedSize(
              duration: Motion.base,
              child: _due == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: [
                          chip(
                            _minutes == null
                                ? 'Tambah jam pengingat'
                                : 'Pukul ${two(_minutes! ~/ 60)}:${two(_minutes! % 60)}',
                            _minutes != null,
                            () async {
                              final t = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(hour: (_minutes ?? 9 * 60) ~/ 60, minute: (_minutes ?? 0) % 60),
                                builder: (ctx, child) => MediaQuery(
                                  data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
                                  child: child!,
                                ),
                              );
                              if (t != null) setState(() => _minutes = t.hour * 60 + t.minute);
                            },
                            icon: Icons.alarm_rounded,
                          ),
                          if (_minutes != null) ...[
                            const SizedBox(width: 6),
                            IconBtn(icon: Icons.close_rounded, onTap: () => setState(() => _minutes = null)),
                          ],
                          if (_due!.weekday >= 6) ...[
                            const SizedBox(width: 8),
                            Tag('Hari libur', icon: Icons.weekend_rounded, color: c.danger),
                          ],
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                if (widget.todo != null) ...[
                  IconBtn(
                    icon: Icons.delete_outline_rounded,
                    color: c.danger,
                    onTap: () async {
                      await ref.read(todosProvider.notifier).delete(widget.todo!);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: AppButton(
                    label: widget.todo == null ? 'Tambah tugas' : 'Simpan',
                    icon: Icons.check_rounded,
                    expand: true,
                    onTap: _title.text.trim().isEmpty ? null : _save,
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
