import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/dates.dart';
import '../../core/theme.dart';
import '../../services/chat_service.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';

/// Long side 1280 px, JPEG. Quality steps down until the file fits the
/// 1 MB bucket limit; most phone photos end up around 150-300 KB.
Future<Uint8List> compressStory(String path) async {
  for (final q in const [72, 60, 45]) {
    final out = await FlutterImageCompress.compressWithFile(path, minWidth: 1280, minHeight: 1280, quality: q);
    if (out == null) break;
    if (out.length < 900 * 1024) return out;
  }
  throw StateError('Foto tidak bisa dikompres');
}

String fmtSize(int bytes) =>
    bytes >= 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';

/// Full-screen camera for stories; the gallery button picks an existing photo.
class StoryCameraScreen extends StatefulWidget {
  const StoryCameraScreen({super.key});

  @override
  State<StoryCameraScreen> createState() => _StoryCameraScreenState();
}

class _StoryCameraScreenState extends State<StoryCameraScreen> with WidgetsBindingObserver {
  CameraController? _cam;
  List<CameraDescription> _cams = const [];
  int _camIndex = 0;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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

  Future<void> _init() async {
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
    // "high" (720p-1080p) is plenty for a story and keeps the shot quick.
    final cam = CameraController(d, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    _cam = cam;
    await old?.dispose();
    try {
      await cam.initialize();
      if (mounted) setState(() {});
    } on CameraException catch (e) {
      if (mounted) setState(() => _error = e.description ?? e.code);
    }
  }

  Future<void> _flip() async {
    if (_cams.length < 2) return;
    _camIndex = (_camIndex + 1) % _cams.length;
    await _start(_cams[_camIndex]);
  }

  Future<void> _shoot() async {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized || _busy) return;
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      final shot = await cam.takePicture();
      await _compose(shot.path, temp: true);
    } catch (e) {
      if (mounted) toast(context, 'Gagal mengambil foto: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _gallery() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) await _compose(picked.path);
  }

  Future<void> _compose(String path, {bool temp = false}) async {
    final posted = await Navigator.of(context).push<bool>(softRoute(StoryComposeScreen(path: path)));
    if (temp) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    if (posted == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    final ready = cam != null && cam.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: cam.value.previewSize!.height,
                  height: cam.value.previewSize!.width,
                  child: CameraPreview(cam),
                ),
              ),
            )
          else
            Center(
              child: _error == null
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
            ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      IconBtn(
                        icon: Icons.close_rounded,
                        color: Colors.white,
                        bg: Colors.black38,
                        onTap: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      const Text(
                        'Story · tampil 24 jam',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      const SizedBox(width: 44),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconBtn(
                        icon: Icons.photo_library_rounded,
                        tooltip: 'Galeri',
                        color: Colors.white,
                        bg: Colors.black38,
                        onTap: _busy ? null : _gallery,
                      ),
                      Pressable(
                        onTap: ready && !_busy ? _shoot : null,
                        scale: .88,
                        child: Container(
                          width: 76,
                          height: 76,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _busy ? Colors.white54 : Colors.white,
                            ),
                          ),
                        ),
                      ),
                      IconBtn(
                        icon: Icons.cameraswitch_rounded,
                        tooltip: 'Ganti kamera',
                        color: Colors.white,
                        bg: Colors.black38,
                        onTap: _cams.length < 2 || _busy ? null : _flip,
                      ),
                    ],
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

/// Shows the compressed result (what other users will see), takes an
/// optional caption, then uploads. Pops true once posted.
class StoryComposeScreen extends StatefulWidget {
  const StoryComposeScreen({super.key, required this.path});
  final String path;

