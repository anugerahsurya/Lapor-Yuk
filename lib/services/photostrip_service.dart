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
  const StripTemplate(this.name, this.sheet, this.paper, this.ink, this.accent);
  final String name;

  /// [sheet] = the 4R paper around the strips, [paper] = the strip itself.
  final Color sheet, paper, ink, accent;
}

// Disusun dari referensi photobooth: tiket bioskop, koran, negatif film,
// pastel bunga, dan tiket "special day".
const stripTemplates = [
  StripTemplate('Bioskop', Color(0xFF6E1A1A), Color(0xFFF6EBDD), Color(0xFF6E1A1A), Color(0xFFB8893A)),
  StripTemplate('Koran', Color(0xFFD9D7D0), Color(0xFFF3F1EA), Color(0xFF1C1C1C), Color(0xFF8A8A84)),
  StripTemplate('Film', Color(0xFFF2F2F0), Color(0xFF151515), Color(0xFFEDEDED), Color(0xFFF2A33A)),
  StripTemplate('Pastel', Color(0xFFFFF7FA), Color(0xFFFFF1F5), Color(0xFFD16B93), Color(0xFF8DB27A)),
  StripTemplate('Tiket', Color(0xFFEFE7E1), Color(0xFFFFFFFF), Color(0xFF7A1F2B), Color(0xFF7A1F2B)),
];

/// Draws a strip sheet. Works at any size (unit = width / 1200), so the same
/// code paints the small preview and the 4R file. Up to 4 people: two identical
/// strips side by side with a cut line, like a photobooth print. 5-6 people:
/// one panel with a 2-column grid. [photos] may hold nulls for boxes still
/// waiting; [labels] names those boxes in the preview.
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
  canvas.drawRect(Offset.zero & size, Paint()..color = t.sheet);
  final m = 40 * u;
  if (photos.length <= 4) {
    final w = (size.width - m * 3) / 2;
    for (final x in [m, m * 2 + w]) {
      _panel(canvas, Rect.fromLTWH(x, m, w, size.height - m * 2), template, t, u, photos, labels, title, date, true);
    }
    final cut = Paint()
      ..color = t.ink.withValues(alpha: .25)
      ..strokeWidth = 2 * u;
    for (var y = m; y < size.height - m; y += 28 * u) {
      canvas.drawLine(Offset(size.width / 2, y), Offset(size.width / 2, y + 14 * u), cut);
    }
  } else {
    _panel(
      canvas,
      Rect.fromLTWH(m, m, size.width - m * 2, size.height - m * 2),
      template,
      t,
      u,
      photos,
      labels,
      title,
      date,
      false,
    );
  }
}

