// Renders the 30 s promo video (1080x1920, 30 fps) frame by frame with the
// app's own painters, piping raw RGBA into ffmpeg. See build.md.
//
//   FFMPEG=<ffmpeg.exe> OUT=<silent.mp4> flutter test tool/promo/promo_video_test.dart
//   PREVIEW="1.5,5,9" OUT=<dir> ...   -> only those times, as PNG
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lapor_sur/core/theme.dart';
import 'package:lapor_sur/services/photostrip_service.dart';
import 'package:lapor_sur/services/watermark.dart';
import 'package:lapor_sur/ui/widgets/logo.dart';

const W = 1080.0, H = 1920.0;
const fps = 30, seconds = 30;

const blue = Color(0xFF2F5FEA);
const navy = Color(0xFF0E1A4F);
const amber = Color(0xFFF5B83D);
const ink = Color(0xFF111A33);
const muted = Color(0xFF66708A);
const green = Color(0xFF2F9E6E);
const maroon = Color(0xFF6E1A1A);
const creamy = Color(0xFFF6EBDD);

final av = <String, ui.Image>{};

double seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
double out(double x) => Curves.easeOutCubic.transform(x.clamp(0.0, 1.0));
double back(double x) => Curves.easeOutBack.transform(x.clamp(0.0, 1.0));
double inOut(double x) => Curves.easeInOutCubic.transform(x.clamp(0.0, 1.0));
Color a(Color c, double k) => c.withValues(alpha: c.a * k.clamp(0.0, 1.0));

TextPainter tp(
  String s,
  double size,
  Color color, {
  FontWeight w = FontWeight.w800,
  double ls = 0,
  double maxW = 2000,
  String? family,
  double height = 1.12,
  TextAlign align = TextAlign.center,
}) => TextPainter(
  text: TextSpan(
    text: s,
    style: TextStyle(
      fontFamily: family ?? kFont,
      fontSize: size,
      fontWeight: w,
      color: color,
      letterSpacing: ls,
      height: height,
    ),
  ),
  textDirection: TextDirection.ltr,
  textAlign: align,
)..layout(maxWidth: maxW);

/// Text centered on [c].
void text(
  Canvas cv,
  String s,
  Offset c,
  double size,
  Color color, {
  FontWeight w = FontWeight.w800,
  double ls = 0,
  double maxW = 2000,
}) {
  final p = tp(s, size, color, w: w, ls: ls, maxW: maxW);
  p.paint(cv, c - Offset(p.width / 2, p.height / 2));
}

void icon(Canvas cv, IconData i, Offset c, double size, Color color) {
  final p = tp(String.fromCharCode(i.codePoint), size, color, family: 'MaterialIcons', w: FontWeight.w400, height: 1);
  p.paint(cv, c - Offset(p.width / 2, p.height / 2));
}

/// Words slide up out of a mask one after another.
void kinetic(
  Canvas cv,
  String s,
  double cx,
  double y,
  double size,
  double t, {
  double start = 0,
  List<Color> colors = const [ink],
  double stagger = .07,
  FontWeight w = FontWeight.w800,
  double ls = -1.5,
}) {
  final words = s.split(' ');
  final space = tp(' ', size, ink, w: w).width;
  final ps = [for (var i = 0; i < words.length; i++) tp(words[i], size, colors[i % colors.length], w: w, ls: ls)];
  final lines = <List<int>>[[]];
  var lw = 0.0;
  for (var i = 0; i < ps.length; i++) {
    if (lw > 0 && lw + space + ps[i].width > 960) {
      lines.add([]);
      lw = 0;
    }
    lw += (lw > 0 ? space : 0) + ps[i].width;
    lines.last.add(i);
  }
  for (var li = 0; li < lines.length; li++) {
    final ids = lines[li];
    final width = ids.fold(0.0, (s, i) => s + ps[i].width) + space * (ids.length - 1);
    var x = cx - width / 2;
    final ly = y + li * size * 1.12;
    for (final i in ids) {
      final e = out(seg(t, start + i * stagger, start + i * stagger + .5));
      if (e > 0) {
        cv.save();
        cv.clipRect(Rect.fromLTWH(x - 10, ly - size * .2, ps[i].width + 20, size * 1.45));
        cv.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, e));
        ps[i].paint(cv, Offset(x, ly + (1 - e) * size * .9));
        cv.restore();
        cv.restore();
      }
      x += ps[i].width + space;
    }
  }
}

void pill(
  Canvas cv,
  Offset c,
  String s,
  double size,
  Color bg,
  Color fg, {
  IconData? lead,
  double scale = 1,
  double padX = 34,
  double padY = 18,
}) {
  if (scale <= 0) return;
  final p = tp(s, size, fg, w: FontWeight.w800, ls: .5);
  final iw = lead == null ? 0.0 : size * 1.3 + 10;
  final r = Rect.fromCenter(center: c, width: p.width + padX * 2 + iw, height: p.height + padY * 2);
  cv.save();
  cv.translate(c.dx, c.dy);
  cv.scale(scale);
  cv.translate(-c.dx, -c.dy);
  cv.drawRRect(
    RRect.fromRectAndRadius(r.shift(const Offset(0, 8)), Radius.circular(r.height)),
    Paint()
      ..color = const Color(0x22000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
  );
  cv.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.height)), Paint()..color = bg);
  if (lead != null) icon(cv, lead, Offset(r.left + padX + size * .65, c.dy), size * 1.3, fg);
  p.paint(cv, Offset(r.left + padX + iw, c.dy - p.height / 2));
  cv.restore();
}

void card(Canvas cv, Rect r, double radius, Color color, {double shadow = .18}) {
  cv.drawRRect(
    RRect.fromRectAndRadius(r.shift(const Offset(0, 24)), Radius.circular(radius)),
    Paint()
      ..color = Color.fromRGBO(10, 20, 60, shadow)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36),
  );
  cv.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)), Paint()..color = color);
}

/// Gradient backdrop with slow drifting blobs.
void backdrop(Canvas cv, Color top, Color bottom, double t, Color blob, {double blobA = .1}) {
  cv.drawRect(
    const Rect.fromLTWH(0, 0, W, H),
    Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(W * .4, H), [top, bottom]),
  );
  final p = Paint()..color = a(blob, blobA);
  for (var i = 0; i < 5; i++) {
    final x = W * ((i * .37 + .1) % 1) + math.sin(t * .6 + i) * 60;
    final y = H * ((i * .29 + .05) % 1) + math.cos(t * .5 + i * 2) * 80;
    cv.drawCircle(Offset(x, y), 220 + i * 50.0, p);
  }
}

void header(
  Canvas cv,
  double t,
  String kick,
  String title,
  String sub, {
  Color fg = ink,
  Color subColor = muted,
  Color kickBg = blue,
  Color kickFg = Colors.white,
}) {
  pill(cv, const Offset(W / 2, 190), kick, 26, kickBg, kickFg, scale: back(seg(t, 0, .45)));
  kinetic(cv, title, W / 2, 252, 88, t, start: .15, colors: [fg]);
  final e = out(seg(t, .5, 1.0));
  if (e > 0) text(cv, sub, Offset(W / 2, 400 + (1 - e) * 30), 36, a(subColor, e), w: FontWeight.w600, maxW: 900);
}

