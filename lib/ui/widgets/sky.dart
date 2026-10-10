import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/sky.dart';

/// Living sky: the sun travels its real arc between sunrise and sunset,
/// clouds drift by day, the moon (with its actual phase) and stars at night.
class SkyView extends StatefulWidget {
  const SkyView({super.key, required this.state, this.child, this.ground = 0});

  final SkyState state;
  final Widget? child;

  /// Height at the bottom covered by the content sheet; hills (and the fox)
  /// are laid out above it.
  final double ground;

  @override
  State<SkyView> createState() => _SkyViewState();
}

class _SkyViewState extends State<SkyView> with TickerProviderStateMixin {
  late final _loop = AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat();
  late final _phase = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400), value: 1);
  late SkyState _from = widget.state;

  @override
  void didUpdateWidget(SkyView old) {
    super.didUpdateWidget(old);
    if (old.state.phase != widget.state.phase) {
      _from = old.state;
      _phase.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SkyPainter(
        loop: _loop,
        phase: CurvedAnimation(parent: _phase, curve: Curves.easeInOutCubic),
        from: _from,
        to: widget.state,
        ground: widget.ground,
      ),
      child: widget.child,
    );
  }
}

List<Color> _gradient(SkyPhase p) => switch (p) {
  SkyPhase.pagi => const [Color(0xFF6FA6EC), Color(0xFFB7D5F4), Color(0xFFFFE1BE)],
  SkyPhase.siang => const [Color(0xFF2F6FE0), Color(0xFF6FA8F0), Color(0xFFCFE6FB)],
  SkyPhase.sore => const [Color(0xFF4A57A6), Color(0xFFE0836A), Color(0xFFFFC27A)],
  SkyPhase.malam => const [Color(0xFF070B18), Color(0xFF111A35), Color(0xFF1E2A4F)],
};

class _SkyPainter extends CustomPainter {
  _SkyPainter({required this.loop, required this.phase, required this.from, required this.to, required this.ground})
    : super(repaint: Listenable.merge([loop, phase]));

  final Animation<double> loop;
  final Animation<double> phase;
  final SkyState from;
  final SkyState to;
  final double ground;

  static final _stars = List.generate(46, (i) {
    final r = math.Random(i * 7919);
    return (r.nextDouble(), r.nextDouble() * .78, .5 + r.nextDouble() * 1.3, r.nextDouble());
  });

