import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/dates.dart';
import '../core/sky.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/todo.dart';
import '../services/chat_service.dart';
import '../services/drive_sync.dart';
import '../services/google_account.dart';
import '../services/update_service.dart';
import '../services/location_service.dart';
import '../services/watermark.dart';

/// Overridden in main() once async init is done.
final prefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError());
final repoProvider = Provider<Repository>((_) => throw UnimplementedError());

enum ThemePref { auto, light, dark }

class AppSettings {
  const AppSettings({
    this.profile = const Profile(),
    this.themePref = ThemePref.auto,
    this.lat = -0.9471, // Padang until we get a real fix
    this.lng = 100.4172,
    this.avatar = 'sun',
    this.scheme = AccentScheme.royal,
    this.reminderOn = true,
    this.reminderMinutes = 16 * 60,
  });

  final Profile profile;
  final ThemePref themePref;
  final double lat;
  final double lng;

  /// Mascot file name in assets/avatars (from ipaslogo.com).
  final String avatar;
  final AccentScheme scheme;

  /// Daily reminder on workdays without an activity, at [reminderMinutes]
  /// after midnight.
  final bool reminderOn;
  final int reminderMinutes;

  AppSettings copyWith({
    Profile? profile,
    ThemePref? themePref,
    double? lat,
    double? lng,
    String? avatar,
    AccentScheme? scheme,
    bool? reminderOn,
    int? reminderMinutes,
  }) => AppSettings(
    profile: profile ?? this.profile,
    themePref: themePref ?? this.themePref,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    avatar: avatar ?? this.avatar,
    scheme: scheme ?? this.scheme,
    reminderOn: reminderOn ?? this.reminderOn,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
  );
}

class SettingsNotifier extends Notifier<AppSettings> {
  SharedPreferences get _p => ref.read(prefsProvider);

  @override
  AppSettings build() {
    final raw = _p.getString('profile');
    return AppSettings(
      profile: raw == null ? const Profile() : Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>),
      themePref: ThemePref.values.byName(_p.getString('theme') ?? 'auto'),
      lat: _p.getDouble('lat') ?? -0.9471,
      lng: _p.getDouble('lng') ?? 100.4172,
      avatar: _p.getString('avatar') ?? 'sun',
      scheme: AccentScheme.values.byName(_p.getString('scheme') ?? 'royal'),
      reminderOn: _p.getBool('reminderOn') ?? true,
      reminderMinutes: _p.getInt('reminderMinutes') ?? 16 * 60,
    );
  }

  /// First-run setup finished (profile filled in).
  bool get onboarded => _p.getBool('onboarded') ?? false;

  Future<void> finishOnboarding() => _p.setBool('onboarded', true);

  /// The intro video plays once, right after the first-run setup.
  bool get promoSeen => _p.getBool('promoSeen') ?? false;

  Future<void> markPromoSeen() => _p.setBool('promoSeen', true);

  void setReminder({bool? on, int? minutes}) {
    if (on != null) _p.setBool('reminderOn', on);
    if (minutes != null) _p.setInt('reminderMinutes', minutes);
    state = state.copyWith(reminderOn: on, reminderMinutes: minutes);
  }

  void setScheme(AccentScheme s) {
    _p.setString('scheme', s.name);
    state = state.copyWith(scheme: s);
  }

  void setAvatar(String a) {
    _p.setString('avatar', a);
    state = state.copyWith(avatar: a);
    ChatService.updateProfile(profile: state.profile, avatar: a).catchError((_) {});
  }

  void setProfile(Profile p) {
    _p.setString('profile', jsonEncode(p.toJson()));
    state = state.copyWith(profile: p);
    ChatService.updateProfile(profile: p, avatar: state.avatar).catchError((_) {});
  }

  void setTheme(ThemePref t) {
    _p.setString('theme', t.name);
    state = state.copyWith(themePref: t);
  }

  void setLocation(double lat, double lng) {
    _p.setDouble('lat', lat);
    _p.setDouble('lng', lng);
    state = state.copyWith(lat: lat, lng: lng);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// Ticks every 30 s so sky and auto-theme follow the real clock.
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});