/// Phone mockup; [draw] paints into the clipped screen.
void phone(Canvas cv, Rect r, void Function(Rect screen) draw) {
  cv.drawRRect(
    RRect.fromRectAndRadius(r.shift(const Offset(0, 40)), const Radius.circular(78)),
    Paint()
      ..color = const Color(0x40101A40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50),
  );
  cv.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(78)), Paint()..color = const Color(0xFF0B1020));
  final s = r.deflate(16);
  cv.save();
  cv.clipRRect(RRect.fromRectAndRadius(s, const Radius.circular(62)));
  draw(s);
  cv.restore();
  cv.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(s.center.dx, s.top + 30), width: 130, height: 36),
      const Radius.circular(18),
    ),
    Paint()..color = const Color(0xFF0B1020),
  );
}

/// A small illustrated "photo" so the mockups have something to show.
void scene(Canvas cv, Rect r, {int variant = 0, double t = 0}) {
  final skies = [
    [const Color(0xFF8EC5FF), const Color(0xFFE6F2FF)],
    [const Color(0xFFFF9A8B), const Color(0xFFFFD3A5)],
    [const Color(0xFFFFC98B), const Color(0xFFFFF1DC)],
  ];
  final hills = [
    [const Color(0xFF7CC576), const Color(0xFF4FA457)],
    [const Color(0xFFB07BC8), const Color(0xFF7D4EA0)],
    [const Color(0xFF9CCB7A), const Color(0xFF6DAA55)],
  ];
  cv.save();
  cv.clipRect(r);
  cv.drawRect(r, Paint()..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, skies[variant]));
  final u = r.width / 100;
  cv.drawCircle(
    Offset(r.left + r.width * .74, r.top + r.height * (variant == 1 ? .42 : .24)),
    u * (variant == 1 ? 13 : 9),
    Paint()..color = const Color(0xFFFFE08A),
  );
  final cloud = Paint()..color = const Color(0xCCFFFFFF);
  for (final (x, y, s) in [(.22, .2, 1.0), (.55, .12, .7)]) {
    final cx = r.left + r.width * x + math.sin(t * .8) * u * 3;
    final cy = r.top + r.height * y;
    for (final (dx, dy, rr) in [(-6.0, 1.0, 5.0), (0.0, -2.0, 7.0), (7.0, 1.0, 5.0)]) {
      cv.drawCircle(Offset(cx + dx * u * s, cy + dy * u * s), rr * u * s, cloud);
    }
  }
  final back = Path()
    ..moveTo(r.left, r.top + r.height * .62)
    ..quadraticBezierTo(r.left + r.width * .3, r.top + r.height * .48, r.left + r.width * .62, r.top + r.height * .6)
    ..quadraticBezierTo(r.left + r.width * .85, r.top + r.height * .68, r.right, r.top + r.height * .56)
    ..lineTo(r.right, r.bottom)
    ..lineTo(r.left, r.bottom)
    ..close();
  cv.drawPath(back, Paint()..color = hills[variant][0]);
  if (variant == 0) {
    // small office building
    final b = Rect.fromLTWH(r.left + r.width * .3, r.top + r.height * .4, r.width * .34, r.height * .3);
    cv.drawRect(b, Paint()..color = const Color(0xFFE9EEF8));
    cv.drawRect(
      Rect.fromLTWH(b.left - u * 2, b.top - u * 3, b.width + u * 4, u * 4),
      Paint()..color = const Color(0xFF2F5FEA),
    );
    final win = Paint()..color = const Color(0xFF9DB7F0);
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 3; j++) {
        cv.drawRect(
          Rect.fromLTWH(b.left + u * 3 + i * b.width / 4.2, b.top + u * 3 + j * b.height / 3.4, u * 4.5, u * 4.5),
          win,
        );
      }
    }
  }
  final front = Path()
    ..moveTo(r.left, r.top + r.height * .78)
    ..quadraticBezierTo(r.left + r.width * .45, r.top + r.height * .64, r.right, r.top + r.height * .8)
    ..lineTo(r.right, r.bottom)
    ..lineTo(r.left, r.bottom)
    ..close();
  cv.drawPath(front, Paint()..color = hills[variant][1]);
  if (variant == 2) {
    final cup = Rect.fromLTWH(r.left + r.width * .38, r.top + r.height * .6, r.width * .24, r.height * .26);
    cv.drawRRect(
      RRect.fromRectAndCorners(cup, bottomLeft: Radius.circular(u * 6), bottomRight: Radius.circular(u * 6)),
      Paint()..color = Colors.white,
    );
    cv.drawCircle(
      Offset(cup.right + u * 2, cup.center.dy),
      u * 5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 2
        ..color = Colors.white,
    );
    cv.drawRect(Rect.fromLTWH(cup.left, cup.top, cup.width, u * 3), Paint()..color = const Color(0xFF8A5A3C));
  }
  cv.restore();
}

Path star(Offset c, double r) {
  final p = Path();
  for (var i = 0; i < 8; i++) {
    final ang = i * math.pi / 4 - math.pi / 2;
    final rr = i.isEven ? r : r * .32;
    final pt = c + Offset(math.cos(ang), math.sin(ang)) * rr;
    i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
  }
  return p..close();
}

void sparkles(Canvas cv, Offset c, double t, {int n = 12, double reach = 380, Color color = amber}) {
  if (t <= 0 || t >= 1) return;
  for (var i = 0; i < n; i++) {
    final ang = i * math.pi * 2 / n + (i.isEven ? .2 : 0);
    final d = out(t) * reach * (i.isEven ? 1 : .7);
    cv.drawPath(star(c + Offset(math.cos(ang), math.sin(ang)) * d, 22 * (1 - t) + 4), Paint()..color = a(color, 1 - t));
  }
}

void confetti(Canvas cv, Offset c, double t) {
  if (t <= 0 || t >= 1) return;
  final rng = math.Random(7);
  const colors = [amber, blue, Color(0xFFFF6FA3), green, Color(0xFFEC6A2C)];
  for (var i = 0; i < 34; i++) {
    final ang = -math.pi / 2 + (rng.nextDouble() - .5) * 2.4;
    final v = 500 + rng.nextDouble() * 650;
    final p = c + Offset(math.cos(ang) * v * t, math.sin(ang) * v * t + 900 * t * t);
    cv.save();
    cv.translate(p.dx, p.dy);
    cv.rotate(t * 8 + i);
    cv.drawRect(const Rect.fromLTWH(-9, -5, 18, 10), Paint()..color = a(colors[i % colors.length], 1 - t * t));
    cv.restore();
  }
}