  @override
  State<StoryComposeScreen> createState() => _StoryComposeScreenState();
}

class _StoryComposeScreenState extends State<StoryComposeScreen> {
  final _caption = TextEditingController();
  Uint8List? _jpeg;
  int _original = 0;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      _original = await File(widget.path).length();
      final out = await compressStory(widget.path);
      if (mounted) setState(() => _jpeg = out);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _post() async {
    if (_jpeg == null || _sending) return;
    setState(() => _sending = true);
    try {
      await ChatService.postStory(_jpeg!, caption: _caption.text);
      if (mounted) {
        toast(context, 'Story terkirim. Hilang otomatis setelah 24 jam.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) toast(context, 'Gagal mengirim story: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jpeg = _jpeg;
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (jpeg != null)
            Image.memory(jpeg, fit: BoxFit.contain)
          else
            Center(
              child: _error == null
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 14),
                        Text('Mengompres foto…', style: TextStyle(color: Colors.white70)),
                      ],
                    )
                  : Text(_error!, style: const TextStyle(color: Colors.white)),
            ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      IconBtn(
                        icon: Icons.arrow_back_rounded,
                        color: Colors.white,
                        bg: Colors.black38,
                        onTap: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      if (jpeg != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                          child: Text(
                            '${fmtSize(_original)} → ${fmtSize(jpeg.length)}',
                            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _caption,
                          maxLength: 200,
                          minLines: 1,
                          maxLines: 3,
                          style: const TextStyle(color: Colors.white),
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Tambah keterangan…',
                            hintStyle: TextStyle(color: Colors.white60),
                            counterText: '',
                            filled: true,
                            fillColor: Colors.white12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Pressable(
                        onTap: jpeg == null || _sending ? null : _post,
                        scale: .85,
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(color: context.c.brand, shape: BoxShape.circle),
                          child: _sending
                              ? Padding(
                                  padding: const EdgeInsets.all(15),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: context.c.onBrand),
                                )
                              : Icon(Icons.send_rounded, color: context.c.onBrand, size: 21),
                        ),
                      ),
                    ],
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

/// Plays one person's stories in order, 6 seconds each. Tap right/left to
/// skip, hold to pause.
class StoryViewer extends StatefulWidget {
  const StoryViewer({super.key, required this.stories, required this.name, this.avatar, this.people = const {}});
  final List<Story> stories;
  final String name;
  final String? avatar;

  /// For the names in "Dilihat oleh".
  final Map<String, ChatProfile> people;

  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(seconds: 6))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
  int _i = 0;
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();
  final _viewerStreams = <int, Stream<List<(String, DateTime)>>>{};
  bool _sendingReply = false;

  @override
  void initState() {
    super.initState();
    // Typing a reply pauses the story.
    _replyFocus.addListener(() => _replyFocus.hasFocus ? _anim.stop() : _anim.forward());
    _load();
  }

  @override
  void dispose() {
    _anim.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  // Timer starts once the photo is on screen, not while it downloads.
  void _load() {
    _anim
      ..stop()
      ..value = 0;
    final i = _i;
    void go() {
      if (!mounted || _i != i) return;
      ChatService.markViewed(widget.stories[i]);
      if (!_replyFocus.hasFocus) _anim.forward();
    }

    NetworkImage(widget.stories[i].url)
        .resolve(const ImageConfiguration())
        .addListener(ImageStreamListener((_, _) => go(), onError: (_, _) => go()));
  }

  void _next() {
    if (_i + 1 >= widget.stories.length) {
      Navigator.pop(context);
      return;
    }
    setState(() => _i++);
    _load();
  }

  void _prev() {
    if (_i == 0) {
      _anim.forward(from: 0);
      return;
    }
    setState(() => _i--);
    _load();
  }

  Future<void> _delete() async {
    _anim.stop();
    final ok = await confirmSheet(
      context,
      title: 'Hapus story?',
      message: 'Story ini akan hilang untuk semua pengguna.',
      confirm: 'Hapus',
      danger: true,
    );
    if (!ok) {
      _anim.forward();
      return;
    }
    try {
      await ChatService.deleteStory(widget.stories[_i]);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, 'Gagal menghapus: $e', icon: Icons.error_outline_rounded);
    }
  }

  Stream<List<(String, DateTime)>> _viewersOf(Story s) => _viewerStreams[s.id] ??= ChatService.viewers(s.id);

  Widget _viewersButton(Story s) => StreamBuilder<List<(String, DateTime)>>(
    stream: _viewersOf(s),
    builder: (context, snap) {
      final list = snap.data ?? const <(String, DateTime)>[];
      return TextButton.icon(
        onPressed: () => _showViewers(list),
        icon: const Icon(Icons.visibility_outlined, color: Colors.white),
        label: Text(
          list.isEmpty ? 'Belum ada yang melihat' : 'Dilihat ${list.length} orang',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      );
    },
  );

  Future<void> _showViewers(List<(String, DateTime)> list) async {
    if (list.isEmpty) return;
    _anim.stop();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            SectionLabel('Dilihat oleh · ${list.length}'),
            for (final (id, at) in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ClipOval(
                  child: Image.asset(
                    avatarAsset(avatars.contains(widget.people[id]?.avatar) ? widget.people[id]!.avatar! : 'sun'),
                    width: 36,
                    height: 36,
                    cacheWidth: 108,
                  ),
                ),
                title: Text(widget.people[id]?.name ?? 'Pengguna'),
                trailing: Text(
                  sameDay(at, DateTime.now()) ? fmtTime(at) : '${fmtDateShort(at)} ${fmtTime(at)}',
                  style: ctx.t.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
    if (mounted) _anim.forward();
  }

  Widget _replyBox(Story s) => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _reply,
          focusNode: _replyFocus,
          minLines: 1,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Balas ${widget.name}…',
            hintStyle: const TextStyle(color: Colors.white60),
            filled: true,
            fillColor: Colors.white12,
          ),
          onSubmitted: (_) => _sendReply(s),
        ),
      ),
      const SizedBox(width: 8),
      IconButton(
        onPressed: _sendingReply ? null : () => _sendReply(s),
        icon: const Icon(Icons.send_rounded, color: Colors.white),
      ),
    ],
  );

