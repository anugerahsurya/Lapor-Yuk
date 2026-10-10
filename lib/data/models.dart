import 'dart:convert';

import '../core/dates.dart';

enum EvidenceKind { camera, image, pdf }

String defaultAchievement(String title) {
  final t = title.trim().replaceAll(RegExp(r'\s+'), ' ');
  return 'Persentase Terselesaikannya ${t.isEmpty ? '…' : t} Sebesar 100%';
}

class Evidence {
  Evidence({
    this.id,
    this.activityId,
    required this.kind,
    required this.name,
    required this.masterPath,
    this.rawPath,
    this.publicPaths = const [],
    this.lat,
    this.lng,
    this.accuracy,
    this.address,
    this.author,
    this.mirrored = false,
    required this.capturedAt,
  });

  final int? id;
  final int? activityId;
  final EvidenceKind kind;
  final String name;

  /// App-private copy. Source of truth for display and for mirroring.
  final String masterPath;

  /// Unstamped camera frame, kept only while the address is still pending.
  final String? rawPath;

  /// Mirrors in /Lapor Yuk/YYYY-MM/.
  final List<String> publicPaths;
  final double? lat;
  final double? lng;
  final double? accuracy;
  final String? address;
  final String? author;

  /// Front-camera shot flipped to match the (mirrored) preview.
  final bool mirrored;
  final DateTime capturedAt;

  bool get isImage => kind != EvidenceKind.pdf;
  bool get addressPending => kind == EvidenceKind.camera && address == null && lat != null && rawPath != null;

  Evidence copyWith({
    int? id,
    int? activityId,
    String? masterPath,
    String? rawPath,
    bool clearRaw = false,
    List<String>? publicPaths,
    String? address,
  }) => Evidence(
    id: id ?? this.id,
    activityId: activityId ?? this.activityId,
    kind: kind,
    name: name,
    masterPath: masterPath ?? this.masterPath,
    rawPath: clearRaw ? null : (rawPath ?? this.rawPath),
    publicPaths: publicPaths ?? this.publicPaths,
    lat: lat,
    lng: lng,
    accuracy: accuracy,
    address: address ?? this.address,
    author: author,
    mirrored: mirrored,
    capturedAt: capturedAt,
  );

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'activity_id': activityId,
    'kind': kind.name,
    'name': name,
    'master_path': masterPath,
    'raw_path': rawPath,
    'public_paths': jsonEncode(publicPaths),
    'lat': lat,
    'lng': lng,
    'accuracy': accuracy,
    'address': address,
    'author': author,
    'mirrored': mirrored ? 1 : 0,
    'captured_at': capturedAt.toIso8601String(),
  };

  factory Evidence.fromRow(Map<String, Object?> r) => Evidence(
    id: r['id'] as int,
    activityId: r['activity_id'] as int?,
    kind: EvidenceKind.values.byName(r['kind'] as String),
    name: r['name'] as String,
    masterPath: r['master_path'] as String,
    rawPath: r['raw_path'] as String?,
    publicPaths: (jsonDecode(r['public_paths'] as String? ?? '[]') as List).cast<String>(),
    lat: (r['lat'] as num?)?.toDouble(),
    lng: (r['lng'] as num?)?.toDouble(),
    accuracy: (r['accuracy'] as num?)?.toDouble(),
    address: r['address'] as String?,
    author: r['author'] as String?,
    mirrored: (r['mirrored'] as int? ?? 0) == 1,
    capturedAt: DateTime.parse(r['captured_at'] as String),
  );
}

class Activity {
  Activity({
    this.id,
    required this.title,
    required this.achievement,
    required this.start,
    required this.end,
    required this.createdAt,
    required this.updatedAt,
    this.evidences = const [],
  });

  final int? id;
  final String title;
  final String achievement;
  final DateTime start;
  final DateTime end;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Evidence> evidences;

  bool get isRange => !sameDay(start, end);
  List<DateTime> get months => monthsBetween(start, end);

  bool touchesMonth(DateTime m) {
    final first = DateTime(m.year, m.month);
    final last = DateTime(m.year, m.month, daysInMonth(m));
    return !start.isAfter(last) && !end.isBefore(first);
  }

  bool coversDay(DateTime d) {
    final x = dateOnly(d);
    return !x.isBefore(start) && !x.isAfter(end);
  }

  /// Shown in months after the one it started in.
  bool isContinuationIn(DateTime m) => start.isBefore(DateTime(m.year, m.month));

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'title': title,
    'achievement': achievement,
    'start_date': isoDate(start),
    'end_date': isoDate(end),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory Activity.fromRow(Map<String, Object?> r, List<Evidence> ev) => Activity(
    id: r['id'] as int,
    title: r['title'] as String,
    achievement: r['achievement'] as String,
    start: parseIso(r['start_date'] as String),
    end: parseIso(r['end_date'] as String),
    createdAt: DateTime.parse(r['created_at'] as String),
    updatedAt: DateTime.parse(r['updated_at'] as String),
    evidences: ev,
  );
}

class Profile {
  const Profile({
    this.name = '',
    this.nip = '',
    this.position = '',
    this.unit = '',
    this.agency = 'Badan Pusat Statistik',
    this.city = '',
  });

  final String name;
  final String nip;
  final String position;
  final String unit;
  final String agency;
  final String city;

  String get firstName => name.trim().isEmpty ? 'Kamu' : name.trim().split(RegExp(r'\s+')).first;

  bool get isComplete => name.trim().isNotEmpty && unit.trim().isNotEmpty;

  Profile copyWith({String? name, String? nip, String? position, String? unit, String? agency, String? city}) =>
      Profile(
        name: name ?? this.name,
        nip: nip ?? this.nip,
        position: position ?? this.position,
        unit: unit ?? this.unit,
        agency: agency ?? this.agency,
        city: city ?? this.city,
      );

  Map<String, String> toJson() => {
    'name': name,
    'nip': nip,
    'position': position,
    'unit': unit,
    'agency': agency,
    'city': city,
  };

  factory Profile.fromJson(Map<String, dynamic> j) {
    const d = Profile();
    return Profile(
      name: j['name'] ?? d.name,
      nip: j['nip'] ?? d.nip,
      position: j['position'] ?? d.position,
      unit: j['unit'] ?? d.unit,
      agency: j['agency'] ?? d.agency,
      city: j['city'] ?? d.city,
    );
  }
}