void avatarCircle(Canvas cv, String name, Offset c, double r) {
  final img = av[name]!;
  cv.save();
  cv.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
  cv.drawImageRect(
    img,
    Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    Rect.fromCircle(center: c, radius: r),
    Paint()..filterQuality = FilterQuality.high,
  );
  cv.restore();
}

/// Pops [draw] in around [anchor] (scale + fade) from [start].
void popIn(Canvas cv, double t, double start, Offset anchor, void Function() draw, {double dur = .45}) {
  final e = seg(t, start, start + dur);
  if (e <= 0) return;
  final s = back(e);
  cv.save();
  cv.translate(anchor.dx, anchor.dy);
  cv.scale(.4 + .6 * s);
  cv.translate(-anchor.dx, -anchor.dy);
  cv.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, out(e * 1.6)));
  draw();
  cv.restore();
  cv.restore();
}

// ---------------------------------------------------------------- scenes

void sceneIntro(Canvas cv, double t, {bool outro = false}) {
  cv.drawRect(
    const Rect.fromLTWH(0, 0, W, H),
    Paint()..shader = ui.Gradient.radial(const Offset(W / 2, H * .42), 1400, [const Color(0xFF3D6EF7), navy]),
  );
  final dot = Paint();
  for (var i = 0; i < 40; i++) {
    final x = (i * 137.5) % W;
    final y = (H - ((i * 211.0 + t * (30 + i % 5 * 12)) % H));
    dot.color = Color.fromRGBO(255, 255, 255, .08 + (i % 4) * .05);
    cv.drawCircle(Offset(x, y), 2.0 + i % 3 * 2, dot);
  }
  final center = Offset(W / 2, outro ? 640 : 800);
  final size = outro ? 260.0 : 380.0;
  final k0 = outro ? 0.0 : .0;
  // light rays
  final rayE = out(seg(t, k0 + .8, k0 + 1.6));
  if (rayE > 0) {
    cv.save();
    cv.translate(center.dx, center.dy);
    cv.rotate(t * .25);
    final ray = Paint()..color = Color.fromRGBO(245, 184, 61, .07 * rayE);
    for (var i = 0; i < 12; i++) {
      cv.rotate(math.pi / 6);
      cv.drawPath(
        Path()
          ..moveTo(0, 0)
          ..lineTo(-90, -1100)
          ..lineTo(90, -1100)
          ..close(),
        ray,
      );
    }
    cv.restore();
  }
  final s = back(seg(t, k0, k0 + .55));
  if (s > 0) {
    cv.save();
    cv.translate(center.dx, center.dy);
    cv.scale(s);
    cv.rotate((1 - out(seg(t, k0, k0 + .55))) * -.35);
    final r = Rect.fromCenter(center: Offset.zero, width: size, height: size);
    cv.drawRRect(
      RRect.fromRectAndRadius(r.shift(const Offset(0, 30)), Radius.circular(size * .23)),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
    );
    cv.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(size * .23)), Paint()..color = kLogoBlue);
    cv.drawRRect(
      RRect.fromRectAndRadius(r, Radius.circular(size * .23)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0x55FFFFFF),
    );
    cv.translate(-size / 2, -size / 2);
    LogoMarkPainter(
      rise: outro ? 1 : out(seg(t, .35, 1.0)),
      rays: outro ? seg(t, .1, .6) : seg(t, .9, 1.5),
      check: outro ? out(seg(t, .3, .7)) : out(seg(t, 1.3, 1.8)),
    ).paint(cv, Size(size, size));
    cv.restore();
  }
  sparkles(cv, center, seg(t, outro ? .2 : 1.0, outro ? .9 : 1.7), reach: size * 1.25);
  final ty = outro ? 840.0 : 1080.0;
  kinetic(
    cv,
    'Lapor Yuk',
    W / 2,
    ty,
    outro ? 120 : 140,
    t,
    start: outro ? .15 : 1.45,
    colors: const [Colors.white, amber],
    ls: -3,
  );
  final e = out(seg(t, outro ? .35 : 1.9, outro ? .8 : 2.4));
  if (e > 0) {
    text(
      cv,
      'Lapor kinerja jadi ringan',
      Offset(W / 2, ty + (outro ? 175 : 205) + (1 - e) * 24),
      46,
      a(Colors.white, .9 * e),
      w: FontWeight.w600,
    );
  }
}

void sceneCamera(Canvas cv, double t) {
  backdrop(cv, const Color(0xFFEAF0FF), Colors.white, t, blue, blobA: .07);
  header(cv, t, '01 · KAMERA', 'Foto ber-timestamp', 'Waktu, lokasi & geotag tercetak otomatis');
  final dy = (1 - out(seg(t, 0, .7))) * 900;
  final r = Rect.fromLTWH(220, 500 + dy, 640, 1340);
  final shot = t >= 1.5;
  phone(cv, r, (s) {
    cv.drawRect(s, Paint()..color = Colors.black);
    final photo = Rect.fromLTWH(s.left, s.top + 110, s.width, s.width * 4 / 3);
    cv.save();
    final zoom = shot ? 1.0 : 1.04 + math.sin(t * 1.3) * .015;
    cv.translate(photo.center.dx, photo.center.dy);
    cv.scale(zoom);
    cv.translate(-photo.center.dx, -photo.center.dy);
    scene(cv, photo, t: shot ? 1.5 : t);
    cv.restore();
    if (!shot) {
      final g = Paint()
        ..color = const Color(0x55FFFFFF)
        ..strokeWidth = 2;
      for (var i = 1; i < 3; i++) {
        cv.drawLine(
          Offset(photo.left + photo.width * i / 3, photo.top),
          Offset(photo.left + photo.width * i / 3, photo.bottom),
          g,
        );
        cv.drawLine(
          Offset(photo.left, photo.top + photo.height * i / 3),
          Offset(photo.right, photo.top + photo.height * i / 3),
          g,
        );
      }
      final f = 1.35 - .35 * out(seg(t, .7, 1.1));
      final fr = Rect.fromCenter(center: photo.center, width: 190 * f, height: 190 * f);
      final br = Paint()
        ..color = amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6;
      const L = 40.0;
      for (final (c, dx, dy) in [
        (fr.topLeft, 1.0, 1.0),
        (fr.topRight, -1.0, 1.0),
        (fr.bottomLeft, 1.0, -1.0),
        (fr.bottomRight, -1.0, -1.0),
      ]) {
        cv.drawPath(
          Path()
            ..moveTo(c.dx + dx * L, c.dy)
            ..lineTo(c.dx, c.dy)
            ..lineTo(c.dx, c.dy + dy * L),
          br,
        );
      }
    } else {
      cv.save();
      cv.clipRect(photo);
      cv.translate(photo.left, photo.top + (1 - back(seg(t, 1.7, 2.25))) * 420);
      paintStamp(
        cv,
        photo.size,
        StampData(
          name: 'Rina Pratiwi',
          time: DateTime(2026, 10, 15, 8, 42),
          lat: -0.9471,
          lng: 100.4172,
          accuracy: 6,
          address: 'Jl. Sudirman, Kota Padang, Sumatera Barat',
        ),
      );
      cv.restore();
    }
    final press = t > 1.42 && t < 1.62 ? .86 : 1.0;
    final sc = Offset(s.center.dx, s.bottom - 150);
    cv.drawCircle(
      sc,
      66 * press,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = Colors.white,
    );
    cv.drawCircle(sc, 52 * press, Paint()..color = Colors.white);
    final flash = shot ? 1 - seg(t, 1.5, 1.85) : 0.0;
    if (flash > 0) cv.drawRect(s, Paint()..color = Color.fromRGBO(255, 255, 255, flash));
  });
  popIn(
    cv,
    t,
    2.35,
    const Offset(220, 1030),
    () => pill(cv, const Offset(220, 1030), 'Geotag', 30, Colors.white, blue, lead: Icons.location_on_rounded),
  );
  popIn(
    cv,
    t,
    2.6,
    const Offset(860, 1230),
    () => pill(cv, const Offset(860, 1230), 'Waktu', 30, amber, ink, lead: Icons.schedule_rounded),
  );
  popIn(
    cv,
    t,
    2.85,
    const Offset(840, 820),
    () => pill(cv, const Offset(840, 820), 'Folder per bulan', 28, blue, Colors.white, lead: Icons.folder_rounded),
  );
}

