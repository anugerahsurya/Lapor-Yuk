import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

class AppUpdate {
  const AppUpdate({required this.versionCode, required this.versionName, required this.url, required this.notes});
  final int versionCode;
  final String versionName, url, notes;
}

/// Checks the version file on the download page. No new version, no network,
/// or any error -> returns null (the app never blocks on this).
abstract final class UpdateService {
  static const _url = 'https://raw.githubusercontent.com/anugerahsurya/Lapor-Yuk/main/landing/version.json';

  static Future<AppUpdate?> check() async {
    HttpClient? client;
    try {
      final info = await PackageInfo.fromPlatform();
      final current = int.tryParse(info.buildNumber) ?? 0;
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final resp = await (await client.getUrl(Uri.parse(_url))).close();
      if (resp.statusCode != 200) return null;
      final j = jsonDecode(await resp.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final code = (j['versionCode'] as num?)?.toInt() ?? 0;
      if (code <= current) return null;
      return AppUpdate(
        versionCode: code,
        versionName: j['versionName'] as String? ?? '',
        url: j['url'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
      );
    } catch (_) {
      return null;
    } finally {
      client?.close();
    }
  }
}
