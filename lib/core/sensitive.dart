// Istilah Sensus Ekonomi / BPS yang disamarkan di chat. Frasa panjang ditaruh
// lebih dulu supaya "Sensus Ekonomi" kena utuh, bukan hanya "Sensus".
const _terms = [
  'Badan Pusat Statistik',
  'Sensus Ekonomi',
  'Sensus Penduduk',
  'Sensus Pertanian',
  r'SE[\s-]?2026',
  r'SE[\s-]?2016',
  r'ST[\s-]?2023',
  r'SP[\s-]?2020',
  'Fasih',
  'Sensus',
  'BPS',
  'Pusat',
  'Survei',
  'Survey',
  'PML',
  'PPL',
  'Kortim',
  'Mitra',
  'Ruta',
  'Susenas',
  'Sakernas',
  'Podes',
  'Pencacah',
  'Responden',
  'Kuesioner',
  'Koseka',
  'KSK',
  'Wilkerstat',
  'Prelist',
  'Statistik',
];

/// Ikut menangkap akhiran umum, mis. "BPS-nya", "mitranya", tapi tidak "rutan".
final sensitiveWords = RegExp(r'\b(?:' + _terms.join('|') + r')(?:-?(?:nya|ku|mu|lah|pun))?\b', caseSensitive: false);

/// Versi teks biasa untuk notifikasi, yang tidak bisa diblur.
String maskSensitive(String s) => s.replaceAll(sensitiveWords, '***');