void _panel(
  Canvas c,
  Rect r,
  int template,
  StripTemplate t,
  double u,
  List<ui.Image?> photos,
  List<String> labels,
  String title,
  DateTime date,
  bool strip,
) {
  final k = strip ? 1.0 : 1.4; // font scale for the wide panel
  final head = (strip ? 250 : 270) * u;
  final foot = (strip ? 190 : 200) * u;
  final pad = (template == 2 ? 74 : 40) * u;
  final ink = t.ink;

  // Paper + per-template edges.
  final radius = switch (template) {
    0 || 4 => 18 * u,
    3 => 26 * u,
    _ => 0.0,
  };
  c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)), Paint()..color = t.paper);
  switch (template) {
    case 0: // perforated ticket edges + double rule
      final hole = Paint()..color = t.sheet;
      for (var y = r.top + 30 * u; y < r.bottom - 20 * u; y += 36 * u) {
        c.drawCircle(Offset(r.left, y), 10 * u, hole);
        c.drawCircle(Offset(r.right, y), 10 * u, hole);
      }
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..color = ink
        ..strokeWidth = 3 * u;
      c.drawRect(r.deflate(22 * u), line);
      c.drawRect(r.deflate(30 * u), line..strokeWidth = 1.2 * u);
    case 1: // newsprint rules
      final rule = Paint()
        ..color = ink
        ..strokeWidth = 2 * u;
      for (final y in [r.top + 70 * u, r.top + 76 * u, r.bottom - 80 * u]) {
        c.drawLine(Offset(r.left + 28 * u, y), Offset(r.right - 28 * u, y), rule);
      }
    case 2: // film sprocket holes
      final hole = Paint()..color = t.sheet;
      for (var y = r.top + 24 * u; y < r.bottom - 40 * u; y += 70 * u) {
        for (final x in [r.left + 18 * u, r.right - 18 * u - 34 * u]) {
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 34 * u, 44 * u), Radius.circular(6 * u)), hole);
        }
      }
    case 3: // pastel stripes + polka bands
      c.save();
      c.clipRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));
      final stripe = Paint()..color = const Color(0xFFF8D3E1);
      for (var x = r.left; x < r.right; x += 52 * u) {
        c.drawRect(Rect.fromLTWH(x, r.top, 26 * u, r.height), stripe);
      }
      final band = Paint()..color = const Color(0xFFC9DDB4);
      final dot = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: .8);
      for (final y in [r.top, r.bottom - 34 * u]) {
        c.drawRect(Rect.fromLTWH(r.left, y, r.width, 34 * u), band);
        for (var x = r.left + 14 * u; x < r.right; x += 30 * u) {
          c.drawCircle(Offset(x, y + 17 * u), 5 * u, dot);
        }
      }
      c.restore();
    case 4: // ticket border, notches and dashed tear lines
      c.drawRRect(
        RRect.fromRectAndRadius(r.deflate(8 * u), Radius.circular(radius)),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = ink
          ..strokeWidth = 5 * u,
      );
      final notch = Paint()..color = t.sheet;
      final dash = Paint()
        ..color = ink.withValues(alpha: .6)
        ..strokeWidth = 2.5 * u;
      for (final y in [r.top + head - 18 * u, r.bottom - foot + 18 * u]) {
        c.drawCircle(Offset(r.left, y), 20 * u, notch);
        c.drawCircle(Offset(r.right, y), 20 * u, notch);
        for (var x = r.left + 34 * u; x < r.right - 34 * u; x += 22 * u) {
          c.drawLine(Offset(x, y), Offset(x + 11 * u, y), dash);
        }
      }
  }

  // Header and footer text.
  final day = '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  final name = title.toUpperCase();
  switch (template) {
    case 0:
      _txt(c, 'PERTUNJUKAN', r, r.top + 52 * u, 18 * k * u, ink, FontWeight.w700, ls: 5 * u);
      _txt(c, name, r, r.top + 82 * u, 46 * k * u, ink, FontWeight.w800, pad: 50 * u);
      _txt(
        c,
        'BARIS A   ·   KURSI 0${photos.length}   ·   $day',
        r,
        r.top + 160 * u,
        17 * k * u,
        ink,
        FontWeight.w700,
        ls: 1.5 * u,
      );
      _txt(c, 'Lapor Yuk.', r, r.bottom - foot + 52 * u, 52 * k * u, ink, FontWeight.w800, ls: -1 * u);
      _txt(
        c,
        'SIMPAN MOMEN TERBAIK',
        r,
        r.bottom - foot + (52 + 60 * k) * u,
        16 * k * u,
        ink,
        FontWeight.w700,
        ls: 4 * u,
      );
    case 1:
      _txt(c, 'EDISI $day   ·   LAPOR YUK DAILY', r, r.top + 40 * u, 15 * k * u, ink, FontWeight.w700, ls: 1 * u);
      _txt(c, 'BREAKING NEWS', r, r.top + 98 * u, 26 * k * u, ink, FontWeight.w700, ls: 4 * u);
      _txt(c, name, r, r.top + 138 * u, 54 * k * u, ink, FontWeight.w800, ls: -1 * u, pad: 36 * u);
      _txt(
        c,
        'Foto bareng ${photos.length} orang, semua tersenyum',
        r,
        r.bottom - foot + 130 * u,
        17 * k * u,
        ink,
        FontWeight.w600,
      );
    case 2:
      _txt(c, 'LAPOR YUK 400', r, r.top + 70 * u, 22 * k * u, t.accent, FontWeight.w800, ls: 6 * u);
      _txt(c, name, r, r.top + 118 * u, 44 * k * u, ink, FontWeight.w800, pad: pad);
      _txt(c, '▸ $day', r, r.bottom - foot + 70 * u, 22 * k * u, t.accent, FontWeight.w700, ls: 3 * u);
    case 3:
      _txt(c, 'Photobooth', r, r.top + 62 * u, 56 * k * u, ink, FontWeight.w800, ls: -1 * u);
      _txt(c, name, r, r.top + 150 * u, 22 * k * u, t.accent, FontWeight.w800, ls: 4 * u, pad: 40 * u);
      _txt(c, day, r, r.bottom - foot + 78 * u, 20 * k * u, ink, FontWeight.w700, ls: 3 * u);
    case 4:
      _barcode(
        c,
        Rect.fromCenter(center: Offset(r.center.dx, r.top + 70 * u), width: r.width * .62, height: 64 * u),
        ink,
        title.hashCode,
      );
      _txt(c, 'PHOTOBOOTH  ·  $day', r, r.top + 150 * u, 16 * k * u, ink, FontWeight.w700, ls: 3 * u);
      _txt(c, 'Special Day', r, r.bottom - foot + 44 * u, 50 * k * u, ink, FontWeight.w800, ls: -1 * u);
      _barcode(
        c,
        Rect.fromCenter(center: Offset(r.center.dx, r.bottom - 54 * u), width: r.width * .5, height: 40 * u),
        ink,
        title.hashCode ~/ 7,
      );
  }

  // Photo boxes.
  final content = Rect.fromLTRB(r.left + pad, r.top + head, r.right - pad, r.bottom - foot);
  final cols = strip ? 1 : 2;
  final rows = (photos.length / cols).ceil();
  final gap = 22 * u;
  final cw = (content.width - (cols - 1) * gap) / cols;
  final ch = math.min((content.height - (rows - 1) * gap) / rows, cw * 4 / 3);
  final y0 = content.top + (content.height - (rows * ch + (rows - 1) * gap)) / 2;
  for (var i = 0; i < cols * rows; i++) {
    final cell = Rect.fromLTWH(content.left + (i % cols) * (cw + gap), y0 + (i ~/ cols) * (ch + gap), cw, ch);
    if (i >= photos.length) {
      _extraCard(c, cell, t, u);
      continue;
    }
    final img = photos[i];
    final (frame, inset, rad) = switch (template) {
      0 => (ink, 5 * u, 2 * u),
      1 => (ink, 3 * u, 0.0),
      2 => (const Color(0xFF3A3A3A), 2 * u, 2 * u),
      3 => (const Color(0xFFFFFFFF), 10 * u, 22 * u),
      _ => (ink, 6 * u, 10 * u),
    };
    c.drawRRect(RRect.fromRectAndRadius(cell, Radius.circular(rad + inset)), Paint()..color = frame);
    final box = cell.deflate(inset);
    if (img != null) {
      _cover(c, img, box, rad, gray: template == 1);
      if (template == 2) {
        final stamp = "'${(date.year % 100).toString().padLeft(2, '0')} ${date.month} ${date.day}";
        // Shadow first so the orange print stays readable on bright photos.
        final at = Offset(box.right - 12 * u, box.bottom - 8 * u);
        final shade = _painter(stamp, 20 * k * u, const Color(0x99000000), FontWeight.w800, ls: 2 * u);
        shade.paint(c, at - Offset(shade.width - 2 * u, shade.height - 2 * u));
        final tp = _painter(stamp, 20 * k * u, t.accent, FontWeight.w800, ls: 2 * u);
        tp.paint(c, at - Offset(tp.width, tp.height));
      }
    } else {
      c.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(rad)), Paint()..color = ink.withValues(alpha: .14));
      final tp = _painter(
        i < labels.length ? labels[i] : 'Kotak ${i + 1}',
        26 * k * u,
        ink.withValues(alpha: .75),
        FontWeight.w700,
        maxW: box.width - 16 * u,
      );
      tp.paint(c, box.center - Offset(tp.width / 2, tp.height / 2));
    }
    if (template == 3 && i.isEven) _flower(c, cell.topLeft + Offset(6 * u, 6 * u), 16 * u);
    if (template == 3 && i.isOdd) _flower(c, cell.bottomRight - Offset(6 * u, 6 * u), 14 * u);
  }
}

