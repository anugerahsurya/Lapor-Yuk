import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../widgets/common.dart';
import 'activities_screen.dart';
import 'kinerja_overview.dart';
import 'rekap_screen.dart';

/// Kinerja (CKP) module: Ringkasan · Kegiatan · Rekap.
/// [tab] lets the hub open a specific tab.
class KinerjaScreen extends StatefulWidget {
  const KinerjaScreen({super.key, required this.tab, required this.onReport});

  final ValueNotifier<int> tab;
  final void Function([DateTime? day]) onReport;

  @override
  State<KinerjaScreen> createState() => _KinerjaScreenState();
}

class _KinerjaScreenState extends State<KinerjaScreen> {
  static const _tabs = ['Ringkasan', 'Kegiatan', 'Rekap'];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pages = [KinerjaOverview(onReport: widget.onReport), const ActivitiesScreen(), const RekapScreen()];
    return ValueListenableBuilder<int>(
      valueListenable: widget.tab,
      builder: (context, index, _) => Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(color: c.brand, borderRadius: BorderRadius.circular(13)),
                        child: Icon(Icons.insights_rounded, color: c.onBrand, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Kinerja', style: context.t.headlineSmall),
                            Text('Capaian Kinerja Pegawai (CKP)', style: context.t.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _Tabs(labels: _tabs, index: index, onChanged: (i) => widget.tab.value = i),
                ],
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                for (var i = 0; i < pages.length; i++)
                  IgnorePointer(
                    ignoring: i != index,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 240),
                      opacity: i == index ? 1 : 0,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        offset: i == index ? Offset.zero : Offset(0, .02),
                        child: TickerMode(enabled: i == index, child: pages[i]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(15)),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / labels.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: Motion.base,
                curve: Motion.ease,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  decoration: BoxDecoration(
                    color: c.brand,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: c.brand.withValues(alpha: .3), blurRadius: 10, offset: const Offset(0, 3)),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: Pressable(
                        onTap: () => onChanged(i),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: Motion.fast,
                            style: context.t.labelLarge!.copyWith(
                              color: i == index ? c.onBrand : c.muted,
                              fontSize: 13.5,
                            ),
                            child: Text(labels[i]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
