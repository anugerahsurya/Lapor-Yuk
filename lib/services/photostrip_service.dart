import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/dates.dart';
import '../core/theme.dart';
import 'chat_service.dart';
import 'storage_service.dart';

class Photostrip {
  const Photostrip({
    required this.id,
    required this.room,
    required this.creator,
    required this.template,
    required this.at,
  });
  final int id;
  final String room, creator;
  final int template;
  final DateTime at;
}

class StripMember {
  const StripMember({required this.userId, required this.slot, this.path});
  final String userId;
  final int slot;

  /// Storage path of this person's shot; null until they take it.
  final String? path;
  bool get done => path != null;
}

/// 4R print (4 x 6 inch) at 300 dpi, portrait.
const stripWidth = 1200;
const stripHeight = 1800;

/// Photostrip bareng: 2-6 people in a DM or group each fill one box with
/// their own camera. Rows live 3 days (see migrations/*_photostrip.sql).
abstract final class PhotostripService {
  static const bucket = 'photostrips';
  static SupabaseClient get _db => Supabase.instance.client;

  /// Creates the strip and posts the invitation message in [room].
  static Future<int> create(String room, int template, List<String> invitees) async =>
      (await _db.rpc('create_photostrip', params: {'r': room, 'tpl': template, 'invitees': invitees}) as num).toInt();

  static Future<Photostrip?> get(int id) async {
    final r = await _db.from('photostrips').select().eq('id', id).maybeSingle();
    if (r == null) return null;
    return Photostrip(
      id: r['id'] as int,
      room: r['room'] as String,
      creator: r['creator'] as String,
      template: (r['template'] as num).toInt(),
      at: DateTime.parse(r['created_at'] as String).toLocal(),
    );
  }

  static Stream<List<StripMember>> members(int id) => _db
      .from('photostrip_members')
      .stream(primaryKey: ['strip_id', 'user_id'])
      .eq('strip_id', id)
      .order('slot', ascending: true)
      .map(
        (rows) => [
          for (final r in rows)
            StripMember(userId: r['user_id'] as String, slot: (r['slot'] as num).toInt(), path: r['path'] as String?),
        ],
      );

  /// Uploads my shot into my box. A retake replaces (and deletes) [old].
  static Future<void> upload(int id, Uint8List jpeg, {String? old}) async {
    final me = ChatService.uid!;
    final path = '$me/${id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _db.storage.from(bucket).uploadBinary(path, jpeg, fileOptions: const FileOptions(contentType: 'image/jpeg'));
    await _db
        .from('photostrip_members')
        .update({'path': path, 'shot_at': DateTime.now().toUtc().toIso8601String()})
        .eq('strip_id', id)
        .eq('user_id', me);
    if (old != null) {
      try {
        await _db.storage.from(bucket).remove([old]);
      } catch (_) {}
    }
  }

  static Future<ui.Image> image(String path) async {
    final bytes = await _db.storage.from(bucket).download(path);
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }

  static Future<void> purge() async {
    if (!ChatService.signedIn) return;
    try {
      final paths = (await _db.rpc('purge_photostrips') as List).cast<String>();
      if (paths.isNotEmpty) await _db.storage.from(bucket).remove(paths);
    } catch (_) {}
  }

  /// Full-size 4R PNG of a finished strip.
  static Future<Uint8List> renderPng(
    int template,
    List<ui.Image> photos, {
    required String title,
    required DateTime date,
  }) async {
    final rec = ui.PictureRecorder();
    paintStrip(
      Canvas(rec),
      const Size(stripWidth + 0.0, stripHeight + 0.0),
      template,
      photos,
      title: title,
      date: date,
    );
    final img = await rec.endRecording().toImage(stripWidth, stripHeight);
    try {
      return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    } finally {
      img.dispose();
    }
  }

