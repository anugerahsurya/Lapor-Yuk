import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import 'common.dart';

class NavItem {
  const NavItem(this.icon, this.activeIcon, this.label);
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Toast-like floating capsule. The active tab grows into a labelled pill;
/// the centre action is the amber "sun" button.
class FloatingNav extends StatelessWidget {
  const FloatingNav({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
    required this.onAction,
  });

  final List<NavItem> items; // exactly 4, the action sits in the middle
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget tab(int i) => Expanded(
      child: _Tab(item: items[i], active: i == index, onTap: () => onSelect(i)),
    );

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AnimatedContainer(
              duration: Motion.slow,
              height: 66,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: c.navBg.withValues(alpha: .92),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 30, offset: const Offset(0, 12)),
                ],
              ),
              child: Row(
                children: [
                  tab(0),
                  tab(1),
                  _Action(onTap: onAction),
                  tab(2),
                  tab(3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.active, required this.onTap});

  final NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable(
      onTap: active ? () {} : onTap,
      scale: .9,
      child: SizedBox(
        height: 66,
        child: Center(
          child: AnimatedContainer(
            duration: Motion.base,
            curve: Motion.ease,
            padding: EdgeInsets.symmetric(horizontal: active ? 12 : 8, vertical: 8),
            decoration: BoxDecoration(
              color: active ? c.navInk.withValues(alpha: .12) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: Motion.base,
                  transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                  child: Icon(
                    active ? item.activeIcon : item.icon,
                    key: ValueKey(active),
                    size: 22,
                    color: active ? c.navInk : c.navInk.withValues(alpha: .55),
                  ),
                ),
                AnimatedSize(
                  duration: Motion.base,
                  curve: Motion.ease,
                  child: active
                      ? Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            item.label,
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: kFont,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: c.navInk,
                            ),
                          ),
                        )
                      : const SizedBox(width: 0, height: 0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatefulWidget {
  const _Action({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_Action> createState() => _ActionState();
}

class _ActionState extends State<_Action> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Pressable(
        scale: .86,
        haptic: false,
        onTap: () {
          HapticFeedback.mediumImpact();
          _spin.forward(from: 0);
          widget.onTap();
        },
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: c.accent,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: c.accent.withValues(alpha: .45), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: RotationTransition(
            turns: CurvedAnimation(parent: _spin, curve: Curves.easeOutBack).drive(Tween(begin: 0, end: .25)),
            child: const Icon(Icons.add_rounded, size: 28, color: Color(0xFF111A33)),
          ),
        ),
      ),
    );
  }
}
