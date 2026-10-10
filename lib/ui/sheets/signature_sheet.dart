import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../../core/theme.dart';
import '../widgets/common.dart';

/// Signature is drawn fresh for every export, as the act of approval.
Future<Uint8List?> askSignature(BuildContext context, {required String name}) {
  return showModalBottomSheet<Uint8List>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    enableDrag: false, // dragging would fight with drawing
    builder: (_) => _SignatureSheet(name: name),
  );
}

class _SignatureSheet extends StatefulWidget {
  const _SignatureSheet({required this.name});
  final String name;

  @override
  State<_SignatureSheet> createState() => _SignatureSheetState();
}

class _SignatureSheetState extends State<_SignatureSheet> {
  late final _ctl = SignatureController(
    penStrokeWidth: 3,
    penColor: const Color(0xFF16181D),
    exportPenColor: Colors.black,
    exportBackgroundColor: Colors.transparent,
    strokeCap: StrokeCap.round,
    strokeJoin: StrokeJoin.round,
    onDrawEnd: () => setState(() {}),
  );

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tanda tangan pengesahan', style: context.t.headlineSmall),
            const SizedBox(height: 4),
            Text('Bubuhkan tanda tangan untuk mengesahkan rekap ini.', style: context.t.bodySmall),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  // Always a light pad so the ink matches what lands on paper.
                  color: const Color(0xFFFBFAF7),
                  border: Border.all(color: c.line),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 48,
                      child: Container(height: 1, color: const Color(0xFFCFCBC0)),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 22,
                      child: Text(
                        widget.name.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: kFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF9A968B),
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    if (_ctl.isEmpty)
                      const Center(
                        child: Text(
                          'Tanda tangan di sini',
                          style: TextStyle(fontFamily: kFont, color: Color(0xFFB5B1A6), fontWeight: FontWeight.w500),
                        ),
                      ),
                    Signature(controller: _ctl, backgroundColor: Colors.transparent, height: 220),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Ulangi',
                    icon: Icons.refresh_rounded,
                    style: BtnStyle.ghost,
                    onTap: () => setState(_ctl.clear),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: AppButton(
                    label: 'Sahkan & unduh',
                    icon: Icons.verified_rounded,
                    onTap: _ctl.isEmpty
                        ? null
                        : () async {
                            final png = await _ctl.toPngBytes();
                            if (context.mounted) Navigator.pop(context, png);
                          },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
