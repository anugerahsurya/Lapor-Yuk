import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../data/todo.dart';
import '../../state/providers.dart';
import '../sheets/todo_sheet.dart';
import '../widgets/activity_card.dart';
import '../widgets/common.dart';

enum _Filter { today, upcoming, all, done }

class TodoScreen extends ConsumerStatefulWidget {
  const TodoScreen({super.key});

  @override
  ConsumerState<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends ConsumerState<TodoScreen> {
  _Filter _filter = _Filter.today;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final today = dateOnly(now);
    final all = ref.watch(todosProvider).value ?? const <Todo>[];
    final open = all.where((t) => !t.done).toList();

    // Today's progress: tasks due today (done or not) + overdue still open.
    final dueToday = all.where((t) => t.due != null && sameDay(t.due!, today)).toList();
    final doneToday = dueToday.where((t) => t.done).length;

    final groups = <String, List<Todo>>{};
    void add(String k, Todo t) => groups.putIfAbsent(k, () => []).add(t);
    switch (_filter) {
      case _Filter.today:
        for (final t in open) {
          if (t.isOverdue(now) && !sameDay(t.due!, today)) add('Terlambat', t);
        }
        for (final t in all.where((t) => t.due != null && sameDay(t.due!, today))) {
          add('Hari ini', t);
        }
      case _Filter.upcoming:
        for (final t in open.where((t) => t.due != null && dateOnly(t.due!).isAfter(today))) {
          final d = dateOnly(t.due!);
          final key = sameDay(d, today.add(const Duration(days: 1)))
              ? 'Besok'
              : d.difference(today).inDays < 7
              ? fmtDay(d)
              : fmtDateShort(d);
          add(key, t);
        }
      case _Filter.all:
        for (final t in open) {
          if (t.due == null) {
            add('Tanpa tanggal', t);
          } else if (t.isOverdue(now) && !sameDay(t.due!, today)) {
            add('Terlambat', t);
          } else if (sameDay(t.due!, today)) {
            add('Hari ini', t);
          } else {
            add('Mendatang', t);
          }
        }
      case _Filter.done:
        final done = all.where((t) => t.done).toList()
          ..sort((a, b) => (b.doneAt ?? b.createdAt).compareTo(a.doneAt ?? a.createdAt));
        for (final t in done.take(60)) {
          add('Selesai', t);
        }
    }

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(13)),
                        child: Icon(Icons.checklist_rounded, color: c.onBrand, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('To Do', style: context.t.headlineSmall),
                            Text('${open.length} tugas aktif', style: context.t.bodySmall),
                          ],
                        ),
                      ),
                      IconBtn(
                        icon: Icons.add_rounded,
                        bg: c.brand,
                        color: c.onBrand,
                        onTap: () => openTodoSheet(context, due: _filter == _Filter.today ? today : null),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _TodayProgress(done: doneToday, total: dueToday.length, weekend: today.weekday >= 6),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        for (final (f, label) in [
                          (_Filter.today, 'Hari ini'),
                          (_Filter.upcoming, 'Mendatang'),
                          (_Filter.all, 'Semua'),
                          (_Filter.done, 'Selesai'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Pressable(
                              onTap: () => setState(() => _filter = f),
                              child: AnimatedContainer(
                                duration: Motion.base,
                                curve: Motion.ease,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _filter == f ? c.brand : c.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _filter == f ? c.brand : c.line),
                                ),
                                child: Text(
                                  label,
                                  style: context.t.labelLarge!.copyWith(
                                    color: _filter == f ? c.onBrand : c.ink,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
          if (groups.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: _filter == _Filter.done ? Icons.inventory_2_outlined : Icons.task_alt_rounded,
                title: switch (_filter) {
                  _Filter.today => today.weekday >= 6 ? 'Hari libur, santai dulu' : 'Bebas tugas hari ini',
                  _Filter.upcoming => 'Belum ada tugas mendatang',
                  _Filter.all => 'Semua beres',
                  _Filter.done => 'Belum ada yang selesai',
                },
                message: 'Ketuk + untuk menambah tugas.',
              ),
            )
          else
            for (final g in groups.entries) ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: SectionLabel(
                    g.key,
                    trailing: Text('${g.value.length}', style: context.t.labelMedium!.copyWith(color: c.muted)),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                sliver: SliverList.separated(
                  itemCount: g.value.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => TodoTile(
                    key: ValueKey(g.value[i].id),
                    todo: g.value[i],
                  ).animate().fadeIn(delay: (25 * i.clamp(0, 10)).ms, duration: 260.ms).slideY(begin: .1, end: 0),
                ),
              ),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: 130)),
        ],
      ),
    );
  }
}

