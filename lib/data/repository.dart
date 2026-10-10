import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/dates.dart';
import '../services/storage_service.dart';
import 'models.dart';
import 'todo.dart';

const _todoTable = '''
  CREATE TABLE todos(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    due TEXT,
    due_minutes INTEGER,
    important INTEGER NOT NULL DEFAULT 0,
    done INTEGER NOT NULL DEFAULT 0,
    done_at TEXT,
    created_at TEXT NOT NULL
  )''';

/// Local file/activity -> Google Drive id (+ shareable link), per account.
const _driveTable = '''
  CREATE TABLE drive_map(
    key TEXT PRIMARY KEY,
    drive_id TEXT NOT NULL,
    link TEXT,
    synced_at TEXT NOT NULL
  )''';

class Repository {
  Repository._(this._db, this.storage);

  final Database _db;
  final StorageService storage;

  static Future<Repository> open(StorageService storage) async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), 'lapor_sur.db'),
      version: 4,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onUpgrade: (db, from, _) async {
        if (from < 2) await db.execute('ALTER TABLE evidences ADD COLUMN mirrored INTEGER NOT NULL DEFAULT 0');
        if (from < 3) await db.execute(_todoTable);
        if (from < 4) await db.execute(_driveTable);
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE activities(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            achievement TEXT NOT NULL,
            start_date TEXT NOT NULL,
            end_date TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE evidences(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            activity_id INTEGER REFERENCES activities(id) ON DELETE CASCADE,
            kind TEXT NOT NULL,
            name TEXT NOT NULL,
            master_path TEXT NOT NULL,
            raw_path TEXT,
            public_paths TEXT NOT NULL DEFAULT '[]',
            lat REAL, lng REAL, accuracy REAL,
            address TEXT,
            author TEXT,
            mirrored INTEGER NOT NULL DEFAULT 0,
            captured_at TEXT NOT NULL
          )''');
        await db.execute('CREATE INDEX idx_act_dates ON activities(start_date, end_date)');
        await db.execute('CREATE INDEX idx_ev_act ON evidences(activity_id)');
        await db.execute(_todoTable);
        await db.execute(_driveTable);
      },
    );
    return Repository._(db, storage);
  }

  Future<List<Activity>> all() async {
    final evRows = await _db.query('evidences', orderBy: 'id');
    final byAct = <int, List<Evidence>>{};
    for (final r in evRows) {
      final e = Evidence.fromRow(r);
      if (e.activityId != null) byAct.putIfAbsent(e.activityId!, () => []).add(e);
    }
    final rows = await _db.query('activities', orderBy: 'start_date DESC, id DESC');
    return [for (final r in rows) Activity.fromRow(r, byAct[r['id']] ?? const [])];
  }

  /// Insert or update an activity together with its evidence list.
  /// New evidence arrives as staging files; it is moved into app storage and
  /// mirrored into every month folder the activity spans.
  Future<void> save(Activity a, {required List<Evidence> evidences, required List<Evidence> removed}) async {
    final int id;
    if (a.id == null) {
      id = await _db.insert('activities', a.toRow());
    } else {
      id = a.id!;
      await _db.update(
        'activities',
        {...a.toRow(), 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    for (final e in removed) {
      if (e.id != null) await _db.delete('evidences', where: 'id = ?', whereArgs: [e.id]);
      await storage.deleteAll([e.masterPath, e.rawPath, ...e.publicPaths]);
    }

    final months = monthsBetween(a.start, a.end);
    for (final e in evidences) {
      var ev = e;
      if (ev.id == null) {
        final newId = await _db.insert('evidences', ev.copyWith(activityId: id).toRow());
        ev = ev.copyWith(id: newId, activityId: id);
        // Move staging -> evidence dir so staging can be wiped freely.
        ev = ev.copyWith(
          masterPath: await _adopt(ev.masterPath, 'ev_$newId'),
          rawPath: ev.rawPath == null ? null : await _adopt(ev.rawPath!, 'raw_$newId'),
        );
      }
      final public = await storage.mirror(
        master: ev.masterPath,
        fileName: publicFileName(ev, a),
        months: months,
        current: ev.publicPaths,
      );
      // Also attaches photos that were captured on their own (activity_id NULL).
      await _db.update(
        'evidences',
        ev.copyWith(activityId: id, publicPaths: public).toRow(),
        where: 'id = ?',
        whereArgs: [ev.id],
      );
    }
  }

  // ---- Google Drive map ----

  Future<({String id, String? link})?> driveGet(String key) async {
    final r = await _db.query('drive_map', where: 'key = ?', whereArgs: [key]);
    if (r.isEmpty) return null;
    return (id: r.first['drive_id'] as String, link: r.first['link'] as String?);
  }

  Future<void> drivePut(String key, String id, {String? link}) => _db.insert('drive_map', {
    'key': key,
    'drive_id': id,
    'link': link,
    'synced_at': DateTime.now().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> driveDelete(String key) => _db.delete('drive_map', where: 'key = ?', whereArgs: [key]);

  /// Links of every synced activity folder for [account]: "actId|yyyy-mm" -> url.
  Future<Map<String, String>> driveActivityLinks(String account) async {
    final rows = await _db.query('drive_map', where: 'key LIKE ?', whereArgs: ['$account|act|%']);
    return {
      for (final r in rows)
        if (r['link'] != null) (r['key'] as String).substring('$account|act|'.length): r['link'] as String,
    };
  }

  // ---- To Do ----

  Future<List<Todo>> todos() async =>
      (await _db.query('todos', orderBy: 'done, due IS NULL, due, due_minutes, id')).map(Todo.fromRow).toList();

  /// Insert or replace (replace also restores a just-deleted task on undo).
  Future<int> saveTodo(Todo t) => _db.insert('todos', t.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteTodo(Todo t) => _db.delete('todos', where: 'id = ?', whereArgs: [t.id]);

  /// Photos taken with the quick camera, not yet attached to any activity.
  Future<List<Evidence>> loose() async {
    final rows = await _db.query('evidences', where: 'activity_id IS NULL', orderBy: 'captured_at DESC');
    return rows.map(Evidence.fromRow).toList();
  }

  /// Stores a quick-camera photo: app storage + Lapor Yuk/YYYY-MM of the
  /// capture date.
  Future<Evidence> saveLoose(Evidence staged) async {
    final id = await _db.insert('evidences', staged.toRow());
    var ev = staged.copyWith(id: id);
    ev = ev.copyWith(
      masterPath: await _adopt(ev.masterPath, 'ev_$id'),
      rawPath: ev.rawPath == null ? null : await _adopt(ev.rawPath!, 'raw_$id'),
    );
    final public = await storage.mirror(
      master: ev.masterPath,
      fileName: looseFileName(ev),
      months: [DateTime(ev.capturedAt.year, ev.capturedAt.month)],
      current: const [],
    );
    ev = ev.copyWith(publicPaths: public);
    await updateEvidence(ev);
    return ev;
  }

  Future<void> deleteEvidence(Evidence e) async {
    await _db.delete('evidences', where: 'id = ?', whereArgs: [e.id]);
    await storage.deleteAll([e.masterPath, e.rawPath, ...e.publicPaths]);
  }

  Future<void> delete(Activity a) async {
    for (final e in a.evidences) {
      await storage.deleteAll([e.masterPath, e.rawPath, ...e.publicPaths]);
    }
    await _db.delete('activities', where: 'id = ?', whereArgs: [a.id]);
  }

  Future<void> updateEvidence(Evidence e) => _db.update('evidences', e.toRow(), where: 'id = ?', whereArgs: [e.id]);

  Future<List<Evidence>> pendingAddress() async {
    final rows = await _db.query(
      'evidences',
      where: "kind = 'camera' AND address IS NULL AND lat IS NOT NULL AND raw_path IS NOT NULL",
    );
    return rows.map(Evidence.fromRow).toList();
  }

  Future<Activity?> byId(int id) async => (await all()).where((a) => a.id == id).firstOrNull;

  /// Re-copy every master into the public folders (after permission granted).
  Future<int> resyncPublic() async {
    var n = 0;
    for (final a in await all()) {
      for (final e in a.evidences) {
        final public = await storage.mirror(
          master: e.masterPath,
          fileName: publicFileName(e, a),
          months: a.months,
          current: e.publicPaths,
        );
        await updateEvidence(e.copyWith(publicPaths: public));
        n += public.length;
      }
    }
    for (final e in await loose()) {
      final public = await storage.mirror(
        master: e.masterPath,
        fileName: looseFileName(e),
        months: [DateTime(e.capturedAt.year, e.capturedAt.month)],
        current: e.publicPaths,
      );
      await updateEvidence(e.copyWith(publicPaths: public));
      n += public.length;
    }
    return n;
  }

  Future<String> _adopt(String path, String base) async {
    final dest = p.join(storage.evidenceDir.path, '$base${p.extension(path)}');
    final f = File(path);
    try {
      await f.rename(dest);
    } catch (_) {
      await f.copy(dest);
      await f.delete();
    }
    return dest;
  }
}

String _stamp(DateTime t) => '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';

String looseFileName(Evidence e) => 'FOTO_${_stamp(e.capturedAt)}_${e.id}${p.extension(e.masterPath).toLowerCase()}';

String publicFileName(Evidence e, Activity a) {
  final stamp = _stamp(e.capturedAt);
  final ext = p.extension(e.masterPath).toLowerCase();
  final prefix = switch (e.kind) {
    EvidenceKind.camera => 'FOTO',
    EvidenceKind.image => 'GAMBAR',
    EvidenceKind.pdf => 'DOK',
  };
  return '${prefix}_${stamp}_${slugify(a.title, max: 32)}_${e.id}$ext';
}