void sceneReport(Canvas cv, double t) {
  backdrop(cv, const Color(0xFFFFF4DC), Colors.white, t, amber, blobA: .16);
  header(
    cv,
    t,
    '02 · LAPOR KEGIATAN',
    'Lapor kegiatan',
    'Capaian otomatis + bukti dukung, siap SKP',
    kickBg: amber,
    kickFg: ink,
  );
  final e = out(seg(t, 0, .6));
  final r = Rect.fromLTWH(90, 500 + (1 - e) * 200, 900, 1180);
  cv.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, e));
  card(cv, r, 54, Colors.white);
  final x = r.left + 56;
  pill(
    cv,
    Offset(x + 190, r.top + 78),
    'Rabu, 15 Okt 2026',
    26,
    const Color(0xFFE8EEFF),
    blue,
    lead: Icons.event_rounded,
    padX: 24,
    padY: 14,
  );
  void label(String s, double y) => tp(s, 30, muted, w: FontWeight.w700).paint(cv, Offset(x, y));
  void field(double y, double h) => cv.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(x, y, r.width - 112, h), const Radius.circular(26)),
    Paint()..color = const Color(0xFFF4F6FB),
  );
  label('Kegiatan', r.top + 150);
  field(r.top + 196, 104);
  const typed = 'Pendataan lapangan';
  final n = (seg(t, .8, 2.0) * typed.length).floor();
  final tt = tp(typed.substring(0, n), 38, ink, w: FontWeight.w700);
  tt.paint(cv, Offset(x + 30, r.top + 248 - tt.height / 2));
  if (t < 2.4 && (t * 2.5).floor().isEven) {
    cv.drawRect(Rect.fromLTWH(x + 34 + tt.width, r.top + 224, 4, 50), Paint()..color = blue);
  }
  label('Capaian', r.top + 340);
  field(r.top + 386, 200);
  final ce = out(seg(t, 2.15, 2.6));
  if (ce > 0) {
    cv.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, ce));
    final hl = seg(t, 2.4, 2.9);
    cv.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(x, r.top + 386, (r.width - 112) * hl, 200), const Radius.circular(26)),
      Paint()..color = const Color(0x33F5B83D),
    );
    tp(
      'Persentase Terselesaikannya Pendataan Lapangan Sebesar 100%',
      34,
      ink,
      w: FontWeight.w600,
      maxW: r.width - 180,
      align: TextAlign.left,
      height: 1.35,
    ).paint(cv, Offset(x + 30, r.top + 412));
    cv.restore();
  }
  popIn(
    cv,
    t,
    2.3,
    Offset(r.right - 160, r.top + 360),
    () => pill(
      cv,
      Offset(r.right - 160, r.top + 360),
      'Otomatis',
      24,
      amber,
      ink,
      lead: Icons.auto_awesome_rounded,
      padX: 20,
      padY: 12,
    ),
  );
  label('Bukti dukung · 3 berkas', r.top + 630);
  for (var i = 0; i < 3; i++) {
    final b = Rect.fromLTWH(x + i * 270, r.top + 680, 240, 240);
    popIn(cv, t, 2.8 + i * .22, b.center, () {
      cv.save();
      cv.clipRRect(RRect.fromRectAndRadius(b, const Radius.circular(28)));
      if (i < 2) {
        scene(cv, b, variant: i == 0 ? 0 : 1);
        if (i == 0) {
          cv.drawRect(Rect.fromLTWH(b.left, b.bottom - 56, b.width, 56), Paint()..color = const Color(0x99000000));
          tp('08.42 · Padang', 22, Colors.white, w: FontWeight.w700).paint(cv, Offset(b.left + 16, b.bottom - 44));
        }
      } else {
        cv.drawRect(b, Paint()..color = const Color(0xFFFFEEEC));
        icon(cv, Icons.picture_as_pdf_rounded, b.center - const Offset(0, 22), 110, const Color(0xFFD9483F));
        text(cv, 'Laporan.pdf', b.center + const Offset(0, 72), 24, ink, w: FontWeight.w700);
      }
      cv.restore();
      final tag = ['FOTO', 'GAMBAR', 'DOK'][i];
      pill(cv, Offset(b.left + 70, b.top + 36), tag, 18, Colors.white, ink, padX: 14, padY: 8);
    });
  }
  final btn = Rect.fromLTWH(x, r.bottom - 170, r.width - 112, 120);
  final done = t >= 4.0;
  final press = t > 3.75 && t < 3.95 ? .95 : 1.0;
  cv.save();
  cv.translate(btn.center.dx, btn.center.dy);
  cv.scale(press);
  cv.translate(-btn.center.dx, -btn.center.dy);
  cv.drawRRect(
    RRect.fromRectAndRadius(btn, const Radius.circular(36)),
    Paint()..color = Color.lerp(blue, green, out(seg(t, 4.0, 4.25)))!,
  );
  if (done) {
    icon(cv, Icons.check_circle_rounded, Offset(btn.center.dx - 140, btn.center.dy), 54, Colors.white);
    text(cv, 'Tersimpan', btn.center + const Offset(30, 0), 40, Colors.white);
  } else {
    text(cv, 'Simpan', btn.center, 40, Colors.white);
  }
  cv.restore();
  cv.restore();
  confetti(cv, btn.center, seg(t, 4.0, 5.0));
  popIn(
    cv,
    t,
    4.25,
    const Offset(W / 2, 1770),
    () => pill(
      cv,
      const Offset(W / 2, 1770),
      'Siap disalin ke SKP',
      32,
      ink,
      Colors.white,
      lead: Icons.content_copy_rounded,
    ),
  );
}

