/// Indonesian date helpers. Kept dependency-free so they work offline and
/// don't need locale data initialisation.
library;

const bulan = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];
const bulanPendek = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
const hari = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
const hariPendek = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime monthOf(DateTime d) => DateTime(d.year, d.month);
DateTime addMonths(DateTime m, int n) => DateTime(m.year, m.month + n);
int daysInMonth(DateTime m) => DateTime(m.year, m.month + 1, 0).day;
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
bool sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

String two(int n) => n.toString().padLeft(2, '0');

/// Folder / storage key: 2026-10 (sorts naturally in file managers).
String monthKey(DateTime d) => '${d.year}-${two(d.month)}';
String isoDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
DateTime parseIso(String s) => DateTime.parse(s);

String fmtDate(DateTime d) => '${d.day} ${bulan[d.month - 1]} ${d.year}';
String fmtDateShort(DateTime d) => '${d.day} ${bulanPendek[d.month - 1]} ${d.year}';
String fmtMonth(DateTime d) => '${bulan[d.month - 1]} ${d.year}';
String fmtDay(DateTime d) => hari[d.weekday - 1];
String fmtTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
String fmtFullDate(DateTime d) => '${fmtDay(d)}, ${fmtDate(d)}';

String fmtPeriod(DateTime start, DateTime end, {bool short = false}) {
  final f = short ? fmtDateShort : fmtDate;
  if (sameDay(start, end)) return f(start);
  if (short && start.year == end.year && start.month == end.month) {
    return '${start.day}–${end.day} ${bulanPendek[end.month - 1]} ${end.year}';
  }
  return '${f(start)} s.d. ${f(end)}';
}

/// Window of dates a report may cover: from exactly one month ago to today.
/// Day-of-month is clamped (31 Mar -> 28/29 Feb) instead of overflowing.
({DateTime min, DateTime max}) reportWindow(DateTime now) {
  final today = dateOnly(now);
  final prev = DateTime(today.year, today.month - 1);
  final day = today.day.clamp(1, daysInMonth(prev));
  return (min: DateTime(prev.year, prev.month, day), max: today);
}

bool inWindow(DateTime d, DateTime now) {
  final w = reportWindow(now);
  final x = dateOnly(d);
  return !x.isBefore(w.min) && !x.isAfter(w.max);
}

/// Every month touched by [start]..[end], in order.
List<DateTime> monthsBetween(DateTime start, DateTime end) {
  final out = <DateTime>[];
  var m = monthOf(start);
  final last = monthOf(end);
  while (!m.isAfter(last)) {
    out.add(m);
    m = addMonths(m, 1);
  }
  return out;
}
