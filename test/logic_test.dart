import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lapor_sur/core/dates.dart';
import 'package:lapor_sur/core/quotes.dart';
import 'package:lapor_sur/core/sky.dart';
import 'package:lapor_sur/data/models.dart';
import 'package:lapor_sur/services/rekap_pdf.dart';
import 'package:lapor_sur/ui/sheets/todo_sheet.dart' show nextWorkday;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reportWindow', () {
    test('one month back to today', () {
      final w = reportWindow(DateTime(2026, 10, 9, 15));
      expect(w.min, DateTime(2026, 9, 9));
      expect(w.max, DateTime(2026, 10, 9));
    });

    test('clamps day overflow (31 Mar -> 28 Feb)', () {
      expect(reportWindow(DateTime(2026, 3, 31)).min, DateTime(2026, 2, 28));
    });

    test('crosses the year', () {
      expect(reportWindow(DateTime(2027, 1, 15)).min, DateTime(2026, 12, 15));
    });

    test('rejects future and too-old dates', () {
      final now = DateTime(2026, 10, 9);
      expect(inWindow(DateTime(2026, 10, 10), now), isFalse);
      expect(inWindow(DateTime(2026, 9, 8), now), isFalse);
      expect(inWindow(DateTime(2026, 9, 9), now), isTrue);
      expect(inWindow(DateTime(2026, 10, 9), now), isTrue);
    });
  });

  group('cross-month activity', () {
    final a = Activity(
      id: 1,
      title: 'Pengawasan Ujian',
      achievement: defaultAchievement('Pengawasan Ujian'),
      start: DateTime(2026, 9, 28),
      end: DateTime(2026, 10, 3),
      createdAt: DateTime(2026, 10, 3),
      updatedAt: DateTime(2026, 10, 3),
    );

    test('appears in both months, flagged as continuation in the second', () {
      expect(a.months, [DateTime(2026, 9), DateTime(2026, 10)]);
      expect(a.touchesMonth(DateTime(2026, 9)), isTrue);
      expect(a.touchesMonth(DateTime(2026, 10)), isTrue);
      expect(a.touchesMonth(DateTime(2026, 11)), isFalse);
      expect(a.isContinuationIn(DateTime(2026, 9)), isFalse);
      expect(a.isContinuationIn(DateTime(2026, 10)), isTrue);
    });

    test('achievement formula', () {
      expect(a.achievement, 'Persentase Terselesaikannya Pengawasan Ujian Sebesar 100%');
    });
  });

  test('sun times for Padang look plausible', () {
    final s = sunTimes(DateTime(2026, 10, 9), -0.9471, 100.4172);
    final len = s.sunset.difference(s.sunrise);
    // Near the equator the day is ~12h.
    expect(len.inMinutes, inInclusiveRange(11 * 60 + 50, 12 * 60 + 15));
  });

  test('four sky phases follow clock and real sun', () {
    final day = DateTime(2026, 10, 9);
    final sun = SunTimes(DateTime(2026, 10, 9, 6, 15), DateTime(2026, 10, 9, 18, 20));
    SkyPhase at(int h, int m) => phaseAt(DateTime(day.year, day.month, day.day, h, m), sun);
    expect(at(5, 30), SkyPhase.malam);
    expect(at(5, 50), SkyPhase.pagi); // 25 min before sunrise
    expect(at(10, 59), SkyPhase.pagi);
    expect(at(11, 0), SkyPhase.siang);
    expect(at(14, 59), SkyPhase.siang);
    expect(at(15, 0), SkyPhase.sore);
    expect(at(18, 40), SkyPhase.sore); // 20 min after sunset
    expect(at(18, 50), SkyPhase.malam);
  });

  test('next workday skips Saturday and Sunday', () {
    expect(nextWorkday(DateTime(2026, 10, 9)), DateTime(2026, 10, 12)); // Fri -> Mon
    expect(nextWorkday(DateTime(2026, 10, 10)), DateTime(2026, 10, 12)); // Sat -> Mon
    expect(nextWorkday(DateTime(2026, 10, 12)), DateTime(2026, 10, 13)); // Mon -> Tue
  });

  test('quote of the day is stable within a day and cycles through all', () {
    expect(quoteOfDay(DateTime(2026, 10, 9, 7)), quoteOfDay(DateTime(2026, 10, 9, 22)));
    final seen = {for (var d = 0; d < quotes.length; d++) quoteOfDay(DateTime(2026, 1, 1).add(Duration(days: d))).text};
    expect(seen.length, quotes.length);
  });

  test('rekap PDF builds', () async {
    // 1x1 transparent PNG as signature.
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 1, 0, 0, 0, 1,
      8, 6, 0, 0, 0, 0x1F, 0x15, 0xC4, 0x89, 0, 0, 0, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0, 1, 0, 0,
      5, 0, 1, 0x0D, 0x0A, 0x2D, 0xB4, 0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
    final acts = [
      for (var i = 1; i <= 12; i++)
        Activity(
          id: i,
          title: 'Kegiatan nomor $i',
          achievement: defaultAchievement('Kegiatan nomor $i'),
          start: DateTime(2026, 9, i * 2),
          end: DateTime(2026, 9, i * 2 + (i.isEven ? 1 : 0)),
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
    ];
    final bytes = await buildRekapPdf(
      month: DateTime(2026, 9),
      activities: acts,
      profile: const Profile(name: 'Pegawai Contoh', nip: '199001012020121001', position: 'Pelaksana', unit: 'BPS Provinsi Contoh', city: 'Padang'),
      signaturePng: png,
      printedAt: DateTime(2026, 10, 9),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final out = Directory.systemTemp.createTempSync('rekap');
    File('${out.path}/Rekap_CKP_2026-09.pdf').writeAsBytesSync(bytes);
    // ignore: avoid_print
    print('PDF: ${out.path}/Rekap_CKP_2026-09.pdf');
  });
}