void sceneRekap(Canvas cv, double t) {
  backdrop(cv, blue, const Color(0xFF1A3BB5), t, Colors.white, blobA: .06);
  header(
    cv,
    t,
    '03 · REKAP & SKP',
    'Rekap sekali ketuk',
    'PDF bulanan bertanda tangan & salin ke SKP',
    fg: Colors.white,
    subColor: const Color(0xD9FFFFFF),
    kickBg: amber,
    kickFg: ink,
  );
  // PDF page
  final pe = out(seg(t, 0, .6));
  cv.save();
  cv.translate(430 - (1 - pe) * 700, 1090);
  cv.rotate(-.06 * pe);
  final page = Rect.fromCenter(center: Offset.zero, width: 560, height: 780);
  card(cv, page, 18, Colors.white, shadow: .35);
  cv.drawRect(Rect.fromLTWH(page.left, page.top, page.width, 90), Paint()..color = const Color(0xFFE8EEFF));
  tp('REKAP CKP · OKTOBER 2026', 26, blue, w: FontWeight.w800).paint(cv, Offset(page.left + 36, page.top + 30));
  for (var i = 0; i < 9; i++) {
    final e = out(seg(t, .3 + i * .09, .55 + i * .09));
    if (e <= 0) continue;
    final y = page.top + 130 + i * 52.0;
    cv.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(page.left + 36, y, 40, 22), const Radius.circular(6)),
      Paint()..color = a(const Color(0xFFD5DEF5), e),
    );
    cv.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(page.left + 96, y, (page.width - 230) * e * (i.isEven ? 1 : .75), 22),
        const Radius.circular(6),
      ),
      Paint()..color = a(const Color(0xFFE3E8F3), e),
    );
    cv.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(page.right - 110, y, 74 * e, 22), const Radius.circular(6)),
      Paint()..color = a(const Color(0x66F5B83D), e),
    );
  }
  tp('Mengetahui,', 22, muted, w: FontWeight.w600).paint(cv, Offset(page.right - 230, page.bottom - 190));
  final sg = seg(t, 1.2, 1.9);
  if (sg > 0) {
    final path = Path()..moveTo(page.right - 240, page.bottom - 80);
    for (var i = 1; i <= 40; i++) {
      final k = i / 40;
      path.lineTo(page.right - 240 + k * 190, page.bottom - 90 + math.sin(k * 14) * 26 * (1 - k * .5) - k * 20);
    }
    final metric = path.computeMetrics().first;
    cv.drawPath(
      metric.extractPath(0, metric.length * sg),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF1B2D7A),
    );
  }
  cv.restore();
  // calendar
  final ce = out(seg(t, .15, .75));
  final cal = Rect.fromLTWH(560 + (1 - ce) * 700, 600, 430, 430);
  card(cv, cal, 36, Colors.white, shadow: .3);
  tp('Oktober', 30, ink).paint(cv, Offset(cal.left + 34, cal.top + 28));
  for (var d = 0; d < 31; d++) {
    final col = (d + 3) % 7, row = (d + 3) ~/ 7;
    final weekend = col >= 5;
    final e = out(seg(t, .3 + d * .03, .5 + d * .03));
    final c = Offset(cal.left + 52 + col * 54, cal.top + 120 + row * 58);
    cv.drawCircle(c, 20, Paint()..color = const Color(0xFFF1F3F8));
    if (e > 0 && !weekend) cv.drawCircle(c, 20 * e, Paint()..color = d % 6 == 4 ? amber : green);
  }
  popIn(cv, t, 1.85, const Offset(W / 2, 1620), () {
    final pr = t > 2.15 && t < 2.3 ? .94 : 1.0;
    cv.save();
    cv.translate(W / 2, 1620);
    cv.scale(pr);
    cv.translate(-W / 2, -1620);
    pill(
      cv,
      const Offset(W / 2, 1620),
      'Salin ke SKP',
      40,
      Colors.white,
      blue,
      lead: Icons.content_copy_rounded,
      padY: 26,
    );
    cv.restore();
  });
  popIn(
    cv,
    t,
    2.3,
    const Offset(W / 2, 1770),
    () => pill(
      cv,
      const Offset(W / 2, 1770),
      'Kegiatan, capaian & link bukti tersalin',
      26,
      ink,
      Colors.white,
      lead: Icons.check_circle_rounded,
    ),
  );
}

void bubble(
  Canvas cv,
  Rect screen,
  double y,
  String msg,
  bool mine,
  double t,
  double start, {
  String? name,
  String? avatar,
  int ticks = 0,
  bool heart = false,
}) {
  final e = seg(t, start, start + .4);
  if (e <= 0) return;
  final p = tp(msg, 30, mine ? Colors.white : ink, w: FontWeight.w600, maxW: 360, align: TextAlign.left, height: 1.3);
  final bw = p.width + 52 + (mine ? 90 : 0), bh = p.height + 42;
  final left = mine ? screen.right - 30 - bw : screen.left + 92;
  final r = Rect.fromLTWH(left, y + (name == null ? 0 : 40), bw, bh);
  final anchor = mine ? r.bottomRight : r.bottomLeft;
  final s = back(e);
  cv.save();
  cv.translate(anchor.dx, anchor.dy);
  cv.scale(.3 + .7 * s);
  cv.translate(-anchor.dx, -anchor.dy);
  if (name != null) {
    avatarCircle(cv, avatar!, Offset(screen.left + 52, y + 18), 22);
    tp(name, 24, blue, w: FontWeight.w800).paint(cv, Offset(screen.left + 92, y + 4));
  }
  cv.drawRRect(
    RRect.fromRectAndCorners(
      r,
      topLeft: Radius.circular(mine ? 30 : 8),
      topRight: Radius.circular(mine ? 8 : 30),
      bottomLeft: const Radius.circular(30),
      bottomRight: const Radius.circular(30),
    ),
    Paint()..color = mine ? blue : Colors.white,
  );
  p.paint(cv, Offset(r.left + 26, r.top + 21));
  if (mine) {
    tp('08.45', 20, const Color(0xBBFFFFFF), w: FontWeight.w600).paint(cv, Offset(r.right - 108, r.bottom - 38));
    if (ticks > 0) {
      icon(
        cv,
        ticks == 1 ? Icons.done_rounded : Icons.done_all_rounded,
        Offset(r.right - 30, r.bottom - 26),
        30,
        ticks == 3 ? amber : const Color(0xBBFFFFFF),
      );
    }
  }
  cv.restore();
  if (heart) {
    popIn(cv, t, start + .5, Offset(r.left + 40, r.bottom + 6), () {
      final h = Rect.fromCenter(center: Offset(r.left + 40, r.bottom + 6), width: 64, height: 44);
      cv.drawRRect(RRect.fromRectAndRadius(h, const Radius.circular(22)), Paint()..color = Colors.white);
      cv.drawRRect(
        RRect.fromRectAndRadius(h, const Radius.circular(22)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFE1E6F0),
      );
      icon(cv, Icons.favorite_rounded, h.center, 28, const Color(0xFFE5484D));
    });
  }
}