  /// Saves into "Lapor Yuk/Photostrip" when folder access is granted,
  /// otherwise into app storage. Returns the file path.
  static Future<String> save(StorageService storage, Uint8List png, int id) async {
    final name = 'Photostrip_${isoDate(DateTime.now())}_$id.png';
    if (await storage.hasPublicAccess()) {
      try {
        final dir = Directory(p.join(storage.publicRoot, 'Photostrip'));
        await dir.create(recursive: true);
        final f = File(p.join(dir.path, name));
        await f.writeAsBytes(png, flush: true);
        await Native.scan([f.path]);
        return f.path;
      } catch (_) {}
    }
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'photostrip'));
    await dir.create(recursive: true);
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes(png, flush: true);
    return f.path;
  }
}

class StripTemplate {
  const StripTemplate(
    this.name,
    this.top,
    this.bottom,
    this.ink, {
    this.radius = 8,
    this.border = 0,
    this.film = false,
    this.polaroid = false,
  });
  final String name;
  final Color top, bottom, ink;
  final double radius, border;
  final bool film, polaroid;
}

const stripTemplates = [
  StripTemplate('Klasik', Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0xFF111A33), radius: 6),
  StripTemplate('Film', Color(0xFF151515), Color(0xFF151515), Color(0xFFF2F2F2), radius: 2, film: true),
  StripTemplate('Pastel', Color(0xFFFFD6E7), Color(0xFFE3D9FF), Color(0xFF7A3E6A), radius: 34, border: 12),
  StripTemplate('Polaroid', Color(0xFFF4EFE6), Color(0xFFEDE5D6), Color(0xFF3A3A3A), radius: 2, polaroid: true),
  StripTemplate('Senja', Color(0xFF2F5FEA), Color(0xFFEC6A2C), Color(0xFFFFFFFF), radius: 26, border: 10),
];

/// Boxes for [n] photos: the grid with the largest 3:4 boxes that fit [area],
/// then widened up to 9:10 to use the paper's width, centered. Extra boxes
/// (3 or 5 people) are drawn as a decoration card.
List<Rect> stripCells(Rect area, int n, double gap) {
  var cols = 1, rows = n;
  var bestW = 0.0;
  for (var c = 1; c <= 3; c++) {
    final r = (n / c).ceil();
    final w = math.min((area.width - (c - 1) * gap) / c, (area.height - (r - 1) * gap) / r * 3 / 4);
    if (w > bestW) {
      bestW = w;
      cols = c;
      rows = r;
    }
  }
  final h = bestW * 4 / 3;
  final w = math.min(h * .9, (area.width - (cols - 1) * gap) / cols);
  final gw = cols * w + (cols - 1) * gap;
  final gh = rows * h + (rows - 1) * gap;
  final x0 = area.left + (area.width - gw) / 2;
  final y0 = area.top + (area.height - gh) / 2;
  return [
    for (var i = 0; i < cols * rows; i++)
      Rect.fromLTWH(x0 + (i % cols) * (w + gap), y0 + (i ~/ cols) * (h + gap), w, h),
  ];
}