DateTime nowOf(Ref ref) => ref.watch(clockProvider).value ?? DateTime.now();

final skyProvider = Provider<SkyState>((ref) {
  final s = ref.watch(settingsProvider);
  return skyAt(nowOf(ref), s.lat, s.lng);
});

final themeModeProvider = Provider<ThemeMode>((ref) {
  return switch (ref.watch(settingsProvider.select((s) => s.themePref))) {
    ThemePref.light => ThemeMode.light,
    ThemePref.dark => ThemeMode.dark,
    ThemePref.auto => ref.watch(skyProvider).isNight ? ThemeMode.dark : ThemeMode.light,
  };
});

class ActivitiesNotifier extends AsyncNotifier<List<Activity>> {
  Repository get _repo => ref.read(repoProvider);

  @override
  Future<List<Activity>> build() => _repo.all();

  Future<void> reload() async => state = AsyncData(await _repo.all());

  Future<void> save(Activity a, {required List<Evidence> evidences, required List<Evidence> removed}) async {
    await _repo.save(a, evidences: evidences, removed: removed);
    await reload();
  }

  Future<void> delete(Activity a) async {
    await _repo.delete(a);
    await reload();
  }
}

final activitiesProvider = AsyncNotifierProvider<ActivitiesNotifier, List<Activity>>(ActivitiesNotifier.new);

class TodosNotifier extends AsyncNotifier<List<Todo>> {
  Repository get _repo => ref.read(repoProvider);

  @override
  Future<List<Todo>> build() => _repo.todos();

  Future<void> reload() async => state = AsyncData(await _repo.todos());

  Future<void> save(Todo t) async {
    await _repo.saveTodo(t);
    await reload();
  }

  Future<void> toggle(Todo t) => save(t.copyWith(done: !t.done));

  Future<void> delete(Todo t) async {
    await _repo.deleteTodo(t);
    await reload();
  }
}

final todosProvider = AsyncNotifierProvider<TodosNotifier, List<Todo>>(TodosNotifier.new);

/// Open tasks due today or overdue (what "Hari ini" shows).
final todayTodosProvider = Provider<List<Todo>>((ref) {
  final now = nowOf(ref);
  final today = dateOnly(now);
  return (ref.watch(todosProvider).value ?? const <Todo>[])
      .where((t) => !t.done && t.due != null && !dateOnly(t.due!).isAfter(today))
      .toList();
});

/// Quick-camera photos not yet attached to a report. Refreshes whenever the
/// activity list reloads (attaching moves photos out of this list).
final looseProvider = FutureProvider<List<Evidence>>((ref) {
  ref.watch(activitiesProvider);
  return ref.read(repoProvider).loose();
});

class GalleryPhoto {
  const GalleryPhoto(this.evidence, this.activity);
  final Evidence evidence;

  /// null for a quick-camera photo not yet attached to a report.
  final Activity? activity;
}

/// Every photo in the app: quick-camera photos plus image evidence from all
/// activities, newest first. PDFs are left out.
final galleryProvider = FutureProvider<List<GalleryPhoto>>((ref) async {
  final acts = ref.watch(activitiesProvider).value ?? const <Activity>[];
  final loose = await ref.watch(looseProvider.future);
  final out = [
    for (final a in acts)
      for (final e in a.evidences)
        if (e.isImage) GalleryPhoto(e, a),
    for (final e in loose) GalleryPhoto(e, null),
  ]..sort((x, y) => y.evidence.capturedAt.compareTo(x.evidence.capturedAt));
  return out;
});

List<Activity> _sorted(Iterable<Activity> xs) =>
    xs.toList()
      ..sort((a, b) => a.start.compareTo(b.start) != 0 ? a.start.compareTo(b.start) : (a.id ?? 0) - (b.id ?? 0));

