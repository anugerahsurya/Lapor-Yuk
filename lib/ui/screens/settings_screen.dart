import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme.dart';
import '../../core/dates.dart';
import '../../data/models.dart';
import '../../core/env.dart';
import '../../services/reminder_service.dart';
import '../../state/providers.dart';
import '../widgets/avatar.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with WidgetsBindingObserver {
  bool? _access;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Returning from the system "All files access" page.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAccess();
  }

  Future<void> _checkAccess() async {
    final v = await ref.read(repoProvider).storage.hasPublicAccess();
    if (mounted) setState(() => _access = v);
  }

  Future<void> _requestNotif() async {
    final status = await Permission.notification.request();
    if (!mounted) return;
    if (status.isGranted) {
      toast(context, 'Izin notifikasi aktif');
    } else {
      toast(
        context,
        'Izin notifikasi masih mati. Nyalakan lewat Pengaturan aplikasi.',
        icon: Icons.notifications_off_rounded,
      );
    }
  }

  Future<void> _editProfile() async {
    final p = ref.read(settingsProvider).profile;
    final updated = await showModalBottomSheet<Profile>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProfileSheet(profile: p),
    );
    if (updated != null) {
      ref.read(settingsProvider.notifier).setProfile(updated);
      if (mounted) toast(context, 'Profil diperbarui');
    }
  }

  Future<void> _resync() async {
    setState(() => _syncing = true);
    final n = await ref.read(repoProvider).resyncPublic();
    await ref.read(activitiesProvider.notifier).reload();
    if (!mounted) return;
    setState(() => _syncing = false);
    toast(context, '$n berkas disalin ke folder Lapor Yuk');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ref.watch(settingsProvider);
    final p = s.profile;
    final storage = ref.read(repoProvider).storage;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 130),
        physics: const BouncingScrollPhysics(),
        children: [
          Text('Profil', style: context.t.headlineMedium),
          const SizedBox(height: 18),
          AppCard(
            onTap: _editProfile,
            child: Row(
              children: [
                Pressable(
                  onTap: () => pickAvatar(context, ref),
                  scale: .9,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Avatar(size: 60),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: c.brand,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.surface, width: 2),
                          ),
                          child: Icon(Icons.swap_horiz_rounded, size: 13, color: c.onBrand),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: context.t.titleMedium),
                      Text('NIP ${p.nip}', style: context.t.bodySmall),
                      Text('${p.position} · ${p.unit}', style: context.t.bodySmall),
                    ],
                  ),
                ),
                Icon(Icons.edit_outlined, color: c.muted, size: 20),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('Tampilan'),
          AppCard(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                for (final (t, icon, label) in [
                  (ThemePref.auto, Icons.brightness_auto_rounded, 'Otomatis'),
                  (ThemePref.light, Icons.light_mode_rounded, 'Terang'),
                  (ThemePref.dark, Icons.dark_mode_rounded, 'Gelap'),
                ])
                  Expanded(
                    child: Pressable(
                      onTap: () => ref.read(settingsProvider.notifier).setTheme(t),
                      child: AnimatedContainer(
                        duration: Motion.base,
                        curve: Motion.ease,
                        height: 64,
                        decoration: BoxDecoration(
                          color: s.themePref == t ? c.brand : Colors.transparent,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, size: 20, color: s.themePref == t ? c.onBrand : c.muted),
                            const SizedBox(height: 4),
                            Text(
                              label,
                              style: context.t.labelMedium!.copyWith(color: s.themePref == t ? c.onBrand : c.ink),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                for (final row in const [
                  [(AccentScheme.royal, 'Royal'), (AccentScheme.navy, 'Navy')],
                  [(AccentScheme.pink, 'Pink'), (AccentScheme.orange, 'Oranye')],
                ])
                  Row(
                    children: [
                      for (final (sch, label) in row)
                        Expanded(
                          child: Pressable(
                            onTap: () => ref.read(settingsProvider.notifier).setScheme(sch),
                            child: AnimatedContainer(
                              duration: Motion.base,
                              curve: Motion.ease,
                              height: 56,
                              margin: const EdgeInsets.all(2),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: s.scheme == sch ? c.primarySoft : Colors.transparent,
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: s.scheme == sch ? c.primary : Colors.transparent, width: 1.5),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: AppColors.brandOf(sch),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                      boxShadow: [
                                        BoxShadow(color: AppColors.brandOf(sch).withValues(alpha: .35), blurRadius: 8),
                                      ],
                                    ),
                                    child: AnimatedOpacity(
                                      duration: Motion.fast,
                                      opacity: s.scheme == sch ? 1 : 0,
                                      child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(label, style: context.t.labelLarge),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Otomatis: gelap setelah matahari terbenam dan terang setelah terbit, dihitung dari lokasimu tanpa internet.',
              style: context.t.bodySmall,
            ),
          ),
          const SizedBox(height: 24),
          // Hidden until GOOGLE_WEB_CLIENT_ID is set in env.json.
          if (Env.googleReady) ...[const SectionLabel('Google Drive'), const _GoogleCard(), const SizedBox(height: 24)],
          const SectionLabel('Pengingat'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.notifications_active_rounded, color: c.primary, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pengingat harian', style: context.t.titleSmall),
                          Text('Hari kerja yang belum ada kegiatannya', style: context.t.bodySmall),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: s.reminderOn,
                      activeTrackColor: c.brand,
                      onChanged: (v) async {
                        if (v) await ReminderService.requestPermission();
                        ref.read(settingsProvider.notifier).setReminder(on: v);
                      },
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: Motion.base,
                  curve: Motion.ease,
                  child: !s.reminderOn
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Pressable(
                                  onTap: () async {
                                    final t = await showTimePicker(
                                      context: context,
                                      initialTime: TimeOfDay(
                                        hour: s.reminderMinutes ~/ 60,
                                        minute: s.reminderMinutes % 60,
                                      ),
                                      helpText: 'Jam pengingat',
                                      builder: (ctx, child) => MediaQuery(
                                        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
                                        child: child!,
                                      ),
                                    );
                                    if (t != null) {
                                      ref.read(settingsProvider.notifier).setReminder(minutes: t.hour * 60 + t.minute);
                                    }
                                  },
                                  child: Container(
                                    height: 52,
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    decoration: BoxDecoration(
                                      color: c.surface2,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.schedule_rounded, size: 19, color: c.primary),
                                        const SizedBox(width: 10),
                                        Text('Setiap pukul', style: context.t.bodySmall),
                                        const Spacer(),
                                        Text(
                                          '${two(s.reminderMinutes ~/ 60)}:${two(s.reminderMinutes % 60)}',
                                          style: context.t.titleMedium!.copyWith(color: c.primary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              AppButton(
                                label: 'Uji',
                                icon: Icons.notifications_rounded,
                                style: BtnStyle.tonal,
                                onTap: ReminderService.test,
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Juga mengingatkan 2 hari sebelum tanggal kosong melewati batas lapor 1 bulan.',
                  style: context.t.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('Penyimpanan'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_rounded, color: c.accent),
                    const SizedBox(width: 10),
                    Expanded(child: Text(storage.publicRoot, style: context.t.titleSmall)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Setiap bulan punya folder sendiri, misalnya "2026-10", berisi foto, PDF bukti dukung, dan rekap.',
                  style: context.t.bodySmall,
                ),
                const SizedBox(height: 14),
                AnimatedSwitcher(
                  duration: Motion.base,
                  child: _access == null
                      ? const SizedBox(height: 52)
                      : _access!
                      ? Row(
                          key: const ValueKey('ok'),
                          children: [
                            Tag('Akses folder aktif', icon: Icons.check_circle_rounded, color: c.success),
                            const Spacer(),
                            AppButton(
                              label: 'Sinkronkan',
                              icon: Icons.sync_rounded,
                              style: BtnStyle.tonal,
                              busy: _syncing,
                              onTap: _resync,
                            ),
                          ],
                        )
                      : AppButton(
                          key: const ValueKey('no'),
                          label: 'Izinkan akses folder',
                          icon: Icons.lock_open_rounded,
                          expand: true,
                          onTap: () async {
                            await storage.requestPublicAccess();
                            _checkAccess();
                          },
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('Izin aplikasi'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Perbarui izin notifikasi, kamera, lokasi, dan lainnya di halaman pengaturan sistem.',
                  style: context.t.bodySmall,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Izin notifikasi',
                        icon: Icons.notifications_active_rounded,
                        style: BtnStyle.tonal,
                        onTap: _requestNotif,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppButton(
                        label: 'Pengaturan aplikasi',
                        icon: Icons.settings_rounded,
                        style: BtnStyle.ghost,
                        onTap: openAppSettings,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                const LogoTile(size: 40),
                const SizedBox(height: 8),
                Text('Lapor Yuk · v1.6', style: context.t.labelLarge),
                Text('Bekerja penuh tanpa internet', style: context.t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet({required this.profile});
  final Profile profile;

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late final _f = {
    'name': TextEditingController(text: widget.profile.name),
    'nip': TextEditingController(text: widget.profile.nip),
    'position': TextEditingController(text: widget.profile.position),
    'unit': TextEditingController(text: widget.profile.unit),
    'agency': TextEditingController(text: widget.profile.agency),
    'city': TextEditingController(text: widget.profile.city),
  };

  @override
  void dispose() {
    for (final c in _f.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String key, String label, {TextInputType? type}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _f[key],
        keyboardType: type,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: label),
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ubah profil', style: context.t.headlineSmall),
            const SizedBox(height: 4),
            Text('Dipakai di watermark foto dan rekap PDF.', style: context.t.bodySmall),
            const SizedBox(height: 16),
            field('name', 'Nama lengkap'),
            field('nip', 'NIP', type: TextInputType.number),
            field('position', 'Jabatan'),
            field('unit', 'Satuan kerja'),
            field('agency', 'Instansi (kop rekap)'),
            field('city', 'Kota penandatanganan'),
            const SizedBox(height: 4),
            AppButton(
              label: 'Simpan profil',
              expand: true,
              onTap: () => Navigator.pop(
                context,
                Profile(
                  name: _f['name']!.text.trim(),
                  nip: _f['nip']!.text.trim(),
                  position: _f['position']!.text.trim(),
                  unit: _f['unit']!.text.trim(),
                  agency: _f['agency']!.text.trim(),
                  city: _f['city']!.text.trim(),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _GoogleCard extends ConsumerStatefulWidget {
  const _GoogleCard();

  @override
  ConsumerState<_GoogleCard> createState() => _GoogleCardState();
}

class _GoogleCardState extends ConsumerState<_GoogleCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() f, String ok) async {
    setState(() => _busy = true);
    try {
      await f();
      if (mounted) toast(context, ok);
    } catch (e) {
      if (mounted) toast(context, 'Gagal: $e', icon: Icons.error_outline_rounded);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final user = ref.watch(googleUserProvider);
    final name = ref.watch(settingsProvider.select((s) => s.profile.name));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(12)),
                child: user?.photo != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(user!.photo!, fit: BoxFit.cover),
                      )
                    : Icon(Icons.add_to_drive_rounded, color: c.primary, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user == null ? 'Belum terhubung' : (user.name ?? user.email), style: context.t.titleSmall),
                    Text(
                      user == null ? 'Pilih akun Google mana saja' : user.email,
                      style: context.t.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            user == null
                ? 'Setelah terhubung, tombol Sinkron di tab Kegiatan mengunggah bukti dukung ke folder "SKP ${name.isEmpty ? '<nama>' : name}" (bisa dikomentari siapa pun yang punya link).'
                : 'Folder Drive: "SKP $name" · siapa pun dengan link bisa berkomentar. Lapor Yuk hanya bisa melihat file yang ia unggah sendiri.',
            style: context.t.bodySmall,
          ),
          const SizedBox(height: 14),
          if (!Env.googleReady)
            Tag('Belum dikonfigurasi di build ini', icon: Icons.info_outline_rounded, color: c.danger)
          else if (user == null)
            AppButton(
              label: 'Hubungkan akun Google',
              icon: Icons.link_rounded,
              expand: true,
              busy: _busy,
              onTap: () => _run(ref.read(googleUserProvider.notifier).connect, 'Akun Google terhubung'),
            )
          else
            AppButton(
              label: 'Putuskan akun',
              icon: Icons.link_off_rounded,
              style: BtnStyle.ghost,
              expand: true,
              busy: _busy,
              onTap: () => _run(ref.read(googleUserProvider.notifier).disconnect, 'Akun Google diputus'),
            ),
        ],
      ),
    );
  }
}
