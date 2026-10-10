import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../services/reminder_service.dart';
import '../../state/providers.dart';
import '../sheets/todo_sheet.dart';
import '../widgets/common.dart';
import '../widgets/floating_nav.dart';
import 'camera_screen.dart';
import 'form_screen.dart';
import 'hub_screen.dart';
import 'kinerja_screen.dart';
import 'settings_screen.dart';
import 'todo_screen.dart';

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  int _index = 0;
  final _kinerjaTab = ValueNotifier(0);

  static const _items = [
    NavItem(Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, 'Beranda'),
    NavItem(Icons.insights_outlined, Icons.insights_rounded, 'Kinerja'),
    NavItem(Icons.checklist_rounded, Icons.checklist_rounded, 'To Do'),
    NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
  ];

  @override
  void initState() {
    super.initState();
    // Kick off the "complete addresses when online" watcher.
    ref.read(addressSyncProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initReminders());
  }

  @override
  void dispose() {
    _kinerjaTab.dispose();
    super.dispose();
  }

  Future<void> _initReminders() async {
    final prefs = ref.read(prefsProvider);
    if (ref.read(settingsProvider).reminderOn && !(prefs.getBool('notifAsked') ?? false)) {
      await prefs.setBool('notifAsked', true);
      await ReminderService.requestPermission();
    }
    await _reschedule();
  }

  Future<void> _reschedule() async {
    final s = ref.read(settingsProvider);
    final acts = ref.read(activitiesProvider).value;
    final todos = ref.read(todosProvider).value;
    if (acts == null || todos == null) return;
    await ReminderService.reschedule(enabled: s.reminderOn, minutes: s.reminderMinutes, activities: acts, todos: todos);
  }

  void _go(int i) => setState(() => _index = i);

  void _openKinerja(int tab) {
    _kinerjaTab.value = tab;
    _go(1);
  }

  void _newReport([DateTime? day]) => Navigator.of(context).push(softRoute(FormScreen(initialDay: day)));

  /// Centre "+" button: quick actions for every module.
  Future<void> _actions() async {
    final c = context.c;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Widget action(int i, IconData icon, String title, String sub, VoidCallback onTap) => Pressable(
          onTap: () {
            Navigator.pop(ctx);
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, color: c.onBrand),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: ctx.t.titleSmall),
                      Text(sub, style: ctx.t.bodySmall),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.muted),
              ],
            ),
          ),
        ).animate().fadeIn(delay: (50 * i).ms, duration: 250.ms).slideY(begin: .2, end: 0);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Mau apa sekarang?', style: ctx.t.headlineSmall),
                const SizedBox(height: 14),
                action(0, Icons.post_add_rounded, 'Lapor kegiatan', 'Isi CKP dengan bukti dukung', _newReport),
                const SizedBox(height: 10),
                action(
                  1,
                  Icons.add_task_rounded,
                  'Tambah tugas',
                  'Masuk ke To Do',
                  () => openTodoSheet(context, due: dateOnly(DateTime.now())),
                ),
                const SizedBox(height: 10),
                action(
                  2,
                  Icons.photo_camera_rounded,
                  'Kamera cepat',
                  'Foto ber-watermark, lampirkan nanti',
                  () => Navigator.of(context).push(softRoute(const CameraScreen(quick: true))),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Filled days / finished tasks drop out of the reminder schedule.
    ref.listen(activitiesProvider, (_, _) => _reschedule());
    ref.listen(todosProvider, (_, _) => _reschedule());
    ref.listen(settingsProvider.select((s) => (s.reminderOn, s.reminderMinutes)), (_, _) => _reschedule());
    final pages = [
      HubScreen(openKinerja: _openKinerja, openTodo: () => _go(2), openProfile: () => _go(3), onReport: _newReport),
      KinerjaScreen(tab: _kinerjaTab, onReport: _newReport),
      const TodoScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          for (var i = 0; i < pages.length; i++)
            IgnorePointer(
              ignoring: i != _index,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                opacity: i == _index ? 1 : 0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  offset: i == _index ? Offset.zero : Offset(i < _index ? -.04 : .04, 0),
                  child: TickerMode(enabled: i == _index, child: pages[i]),
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FloatingNav(items: _items, index: _index, onSelect: _go, onAction: _actions),
          ),
        ],
      ),
    );
  }
}
