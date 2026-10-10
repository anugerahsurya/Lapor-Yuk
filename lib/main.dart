import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme.dart';
import 'data/repository.dart';
import 'services/chat_service.dart';
import 'services/storage_service.dart';
import 'state/providers.dart';
import 'ui/screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
  );
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final prefs = await SharedPreferences.getInstance();
  final storage = await StorageService.create();
  final repo = await Repository.open(storage);
  await ChatService.init(); // no-op until SUPABASE_ANON_KEY is configured

  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs), repoProvider.overrideWithValue(repo)],
      child: const LaporYukApp(),
    ),
  );
}

class LaporYukApp extends ConsumerWidget {
  const LaporYukApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = ref.watch(settingsProvider.select((s) => s.scheme));
    return MaterialApp(
      title: 'Lapor Yuk',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, scheme),
      darkTheme: buildTheme(Brightness.dark, scheme),
      themeMode: ref.watch(themeModeProvider),
      themeAnimationDuration: const Duration(milliseconds: 700),
      themeAnimationCurve: Curves.easeInOutCubic,
      home: const SplashScreen(),
    );
  }
}
