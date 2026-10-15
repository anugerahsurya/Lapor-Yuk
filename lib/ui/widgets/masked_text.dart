import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/sensitive.dart';

/// Text that blurs [sensitiveWords]. Press and hold a blurred word to read it;
/// it blurs again on release.
class MaskedText extends StatelessWidget {
  const MaskedText(this.text, {super.key, this.style, this.maxLines, this.overflow, this.textAlign});
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final matches = sensitiveWords.allMatches(text).toList();
    if (matches.isEmpty) return Text(text, style: style, maxLines: maxLines, overflow: overflow, textAlign: textAlign);
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final spans = <InlineSpan>[];
    var i = 0;
    for (final m in matches) {
      if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _Hidden(m[0]!, effective),
        ),
      );
      i = m.end;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}

class _Hidden extends StatefulWidget {
  const _Hidden(this.word, this.style);
  final String word;
  final TextStyle style;

  @override
  State<_Hidden> createState() => _HiddenState();
}

class _HiddenState extends State<_Hidden> {
  bool _show = false;

  void _set(bool v) {
    if (v) HapticFeedback.selectionClick();
    setState(() => _show = v);
  }

  @override
  Widget build(BuildContext context) {
    final word = Text(widget.word, style: widget.style);
    return GestureDetector(
      // Wins over the bubble's long-press menu because it sits deeper.
      onLongPressStart: (_) => _set(true),
      onLongPressEnd: (_) => _set(false),
      onLongPressCancel: () => _set(false),
      child: _show
          ? word
          : ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5, tileMode: TileMode.decal),
              child: word,
            ),
    );
  }
}
