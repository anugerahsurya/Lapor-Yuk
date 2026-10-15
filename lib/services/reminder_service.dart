import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/dates.dart';
import '../data/models.dart';
import '../data/todo.dart';

/// Offline daily reminders, scheduled ahead on the device:
///  * workdays with no activity yet, at the chosen time
///  * a heads-up two days before an empty workday falls out of the
///    one-month reporting window
/// Rescheduled whenever activities or settings change, so days that get
/// filled are dropped automatically.
abstract final class ReminderService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _daily = 1000;
  static const _deadline = 1100;
  static const _todo = 1200;
  static const _horizonDays = 14;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminder_harian',
      'Pengingat harian',
      channelDescription: 'Pengingat mengisi kegiatan dan batas pelaporan',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_sun',
      color: Color(0xFF2F5FEA),
    ),
  );

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_sun')),
    );
    _ready = true;
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Android 13+ runtime permission. Returns true if notifications may show.
  static Future<bool> requestPermission() async {
    await init();
    return await _android?.requestNotificationsPermission() ?? true;
  }

  static Future<void> reschedule({
    required bool enabled,
    required int minutes,
    required List<Activity> activities,
    List<Todo> todos = const [],
    DateTime? now,
  }) async {
    await init();
    for (var i = 0; i < 60; i++) {
      await _plugin.cancel(id: _daily + i);
      await _plugin.cancel(id: _deadline + i);
      await _plugin.cancel(id: _todo + i);
    }
    final n = now ?? DateTime.now();

    // To Do reminders at their own time (independent of the CKP switch).
    final timed = todos.where((t) => !t.done && t.dueMinutes != null && t.dueAt!.isAfter(n)).toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    for (final (i, t) in timed.take(60).indexed) {
      await _schedule(
        _todo + i,
        t.dueAt!,
        t.important ? '⭐ ${t.title}' : t.title,
        t.note.isEmpty ? 'Pengingat tugas To Do' : t.note,
      );
    }

    if (!enabled) return;

    final today = dateOnly(n);
    bool filled(DateTime d) => activities.any((a) => a.coversDay(d));
    DateTime at(DateTime d) => DateTime(d.year, d.month, d.day, minutes ~/ 60, minutes % 60);

    // 1) Daily nudges.
    var id = _daily;
    for (var i = 0; i < _horizonDays; i++) {
      final d = today.add(Duration(days: i));
      final when = at(d);
      if (!when.isAfter(n) || d.weekday > 5 || filled(d)) continue;
      await _schedule(
        id++,
        when,
        'Belum ada kegiatan hari ini',
        'Catat kegiatan ${fmtDay(d)}, ${fmtDateShort(d)} selagi masih ingat.',
      );
    }

    // 2) Deadline heads-up: empty workdays whose window closes soon.
    final expiring = <DateTime, List<DateTime>>{};
    for (var back = 0; back <= 31; back++) {
      final d = today.subtract(Duration(days: back));
      if (d.weekday > 5 || filled(d)) continue;
      final warn = _lastReportableDay(d).subtract(const Duration(days: 2));
      if (warn.isBefore(today) || warn.isAfter(today.add(const Duration(days: _horizonDays)))) continue;
      expiring.putIfAbsent(warn, () => []).add(d);
    }
    id = _deadline;
    for (final e in expiring.entries) {
      final when = at(e.key);
      if (!when.isAfter(n)) continue;
      final days = e.value..sort();
      final list = days.map(fmtDateShort).join(', ');
      await _schedule(
        id++,
        when,
        days.length == 1 ? 'Batas lapor hampir lewat' : '${days.length} tanggal hampir lewat batas',
        '$list masih kosong. Tinggal 2 hari lagi untuk melaporkannya.',
      );
    }
  }

  /// Last calendar day on which [d] is still inside the one-month window.
  static DateTime _lastReportableDay(DateTime d) {
    var x = d;
    while (inWindow(d, x.add(const Duration(days: 1)))) {
      x = x.add(const Duration(days: 1));
    }
    return x;
  }

  static Future<void> _schedule(int id, DateTime when, String title, String body) async {
    try {
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
      );
    } catch (e) {
      debugPrint('reminder schedule failed: $e');
    }
  }

  static const _chatDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'pesan_chat',
      'Pesan chat',
      channelDescription: 'Pesan baru dari teman, grup, dan Ruang Umum',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_sun',
      color: Color(0xFF2F5FEA),
      category: AndroidNotificationCategory.message,
    ),
  );

  /// One notification per room; a newer message replaces the older one.
  static Future<void> chat(int id, String title, String body) async {
    await init();
    await _plugin.show(id: id, title: title, body: body, notificationDetails: _chatDetails);
  }

  /// Fires one right away so the user can see what it looks like.
  static Future<void> test() async {
    await init();
    await _plugin.show(
      id: 999,
      title: 'Pengingat Lapor Yuk aktif',
      body: 'Kamu akan diingatkan di hari kerja yang belum ada kegiatannya.',
      notificationDetails: _details,
    );
  }
}