void sceneChat(Canvas cv, double t) {
  backdrop(cv, const Color(0xFFF1EDFF), Colors.white, t, const Color(0xFF8B6CF0), blobA: .07);
  header(cv, t, '04 · CHAT', 'Chat & grup', 'Ngobrol bareng teman kerja yang sudah Connect');
  final dy = (1 - out(seg(t, 0, .6))) * 900;
  final r = Rect.fromLTWH(200, 490 + dy, 680, 1400);
  phone(cv, r, (s) {
    cv.drawRect(s, Paint()..color = const Color(0xFFF4F6FB));
    cv.drawRect(Rect.fromLTWH(s.left, s.top, s.width, 170), Paint()..color = Colors.white);
    icon(cv, Icons.arrow_back_rounded, Offset(s.left + 50, s.top + 110), 36, ink);
    cv.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(s.left + 90, s.top + 80, 60, 60), const Radius.circular(18)),
      Paint()..color = blue,
    );
    icon(cv, Icons.group_rounded, Offset(s.left + 120, s.top + 110), 34, Colors.white);
    tp('Tim Lapangan', 32, ink).paint(cv, Offset(s.left + 168, s.top + 76));
    tp('4 anggota · 2 online', 22, muted, w: FontWeight.w600).paint(cv, Offset(s.left + 168, s.top + 116));
    final ticks = t < 1.35 ? 1 : (t < 2.3 ? 2 : 3);
    bubble(cv, s, s.top + 210, 'Laporan minggu ini aman?', false, t, .4, name: 'Rina', avatar: 'fox');
    bubble(cv, s, s.top + 400, 'Aman! Bukti udah aku upload', true, t, 1.0, ticks: ticks);
    bubble(cv, s, s.top + 530, 'Mantap, makasih ya', false, t, 1.6, name: 'Bayu', avatar: 'bear', heart: true);
    bubble(cv, s, s.top + 760, 'Nanti sore photostrip bareng?', true, t, 2.6, ticks: t < 3.1 ? 1 : 2);
    cv.drawRect(Rect.fromLTWH(s.left, s.bottom - 130, s.width, 130), Paint()..color = Colors.white);
    cv.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(s.left + 30, s.bottom - 110, s.width - 160, 76), const Radius.circular(38)),
      Paint()..color = const Color(0xFFF1F3F8),
    );
    tp('Tulis pesan…', 26, muted, w: FontWeight.w500).paint(cv, Offset(s.left + 64, s.bottom - 88));
    cv.drawCircle(Offset(s.right - 70, s.bottom - 72), 40, Paint()..color = blue);
    icon(cv, Icons.mic_rounded, Offset(s.right - 70, s.bottom - 72), 36, Colors.white);
  });
  // friend request card overlapping the phone
  popIn(cv, t, 3.0, const Offset(W / 2, 1700), () {
    final c = Rect.fromCenter(center: const Offset(W / 2, 1700), width: 820, height: 150);
    card(cv, c, 40, Colors.white, shadow: .3);
    avatarCircle(cv, 'koala', Offset(c.left + 80, c.center.dy), 46);
    tp('Dewi ingin berteman', 30, ink).paint(cv, Offset(c.left + 148, c.center.dy - 38));
    tp('Connect dulu, baru bisa chat', 22, muted, w: FontWeight.w600).paint(cv, Offset(c.left + 148, c.center.dy + 4));
    final ok = t > 3.45;
    pill(
      cv,
      Offset(c.right - 120, c.center.dy),
      ok ? 'Teman' : 'Terima',
      26,
      ok ? green : blue,
      Colors.white,
      lead: ok ? Icons.check_rounded : null,
      padX: 22,
      scale: t > 3.35 && t < 3.45 ? .9 : 1,
    );
  });
}

void sceneStory(Canvas cv, double t) {
  cv.drawRect(
    const Rect.fromLTWH(0, 0, W, H),
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(W, H), [
        const Color(0xFFFF6FA3),
        const Color(0xFFFFA94D),
      ]),
  );
  header(
    cv,
    t,
    '05 · STORY',
    'Story 24 jam',
    'Bagikan momen harian, hilang esok hari',
    fg: Colors.white,
    subColor: const Color(0xE6FFFFFF),
    kickBg: Colors.white,
    kickFg: const Color(0xFFE2457F),
  );
  const names = ['fox', 'koala', 'cat', 'owl', 'penguin'];
  const labels = ['Rina', 'Dewi', 'Sari', 'Bayu', 'Andi'];
  final open = out(seg(t, 1.0, 1.5));
  for (var i = 0; i < 5; i++) {
    final e = back(seg(t, .1 + i * .08, .5 + i * .08));
    if (e <= 0) continue;
    final c = Offset(150 + i * 195.0, 590);
    cv.save();
    cv.translate(c.dx, c.dy);
    cv.scale(e);
    cv.translate(-c.dx, -c.dy);
    cv.drawCircle(c, 78, Paint()..shader = ui.Gradient.sweep(c, [amber, const Color(0xFFE2457F), amber], [0, .5, 1]));
    cv.drawCircle(c, 70, Paint()..color = Colors.white);
    avatarCircle(cv, names[i], c, 63);
    text(cv, labels[i], c + const Offset(0, 112), 26, Colors.white, w: FontWeight.w700);
    cv.restore();
  }
  // tap ripple on Dewi
  final rp = seg(t, .75, 1.15);
  if (rp > 0 && rp < 1) {
    cv.drawCircle(
      const Offset(345, 590),
      80 + rp * 120,
      Paint()..color = Color.fromRGBO(255, 255, 255, .45 * (1 - rp)),
    );
  }
  if (open > 0) {
    final from = Rect.fromCircle(center: const Offset(345, 590), radius: 70);
    const to = Rect.fromLTWH(200, 760, 680, 1080);
    final r = Rect.lerp(from, to, open)!;
    final rad = 70 - 30 * open;
    card(cv, r, rad, Colors.black, shadow: .35);
    cv.save();
    cv.clipRRect(RRect.fromRectAndRadius(r, Radius.circular(rad)));
    scene(cv, r, variant: 2, t: t);
    cv.drawRect(
      Rect.fromLTWH(r.left, r.top, r.width, 170),
      Paint()
        ..shader = ui.Gradient.linear(r.topCenter, r.topCenter + const Offset(0, 170), [
          const Color(0x88000000),
          const Color(0x00000000),
        ]),
    );
    for (var i = 0; i < 3; i++) {
      final seg3 = Rect.fromLTWH(r.left + 24 + i * (r.width - 48) / 3, r.top + 24, (r.width - 48) / 3 - 10, 7);
      cv.drawRRect(RRect.fromRectAndRadius(seg3, const Radius.circular(4)), Paint()..color = const Color(0x66FFFFFF));
      final fill = i == 0 ? 1.0 : (i == 1 ? seg(t, 1.5, 3.0) : 0.0);
      cv.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(seg3.left, seg3.top, seg3.width * fill, 7), const Radius.circular(4)),
        Paint()..color = Colors.white,
      );
    }
    avatarCircle(cv, 'koala', Offset(r.left + 64, r.top + 92), 30);
    tp('Dewi', 28, Colors.white).paint(cv, Offset(r.left + 108, r.top + 72));
    tp('08.10', 22, const Color(0xCCFFFFFF), w: FontWeight.w600).paint(cv, Offset(r.left + 190, r.top + 76));
    final cap = out(seg(t, 1.6, 2.0));
    if (cap > 0) {
      cv.drawRect(
        Rect.fromLTWH(r.left, r.bottom - 150, r.width, 150),
        Paint()..color = Color.fromRGBO(0, 0, 0, .45 * cap),
      );
      text(
        cv,
        'Ngopi dulu sebelum turun lapangan',
        Offset(r.center.dx, r.bottom - 76),
        30,
        a(Colors.white, cap),
        w: FontWeight.w700,
      );
    }
    cv.restore();
  }
  popIn(
    cv,
    t,
    2.2,
    const Offset(830, 1700),
    () => pill(
      cv,
      const Offset(830, 1700),
      'Dilihat 12',
      28,
      Colors.white,
      const Color(0xFFE2457F),
      lead: Icons.visibility_rounded,
    ),
  );
}

