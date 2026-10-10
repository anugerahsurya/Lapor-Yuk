import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../core/dates.dart';
import '../core/theme.dart';
import 'location_service.dart';
import 'storage_service.dart';

class StampData {
  const StampData({required this.name, required this.time, this.lat, this.lng, this.accuracy, this.address});

  final String name;
  final DateTime time;
  final double? lat;
  final double? lng;
  final double? accuracy;
  final String? address;
}

const _accent = Color(0xFFF2B35A);

/// Paints the timestamp card. Used both for the live camera overlay and for
/// burning into the final JPEG, so preview == result.
void paintStamp(Canvas canvas, Size size, StampData d) {
  final u = math.min(size.width, size.height) / 360;
  final margin = 12 * u;
  final pad = 12 * u;
  final maxW = size.width - margin * 2 - pad * 2 - 4 * u;

  TextPainter tp(
    String text,
    double fs,
    FontWeight w, {
    Color color = const Color(0xFFFFFFFF),
    int? lines,
    double ls = 0,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontFamily: kFont, fontSize: fs, fontWeight: w, color: color, height: 1.25, letterSpacing: ls),
      ),
      textDirection: TextDirection.ltr,
      maxLines: lines,
      ellipsis: lines == null ? null : '…',
    )..layout(maxWidth: maxW);
  }

  final soft = const Color(0xFFFFFFFF).withValues(alpha: .78);
  final time = tp(fmtTime(d.time), 30 * u, FontWeight.w800, ls: -0.5 * u);
  final dayP = tp(fmtDay(d.time), 9.5 * u, FontWeight.w700, color: _accent);
  final dateP = tp(fmtDate(d.time), 9.5 * u, FontWeight.w600);
  final nameP = tp(d.name, 11 * u, FontWeight.w700, lines: 1);
  final addrP = tp(
    d.address ?? (d.lat == null ? 'Lokasi tidak tersedia' : 'Alamat dilengkapi otomatis saat online'),
    8.6 * u,
    FontWeight.w500,
    color: d.address == null ? soft.withValues(alpha: .6) : soft,
    lines: 2,
  );
  final coordP = d.lat == null
      ? null
      : tp(
          '${fmtCoord(d.lat!, d.lng!)}${d.accuracy != null ? '   ±${d.accuracy!.round()} m' : ''}',
          8 * u,
          FontWeight.w600,
          color: soft,
          lines: 1,
        );

  final gap = 6 * u;
  final headerH = time.height;
  final contentH = headerH + gap + nameP.height + 2 * u + addrP.height + (coordP == null ? 0 : 3 * u + coordP.height);
  final panelH = contentH + pad * 2;
  final panel = RRect.fromRectAndRadius(
    Rect.fromLTWH(margin, size.height - margin - panelH, size.width - margin * 2, panelH),
    Radius.circular(10 * u),
  );

  // Soft scrim behind everything so text survives bright photos.
  final scrim = Rect.fromLTWH(0, panel.top - 40 * u, size.width, size.height - panel.top + 40 * u);
  canvas.drawRect(
    scrim,
    Paint()
      ..shader = ui.Gradient.linear(scrim.topCenter, scrim.bottomCenter, [
        const Color(0x00000000),
        const Color(0x73000000),
      ]),
  );
  canvas.drawRRect(panel, Paint()..color = const Color(0xFF0E1117).withValues(alpha: .62));
  canvas.drawRRect(
    panel,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8 * u
      ..color = const Color(0xFFFFFFFF).withValues(alpha: .14),
  );
  // Accent bar
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(panel.left + pad, panel.top + pad, 3 * u, headerH), Radius.circular(2 * u)),
    Paint()..color = _accent,
  );

  final x = panel.left + pad + 9 * u;
  var y = panel.top + pad;
  time.paint(canvas, Offset(x, y));
  final dx = x + time.width + 10 * u;
  canvas.drawRect(
    Rect.fromLTWH(dx - 5 * u, y + 4 * u, .8 * u, headerH - 8 * u),
    Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: .3),
  );
  final stackH = dayP.height + dateP.height;
  dayP.paint(canvas, Offset(dx + 2 * u, y + (headerH - stackH) / 2));
  dateP.paint(canvas, Offset(dx + 2 * u, y + (headerH - stackH) / 2 + dayP.height));

  // Brand mark, top-right of panel.
  final brand = tp('LAPOR YUK', 6.5 * u, FontWeight.w800, color: soft.withValues(alpha: .7), ls: 1.2 * u);
  brand.paint(canvas, Offset(panel.right - pad - brand.width, panel.top + pad));

  y += headerH + gap;
  nameP.paint(canvas, Offset(panel.left + pad, y));
  y += nameP.height + 2 * u;
  addrP.paint(canvas, Offset(panel.left + pad, y));
  y += addrP.height;
  if (coordP != null) {
    y += 3 * u;
    _pin(canvas, Offset(panel.left + pad + 3.5 * u, y + coordP.height / 2), 3.6 * u);
    coordP.paint(canvas, Offset(panel.left + pad + 10 * u, y));
  }
}

