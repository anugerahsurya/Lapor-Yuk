import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import '../widgets/avatar.dart';
import 'onboarding_screen.dart' show fadeRoute;
import 'shell.dart';

/// "Halo, `nama`" moment between the logo and the app. Tap to skip.
class GreetingScreen extends ConsumerStatefulWidget {
  const GreetingScreen({super.key});

  @override
  ConsumerState<GreetingScreen> createState() => _GreetingScreenState();
}

class _GreetingScreenState extends ConsumerState<GreetingScreen> with SingleTickerProviderStateMixin {
  late final _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();
  Timer? _timer;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2300), _enter);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _wave.dispose();
    super.dispose();
  }

  void _enter() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(fadeRoute(const Shell()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ref.watch(settingsProvider);
    final sky = ref.watch(skyProvider);
    final now = DateTime.now();
    final todos = ref.watch(todayTodosProvider).length;
    final line = now.weekday >= 6
        ? 'Selamat berakhir pekan. Istirahat yang cukup, ya!'
        : 'Selamat ${sky.phase.label.toLowerCase()}! Siap mencatat kegiatan hari ini?';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _enter,
        child: Scaffold(
          body: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.brand, Color.lerp(c.brand, const Color(0xFF0A1230), .45)!],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(flex: 3),
                    Avatar(
                      size: 96,
                      ring: Colors.white.withValues(alpha: .5),
                    ).animate().scale(begin: const Offset(.4, .4), duration: 700.ms, curve: Curves.elasticOut),
                    const SizedBox(height: 26),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            'Halo, ${s.profile.firstName}',
                            style: context.t.displaySmall!.copyWith(color: Colors.white, fontSize: 38),
                          ),
                        ),
                        const SizedBox(width: 10),
                        AnimatedBuilder(
                          animation: _wave,
                          builder: (_, child) => Transform.rotate(
                            angle: math.sin(_wave.value * math.pi * 6) * .45 * (1 - _wave.value),
                            alignment: Alignment.bottomRight,
                            child: child,
                          ),
                          child: const Text('👋', style: TextStyle(fontSize: 36)),
                        ),
                      ],
                    ).animate().fadeIn(delay: 150.ms, duration: 500.ms).slideY(begin: .3, end: 0),
                    const SizedBox(height: 12),
                    Text(
                      line,
                      style: context.t.titleMedium!.copyWith(
                        color: Colors.white.withValues(alpha: .85),
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ).animate().fadeIn(delay: 400.ms, duration: 500.ms).slideY(begin: .3, end: 0),
                    if (todos > 0) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$todos tugas menunggu hari ini',
                          style: context.t.labelLarge!.copyWith(color: Colors.white),
                        ),
                      ).animate().fadeIn(delay: 650.ms).scale(begin: const Offset(.9, .9)),
                    ],
                    const Spacer(flex: 4),
                    Center(
                      child: Text(
                        'Ketuk untuk masuk',
                        style: context.t.labelMedium!.copyWith(color: Colors.white.withValues(alpha: .55)),
                      ),
                    ).animate(onPlay: (a) => a.repeat(reverse: true)).fadeIn(duration: 900.ms),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
