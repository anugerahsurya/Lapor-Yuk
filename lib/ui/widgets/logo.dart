import 'dart:math' as math;

import 'package:flutter/material.dart';

const kLogoBlue = Color(0xFF2F5FEA); // royal blue
const kLogoAmber = Color(0xFFF5B83D);

/// The "sunrise + check" mark. Geometry mirrors tool/make_icons.py so the
/// launcher icon and the in-app logo are identical.
///
/// [rise] lifts the sun above the horizon, [rays] pops the three rays in
/// sequence, [check] draws the tick. All 0..1; defaults give the static logo.
class LogoMarkPainter extends CustomPainter {
  LogoMarkPainter({this.rise = 1, this.rays = 1, this.check = 1, this.color = Colors.white, this.cut = kLogoBlue});

  final double rise, rays, check;
  final Color color, cut;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    Offset p(double x, double y) => Offset(x * s, y * s);
    final ink = Paint()..color = color;
    const cx = .5, cy = .655, r = .215;
    const horizonTop = cy; // top edge of the horizon stroke (centre .04 below, width .08)

    // Sun, clipped at the horizon so it can rise from behind it.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, s, (horizonTop + .001) * s));
    final sunCenter = p(cx, cy + (1 - rise) * (r + .02));
    canvas.drawArc(Rect.fromCircle(center: sunCenter, radius: r * s), math.pi, math.pi, true, ink);
    // Check cut-out, drawn progressively.
    if (check > 0) {
      final dy = (1 - rise) * (r + .02);
      final pts = [p(cx - .09, cy - .095 + dy), p(cx - .03, cy - .045 + dy), p(cx + .09, cy - .15 + dy)];
      final l1 = (pts[1] - pts[0]).distance, l2 = (pts[2] - pts[1]).distance;
      final along = (l1 + l2) * check.clamp(0, 1);
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      if (along <= l1) {
        path.lineTo(pts[0].dx + (pts[1].dx - pts[0].dx) * along / l1, pts[0].dy + (pts[1].dy - pts[0].dy) * along / l1);
      } else {
        final t = (along - l1) / l2;
        path
          ..lineTo(pts[1].dx, pts[1].dy)
          ..lineTo(pts[1].dx + (pts[2].dx - pts[1].dx) * t, pts[1].dy + (pts[2].dy - pts[1].dy) * t);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = cut
          ..style = PaintingStyle.stroke
          ..strokeWidth = .06 * s
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();

    // Horizon
    final line = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = .08 * s;
    canvas.drawLine(p(.20, cy + .04), p(.80, cy + .04), line);

    // Rays pop in one after another.
    final ray = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = .075 * s;
    const angles = [-150.0, -90.0, -30.0];
    for (var i = 0; i < 3; i++) {
      final local = ((rays * 3) - i).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final k = Curves.easeOutBack.transform(local);
      final a = angles[i] * math.pi / 180;
      final dir = Offset(math.cos(a), math.sin(a));
      const r0 = r + .07, r1 = r + .15;
      final mid = (r0 + r1) / 2, half = (r1 - r0) / 2 * k;
      canvas.drawLine(
        p(cx + dir.dx * (mid - half), cy + dir.dy * (mid - half)),
        p(cx + dir.dx * (mid + half), cy + dir.dy * (mid + half)),
        ray,
      );
    }
  }

  @override
  bool shouldRepaint(LogoMarkPainter o) =>
      o.rise != rise || o.rays != rays || o.check != check || o.color != color || o.cut != cut;
}

/// Static app logo tile (royal-blue squircle + white mark).
class LogoTile extends StatelessWidget {
  const LogoTile({super.key, this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: kLogoBlue, borderRadius: BorderRadius.circular(size * .23)),
    child: CustomPaint(painter: LogoMarkPainter()),
  );
}