  @override
  void paint(Canvas canvas, Size full) {
    final size = Size(full.width, full.height - ground);
    final t = phase.value;
    final a = _gradient(from.phase), b = _gradient(to.phase);
    final colors = List.generate(3, (i) => Color.lerp(a[i], b[i], t)!);
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ).createShader(rect),
    );

    final nightness = _n(from) * (1 - t) + _n(to) * t;
    _warm = _w(from.phase) * (1 - t) + _w(to.phase) * t;
    if (nightness > 0) _drawStars(canvas, size, nightness);
    if (nightness < 1) _drawSun(canvas, size, 1 - nightness);
    if (nightness > 0) _drawMoon(canvas, size, nightness);
    _drawClouds(canvas, size, 1 - nightness * .75);
    final birds = (_b(from.phase) * (1 - t) + _b(to.phase) * t) * (1 - nightness);
    if (birds > 0) _drawBirds(canvas, size, birds);
    _drawHills(canvas, size, nightness, full.height);
    _drawFox(canvas, size, nightness);
  }

  double _n(SkyState s) => s.isNight ? 1 : 0;

  /// Golden-hour warmth applied to the meadow (morning a little, afternoon most).
  double _w(SkyPhase p) => switch (p) {
    SkyPhase.pagi => .45,
    SkyPhase.sore => 1,
    _ => 0,
  };

  /// How lively the birds are.
  double _b(SkyPhase p) => switch (p) {
    SkyPhase.pagi => 1,
    SkyPhase.siang => .6,
    SkyPhase.sore => .5,
    _ => 0,
  };

  double _warm = 0;

  /// Small flock gliding across, wings flapping.
  void _drawBirds(Canvas c, Size size, double o) {
    final p = Paint()
      ..color = const Color(0xFF263256).withValues(alpha: .55 * o)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final s = size.shortestSide * .028;
    for (final (i, (dx, dy)) in [(0.0, 0.0), (-1.6, .9), (-3.0, -.4)].indexed) {
      final span = size.width + 30 * s;
      final x = ((loop.value * 2 + .3) % 1) * span - 6 * s + dx * s * 2;
      final y = size.height * .2 + dy * s * 2 + math.sin(loop.value * math.pi * 6 + i) * s;
      final flap = math.sin(loop.value * math.pi * 2 * 40 + i * 1.7);
      final wing = s * (.35 + .45 * flap);
      c.drawPath(
        Path()
          ..moveTo(x - s, y - wing)
          ..quadraticBezierTo(x - s * .4, y - wing * .2, x, y)
          ..quadraticBezierTo(x + s * .4, y - wing * .2, x + s, y - wing),
        p,
      );
    }
  }

  Offset _arc(Size size, double p) {
    final x = size.width * (.08 + .84 * p);
    final y = size.height * (.72 - .52 * math.sin(math.pi * p.clamp(0, 1)));
    return Offset(x, y);
  }

  void _drawSun(Canvas c, Size size, double o) {
    final pos = _arc(size, to.isNight ? .5 : to.sunProgress.clamp(0.02, .98));
    final r = size.shortestSide * .085;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFE6A3).withValues(alpha: .55 * o),
          const Color(0xFFFFE6A3).withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: pos, radius: r * 4));
    c.drawCircle(pos, r * 4, glow);
    // Slowly turning rays
    final rays = Paint()
      ..color = const Color(0xFFFFF1C9).withValues(alpha: .45 * o)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final rot = loop.value * math.pi * 2 / 3;
    for (var i = 0; i < 12; i++) {
      final ang = rot + i * math.pi / 6;
      final pulse = 1 + .08 * math.sin(loop.value * math.pi * 8 + i);
      c.drawLine(
        pos + Offset(math.cos(ang), math.sin(ang)) * r * 1.45,
        pos + Offset(math.cos(ang), math.sin(ang)) * r * 1.85 * pulse,
        rays,
      );
    }
    c.drawCircle(pos, r, Paint()..color = const Color(0xFFFFD873).withValues(alpha: o));
    c.drawCircle(
      pos.translate(-r * .25, -r * .25),
      r * .55,
      Paint()..color = const Color(0xFFFFEDB0).withValues(alpha: .7 * o),
    );
  }

  void _drawMoon(Canvas c, Size size, double o) {
    final pos = Offset(size.width * .78, size.height * .3);
    final r = size.shortestSide * .075;
    c.drawCircle(
      pos,
      r * 3.2,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFDCE6FF).withValues(alpha: .22 * o),
            const Color(0xFFDCE6FF).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: pos, radius: r * 3.2)),
    );
    // Lit part = disc minus a shifted shadow disc, driven by the real phase.
    final ph = to.moonPhase;
    final lit = (1 - math.cos(ph * 2 * math.pi)) / 2; // 0 new .. 1 full
    // Shadow offset grows with illumination; keep at least a thin crescent.
    final shift = r * 2 * math.max(lit, .18) * (ph < .5 ? -1 : 1);
    final disc = Path()..addOval(Rect.fromCircle(center: pos, radius: r));
    final shadow = Path()..addOval(Rect.fromCircle(center: pos.translate(shift, -r * .08), radius: r * 1.02));
    final moon = lit > .97 ? disc : Path.combine(PathOperation.difference, disc, shadow);
    c.drawPath(disc, Paint()..color = const Color(0xFF2A3560).withValues(alpha: .55 * o));
    c.drawPath(moon, Paint()..color = const Color(0xFFF4F1E4).withValues(alpha: o));
    final crater = Paint()..color = const Color(0xFFD9D4C2).withValues(alpha: .55 * o);
    c.save();
    c.clipPath(moon);
    c.drawCircle(pos.translate(-r * .3, -r * .2), r * .18, crater);
    c.drawCircle(pos.translate(r * .25, r * .35), r * .12, crater);
    c.drawCircle(pos.translate(r * .05, -r * .5), r * .08, crater);
    c.restore();
  }

  void _drawStars(Canvas c, Size size, double o) {
    final p = Paint();
    for (final (x, y, r, seed) in _stars) {
      final tw = .35 + .65 * (.5 + .5 * math.sin((loop.value * 6 + seed) * math.pi * 2));
      p.color = Colors.white.withValues(alpha: o * tw * .9);
      c.drawCircle(Offset(x * size.width, y * size.height), r, p);
    }
  }

  void _drawClouds(Canvas c, Size size, double o) {
    final p = Paint()..color = Colors.white.withValues(alpha: .55 * o);
    void cloud(double baseX, double y, double s, double speed) {
      final w = size.width + 160 * s;
      final x = (baseX * w + loop.value * w * speed) % w - 80 * s;
      final path = Path()
        ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, 90 * s, 22 * s), Radius.circular(11 * s)))
        ..addOval(Rect.fromCircle(center: Offset(x + 30 * s, y + 4 * s), radius: 17 * s))
        ..addOval(Rect.fromCircle(center: Offset(x + 56 * s, y), radius: 22 * s));
      c.drawPath(path, p);
    }

    cloud(.1, size.height * .28, .8, 1);
    cloud(.55, size.height * .46, .55, 2);
    cloud(.8, size.height * .16, .45, 1.5);
  }

  // Meadow palette: day -> night.
  Color _g(int day, int night, double t) =>
      Color.lerp(Color.lerp(Color(day), Color(night), t)!, const Color(0xFFD9A15A), _warm * .2 * (1 - t))!;

  static const _farCurve = [0.0, .80, .3, .66, .62, .78, .62, .78, .85, .86, 1.0, .74];
  static const _backCurve = [0.0, .86, .25, .70, .55, .84, .55, .84, .80, .94, 1.0, .80];

  /// y on a two-segment quadratic curve given as fractions
  /// [x0,y0,cx,cy,x1,y1, x1,y1,cx2,cy2,x2,y2].
  double _curveY(List<double> k, double x, Size size) {
    final w = size.width, h = size.height;
    final seg = x / w <= k[4] ? 0 : 6;
    final x0 = k[seg] * w, cx = k[seg + 2] * w, x1 = k[seg + 4] * w;
    var lo = 0.0, hi = 1.0;
    for (var i = 0; i < 18; i++) {
      final m = (lo + hi) / 2;
      final xm = (1 - m) * (1 - m) * x0 + 2 * (1 - m) * m * cx + m * m * x1;
      if (xm < x) {
        lo = m;
      } else {
        hi = m;
      }
    }
    final t = (lo + hi) / 2;
    return ((1 - t) * (1 - t) * k[seg + 1] + 2 * (1 - t) * t * k[seg + 3] + t * t * k[seg + 5]) * h;
  }

  Path _curvePath(List<double> k, Size size) {
    final w = size.width, h = size.height;
    return Path()
      ..moveTo(k[0] * w, k[1] * h)
      ..quadraticBezierTo(k[2] * w, k[3] * h, k[4] * w, k[5] * h)
      ..quadraticBezierTo(k[8] * w, k[9] * h, k[10] * w, k[11] * h)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
  }

  void _drawHills(Canvas c, Size size, double night, double fullH) {
    final h = size.height;
    final w = size.width;
    final sway = math.sin(loop.value * math.pi * 2 * 6);

    // Far hills, hazy.
    c.drawPath(_curvePath(_farCurve, size), Paint()..color = _g(0xFFB9DDA0, 0xFF1A2E2A, night));
    for (final (fx, sc) in [(.42, .7), (.5, .55), (.74, .6)]) {
      final x = fx * w;
      _pine(c, Offset(x, _curveY(_farCurve, x, size) + 2), h * .07 * sc, _g(0xFF8DC57A, 0xFF16291F, night), sway * .3);
    }

    // Back hill with a small grove.
    c.drawPath(_curvePath(_backCurve, size), Paint()..color = _g(0xFF86C46A, 0xFF16301F, night));
    for (final (i, (fx, sc, round)) in [
      (.07, 1.0, true),
      (.15, .8, false),
      (.22, .65, true),
      (.88, .95, true),
      (.95, .75, false),
    ].indexed) {
      final x = fx * w;
      final base = Offset(x, _curveY(_backCurve, x, size) + h * .015);
      if (round) {
        _tree(c, base, h * .11 * sc, night, math.sin(loop.value * math.pi * 2 * 6 + i));
      } else {
        _pine(c, base, h * .13 * sc, _g(0xFF3F8C46, 0xFF0F2318, night), sway);
      }
    }

    // Front meadow.
    final front = _frontSolid(night);
    c.drawPath(
      Path()
        ..moveTo(0, h * .95)
        ..quadraticBezierTo(w * .4, h * .82, w * .7, h * .93)
        ..quadraticBezierTo(w * .88, h * .99, w, h * .92)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(),
      Paint()..color = front,
    );
    // Grass tufts + flowers along the crest.
    final tuft = Paint()
      ..color = _g(0xFF4C9A40, 0xFF0C1F15, night)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final rnd = math.Random(7);
    for (var i = 0; i < 26; i++) {
      final x = (i + rnd.nextDouble()) / 26 * w;
      final y = _frontY(x, size) + 3 + rnd.nextDouble() * h * .03;
      final lean = sway * 1.2;
      c.drawLine(Offset(x, y), Offset(x - 2 + lean, y - 5), tuft);
      c.drawLine(Offset(x, y), Offset(x + lean, y - 7), tuft);
      c.drawLine(Offset(x, y), Offset(x + 2 + lean, y - 5), tuft);
      if (i % 3 == 1) {
        final petal = [const Color(0xFFFFFFFF), const Color(0xFFFFD45C), const Color(0xFFFF9EB5)][i % 9 ~/ 3];
        c.drawCircle(
          Offset(x + 5, y - 2),
          2.2,
          Paint()..color = Color.lerp(petal, const Color(0xFF2A3B4A), night * .8)!,
        );
      }
    }
    // Solid ground under the sheet so its rounded corners sit on grass.
    if (fullH > h) c.drawRect(Rect.fromLTRB(0, h - 1, w, fullH), Paint()..color = front);
  }

  Color _frontSolid(double night) => _g(0xFF66B04F, 0xFF10241A, night);

  /// Round, leafy tree: trunk + three canopy blobs, gently swaying.
  void _tree(Canvas c, Offset base, double size, double night, double sway) {
    final trunk = Paint()..color = _g(0xFF8A5B3C, 0xFF1A1A1F, night);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: base.translate(0, -size * .22), width: size * .13, height: size * .46),
        Radius.circular(size * .05),
      ),
      trunk,
    );
    final top = base.translate(sway * size * .04, -size * .62);
    final dark = Paint()..color = _g(0xFF3E8A3F, 0xFF0E2218, night);
    final light = Paint()..color = _g(0xFF58A94F, 0xFF143022, night);
    c.drawCircle(top.translate(-size * .2, size * .08), size * .26, dark);
    c.drawCircle(top.translate(size * .2, size * .1), size * .24, dark);
    c.drawCircle(top.translate(0, -size * .06), size * .3, light);
    c.drawCircle(
      top.translate(-size * .08, -size * .14),
      size * .1,
      Paint()..color = Colors.white.withValues(alpha: .12 * (1 - night)),
    );
  }

  /// Simple two-tier pine.
  void _pine(Canvas c, Offset base, double size, Color color, double sway) {
    final p = Paint()..color = color;
    c.drawRect(
      Rect.fromCenter(center: base.translate(0, -size * .08), width: size * .08, height: size * .18),
      Paint()..color = Color.lerp(color, const Color(0xFF5A3A26), .5)!,
    );
    final tip = base.translate(sway * size * .05, -size);
    for (final (y0, half) in [(.15, .32), (.45, .25)]) {
      final by = base.dy - size * y0;
      c.drawPath(
        Path()
          ..moveTo(base.dx - size * half, by)
          ..lineTo(tip.dx, y0 == .15 ? tip.dy + size * .3 : tip.dy)
          ..lineTo(base.dx + size * half, by)
          ..close(),
        p,
      );
    }
  }

  /// y of the front hill's top edge at x (same curve as in _drawHills).
  double _frontY(double x, Size size) {
    final w = size.width, h = size.height;
    double solve(double x0, double cx, double x1, double target) {
      var lo = 0.0, hi = 1.0;
      for (var i = 0; i < 18; i++) {
        final m = (lo + hi) / 2;
        final xm = (1 - m) * (1 - m) * x0 + 2 * (1 - m) * m * cx + m * m * x1;
        if (xm < target) {
          lo = m;
        } else {
          hi = m;
        }
      }
      return (lo + hi) / 2;
    }

    double quad(double a, double b, double cc, double t) => (1 - t) * (1 - t) * a + 2 * (1 - t) * t * b + t * t * cc;
    final xc = x.clamp(0.0, w);
    if (xc <= w * .7) {
      final t = solve(0, w * .4, w * .7, xc);
      return quad(h * .95, h * .82, h * .93, t);
    }
    final t = solve(w * .7, w * .88, w, xc);
    return quad(h * .93, h * .99, h * .92, t);
  }

  /// A little fox galloping along the front hill.
  void _drawFox(Canvas c, Size size, double night) {
    final s = size.height * .052;
    final span = size.width + 10 * s;
    final x = (loop.value * 3 % 1) * span - 5 * s;
    final y = _frontY(x, size) + s * .15;
    final slope = math.atan2(_frontY(x + 4, size) - _frontY(x - 4, size), 8);
    final ph = loop.value * 40 * 2.6 * math.pi * 2; // ~2.6 strides per second

    final body = Color.lerp(const Color(0xFFE8743B), const Color(0xFF1C2650), night)!;
    final dark = Color.lerp(const Color(0xFFB0501F), const Color(0xFF141C3D), night)!;
    final light = Color.lerp(const Color(0xFFFFF3E3), const Color(0xFF3C4A7A), night)!;

    c.save();
    c.translate(x, y);
    c.rotate(slope);
    // shadow
    c.drawOval(
      Rect.fromCenter(center: Offset(0, -s * .05), width: s * 2.6, height: s * .35),
      Paint()..color = Colors.black.withValues(alpha: .12 * (1 - night * .5)),
    );

    final bob = math.sin(ph * 2) * .12 * s;
    final hip = Offset(-.72 * s, -.78 * s + bob);
    final shoulder = Offset(.68 * s, -.8 * s + bob);
    void leg(Offset root, double angle, Color col) {
      final knee = root + Offset(math.sin(angle) * .45 * s, math.cos(angle) * .45 * s);
      final paw = knee + Offset(math.sin(angle * .4) * .42 * s, math.cos(angle * .4) * .42 * s);
      c.drawPath(
        Path()
          ..moveTo(root.dx, root.dy)
          ..lineTo(knee.dx, knee.dy)
          ..lineTo(paw.dx, paw.dy),
        Paint()
          ..color = col
          ..style = PaintingStyle.stroke
          ..strokeWidth = .2 * s
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final swing = math.sin(ph), swing2 = math.sin(ph + math.pi);
    // far legs
    leg(hip, swing2 * .85 + .35, dark);
    leg(shoulder, swing * .85 - .2, dark);

    // tail (wags with the stride) + white tip
    final wag = math.sin(ph + 1) * .18 * s;
    final tailEnd = Offset(-2.15 * s, -1.55 * s + bob + wag);
    c.drawPath(
      Path()
        ..moveTo(-.8 * s, -1.1 * s + bob)
        ..quadraticBezierTo(-1.6 * s, -1.0 * s + bob, tailEnd.dx, tailEnd.dy),
      Paint()
        ..color = body
        ..style = PaintingStyle.stroke
        ..strokeWidth = .48 * s
        ..strokeCap = StrokeCap.round,
    );
    c.drawCircle(tailEnd, .24 * s, Paint()..color = light);

    // body
    c.save();
    c.translate(0, -1.05 * s + bob);
    c.rotate(math.sin(ph) * .05);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: 2.15 * s, height: .86 * s), Paint()..color = body);
    c.drawOval(
      Rect.fromCenter(center: Offset(.55 * s, .18 * s), width: .8 * s, height: .42 * s),
      Paint()..color = light,
    );
    c.restore();

    // near legs
    leg(hip, swing * .85 + .35, body);
    leg(shoulder, swing2 * .85 - .2, body);

    // head
    final hc = Offset(1.22 * s, -1.42 * s + bob * 1.2);
    final ear = Paint()..color = dark;
    c.drawPath(
      Path()
        ..moveTo(hc.dx - .28 * s, hc.dy - .18 * s)
        ..lineTo(hc.dx - .2 * s, hc.dy - .72 * s)
        ..lineTo(hc.dx + .05 * s, hc.dy - .28 * s)
        ..close(),
      ear,
    );
    c.drawPath(
      Path()
        ..moveTo(hc.dx + .02 * s, hc.dy - .25 * s)
        ..lineTo(hc.dx + .18 * s, hc.dy - .74 * s)
        ..lineTo(hc.dx + .34 * s, hc.dy - .18 * s)
        ..close(),
      Paint()..color = body,
    );
    c.drawCircle(hc, .38 * s, Paint()..color = body);
    c.drawPath(
      Path()
        ..moveTo(hc.dx + .2 * s, hc.dy - .14 * s)
        ..lineTo(hc.dx + .82 * s, hc.dy + .1 * s)
        ..lineTo(hc.dx + .14 * s, hc.dy + .32 * s)
        ..close(),
      Paint()..color = light,
    );
    c.drawCircle(Offset(hc.dx + .8 * s, hc.dy + .1 * s), .08 * s, Paint()..color = const Color(0xFF16181D));
    c.drawCircle(
      Offset(hc.dx + .16 * s, hc.dy - .08 * s),
      .065 * s,
      Paint()..color = Color.lerp(const Color(0xFF16181D), const Color(0xFFF2B35A), night)!,
    );
    c.restore();
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.to != to || old.from != from;
}