void sceneVoice(Canvas cv, double t) {
  cv.drawRect(
    const Rect.fromLTWH(0, 0, W, H),
    Paint()..shader = ui.Gradient.radial(const Offset(W / 2, 980), 1300, [const Color(0xFF243C9E), navy]),
  );
  header(
    cv,
    t,
    '06 · PESAN SUARA',
    'Pesan suara',
    'VN tersimpan 3 hari, lalu terhapus otomatis',
    fg: Colors.white,
    subColor: const Color(0xD9FFFFFF),
    kickBg: amber,
    kickFg: ink,
  );
  final shrink = out(seg(t, 1.85, 2.2));
  final micE = back(seg(t, .1, .5)) * (1 - shrink);
  const mc = Offset(W / 2, 960);
  if (micE > 0.01) {
    for (var k = 0; k < 3; k++) {
      final ph = ((t * 1.1 + k / 3) % 1);
      if (t < 1.85) {
        cv.drawCircle(mc, 140 + ph * 220, Paint()..color = Color.fromRGBO(245, 184, 61, .35 * (1 - ph) * micE));
      }
    }
    cv.drawCircle(mc, 140 * micE, Paint()..color = amber);
    icon(cv, Icons.mic_rounded, mc, 150 * micE, ink);
    final secs = (1 + seg(t, .3, 1.8) * 6).floor();
    cv.drawCircle(
      Offset(W / 2 - 92, 1205),
      12,
      Paint()..color = a((t * 3).floor().isEven ? const Color(0xFFFF5A5F) : const Color(0x55FF5A5F), micE),
    );
    text(cv, 'Merekam  0:0$secs', const Offset(W / 2 + 20, 1205), 38, a(Colors.white, micE), w: FontWeight.w700);
    for (var i = 0; i < 30; i++) {
      final hgt = 14 + (math.sin(i * .7 + t * 9).abs() * math.sin(i * .23 + t * 3).abs()) * 150 * micE;
      final x = W / 2 - 29 * 13 + i * 26.0;
      cv.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, 1400), width: 14, height: hgt),
          const Radius.circular(7),
        ),
        Paint()..color = Color.fromRGBO(255, 255, 255, .85 * micE),
      );
    }
  }
  popIn(cv, t, 1.95, const Offset(980, 960), () {
    final b = Rect.fromLTWH(220, 880, 760, 160);
    cv.drawRRect(
      RRect.fromRectAndCorners(
        b,
        topLeft: const Radius.circular(40),
        topRight: const Radius.circular(10),
        bottomLeft: const Radius.circular(40),
        bottomRight: const Radius.circular(40),
      ),
      Paint()..color = blue,
    );
    icon(cv, Icons.play_circle_fill_rounded, Offset(b.left + 80, b.center.dy), 96, Colors.white);
    for (var i = 0; i < 22; i++) {
      final hgt = 12 + (math.sin(i * 1.3).abs() * 0.7 + .3) * 54;
      cv.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(b.left + 160 + i * 20.0, b.center.dy - 8), width: 9, height: hgt),
          const Radius.circular(5),
        ),
        Paint()..color = i < (seg(t, 2.4, 3.0) * 22) ? Colors.white : const Color(0x88FFFFFF),
      );
    }
    tp('0:07', 26, const Color(0xDDFFFFFF), w: FontWeight.w700).paint(cv, Offset(b.left + 160, b.bottom - 44));
    icon(cv, Icons.done_all_rounded, Offset(b.right - 50, b.bottom - 32), 32, amber);
  });
  // a voice reply from a friend
  popIn(cv, t, 2.5, const Offset(190, 1180), () {
    avatarCircle(cv, 'fox', const Offset(150, 1180), 46);
    final b = Rect.fromLTWH(220, 1100, 620, 160);
    cv.drawRRect(
      RRect.fromRectAndCorners(
        b,
        topLeft: const Radius.circular(10),
        topRight: const Radius.circular(40),
        bottomLeft: const Radius.circular(40),
        bottomRight: const Radius.circular(40),
      ),
      Paint()..color = Colors.white,
    );
    icon(cv, Icons.play_circle_fill_rounded, Offset(b.left + 80, b.center.dy), 96, blue);
    for (var i = 0; i < 17; i++) {
      final hgt = 12 + (math.cos(i * 1.7).abs() * .7 + .3) * 54;
      cv.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(b.left + 160 + i * 22.0, b.center.dy - 8), width: 9, height: hgt),
          const Radius.circular(5),
        ),
        Paint()..color = const Color(0xFFB9C7F2),
      );
    }
    tp('0:12', 26, muted, w: FontWeight.w700).paint(cv, Offset(b.left + 160, b.bottom - 44));
  });
  popIn(
    cv,
    t,
    2.35,
    const Offset(W / 2, 1460),
    () => pill(
      cv,
      const Offset(W / 2, 1460),
      'Terhapus otomatis dalam 3 hari',
      30,
      Colors.white,
      ink,
      lead: Icons.hourglass_bottom_rounded,
    ),
  );
}

