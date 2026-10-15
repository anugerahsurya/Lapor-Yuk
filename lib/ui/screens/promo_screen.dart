import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../state/providers.dart';
import '../widgets/common.dart';

/// Plays the 30 s promo video (assets/video/promo.mp4, 9:16). After the
/// first-run setup it plays once and then continues to [next]; from Beranda
/// it simply closes when done.
class PromoVideoScreen extends ConsumerStatefulWidget {
  const PromoVideoScreen({super.key, this.next});
  final Widget? next;

  @override
  ConsumerState<PromoVideoScreen> createState() => _PromoVideoScreenState();
}

class _PromoVideoScreenState extends ConsumerState<PromoVideoScreen> {
  final _video = VideoPlayerController.asset('assets/video/promo.mp4');
  bool _ready = false;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    ref.read(settingsProvider.notifier).markPromoSeen();
    _video.addListener(_tick);
    _video.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _video.play();
    }, onError: (_) => _leave());
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _video
      ..removeListener(_tick)
      ..dispose();
    super.dispose();
  }

  void _tick() {
    final v = _video.value;
    if (v.isInitialized && !v.isPlaying && v.position >= v.duration) {
      _leave();
    } else if (mounted) {
      setState(() {});
    }
  }

  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    final next = widget.next;
    if (next != null) {
      Navigator.of(context).pushReplacement(softRoute(next));
    } else {
      Navigator.of(context).pop();
    }
  }

  void _toggle() => _video.value.isPlaying ? _video.pause() : _video.play();

  @override
  Widget build(BuildContext context) {
    final v = _video.value;
    final progress = v.duration.inMilliseconds == 0 ? 0.0 : v.position.inMilliseconds / v.duration.inMilliseconds;
    return PopScope(
      canPop: widget.next == null,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: _ready ? _toggle : null,
              child: Center(
                child: _ready
                    ? AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_video))
                    : const CircularProgressIndicator(color: Colors.white),
              ),
            ),
            if (_ready && !v.isPlaying && progress < 1)
              const IgnorePointer(
                child: Center(child: Icon(Icons.play_circle_fill_rounded, size: 84, color: Colors.white70)),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 3,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        IconBtn(
                          icon: v.volume > 0 ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                          tooltip: 'Suara',
                          color: Colors.white,
                          bg: Colors.black38,
                          onTap: () => _video.setVolume(v.volume > 0 ? 0 : 1),
                        ),
                        const Spacer(),
                        Pressable(
                          onTap: _leave,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                            decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20)),
                            child: Text(
                              widget.next != null ? 'Lewati' : 'Tutup',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
