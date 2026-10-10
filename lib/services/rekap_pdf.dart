import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/dates.dart';
import '../data/models.dart';

/// Builds the monthly recap in the same layout as the office template
/// ("Laporan Rekapitulasi Kegiatan Bulanan").
Future<Uint8List> buildRekapPdf({
  required DateTime month,
  required List<Activity> activities,
  required Profile profile,
  required Uint8List signaturePng,
  DateTime? printedAt,
}) async {
  final printed = printedAt ?? DateTime.now();
  final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'));
  final medium = pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans-Medium.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans-Bold.ttf'));
  final sig = pw.MemoryImage(signaturePng);

  final theme = pw.ThemeData.withFont(base: regular, bold: bold);
  pw.TextStyle st(double size, {pw.Font? font, PdfColor? color}) =>
      pw.TextStyle(font: font ?? regular, fontSize: size, color: color ?? PdfColors.black, lineSpacing: 2);

  final period = fmtMonth(month);
  final doc = pw.Document(title: 'Rekap Kegiatan $period', author: profile.name, creator: 'Lapor Yuk');

  pw.Widget idRow(String k, String v, {double keyW = 110, bool boldKey = true}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: keyW,
          child: pw.Text(k, style: st(10.5, font: boldKey ? bold : regular)),
        ),
        pw.SizedBox(width: 18, child: pw.Text(':', style: st(10.5))),
        pw.Expanded(child: pw.Text(v, style: st(10.5))),
      ],
    ),
  );

  pw.Widget cell(String text, {pw.Font? font, pw.TextAlign align = pw.TextAlign.left, PdfColor? color}) => pw.Padding(
    padding: const pw.EdgeInsets.fromLTRB(8, 8, 8, 10),
    child: pw.Text(
      text,
      style: st(10, font: font, color: color),
      textAlign: align,
    ),
  );

  final header = pw.TableRow(
    repeat: true,
    children: [
      cell('No', font: bold, align: pw.TextAlign.center),
      cell('Periode', font: bold, align: pw.TextAlign.center),
      cell('Uraian Kegiatan', font: bold, align: pw.TextAlign.center),
      cell('Capaian', font: bold, align: pw.TextAlign.center),
      cell('Bukti', font: bold, align: pw.TextAlign.center),
    ],
  );

  final rows = <pw.TableRow>[
    for (final (i, a) in activities.indexed)
      pw.TableRow(
        children: [
          cell('${i + 1}', align: pw.TextAlign.center),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(fmtPeriod(a.start, a.end), style: st(10)),
                if (a.isContinuationIn(month))
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 3),
                    child: pw.Text(
                      '(Lanjutan dari ${fmtMonth(a.start)})',
                      style: st(8.5, font: medium, color: PdfColors.grey700),
                    ),
                  ),
              ],
            ),
          ),
          cell(a.title),
          cell(a.achievement),
          cell(
            a.evidences.isEmpty ? 'Tidak Ada' : 'Ada',
            font: bold,
            align: pw.TextAlign.center,
            color: a.evidences.isEmpty ? PdfColors.red700 : null,
          ),
        ],
      ),
  ];

  doc.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4.copyWith(
        marginLeft: 2.2 * PdfPageFormat.cm,
        marginRight: 2.2 * PdfPageFormat.cm,
        marginTop: 2 * PdfPageFormat.cm,
        marginBottom: 2 * PdfPageFormat.cm,
      ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Halaman ${ctx.pageNumber} dari ${ctx.pagesCount}', style: st(8, color: PdfColors.grey600)),
      ),
      build: (ctx) => [
        pw.Center(
          child: pw.Text(profile.agency.toUpperCase(), style: st(16, font: bold)),
        ),
        pw.SizedBox(height: 6),
        pw.Center(
          child: pw.Text('LAPORAN REKAPITULASI KEGIATAN BULANAN', style: st(13, font: bold)),
        ),
        pw.SizedBox(height: 4),
        pw.Center(child: pw.Text('Periode $period', style: st(10.5))),
        pw.SizedBox(height: 12),
        pw.Container(height: 2, color: PdfColors.black),
        pw.SizedBox(height: 18),
        idRow('Nama Pegawai', profile.name),
        idRow('NIP', profile.nip),
        idRow('Jabatan', profile.position),
        idRow('Satuan Kerja', profile.unit),
        pw.SizedBox(height: 18),
        pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: .8)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('RINGKASAN', style: st(10.5, font: bold)),
              pw.SizedBox(height: 6),
              idRow('Periode Laporan', period, keyW: 200, boldKey: false),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                child: pw.Row(
                  children: [
                    pw.SizedBox(width: 200, child: pw.Text('Jumlah Kegiatan', style: st(10.5))),
                    pw.SizedBox(width: 18, child: pw.Text(':', style: st(10.5))),
                    pw.Text('${activities.length}', style: st(10.5, font: bold)),
                    pw.Text(' kegiatan', style: st(10.5)),
                  ],
                ),
              ),
              idRow('Tanggal Cetak', fmtDate(printed), keyW: 200, boldKey: false),
            ],
          ),
        ),
        pw.SizedBox(height: 18),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey800, width: .7),
          columnWidths: const {
            0: pw.FixedColumnWidth(30),
            1: pw.FlexColumnWidth(1.25),
            2: pw.FlexColumnWidth(1.15),
            3: pw.FlexColumnWidth(1.35),
            4: pw.FixedColumnWidth(58),
          },
          children: [header, ...rows],
        ),
        pw.SizedBox(height: 20),
        pw.RichText(
          textAlign: pw.TextAlign.justify,
          text: pw.TextSpan(
            style: st(10.5),
            children: [
              const pw.TextSpan(
                text: 'Laporan ini merupakan rekapitulasi kegiatan yang telah dilaksanakan selama periode ',
              ),
              pw.TextSpan(
                text: period,
                style: st(10.5, font: bold),
              ),
              const pw.TextSpan(
                text: '. Seluruh data bersumber dari isian kegiatan harian pegawai pada aplikasi pelaporan kegiatan.',
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        pw.RichText(
          text: pw.TextSpan(
            style: st(10.5),
            children: [
              const pw.TextSpan(text: 'Jumlah kegiatan yang tercatat pada periode ini adalah '),
              pw.TextSpan(
                text: '${activities.length} kegiatan',
                style: st(10.5, font: bold),
              ),
              const pw.TextSpan(text: '.'),
            ],
          ),
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          'Demikian laporan kegiatan bulanan ini dibuat sebagai bentuk dokumentasi dan pertanggungjawaban '
          'pelaksanaan tugas selama periode tersebut.',
          style: st(10.5),
          textAlign: pw.TextAlign.justify,
        ),
        pw.SizedBox(height: 28),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.SizedBox(
            width: 220,
            child: pw.Column(
              children: [
                pw.Text('${profile.city}, ${fmtDate(printed)}', style: st(10.5)),
                pw.SizedBox(height: 2),
                pw.Text('Pegawai yang Bersangkutan', style: st(10.5)),
                pw.SizedBox(height: 6),
                pw.SizedBox(height: 64, child: pw.Image(sig, fit: pw.BoxFit.contain)),
                pw.SizedBox(height: 6),
                pw.Text(
                  profile.name.toUpperCase(),
                  style: st(10.5, font: bold).copyWith(decoration: pw.TextDecoration.underline),
                ),
                pw.SizedBox(height: 2),
                pw.Text('NIP. ${profile.nip}', style: st(10.5)),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  return doc.save();
}