TextPainter _painter(String s, double fs, Color color, FontWeight w, {double ls = 0, double? maxW}) => TextPainter(
  text: TextSpan(
    text: s,
    style: TextStyle(fontFamily: kFont, fontSize: fs, fontWeight: w, letterSpacing: ls, color: color, height: 1.1),
  ),
  textDirection: TextDirection.ltr,
  textAlign: TextAlign.center,
  maxLines: 2,
  ellipsis: '…',
)..layout(maxWidth: maxW ?? double.infinity);

/// Centered one-line text inside [r] at [y].
void _txt(
  Canvas c,
  String s,
  Rect r,
  double y,
  double fs,
  Color color,
  FontWeight w, {
  double ls = 0,
  double pad = 30,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(fontFamily: kFont, fontSize: fs, fontWeight: w, letterSpacing: ls, color: color, height: 1.1),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: r.width - pad * 2);
  tp.paint(c, Offset(r.center.dx - tp.width / 2, y));
}

/// Decorative barcode; bar widths come from [seed] so each title looks different.
void _barcode(Canvas c, Rect r, Color color, int seed) {
  final rng = math.Random(seed);
  final p = Paint()..color = color;
  var x = r.left;
  while (x < r.right) {
    final w = r.width * (rng.nextInt(3) + 1) / 110;
    if (x + w > r.right) break;
    c.drawRect(Rect.fromLTWH(x, r.top, w, r.height), p);
    x += w + r.width * (rng.nextInt(2) + 1) / 110;
  }
}

