import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import '../widgets/logo.dart';
import 'greeting_screen.dart';
import 'onboarding_screen.dart';

/// Opening sequence: tile pops in, the sun rises, rays pop, the tick is
/// drawn, then the wordmark slides in and everything hands over to the app.
/// Background matches the native Android splash so the handoff is seamless.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2300));

  Animation<double> _seg(double a, double b, [Curve curve = Curves.easeOutCubic]) => CurvedAnimation(
    parent: _c,
    curve: Interval(a, b, curve: curve),
  );

  late final _tile = _seg(0, .22, Curves.easeOutBack);
  late final _rise = _seg(.12, .42);
  late final _rays = _seg(.36, .62, Curves.linear);
  late final _check = _seg(.56, .74, Curves.easeInOutCubic);
  late final _word = _seg(.58, .84);
  late final _lift = _seg(.55, .8, Curves.easeInOutCubic);

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(_enter);
    Future.delayed(const Duration(milliseconds: 1500), HapticFeedback.lightImpact);
  }

  void _enter() {
    if (!mounted) return;
    // New users set up their profile first; everyone else gets a hello.
    final next = ref.read(settingsProvider.notifier).onboarded ? const GreetingScreen() : const OnboardingScreen();
    Navigator.of(context).pushReplacement(fadeRoute(next));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: kLogoBlue,
        body: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            const tileSize = 112.0;
            return Center(
              child: Transform.translate(
                // Start with the tile dead-centre (like the native splash), end
                // with tile + wordmark centred together.
                offset: Offset(0, 44 * (1 - _lift.value)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: .6 + .4 * _tile.value,
                      child: Opacity(
                        opacity: _tile.value.clamp(0, 1),
                        child: Container(
                          width: tileSize,
                          height: tileSize,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(tileSize * .23),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: .28 * _rise.value),
                                blurRadius: 40,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: CustomPaint(
                            painter: LogoMarkPainter(
                              rise: _rise.value,
                              rays: _rays.value,
                              check: _check.value,
                              color: kLogoBlue,
                              cut: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Opacity(
                      opacity: _word.value,
                      child: Transform.translate(
                        offset: Offset(0, 14 * (1 - _word.value)),
                        child: Column(
                          children: [
                            Text.rich(
                              const TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'lapor ',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  TextSpan(
                                    text: 'yuk',
                                    style: TextStyle(color: kLogoAmber),
                                  ),
                                ],
                              ),
                              style: const TextStyle(
                                fontFamily: kFont,
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.2,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Catat kerja, setiap hari.',
                              style: TextStyle(
                                fontFamily: kFont,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: .7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
