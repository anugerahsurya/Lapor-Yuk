import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

abstract final class LocationService {
  /// Asks for permission if needed. Returns false if location is unusable.
  static Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  static Stream<Position> stream() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3),
  );

  static Future<Position?> current() async {
    if (!await ensurePermission()) return null;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
      );
    } catch (_) {
      return Geolocator.getLastKnownPosition();
    }
  }

  static Future<bool> isOnline() async {
    try {
      final r = await Connectivity().checkConnectivity();
      return r.any((e) => e != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  static Stream<bool> onlineChanges() =>
      Connectivity().onConnectivityChanged.map((r) => r.any((e) => e != ConnectivityResult.none));

  /// Reverse geocode via the platform geocoder (needs network). Returns null
  /// when offline or when the lookup fails/times out.
  static Future<String?> address(double lat, double lng) async {
    if (!await isOnline()) return null;
    try {
      final list = await Geocoding()
          .placemarkFromCoordinates(lat, lng, locale: const Locale('id', 'ID'))
          .timeout(const Duration(seconds: 8));
      if (list.isEmpty) return null;
      final pm = list.first;
      final parts = <String>[];
      for (final s in [pm.street, pm.subLocality, pm.locality, pm.subAdministrativeArea, pm.administrativeArea]) {
        final v = s?.trim() ?? '';
        if (v.isEmpty || v.contains('+')) continue; // skip plus-codes
        if (parts.any((x) => x.toLowerCase() == v.toLowerCase())) continue;
        parts.add(v);
      }
      return parts.isEmpty ? null : parts.join(', ');
    } catch (_) {
      return null;
    }
  }
}

String fmtCoord(double lat, double lng) =>
    '${lat.abs().toStringAsFixed(5)}° ${lat < 0 ? 'LS' : 'LU'}  ${lng.abs().toStringAsFixed(5)}° ${lng < 0 ? 'BB' : 'BT'}';
