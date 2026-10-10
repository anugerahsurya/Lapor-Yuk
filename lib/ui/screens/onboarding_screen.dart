import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/location_service.dart';
import '../../services/reminder_service.dart';
import '../../state/providers.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';
import 'greeting_screen.dart';

/// First-run setup so anyone can use the app: welcome → personal data →
/// avatar → permissions. Everything stays on the device.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _step = 0;
  static const _steps = 4;

  final _name = TextEditingController();
  final _nip = TextEditingController();
  final _position = TextEditingController();
  final _unit = TextEditingController();
  final _agency = TextEditingController(text: 'Badan Pusat Statistik');
  final _city = TextEditingController();
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    final p = ref.read(settingsProvider).profile;
    if (p.name.isNotEmpty) _name.text = p.name;
    _nip.text = p.nip;
    _position.text = p.position;
    _unit.text = p.unit;
    if (p.agency.isNotEmpty) _agency.text = p.agency;
    _city.text = p.city;
    for (final c in [_name, _unit]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _page.dispose();
    for (final c in [_name, _nip, _position, _unit, _agency, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _dataValid => _name.text.trim().isNotEmpty && _unit.text.trim().isNotEmpty;

  void _go(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    _page.animateToPage(step, duration: const Duration(milliseconds: 480), curve: Curves.easeOutCubic);
  }

  void _next() {
    if (_step == 1) {
      setState(() => _tried = true);
      if (!_dataValid) {
        HapticFeedback.heavyImpact();
        return;
      }
      ref
          .read(settingsProvider.notifier)
          .setProfile(
            Profile(
              name: _name.text.trim().replaceAll(RegExp(r'\s+'), ' '),
              nip: _nip.text.replaceAll(RegExp(r'\s'), ''),
              position: _position.text.trim(),
              unit: _unit.text.trim(),
              agency: _agency.text.trim(),
              city: _city.text.trim(),
            ),
          );
    }
    if (_step < _steps - 1) {
      _go(_step + 1);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await ref.read(settingsProvider.notifier).finishOnboarding();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(fadeRoute(const GreetingScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  AnimatedOpacity(
                    duration: Motion.fast,
                    opacity: _step > 0 ? 1 : 0,
                    child: IconBtn(icon: Icons.arrow_back_rounded, onTap: _step > 0 ? () => _go(_step - 1) : null),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 0; i < _steps; i++)
                          Expanded(
                            child: AnimatedContainer(
                              duration: Motion.base,
                              curve: Motion.ease,
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: i <= _step ? c.brand : c.line,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 56),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  const _Welcome(),
                  _DataStep(
                    name: _name,
                    nip: _nip,
                    position: _position,
                    unit: _unit,
                    agency: _agency,
                    city: _city,
                    tried: _tried,
                  ),
                  const _AvatarStep(),
                  const _PermissionStep(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: AppButton(
                label: switch (_step) {
                  0 => 'Mulai',
                  3 => 'Selesai, masuk aplikasi',
                  _ => 'Lanjut',
                },
                icon: _step == 3 ? Icons.check_rounded : Icons.arrow_forward_rounded,
                expand: true,
                onTap: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget point(int i, IconData icon, String title, String sub) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: c.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.t.titleSmall),
                Text(sub, style: context.t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: (300 + 90 * i).ms, duration: 400.ms).slideX(begin: .08, end: 0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      children: [
        const LogoTile(size: 72).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
        const SizedBox(height: 22),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Selamat datang di\n'),
              TextSpan(
                text: 'Lapor Yuk',
                style: TextStyle(color: c.primary),
              ),
            ],
          ),
          style: context.t.displaySmall,
        ).animate().fadeIn(delay: 120.ms).slideY(begin: .2, end: 0),
        const SizedBox(height: 10),
        Text(
          'Catat kegiatan harian, kumpulkan bukti dukung, dan siapkan laporan kinerja bulanan dalam satu aplikasi.',
          style: context.t.bodyLarge!.copyWith(color: c.muted),
        ).animate().fadeIn(delay: 200.ms),
        const SizedBox(height: 26),
        point(
          0,
          Icons.edit_calendar_rounded,
          'Lapor kegiatan harian',
          'Capaian terisi otomatis, periode tunggal atau rentang',
        ),
        point(1, Icons.photo_camera_rounded, 'Foto ber-watermark', 'Nama, waktu, lokasi, dan geotag langsung di foto'),
        point(2, Icons.picture_as_pdf_rounded, 'Rekap PDF bulanan', 'Siap ditandatangani dan dilaporkan'),
        if (Env.googleReady)
          point(3, Icons.cloud_upload_rounded, 'Sinkron Google Drive', 'Link bukti dukung siap disalin untuk SKP'),
        point(4, Icons.wifi_off_rounded, 'Bekerja tanpa internet', 'Semua data tersimpan di HP-mu'),
      ],
    );
  }
}

class _DataStep extends StatelessWidget {
  const _DataStep({
    required this.name,
    required this.nip,
    required this.position,
    required this.unit,
    required this.agency,
    required this.city,
    required this.tried,
  });

  final TextEditingController name, nip, position, unit, agency, city;
  final bool tried;

  @override
  Widget build(BuildContext context) {
    Widget field(
      TextEditingController c,
      String label,
      String hint, {
      bool required = false,
      TextInputType? type,
      TextCapitalization cap = TextCapitalization.words,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: type,
        textCapitalization: cap,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hint,
          errorText: tried && required && c.text.trim().isEmpty ? '$label wajib diisi' : null,
        ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      children: [
        Text('Kenalan dulu, yuk', style: context.t.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'Data ini dipakai di watermark foto, rekap PDF, dan nama folder Google Drive. Hanya tersimpan di HP-mu.',
          style: context.t.bodyMedium!.copyWith(color: context.c.muted),
        ),
        const SizedBox(height: 22),
        field(name, 'Nama lengkap', 'Sesuai SK / tanda tangan', required: true),
        field(nip, 'NIP', '18 digit', type: TextInputType.number, cap: TextCapitalization.none),
        field(position, 'Jabatan', 'Contoh: Statistisi Ahli Pertama'),
        field(unit, 'Satuan kerja', 'Contoh: BPS Kabupaten Agam', required: true),
        field(agency, 'Instansi (kop rekap)', 'Contoh: Badan Pusat Statistik'),
        field(city, 'Kota penandatanganan', 'Contoh: Padang'),
      ],
    );
  }
}

class _AvatarStep extends ConsumerWidget {
  const _AvatarStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final current = ref.watch(settingsProvider.select((s) => s.avatar));
    final name = ref.watch(settingsProvider.select((s) => s.profile.firstName));
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      children: [
        Text('Pilih avatarmu, $name', style: context.t.headlineMedium),
        const SizedBox(height: 6),
        Text('Bisa diganti kapan saja di Profil.', style: context.t.bodyMedium!.copyWith(color: c.muted)),
        const SizedBox(height: 22),
        Center(
          child: const Avatar(size: 112).animate(key: ValueKey(current)).scale(curve: Curves.easeOutBack),
        ),
        const SizedBox(height: 22),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            for (final a in avatars)
              Pressable(
                onTap: () => ref.read(settingsProvider.notifier).setAvatar(a),
                scale: .9,
                child: AnimatedContainer(
                  duration: Motion.base,
                  padding: EdgeInsets.all(a == current ? 4 : 0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: a == current ? c.brand : Colors.transparent, width: 3),
                  ),
                  child: ClipOval(child: Image.asset(avatarAsset(a), fit: BoxFit.cover, cacheWidth: 240)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PermissionStep extends ConsumerStatefulWidget {
  const _PermissionStep();

  @override
  ConsumerState<_PermissionStep> createState() => _PermissionStepState();
}

class _PermissionStepState extends ConsumerState<_PermissionStep> {
  final _granted = <String>{};

  Future<void> _ask(String key, Future<bool> Function() request) async {
    final ok = await request();
    if (ok && mounted) setState(() => _granted.add(key));
  }

  @override
  Widget build(BuildContext context) {
    final storage = ref.read(repoProvider).storage;
    Widget tile(String key, IconData icon, String title, String sub, Future<bool> Function() request) {
      final c = context.c;
      final done = _granted.contains(key);
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(
          onTap: done ? null : () => _ask(key, request),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: done ? c.success.withValues(alpha: .14) : c.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(done ? Icons.check_rounded : icon, color: done ? c.success : c.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.t.titleSmall),
                    Text(sub, style: context.t.bodySmall),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: Motion.base,
                child: done
                    ? Tag('Aktif', key: const ValueKey(1), color: c.success)
                    : Tag('Izinkan', key: const ValueKey(0), color: c.primary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      children: [
        Text('Satu langkah lagi', style: context.t.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'Izinkan fitur berikut supaya Lapor Yuk bekerja penuh. Bisa juga dilewati dan diatur nanti.',
          style: context.t.bodyMedium!.copyWith(color: context.c.muted),
        ),
        const SizedBox(height: 22),
        tile(
          'notif',
          Icons.notifications_active_rounded,
          'Notifikasi',
          'Pengingat harian & tugas To Do',
          ReminderService.requestPermission,
        ),
        tile(
          'loc',
          Icons.location_on_rounded,
          'Lokasi',
          'Geotag & alamat di foto bukti',
          LocationService.ensurePermission,
        ),
        tile(
          'files',
          Icons.folder_rounded,
          'Akses folder',
          'Simpan bukti ke folder "Lapor Yuk" di HP',
          storage.requestPublicAccess,
        ),
      ],
    );
  }
}

/// Plain cross-fade, used between setup / greeting / app.
Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 600),
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (_, a, _, child) => FadeTransition(
    opacity: CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
    child: child,
  ),
);