void _flower(Canvas c, Offset o, double r) {
  final petal = Paint()..color = const Color(0xFFF2A7C3);
  for (var i = 0; i < 5; i++) {
    final a = i * math.pi * 2 / 5 - math.pi / 2;
    c.drawCircle(o + Offset(math.cos(a), math.sin(a)) * r * .6, r * .5, petal);
  }
  c.drawCircle(o, r * .35, Paint()..color = const Color(0xFFF7D46B));
}

/// Center-crop [img] into [r], biased up a little so faces stay in frame.
void _cover(Canvas canvas, ui.Image img, Rect r, double radius, {bool gray = false}) {
  final iw = img.width.toDouble(), ih = img.height.toDouble();
  final k = math.max(r.width / iw, r.height / ih);
  final sw = r.width / k, sh = r.height / k;
  final paint = Paint()..filterQuality = FilterQuality.high;
  if (gray) {
    paint.colorFilter = const ColorFilter.matrix([
      0.33, 0.59, 0.11, 0, -8, //
      0.33, 0.59, 0.11, 0, -8,
      0.33, 0.59, 0.11, 0, -8,
      0, 0, 0, 1, 0,
    ]);
  }
  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));
  canvas.drawImageRect(img, Rect.fromLTWH((iw - sw) / 2, (ih - sh) * .4, sw, sh), r, paint);
  canvas.restore();
}

/// Filler for the empty box when 5 people join (2-column grid).
void _extraCard(Canvas canvas, Rect cell, StripTemplate t, double u) {
  canvas.drawRect(cell, Paint()..color = t.ink.withValues(alpha: .08));
  final tp = _painter('foto\nbareng', 64 * u, t.ink.withValues(alpha: .55), FontWeight.w800, maxW: cell.width);
  tp.paint(canvas, cell.center - Offset(tp.width / 2, tp.height / 2));
}
