import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../../services/location_service.dart';
import '../../services/watermark.dart';
import '../widgets/common.dart';

/// Full-screen 3:4 camera with a live preview of the timestamp stamp.
///
/// Report mode pops with a staged [Evidence] (already stamped) or null.
/// [quick] mode saves each shot straight to "Foto tersimpan" and the month
/// folder, and stays open for the next shot.
class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key, this.quick = false});

  final bool quick;

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> with WidgetsBindingObserver {
  CameraController? _cam;
  List<CameraDescription> _cams = const [];
  int _camIndex = 0;
  FlashMode _flash = FlashMode.off;
  String? _error;
  bool _busy = false;
  bool _flashFx = false;
  int _saved = 0;
  String? _lastShot;

  Position? _pos;
  String? _address;
  bool _locDenied = false;
  StreamSubscription<Position>? _posSub;
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
    _initCamera();
    _initLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _clock?.cancel();
    _posSub?.cancel();
    _cam?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      cam.dispose();
      _cam = null;
    } else if (state == AppLifecycleState.resumed) {
      _start(_cams[_camIndex]);
    }
  }

  Future<void> _initCamera() async {
    try {
      _cams = await availableCameras();
      if (_cams.isEmpty) throw CameraException('none', 'Kamera tidak ditemukan');
      _camIndex = _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back).clamp(0, _cams.length - 1);
      await _start(_cams[_camIndex]);
    } on CameraException catch (e) {
      setState(
        () => _error = e.code == 'CameraAccessDenied'
            ? 'Izin kamera ditolak. Aktifkan di Pengaturan > Aplikasi > Lapor Yuk.'
            : (e.description ?? e.code),
      );
    }
  }

  Future<void> _start(CameraDescription d) async {
    final old = _cam;
    final cam = CameraController(d, ResolutionPreset.max, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    _cam = cam;
    await old?.dispose();
    try {
      await cam.initialize();
      await cam.setFlashMode(_flash);
      if (mounted) setState(() {});
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = e.description ?? e.code);
    }
  }

  Future<void> _initLocation() async {
    if (!await LocationService.ensurePermission()) {
      if (mounted) setState(() => _locDenied = true);
      return;
    }
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && mounted) setState(() => _pos = last);
    _posSub = LocationService.stream().listen((p) async {
      final first = _pos == null || _address == null;
      if (mounted) setState(() => _pos = p);
      if (first) {
        ref.read(settingsProvider.notifier).setLocation(p.latitude, p.longitude);
        final a = await LocationService.address(p.latitude, p.longitude);
        if (a != null && mounted) setState(() => _address = a);
      }
    });
  }

  StampData _stamp(DateTime t) => StampData(
    name: ref.read(settingsProvider).profile.name,
    time: t,
    lat: _pos?.latitude,
    lng: _pos?.longitude,
    accuracy: _pos?.accuracy,
    address: _address,
  );

  Future<void> _shoot() async {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized || _busy) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _busy = true;
      _flashFx = true;
    });
    Future.delayed(const Duration(milliseconds: 120), () => mounted ? setState(() => _flashFx = false) : null);
    try {
      final shot = await cam.takePicture();
      final storage = ref.read(repoProvider).storage;
      final t = DateTime.now();
      final raw = storage.newStagingPath('jpg');
      await File(shot.path).copy(raw);
      try {
        await File(shot.path).delete();
      } catch (_) {}
      final data = _stamp(t);
      final mirror = cam.description.lensDirection == CameraLensDirection.front;
      final out = await renderStamped(rawPath: raw, outPath: storage.newStagingPath('jpg'), data: data, mirror: mirror);
      final keepRaw = data.address == null && data.lat != null;
      if (!keepRaw) await File(raw).delete();
      final ev = Evidence(
        kind: EvidenceKind.camera,
        name: 'Foto ${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}',
        masterPath: out,
        rawPath: keepRaw ? raw : null,
        lat: data.lat,
        lng: data.lng,
        accuracy: data.accuracy,
        address: data.address,
        author: data.name,
        mirrored: mirror,
        capturedAt: t,
      );
      if (!mounted) return;
      final ok = await Navigator.of(context).push<bool>(softRoute(_Review(path: out, quick: widget.quick)));
      if (ok == true && widget.quick) {
        final saved = await ref.read(repoProvider).saveLoose(ev);
        ref.invalidate(looseProvider);
        if (!mounted) return;
        setState(() {
          _saved++;
          _lastShot = saved.masterPath;
        });
        toast(context, 'Tersimpan di Foto tersimpan & folder Lapor Yuk');
      } else if (ok == true) {
        if (mounted) Navigator.pop(context, ev);
      } else {
        await ref.read(repoProvider).storage.deleteAll([out, ev.rawPath]);
      }
    } catch (e) {
      if (mounted) toast(context, 'Gagal mengambil foto: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleFlash() {
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    setState(() => _flash = next);
    _cam?.setFlashMode(next);
  }

  void _switch() {
    if (_cams.length < 2) return;
    _camIndex = (_camIndex + 1) % _cams.length;
    _start(_cams[_camIndex]);
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    Widget preview;
    if (_error != null) {
      preview = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontFamily: kFont),
          ),
        ),
      );
    } else if (cam != null && cam.value.isInitialized) {
      preview = Stack(
        fit: StackFit.expand,
        children: [
          // Sensor frame scaled to cover the 3:4 window (the saved photo is
          // cropped the same way).
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(width: 300, height: 300 * cam.value.aspectRatio, child: CameraPreview(cam)),
          ),
          // Live stamp – same painter as the saved photo.
          CustomPaint(painter: _StampPainter(_stamp(_now))),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _flashFx ? 1 : 0,
              duration: const Duration(milliseconds: 100),
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ],
      );
    } else {
      preview = const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Row(
                children: [
                  _Round(icon: Icons.close_rounded, onTap: () => Navigator.pop(context)),
                  const Spacer(),
                  _LocPill(pos: _pos, address: _address, denied: _locDenied),
                  const Spacer(),
                  _Round(
                    icon: switch (_flash) {
                      FlashMode.auto => Icons.flash_auto_rounded,
                      FlashMode.always => Icons.flash_on_rounded,
                      _ => Icons.flash_off_rounded,
                    },
                    onTap: _toggleFlash,
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: ColoredBox(color: const Color(0xFF0B0B0B), child: preview),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.quick
                        ? (_saved == 0 ? 'KAMERA CEPAT · 3:4' : 'KAMERA CEPAT · $_saved FOTO TERSIMPAN')
                        : 'FOTO BUKTI DUKUNG · 3:4',
                    style: TextStyle(
                      fontFamily: kFont,
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: .6),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Last quick shot (tap = done), or a spacer.
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: AnimatedSwitcher(
                          duration: Motion.base,
                          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                          child: _lastShot == null
                              ? const SizedBox.shrink()
                              : Pressable(
                                  key: ValueKey(_lastShot),
                                  onTap: () => Navigator.pop(context),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white, width: 2),
                                      image: DecorationImage(
                                        image: ResizeImage(FileImage(File(_lastShot!)), width: 150),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      Pressable(
                        onTap: _busy ? null : _shoot,
                        scale: .88,
                        haptic: false,
                        child: AnimatedContainer(
                          duration: Motion.base,
                          width: 78,
                          height: 78,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: AnimatedContainer(
                            duration: Motion.base,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _busy ? const Color(0xFF2F5FEA) : Colors.white,
                            ),
                            child: _busy
                                ? const Padding(
                                    padding: EdgeInsets.all(22),
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                  )
                                : null,
                          ),
                        ),
                      ),
                      _Round(icon: Icons.cameraswitch_rounded, onTap: _cams.length > 1 ? _switch : null),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StampPainter extends CustomPainter {
  _StampPainter(this.data);
  final StampData data;

  @override
  void paint(Canvas canvas, Size size) => paintStamp(canvas, size, data);

  @override
  bool shouldRepaint(_StampPainter old) =>
      old.data.time.second != data.time.second || old.data.lat != data.lat || old.data.address != data.address;
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    scale: .85,
    child: Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .4), shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white),
    ),
  );
}

class _LocPill extends StatelessWidget {
  const _LocPill({required this.pos, required this.address, required this.denied});
  final Position? pos;
  final String? address;
  final bool denied;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = denied
        ? (Icons.location_disabled_rounded, 'Lokasi nonaktif', const Color(0xFFF07167))
        : pos == null
        ? (Icons.gps_not_fixed_rounded, 'Mencari GPS…', Colors.white)
        : address == null
        ? (Icons.gps_fixed_rounded, 'GPS ±${pos!.accuracy.round()} m · offline', const Color(0xFFF2B35A))
        : (Icons.gps_fixed_rounded, 'GPS ±${pos!.accuracy.round()} m', const Color(0xFF4CC08D));
    return AnimatedContainer(
      duration: Motion.base,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .45), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontFamily: kFont, color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.path, this.quick = false});
  final String path;
  final bool quick;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(child: Center(child: Image.file(File(path)))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Pressable(
                      onTap: () => Navigator.pop(context, false),
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          'Ulangi',
                          style: TextStyle(fontFamily: kFont, color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Pressable(
                      onTap: () => Navigator.pop(context, true),
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2F5FEA),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          quick ? 'Simpan foto' : 'Gunakan foto',
                          style: const TextStyle(fontFamily: kFont, color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
