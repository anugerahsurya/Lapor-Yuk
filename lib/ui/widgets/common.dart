import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

/// Every tappable thing goes through this: a quick squash + haptic tick.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = .96, this.haptic = true});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: _down ? const Duration(milliseconds: 90) : Motion.base,
        curve: _down ? Curves.easeOut : Motion.spring,
        child: AnimatedOpacity(
          opacity: widget.onTap == null && widget.onLongPress == null ? .45 : 1,
          duration: Motion.fast,
          child: widget.child,
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: Motion.slow,
      curve: Motion.ease,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.c.line),
      ),
      child: child,
    );
    return onTap == null ? card : Pressable(onTap: onTap, scale: .98, child: card);
  }
}

enum BtnStyle { primary, tonal, ghost, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.style = BtnStyle.primary,
    this.busy = false,
    this.expand = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final BtnStyle style;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg, border) = switch (style) {
      BtnStyle.primary => (c.brand, c.onBrand, Colors.transparent),
      BtnStyle.tonal => (c.primarySoft, c.primary, Colors.transparent),
      BtnStyle.ghost => (Colors.transparent, c.ink, c.line),
      BtnStyle.danger => (c.danger.withValues(alpha: .1), c.danger, Colors.transparent),
    };
    final content = AnimatedSwitcher(
      duration: Motion.fast,
      child: busy
          ? SizedBox(
              key: const ValueKey('busy'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 19, color: fg), const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: context.t.labelLarge!.copyWith(color: fg),
                  ),
                ),
              ],
            ),
    );
    return Pressable(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: Motion.base,
        height: 52,
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: content,
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.icon, this.color});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final col = color ?? context.c.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: col.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: col), const SizedBox(width: 4)],
          Text(label, style: context.t.labelMedium!.copyWith(color: col, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(text.toUpperCase(), style: context.t.labelSmall!.copyWith(color: context.c.muted)),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class IconBtn extends StatelessWidget {
  const IconBtn({super.key, required this.icon, this.onTap, this.tooltip, this.color, this.bg});

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? color;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    final w = Pressable(
      onTap: onTap,
      scale: .88,
      child: AnimatedContainer(
        duration: Motion.base,
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: bg ?? context.c.surface,
          shape: BoxShape.circle,
          border: Border.all(color: bg == null ? context.c.line : Colors.transparent),
        ),
        child: Icon(icon, size: 20, color: color ?? context.c.ink),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

/// Slide-up + fade route used for full-screen flows (form, detail).
Route<T> softRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 420),
  reverseTransitionDuration: const Duration(milliseconds: 300),
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (_, anim, _, child) {
    final a = CurvedAnimation(parent: anim, curve: Curves.easeOutQuart, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .06), end: Offset.zero).animate(a),
        child: child,
      ),
    );
  },
);

void toast(BuildContext context, String msg, {IconData icon = Icons.check_circle_rounded}) {
  final c = context.c;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 110),
        duration: const Duration(milliseconds: 2600),
        content: Row(
          children: [
            Icon(icon, color: c.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
      ),
    );
}

Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  bool danger = false,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: ctx.t.headlineSmall),
            const SizedBox(height: 8),
            Text(message, style: ctx.t.bodyMedium!.copyWith(color: ctx.c.muted)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: AppButton(label: 'Batal', style: BtnStyle.ghost, onTap: () => Navigator.pop(ctx, false)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: confirm,
                    style: danger ? BtnStyle.danger : BtnStyle.primary,
                    onTap: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return r ?? false;
}
