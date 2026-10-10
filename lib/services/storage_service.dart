import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/dates.dart';

const appFolderName = 'Lapor Yuk';

/// Thin wrapper around the Kotlin side (MainActivity.kt).
abstract final class Native {
  static const _ch = MethodChannel('lapor_sur/native');

  static Future<int> sdkInt() async => await _ch.invokeMethod<int>('sdkInt') ?? 30;
  static Future<String> externalRoot() async => await _ch.invokeMethod<String>('externalRoot') ?? '/storage/emulated/0';
  static Future<bool> hasAllFilesAccess() async => await _ch.invokeMethod<bool>('hasAllFilesAccess') ?? false;
  static Future<void> scan(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _ch.invokeMethod('scanFiles', {'paths': paths});
    } catch (_) {}
  }

  static Future<void> saveJpeg({
    required Uint8List rgba,
    required int width,
    required int height,
    required String path,
    int quality = 90,
    double? lat,
    double? lng,
    DateTime? time,
  }) => _ch.invokeMethod('saveJpeg', {
    'rgba': rgba,
    'width': width,
    'height': height,
    'path': path,
    'quality': quality,
    'lat': lat,
    'lng': lng,
    'timeMillis': time?.millisecondsSinceEpoch,
  });
}

/// Where files live:
///  * app-private  : `docs/evidence/`  (masters, never touched by the user)
///  * public mirror: /storage/emulated/0/Lapor Yuk/2026-10/
class StorageService {
  StorageService._(this._docs, this._root);

  final Directory _docs;
  final String _root;

  static Future<StorageService> create() async {
    final docs = await getApplicationDocumentsDirectory();
    var root = '/storage/emulated/0';
    try {
      root = await Native.externalRoot();
    } catch (_) {}
    return StorageService._(docs, root);
  }

  String get publicRoot => p.join(_root, appFolderName);
  String publicMonthDir(DateTime month) => p.join(publicRoot, monthKey(month));

  Directory get evidenceDir => Directory(p.join(_docs.path, 'evidence'))..createSync(recursive: true);
  Directory get stagingDir => Directory(p.join(_docs.path, 'staging'))..createSync(recursive: true);
  Directory get reportsDir => Directory(p.join(_docs.path, 'rekap'))..createSync(recursive: true);

  String newStagingPath(String ext) => p.join(stagingDir.path, '${DateTime.now().microsecondsSinceEpoch}.$ext');

  Future<bool> hasPublicAccess() async {
    try {
      final sdk = await Native.sdkInt();
      if (sdk >= 30) return await Native.hasAllFilesAccess();
      return await Permission.storage.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system "All files access" page on Android 11+.
  Future<bool> requestPublicAccess() async {
    final sdk = await Native.sdkInt();
    final status = sdk >= 30 ? await Permission.manageExternalStorage.request() : await Permission.storage.request();
    return status.isGranted;
  }

  /// Copies [master] into each month folder; removes copies in folders that
  /// are no longer part of the activity. Returns the resulting list.
  Future<List<String>> mirror({
    required String master,
    required String fileName,
    required List<DateTime> months,
    required List<String> current,
  }) async {
    if (!await hasPublicAccess()) return current;
    final wanted = {for (final m in months) p.join(publicMonthDir(m), fileName)};
    final result = <String>[];
    final scanned = <String>[];
    for (final old in current) {
      if (!wanted.contains(old)) {
        await _tryDelete(old);
        scanned.add(old);
      }
    }
    for (final target in wanted) {
      try {
        await Directory(p.dirname(target)).create(recursive: true);
        await File(master).copy(target);
        result.add(target);
        scanned.add(target);
      } catch (_) {}
    }
    await Native.scan(scanned);
    return result;
  }

  Future<void> deleteAll(Iterable<String?> paths) async {
    final gone = <String>[];
    for (final path in paths) {
      if (path == null) continue;
      await _tryDelete(path);
      gone.add(path);
    }
    await Native.scan(gone.where((e) => e.startsWith(publicRoot)).toList());
  }

  /// Writes a rekap PDF into the month folder (if allowed) and app storage.
  Future<String> saveReport(DateTime month, Uint8List bytes) async {
    final name = 'Rekap_CKP_${monthKey(month)}.pdf';
    final private = File(p.join(reportsDir.path, name));
    await private.writeAsBytes(bytes, flush: true);
    if (await hasPublicAccess()) {
      try {
        final dir = Directory(publicMonthDir(month));
        await dir.create(recursive: true);
        final pub = File(p.join(dir.path, name));
        await pub.writeAsBytes(bytes, flush: true);
        await Native.scan([pub.path]);
        return pub.path;
      } catch (_) {}
    }
    return private.path;
  }

  Future<void> _tryDelete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

String slugify(String s, {int max = 40}) {
  final cleaned = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  final out = cleaned.length > max ? cleaned.substring(0, max).replaceAll(RegExp(r'_+$'), '') : cleaned;
  return out.isEmpty ? 'kegiatan' : out;
}
