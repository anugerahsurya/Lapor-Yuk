import 'dart:math' as math;

/// Offline astronomy: sunrise/sunset (NOAA "Almanac for Computers" method)
/// and moon phase. Accurate to a couple of minutes, which is plenty for
/// switching the sky and the theme.
class SunTimes {
  const SunTimes(this.sunrise, this.sunset);
  final DateTime sunrise;
  final DateTime sunset;
}

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;
double _norm(double v, double max) => ((v % max) + max) % max;

SunTimes sunTimes(DateTime day, double lat, double lng) {
  DateTime? calc(bool rising) {
    final n = day.difference(DateTime(day.year, 1, 1)).inDays + 1;
    final lngHour = lng / 15;
    final t = n + ((rising ? 6 : 18) - lngHour) / 24;
    final m = 0.9856 * t - 3.289;
    final l = _norm(m + 1.916 * math.sin(_rad(m)) + 0.020 * math.sin(_rad(2 * m)) + 282.634, 360);
    var ra = _norm(_deg(math.atan(0.91764 * math.tan(_rad(l)))), 360);
    ra += (l / 90).floor() * 90 - (ra / 90).floor() * 90;
    ra /= 15;
    final sinDec = 0.39782 * math.sin(_rad(l));
    final cosDec = math.cos(math.asin(sinDec));
    final cosH = (math.cos(_rad(90.833)) - sinDec * math.sin(_rad(lat))) / (cosDec * math.cos(_rad(lat)));
    if (cosH > 1 || cosH < -1) return null;
    final h = (rising ? 360 - _deg(math.acos(cosH)) : _deg(math.acos(cosH))) / 15;
    final localT = h + ra - 0.06571 * t - 6.622;
    final ut = _norm(localT - lngHour, 24);
    final utc = DateTime.utc(day.year, day.month, day.day).add(Duration(minutes: (ut * 60).round()));
    final local = utc.toLocal();
    // Pin back to the requested calendar day (UT may have wrapped).
    return DateTime(day.year, day.month, day.day, local.hour, local.minute);
  }

  return SunTimes(
    calc(true) ?? DateTime(day.year, day.month, day.day, 6),
    calc(false) ?? DateTime(day.year, day.month, day.day, 18),
  );
}

/// The four times of day shown in the app.
enum SkyPhase {
  pagi('Pagi'),
  siang('Siang'),
  sore('Sore'),
  malam('Malam');

  const SkyPhase(this.label);
  final String label;
}

class SkyState {
  const SkyState({required this.phase, required this.sunProgress, required this.moonPhase, required this.isNight});

  /// 0 at sunrise, 1 at sunset. Outside that range at night.
  final double sunProgress;
  final SkyPhase phase;

  /// 0 = new moon, 0.5 = full moon.
  final double moonPhase;
  final bool isNight;
}

/// Pagi: dawn (30 min before sunrise) .. 11:00
/// Siang: 11:00 .. 15:00
/// Sore: 15:00 .. 25 min after sunset
/// Malam: the rest. Night bounds follow the real sun for the location.
SkyPhase phaseAt(DateTime now, SunTimes s) {
  final day = DateTime(now.year, now.month, now.day);
  if (now.isBefore(s.sunrise.subtract(const Duration(minutes: 30))) ||
      now.isAfter(s.sunset.add(const Duration(minutes: 25)))) {
    return SkyPhase.malam;
  }
  if (now.isBefore(day.add(const Duration(hours: 11)))) return SkyPhase.pagi;
  if (now.isBefore(day.add(const Duration(hours: 15)))) return SkyPhase.siang;
  return SkyPhase.sore;
}

SkyState skyAt(DateTime now, double lat, double lng) {
  final s = sunTimes(now, lat, lng);
  final total = s.sunset.difference(s.sunrise).inSeconds;
  final p = now.difference(s.sunrise).inSeconds / total;
  final phase = phaseAt(now, s);
  return SkyState(phase: phase, sunProgress: p, moonPhase: moonPhase(now), isNight: phase == SkyPhase.malam);
}

double moonPhase(DateTime now) {
  const synodic = 29.530588853;
  final ref = DateTime.utc(2000, 1, 6, 18, 14);
  final days = now.toUtc().difference(ref).inSeconds / 86400;
  return _norm(days, synodic) / synodic;
}
