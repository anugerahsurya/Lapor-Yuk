import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import 'common.dart';

/// Mascots bundled from ipaslogo.com (free for commercial use), so the
/// profile picture works offline.
const avatars = [
  'sun',
  'capybara',
  'red_panda',
  'otter',
  'owl',
  'baby_panda',
  'fox',
  'cat',
  'penguin',
  'pangolin',
  'toucan',
  'hamster',
  'alpaca',
  'seal',
  'dachshund',
  'koala',
  'hedgehog',
  'sparrow',
  'bear',
];

String avatarAsset(String name) => 'assets/avatars/$name.webp';

class Avatar extends ConsumerWidget {
  const Avatar({super.key, this.size = 44, this.ring});

  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(settingsProvider.select((s) => s.avatar));
    return AnimatedSwitcher(
      duration: Motion.base,
      transitionBuilder: (c, a) => ScaleTransition(
        scale: a,
        child: FadeTransition(opacity: a, child: c),
      ),
      child: Container(
        key: ValueKey(name),
        width: size,
        height: size,
        padding: EdgeInsets.all(ring == null ? 0 : 2.5),
        decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
        child: ClipOval(
          child: Image.asset(avatarAsset(name), fit: BoxFit.cover, cacheWidth: (size * 3).round()),
        ),
      ),
    );
  }
}

Future<void> pickAvatar(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final current = ref.watch(settingsProvider.select((s) => s.avatar));
        final c = ctx.c;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pilih avatar', style: ctx.t.headlineSmall),
                const SizedBox(height: 4),
                Text('Maskot dari ipaslogo.com, tersimpan di aplikasi.', style: ctx.t.bodySmall),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final (i, a) in avatars.indexed)
                      Pressable(
                        onTap: () {
                          ref.read(settingsProvider.notifier).setAvatar(a);
                          Navigator.pop(ctx);
                        },
                        scale: .9,
                        child: AnimatedContainer(
                          duration: Motion.base,
                          padding: EdgeInsets.all(a == current ? 4 : 0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: a == current ? c.accent : Colors.transparent, width: 3),
                          ),
                          child: ClipOval(child: Image.asset(avatarAsset(a), fit: BoxFit.cover, cacheWidth: 240)),
                        ),
                      ).animate().fadeIn(delay: (25 * i).ms, duration: 250.ms).scale(begin: const Offset(.8, .8)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