void sceneStrip(Canvas cv, double t) {
  cv.drawRect(
    const Rect.fromLTWH(0, 0, W, H),
    Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(0, H), [maroon, const Color(0xFF3E0D0D)]),
  );
  final dot = Paint()..color = const Color(0x12F6EBDD);
  for (var y = 0.0; y < H; y += 60) {
    for (var x = (y / 60).floor().isEven ? 0.0 : 30.0; x < W; x += 60) {
      cv.drawCircle(Offset(x, y + (t * 20) % 60), 4, dot);
    }
  }
  header(
    cv,
    t,
    '07 · PHOTOSTRIP',
    'Photostrip bareng',
    'Sampai 6 orang · unduh PNG ukuran 4R',
    fg: creamy,
    subColor: const Color(0xD9F6EBDD),
    kickBg: amber,
    kickFg: ink,
  );
  final e = out(seg(t, 0, .55));
  const sw = 820.0, sh = 1230.0;
  cv.save();
  cv.translate(W / 2, 1100 + (1 - e) * 500);
  cv.rotate((1 - e) * .12 - .02);
  cv.translate(-sw / 2, -sh / 2);
  card(cv, const Rect.fromLTWH(0, 0, sw, sh), 6, Colors.white, shadow: .45);
  const faces = ['fox', 'bear', 'koala', 'cat'];
  paintStrip(
    cv,
    const Size(sw, sh),
    0,
    [for (var i = 0; i < 4; i++) t >= .6 + i * .38 ? av[faces[i]] : null],
    title: 'Tim Lapangan',
    date: DateTime(2026, 10, 15),
    labels: const ['Rina', 'Bayu', 'Dewi', 'Kamu'],
  );
  for (var i = 0; i < 4; i++) {
    final f = 1 - seg(t, .6 + i * .38, .75 + i * .38);
    if (t >= .6 + i * .38 && f > 0) {
      cv.drawRect(const Rect.fromLTWH(0, 0, sw, sh), Paint()..color = Color.fromRGBO(255, 255, 255, .3 * f));
    }
  }
  cv.restore();
  popIn(cv, t, 2.15, const Offset(W / 2, 1810), () {
    final bounce = math.sin(seg(t, 2.4, 3.0) * math.pi * 3).abs() * 10;
    pill(cv, Offset(W / 2, 1810 - bounce), 'Unduh PNG 4R', 34, amber, ink, lead: Icons.download_rounded);
  });
}

void sceneOutro(Canvas cv, double t) {
  sceneIntro(cv, t, outro: true);
  const chips = [
    (Icons.photo_camera_rounded, 'Foto stamp'),
    (Icons.assignment_turned_in_rounded, 'Lapor SKP'),
    (Icons.picture_as_pdf_rounded, 'Rekap PDF'),
    (Icons.forum_rounded, 'Chat & grup'),
    (Icons.mic_rounded, 'Story & VN'),
    (Icons.photo_camera_front_rounded, 'Photostrip'),
  ];
  for (var i = 0; i < chips.length; i++) {
    final c = Offset(W / 2 + (i % 3 - 1) * 330, 1190 + (i ~/ 3) * 110.0);
    popIn(
      cv,
      t,
      .45 + i * .09,
      c,
      () => pill(cv, c, chips[i].$2, 26, const Color(0x26FFFFFF), Colors.white, lead: chips[i].$1, padX: 22, padY: 16),
    );
  }
  final pulse = 1 + math.sin(seg(t, 1.3, 2.0) * math.pi * 2) * .04;
  popIn(
    cv,
    t,
    1.0,
    const Offset(W / 2, 1480),
    () => pill(
      cv,
      const Offset(W / 2, 1480),
      'Unduh gratis di Android',
      40,
      amber,
      ink,
      lead: Icons.download_rounded,
      padY: 28,
      scale: pulse,
    ),
  );
  final e = out(seg(t, 1.3, 1.7));
  if (e > 0) {
    text(
      cv,
      'Catat kegiatan tetap jalan tanpa internet',
      Offset(W / 2, 1620),
      30,
      a(Colors.white, .75 * e),
      w: FontWeight.w600,
    );
  }
}

const starts = [0.0, 3.0, 7.0, 12.0, 15.0, 19.0, 22.0, 25.0, 28.0];
final scenes = <void Function(Canvas, double)>[
  sceneIntro,
  sceneCamera,
  sceneReport,
  sceneRekap,
  sceneChat,
  sceneStory,
  sceneVoice,
  sceneStrip,
  sceneOutro,
];

void frame(Canvas cv, double t) {
  var i = starts.length - 1;
  while (starts[i] > t) {
    i--;
  }
  final lt = t - starts[i];
  const tr = .5;
  if (i > 0 && lt < tr) {
    scenes[i - 1](cv, t - starts[i - 1]);
    final e = inOut(lt / tr);
    const c = Offset(W / 2, H * .55);
    final rr = 2300 * e;
    cv.save();
    cv.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: rr)));
    scenes[i](cv, lt);
    cv.restore();
    cv.drawCircle(
      c,
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 70 * (1 - e)
        ..color = amber,
    );
  } else {
    scenes[i](cv, lt);
  }
  final fade = 1 - seg(t, 0, .25);
  if (fade > 0) cv.drawRect(const Rect.fromLTWH(0, 0, W, H), Paint()..color = Color.fromRGBO(0, 0, 0, fade));
}

Future<ui.Image> render(double t) async {
  final rec = ui.PictureRecorder();
  final cv = Canvas(rec);
  frame(cv, t);
  return rec.endRecording().toImage(W.toInt(), H.toInt());
}

void main() {
  testWidgets('promo video', timeout: const Timeout(Duration(minutes: 40)), (tester) async {
    await tester.runAsync(() async {
      final jakarta = FontLoader(kFont);
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
        jakarta.addFont(
          Future.value(ByteData.sublistView(File('assets/fonts/PlusJakartaSans-$w.ttf').readAsBytesSync())),
        );
      }
      await jakarta.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '${Platform.environment['FLUTTER_ROOT'] ?? 'D:/dev/flutter'}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
              ).readAsBytesSync(),
            ),
          ),
        );
      await icons.load();
      for (final n in ['fox', 'bear', 'koala', 'cat', 'owl', 'penguin']) {
        final codec = await ui.instantiateImageCodec(File('assets/avatars/$n.webp').readAsBytesSync());
        av[n] = (await codec.getNextFrame()).image;
      }

      final outPath = Platform.environment['OUT']!;
      final preview = Platform.environment['PREVIEW'];
      if (preview != null) {
        for (final s in preview.split(',')) {
          final img = await render(double.parse(s));
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$outPath/f_$s.png').writeAsBytesSync(png!.buffer.asUint8List());
          img.dispose();
        }
        return;
      }
      final ff = await Process.start(Platform.environment['FFMPEG']!, [
        '-y', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', '${W.toInt()}x${H.toInt()}', '-r', '$fps', '-i', '-',
        '-c:v', 'libx264', '-preset', 'slow', '-crf', '18', '-pix_fmt', 'yuv420p', outPath, //
      ]);
      ff.stdout.drain<void>();
      ff.stderr.drain<void>();
      for (var f = 0; f < fps * seconds; f++) {
        final img = await render(f / fps);
        final raw = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        ff.stdin.add(raw!.buffer.asUint8List());
        await ff.stdin.flush();
        img.dispose();
      }
      await ff.stdin.close();
      expect(await ff.exitCode, 0);
    });
  });
}