final monthActivitiesProvider = Provider.family<List<Activity>, DateTime>((ref, month) {
  final all = ref.watch(activitiesProvider).value ?? const [];
  return _sorted(all.where((a) => a.touchesMonth(month)));
});

final dayActivitiesProvider = Provider.family<List<Activity>, DateTime>((ref, day) {
  final all = ref.watch(activitiesProvider).value ?? const [];
  return _sorted(all.where((a) => a.coversDay(day)));
});

/// Day-of-month -> number of activities covering it.
final monthMarksProvider = Provider.family<Map<int, int>, DateTime>((ref, month) {
  final marks = <int, int>{};
  for (final a in ref.watch(monthActivitiesProvider(month))) {
    for (var d = 1; d <= daysInMonth(month); d++) {
      if (a.coversDay(DateTime(month.year, month.month, d))) marks[d] = (marks[d] ?? 0) + 1;
    }
  }
  return marks;
});

class MonthSummary {
  const MonthSummary({
    required this.activities,
    required this.noEvidence,
    required this.workdays,
    required this.filledWorkdays,
    required this.streak,
  });

  final int activities;
  final int noEvidence;

  /// Mon–Fri elapsed so far in the month (whole month if it is in the past).
  final int workdays;
  final int filledWorkdays;

  /// Consecutive workdays with an activity, counting back from today
  /// (today may still be empty without breaking the streak).
  final int streak;

  int get emptyWorkdays => workdays - filledWorkdays;
  double get progress => workdays == 0 ? 0 : filledWorkdays / workdays;
}

bool isWorkday(DateTime d) => d.weekday <= 5;

final monthSummaryProvider = Provider.family<MonthSummary, DateTime>((ref, month) {
  final acts = ref.watch(monthActivitiesProvider(month));
  final marks = ref.watch(monthMarksProvider(month));
  final all = ref.watch(activitiesProvider).value ?? const <Activity>[];
  final today = dateOnly(nowOf(ref));
  final lastDay = sameMonth(month, today) ? today.day : (month.isAfter(today) ? 0 : daysInMonth(month));
  var work = 0, filled = 0;
  for (var d = 1; d <= lastDay; d++) {
    if (!isWorkday(DateTime(month.year, month.month, d))) continue;
    work++;
    if (marks.containsKey(d)) filled++;
  }
  var streak = 0;
  var day = today;
  bool covered(DateTime d) => all.any((a) => a.coversDay(d));
  if (!covered(day)) day = day.subtract(const Duration(days: 1));
  for (var guard = 0; guard < 400; guard++) {
    if (isWorkday(day)) {
      if (!covered(day)) break;
      streak++;
    }
    day = day.subtract(const Duration(days: 1));
  }
  return MonthSummary(
    activities: acts.length,
    noEvidence: acts.where((a) => a.evidences.isEmpty).length,
    workdays: work,
    filledWorkdays: filled,
    streak: streak,
  );
});

/// Completes addresses for photos taken offline: once online, reverse-geocode,
/// re-render the stamp from the untouched frame, refresh public copies.
class AddressSync {
  AddressSync(this.ref);

  final Ref ref;
  bool _running = false;
  StreamSubscription<bool>? _sub;

  void start() {
    _sub = LocationService.onlineChanges().listen((online) {
      if (online) run();
    });
    run();
  }

  void dispose() => _sub?.cancel();

  Future<void> run() async {
    if (_running) return;
    _running = true;
    try {
      final repo = ref.read(repoProvider);
      final pending = await repo.pendingAddress();
      if (pending.isEmpty || !await LocationService.isOnline()) return;
      var changed = false;
      for (final e in pending) {
        final addr = await LocationService.address(e.lat!, e.lng!);
        if (addr == null) continue;
        final out = await renderStamped(
          mirror: e.mirrored,
          rawPath: e.rawPath!,
          outPath: e.masterPath,
          data: StampData(
            name: e.author ?? ref.read(settingsProvider).profile.name,
            time: e.capturedAt,
            lat: e.lat,
            lng: e.lng,
            accuracy: e.accuracy,
            address: addr,
          ),
        );
        var updated = e.copyWith(address: addr, masterPath: out, clearRaw: true);
        // Overwrite each public mirror in place.
        for (final pub in e.publicPaths) {
          try {
            await File(out).copy(pub);
          } catch (_) {}
        }
        await repo.updateEvidence(updated);
        try {
          await File(e.rawPath!).delete();
        } catch (_) {}
        changed = true;
      }
      if (changed) await ref.read(activitiesProvider.notifier).reload();
    } finally {
      _running = false;
    }
  }
}