/// Draws a strip. Works at any size (unit = width / 1200), so the same code
/// paints the small preview and the 4R file. [photos] may hold nulls for boxes
/// still waiting; [labels] names those boxes in the preview.
void paintStrip(
  Canvas canvas,
  Size size,
  int template,
  List<ui.Image?> photos, {
  required String title,
  required DateTime date,
  List<String> labels = const [],
}) {
  final t = stripTemplates[template.clamp(0, stripTemplates.length - 1)];
  final u = size.width / stripWidth;
  final all = Offset.zero & size;
  canvas.drawRect(
    all,
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(size.width * (t.name == 'Senja' ? 1 : 0), size.height), [
        t.top,
        t.bottom,
      ]),
  );

  final side = (t.film ? 120 : 70) * u;
  if (t.film) {
    final hole = Paint()..color = const Color(0xFFE8E8E8).withValues(alpha: .85);
    for (var y = 40 * u; y < size.height - 40 * u; y += 90 * u) {
      for (final x in [36 * u, size.width - 36 * u - 44 * u]) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 44 * u, 56 * u), Radius.circular(8 * u)), hole);
      }
    }
  }
  if (t.name == 'Pastel') {
    final dot = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: .45);
    for (final (x, y, r) in [(.12, .06, 34.0), (.9, .1, 22.0), (.08, .93, 26.0), (.88, .95, 40.0), (.5, .03, 14.0)]) {
      canvas.drawCircle(Offset(size.width * x, size.height * y), r * u, dot);
    }
  }

  void text(String s, double y, double fs, FontWeight w, {double alpha = 1, double ls = 0}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: kFont,
          fontSize: fs * u,
          fontWeight: w,
          letterSpacing: ls * u,
          color: t.ink.withValues(alpha: alpha),
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: size.width - side * 2);
    tp.paint(canvas, Offset((size.width - tp.width) / 2, y));
  }

  text(title.toUpperCase(), 62 * u, 56, FontWeight.w800, ls: 3);
  text(fmtFullDate(date), size.height - 122 * u, 30, FontWeight.w600, alpha: .85);
  text('Lapor Yuk · Photostrip', size.height - 76 * u, 24, FontWeight.w600, alpha: .6, ls: 1);

  final area = Rect.fromLTRB(side, 170 * u, size.width - side, size.height - 150 * u);
  final cells = stripCells(area, photos.length, 28 * u);
  for (var i = 0; i < cells.length; i++) {
    final cell = cells[i];
    if (i >= photos.length) {
      _extraCard(canvas, cell, t, u);
      continue;
    }
    var box = cell;
    if (t.polaroid) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(cell.shift(Offset(0, 6 * u)), Radius.circular(6 * u)),
        Paint()
          ..color = const Color(0x33000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * u),
      );
      canvas.drawRRect(RRect.fromRectAndRadius(cell, Radius.circular(6 * u)), Paint()..color = const Color(0xFFFFFFFF));
      box = Rect.fromLTRB(cell.left + 16 * u, cell.top + 16 * u, cell.right - 16 * u, cell.bottom - 62 * u);
    } else if (t.border > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(cell, Radius.circular(t.radius * u)),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      box = cell.deflate(t.border * u);
    }
    final r = math.max(0.0, (t.radius - t.border) * u);
    final img = photos[i];
    if (img != null) {
      _cover(canvas, img, box, r);
    } else {
      canvas.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(r)), Paint()..color = t.ink.withValues(alpha: .12));
      final label = i < labels.length ? labels[i] : 'Kotak ${i + 1}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: kFont,
            fontSize: 30 * u,
            fontWeight: FontWeight.w700,
            color: t.ink.withValues(alpha: .7),
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: box.width - 20 * u);
      tp.paint(canvas, box.center - Offset(tp.width / 2, tp.height / 2));
    }
  }
}

void _cover(Canvas canvas, ui.Image img, Rect r, double radius) {
  final iw = img.width.toDouble(), ih = img.height.toDouble();
  final k = math.max(r.width / iw, r.height / ih);
  final sw = r.width / k, sh = r.height / k;
  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));
  canvas.drawImageRect(
    img,
    Rect.fromLTWH((iw - sw) / 2, (ih - sh) / 2, sw, sh),
    r,
    Paint()..filterQuality = FilterQuality.high,
  );
  canvas.restore();
}

/// Filler for the empty box when 3 or 5 people join (grid is 2 x n).
void _extraCard(Canvas canvas, Rect cell, StripTemplate t, double u) {
  canvas.drawRRect(
    RRect.fromRectAndRadius(cell, Radius.circular(math.max(t.radius, 6) * u)),
    Paint()..color = t.ink.withValues(alpha: .08),
  );
  final tp = TextPainter(
    text: TextSpan(
      text: 'foto\nbareng',
      style: TextStyle(
        fontFamily: kFont,
        fontSize: 64 * u,
        height: 1.05,
        fontWeight: FontWeight.w800,
        color: t.ink.withValues(alpha: .55),
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: cell.width);
  tp.paint(canvas, cell.center - Offset(tp.width / 2, tp.height / 2));
}