void _pin(Canvas c, Offset center, double r) {
  final path = Path()
    ..moveTo(center.dx, center.dy + r * 1.5)
    ..cubicTo(
      center.dx - r * 1.6,
      center.dy - r * .1,
      center.dx - r,
      center.dy - r * 1.4,
      center.dx,
      center.dy - r * 1.4,
    )
    ..cubicTo(
      center.dx + r,
      center.dy - r * 1.4,
      center.dx + r * 1.6,
      center.dy - r * .1,
      center.dx,
      center.dy + r * 1.5,
    )
    ..close();
  c.drawPath(path, Paint()..color = _accent);
  c.drawCircle(Offset(center.dx, center.dy - r * .45), r * .42, Paint()..color = const Color(0xFF0E1117));
}

/// Decodes [rawPath], center-crops it to a 3:4 portrait frame, draws the
/// stamp and encodes to JPEG at [outPath]. Decoding is size-capped so 50 MP
/// sensors don't exhaust memory.
Future<String> renderStamped({
  required String rawPath,
  required String outPath,
  required StampData data,
  int maxSide = 2400,
  bool mirror = false,
}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(await File(rawPath).readAsBytes());
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (iw, ih) {
      final k = math.min(1.0, (maxSide * 1.34) / math.max(iw, ih));
      return ui.TargetImageSize(width: (iw * k).round());
    },
  );
  final frame = await codec.getNextFrame();
  final src = frame.image;

  // 3:4 portrait crop (keeps the full width of a 4:3 sensor frame).
  var cw = src.width.toDouble(), ch = src.height.toDouble();
  // Portrait -> 3:4; a landscape frame (phone held sideways) -> 4:3.
  final target = cw > ch ? 4 / 3 : 3 / 4;
  if (cw / ch > target) {
    cw = ch * target;
  } else {
    ch = cw / target;
  }
  final crop = Rect.fromLTWH((src.width - cw) / 2, (src.height - ch) / 2, cw, ch);
  final scale = math.min(1.0, maxSide / math.max(cw, ch));
  final w = (cw * scale).round();
  final h = (ch * scale).round();

  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  if (mirror) {
    // Front camera: match the selfie-style preview. Only the photo is flipped;
    // the stamp below is drawn normally.
    canvas.save();
    canvas.translate(w.toDouble(), 0);
    canvas.scale(-1, 1);
  }
  canvas.drawImageRect(
    src,
    crop,
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  if (mirror) canvas.restore();
  paintStamp(canvas, Size(w.toDouble(), h.toDouble()), data);
  final out = await rec.endRecording().toImage(w, h);
  src.dispose();

  try {
    final rgba = (await out.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
    await Native.saveJpeg(
      rgba: rgba,
      width: w,
      height: h,
      path: outPath,
      quality: 88,
      lat: data.lat,
      lng: data.lng,
      time: data.time,
    );
    return outPath;
  } catch (_) {
    // Fallback if the native encoder is unavailable: lossless PNG.
    final png = (await out.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    final pngPath = outPath.replaceAll(RegExp(r'\.jpe?g$'), '.png');
    await File(pngPath).writeAsBytes(png, flush: true);
    return pngPath;
  } finally {
    out.dispose();
  }
}