final addressSyncProvider = Provider<AddressSync>((ref) {
  final s = AddressSync(ref)..start();
  ref.onDispose(s.dispose);
  return s;
});

// ---------------------------------------------------------------------------
// Google account, Drive sync, chat identity

class GoogleUser {
  const GoogleUser({required this.email, this.name, this.photo});
  final String email;
  final String? name;
  final String? photo;
}

class GoogleUserNotifier extends Notifier<GoogleUser?> {
  @override
  GoogleUser? build() {
    _restore();
    return null;
  }

  GoogleUser? _from(dynamic acc) =>
      acc == null ? null : GoogleUser(email: acc.email, name: acc.displayName, photo: acc.photoUrl);

  Future<void> _restore() async {
    final acc = await GoogleAccount.restore();
    if (acc == null) return;
    state = _from(acc);
  }

  Future<void> connect() async {
    final acc = await GoogleAccount.connect();
    state = _from(acc);
  }

  Future<void> disconnect() async {
    await GoogleAccount.disconnect();
    state = null;
  }
}

final googleUserProvider = NotifierProvider<GoogleUserNotifier, GoogleUser?>(GoogleUserNotifier.new);

/// "activityId|yyyy-mm" -> Drive folder link of that activity's evidence.
final driveLinksProvider = FutureProvider<Map<String, String>>((ref) async {
  final user = ref.watch(googleUserProvider);
  ref.watch(activitiesProvider);
  ref.watch(driveSyncProvider.select((s) => s.lastDone));
  if (user == null) return const {};
  return ref.read(repoProvider).driveActivityLinks(user.email);
});

class DriveSyncState {
  const DriveSyncState({this.month, this.progress, this.lastDone, this.error});
  final DateTime? month;
  final SyncProgress? progress;
  final DateTime? lastDone;
  final String? error;
  bool get busy => month != null;
}

class DriveSyncNotifier extends Notifier<DriveSyncState> {
  @override
  DriveSyncState build() => const DriveSyncState();

  Future<SyncResult?> sync(DateTime month) async {
    if (state.busy) return null;
    final user = ref.read(googleUserProvider);
    if (user == null) throw StateError('Hubungkan akun Google dulu di Profil.');
    state = DriveSyncState(month: month, lastDone: state.lastDone);
    try {
      final result =
          await DriveSync(
            ref.read(repoProvider),
            account: user.email,
            ownerName: ref.read(settingsProvider).profile.name,
          ).syncMonth(
            month,
            ref.read(monthActivitiesProvider(month)),
            onProgress: (p) => state = DriveSyncState(month: month, progress: p, lastDone: state.lastDone),
          );
      ref.read(prefsProvider).setString('driveSynced|${monthKey(month)}', DateTime.now().toIso8601String());
      state = DriveSyncState(lastDone: DateTime.now());
      return result;
    } catch (e) {
      state = DriveSyncState(lastDone: state.lastDone, error: '$e');
      rethrow;
    }
  }

  DateTime? lastSynced(DateTime month) {
    final v = ref.read(prefsProvider).getString('driveSynced|${monthKey(month)}');
    return v == null ? null : DateTime.parse(v);
  }
}

final driveSyncProvider = NotifierProvider<DriveSyncNotifier, DriveSyncState>(DriveSyncNotifier.new);

/// Latest available app update (null when up to date or offline). Checked once
/// when home loads; refresh on pull-to-refresh by invalidating.
final updateProvider = FutureProvider<AppUpdate?>((ref) => UpdateService.check());
