import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;

import '../core/dates.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'google_account.dart';

const _folderMime = 'application/vnd.google-apps.folder';

class SyncProgress {
  const SyncProgress(this.done, this.total, this.label);
  final int done, total;
  final String label;
}

class SyncResult {
  const SyncResult({required this.uploaded, required this.activities, required this.folderLink});
  final int uploaded, activities;
  final String? folderLink;
}

/// Mirrors one month to Google Drive:
///
///   `SKP nama`/                (anyone with the link: commenter)
///     2026-10/
///       09 Okt · Pengawasan Ujian/   ← link copied as "Bukti Dukung"
///         FOTO_….jpg, DOK_….pdf
///       Rekap_CKP_2026-10.pdf
///
/// Ids are remembered in drive_map so re-syncing only uploads what's new.
class DriveSync {
  DriveSync(this.repo, {required this.account, required this.ownerName});

  final Repository repo;
  final String account; // e-mail; namespaces the id map
  final String ownerName;
  late drive.DriveApi _api;

  String _k(String rest) => '$account|$rest';

  Future<SyncResult> syncMonth(
    DateTime month,
    List<Activity> activities, {
    void Function(SyncProgress)? onProgress,
  }) async {
    _api = drive.DriveApi(await GoogleAccount.client());
    final mk = monthKey(month);
    final files = [for (final a in activities) ...a.evidences];
    final reportFile = File(p.join(repo.storage.reportsDir.path, 'Rekap_CKP_$mk.pdf'));
    final total = files.length + activities.length + (reportFile.existsSync() ? 1 : 0) + 2;
    var done = 0;
    var uploaded = 0;
    void tick(String label) => onProgress?.call(SyncProgress(++done, total, label));

    final root = await _rootFolder();
    tick('Folder SKP $ownerName');
    final monthFolder = await _folder('month|$mk', mk, root.id);
    tick('Folder $mk');

    for (final a in activities) {
      final actFolder = await _folder('act|${a.id}|$mk', _activityFolderName(a), monthFolder.id, rename: true);
      tick(a.title);
      for (final e in a.evidences) {
        if (await _uploadOnce('ev|${e.id}|$mk', File(e.masterPath), publicFileName(e, a), actFolder.id)) uploaded++;
        tick(e.name);
      }
    }
    if (reportFile.existsSync()) {
      await _upsertFile('rekap|$mk', reportFile, p.basename(reportFile.path), monthFolder.id);
      uploaded++;
      tick('Rekap PDF');
    }
    return SyncResult(uploaded: uploaded, activities: activities.length, folderLink: monthFolder.link);
  }

  /// Root "SKP nama", shared as commenter with anyone who has the link.
  Future<({String id, String? link})> _rootFolder() async {
    final f = await _folder('root', 'SKP $ownerName', null, rename: true);
    final shared = await repo.driveGet(_k('root|shared'));
    if (shared == null) {
      await _api.permissions.create(drive.Permission(type: 'anyone', role: 'commenter'), f.id);
      await repo.drivePut(_k('root|shared'), f.id);
    }
    return f;
  }

  String _activityFolderName(Activity a) {
    final when = sameDay(a.start, a.end)
        ? '${two(a.start.day)} ${bulanPendek[a.start.month - 1]}'
        : '${two(a.start.day)} ${bulanPendek[a.start.month - 1]}–${two(a.end.day)} ${bulanPendek[a.end.month - 1]}';
    final title = a.title.length > 80 ? '${a.title.substring(0, 80)}…' : a.title;
    return '$when · $title'.replaceAll(RegExp(r'[\\/]'), '-');
  }

  /// Returns the mapped folder if it still exists (optionally renaming it),
  /// otherwise creates it.
  Future<({String id, String? link})> _folder(String key, String name, String? parent, {bool rename = false}) async {
    final known = await repo.driveGet(_k(key));
    if (known != null) {
      try {
        final f = await _api.files.get(known.id, $fields: 'id,name,trashed,webViewLink') as drive.File;
        if (f.trashed != true) {
          if (rename && f.name != name) await _api.files.update(drive.File(name: name), known.id);
          return (id: known.id, link: f.webViewLink ?? known.link);
        }
      } on drive.DetailedApiRequestError catch (e) {
        if (e.status != 404) rethrow;
      }
    }
    final created = await _api.files.create(
      drive.File(name: name, mimeType: _folderMime, parents: parent == null ? null : [parent]),
      $fields: 'id,webViewLink',
    );
    await repo.drivePut(_k(key), created.id!, link: created.webViewLink);
    return (id: created.id!, link: created.webViewLink);
  }

  /// Uploads [file] unless it's already there. Returns true if uploaded.
  Future<bool> _uploadOnce(String key, File file, String name, String parent) async {
    if (!file.existsSync()) return false;
    final known = await repo.driveGet(_k(key));
    if (known != null) {
      try {
        final f = await _api.files.get(known.id, $fields: 'id,trashed,parents') as drive.File;
        if (f.trashed != true) {
          // Activity moved/renamed: keep the file in the right folder.
          if (!(f.parents ?? const []).contains(parent)) {
            await _api.files.update(
              drive.File(),
              known.id,
              addParents: parent,
              removeParents: (f.parents ?? const []).join(','),
            );
          }
          return false;
        }
      } on drive.DetailedApiRequestError catch (e) {
        if (e.status != 404) rethrow;
      }
    }
    final created = await _api.files.create(
      drive.File(name: name, parents: [parent]),
      uploadMedia: drive.Media(file.openRead(), file.lengthSync()),
      $fields: 'id,webViewLink',
    );
    await repo.drivePut(_k(key), created.id!, link: created.webViewLink);
    return true;
  }

  /// Uploads or replaces the content of [file] (used for the rekap PDF).
  Future<void> _upsertFile(String key, File file, String name, String parent) async {
    final known = await repo.driveGet(_k(key));
    if (known != null) {
      try {
        await _api.files.update(
          drive.File(name: name),
          known.id,
          uploadMedia: drive.Media(file.openRead(), file.lengthSync()),
        );
        return;
      } on drive.DetailedApiRequestError catch (e) {
        if (e.status != 404) rethrow;
      }
    }
    final created = await _api.files.create(
      drive.File(name: name, parents: [parent]),
      uploadMedia: drive.Media(file.openRead(), file.lengthSync()),
      $fields: 'id,webViewLink',
    );
    await repo.drivePut(_k(key), created.id!, link: created.webViewLink);
  }
}