class _TodayProgress extends StatelessWidget {
  const _TodayProgress({required this.done, required this.total, required this.weekend});
  final int done, total;
  final bool weekend;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final p = total == 0 ? 0.0 : done / total;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c.brand, Color.lerp(c.brand, const Color(0xFF0A1230), .35)!]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  total == 0
                      ? (weekend ? 'Akhir pekan — tidak ada tenggat hari ini' : 'Tidak ada tenggat hari ini')
                      : done == total
                      ? 'Semua tugas hari ini selesai 🎉'
                      : '$done dari $total tugas hari ini selesai',
                  style: context.t.titleSmall!.copyWith(color: Colors.white),
                ),
              ),
              Text('${(p * 100).round()}%', style: context.t.titleMedium!.copyWith(color: c.accent)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: p),
              duration: Motion.slow,
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: .18),
                valueColor: AlwaysStoppedAnimation(c.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One task row: animated check, swipe left to delete (with undo).
class TodoTile extends ConsumerWidget {
  const TodoTile({super.key, required this.todo, this.compact = false});
  final Todo todo;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final t = todo;
    final now = DateTime.now();
    final overdue = t.isOverdue(now);
    final dueLabel = t.due == null
        ? null
        : sameDay(t.due!, now)
        ? (t.dueMinutes == null ? 'Hari ini' : 'Hari ini ${two(t.dueMinutes! ~/ 60)}:${two(t.dueMinutes! % 60)}')
        : '${fmtDateShort(t.due!)}${t.dueMinutes == null ? '' : ' ${two(t.dueMinutes! ~/ 60)}:${two(t.dueMinutes! % 60)}'}';

    final tile = AppCard(
      onTap: () => openTodoSheet(context, todo: t),
      padding: EdgeInsets.fromLTRB(12, compact ? 10 : 12, 14, compact ? 10 : 12),
      child: Row(
        children: [
          _Check(
            done: t.done,
            onTap: () {
              HapticFeedback.lightImpact();
              ref.read(todosProvider.notifier).toggle(t);
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedDefaultTextStyle(
                  duration: Motion.base,
                  style: context.t.titleSmall!.copyWith(
                    color: t.done ? c.muted : c.ink,
                    decoration: t.done ? TextDecoration.lineThrough : null,
                    decorationColor: c.muted,
                  ),
                  child: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                if (t.note.isNotEmpty && !compact)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(t.note, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.t.bodySmall),
                  ),
                if (dueLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Tag(
                      dueLabel,
                      icon: t.dueMinutes != null ? Icons.alarm_rounded : Icons.event_rounded,
                      color: overdue ? c.danger : c.primary,
                    ),
                  ),
              ],
            ),
          ),
          if (t.important) Icon(Icons.star_rounded, color: c.accent, size: 20),
        ],
      ),
    );

    return Dismissible(
      key: ValueKey('todo-${t.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(color: c.danger.withValues(alpha: .14), borderRadius: BorderRadius.circular(20)),
        child: Icon(Icons.delete_outline_rounded, color: c.danger),
      ),
      onDismissed: (_) async {
        final notifier = ref.read(todosProvider.notifier);
        await notifier.delete(t);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 110),
              content: Text('"${t.title}" dihapus'),
              action: SnackBarAction(label: 'Urungkan', textColor: c.accent, onPressed: () => notifier.save(t)),
            ),
          );
      },
      child: tile,
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.done, required this.onTap});
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      scale: .8,
      haptic: false,
      child: AnimatedContainer(
        duration: Motion.base,
        curve: Motion.spring,
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: done ? c.brand : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: done ? c.brand : c.muted.withValues(alpha: .6), width: 2),
        ),
        child: AnimatedScale(
          scale: done ? 1 : 0,
          duration: Motion.base,
          curve: Motion.spring,
          child: Icon(Icons.check_rounded, size: 17, color: c.onBrand),
        ),
      ),
    );
  }
}