  /// Story replies go to a DM with the author, with a thumbnail of the story.
  Future<void> _sendReply(Story s) async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sendingReply) return;
    setState(() => _sendingReply = true);
    try {
      await ChatService.send(ChatService.dmRoom(s.author), text, storyPath: s.path);
      _reply.clear();
      _replyFocus.unfocus();
      if (mounted) toast(context, 'Balasan terkirim ke chat ${widget.name}');
    } catch (e) {
      if (mounted) toast(context, 'Gagal mengirim: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _sendingReply = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stories[_i];
    final mine = s.author == ChatService.uid;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (d) => d.globalPosition.dx < MediaQuery.sizeOf(context).width / 3 ? _prev() : _next(),
        onLongPressStart: (_) => _anim.stop(),
        onLongPressEnd: (_) => _anim.forward(),
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              s.url,
              key: ValueKey(s.id),
              fit: BoxFit.contain,
              loadingBuilder: (_, child, p) =>
                  p == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
              errorBuilder: (_, _, _) => const Center(
                child: Text('Foto tidak bisa dimuat', style: TextStyle(color: Colors.white70)),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (var k = 0; k < widget.stories.length; k++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: AnimatedBuilder(
                                animation: _anim,
                                builder: (_, _) => LinearProgressIndicator(
                                  value: k < _i ? 1 : (k == _i ? _anim.value : 0),
                                  minHeight: 2.5,
                                  borderRadius: BorderRadius.circular(2),
                                  color: Colors.white,
                                  backgroundColor: Colors.white30,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ClipOval(
                          child: Image.asset(
                            avatarAsset(avatars.contains(widget.avatar) ? widget.avatar! : 'sun'),
                            width: 36,
                            height: 36,
                            cacheWidth: 108,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mine ? 'Story kamu' : widget.name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                sameDay(s.at, DateTime.now())
                                    ? fmtTime(s.at)
                                    : '${fmtDateShort(s.at)} ${fmtTime(s.at)}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        if (mine)
                          IconButton(
                            onPressed: _delete,
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                          ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black54,
                padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if ((s.caption ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          s.caption!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                        ),
                      ),
                    if (mine) _viewersButton(s) else _replyBox(s),
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
