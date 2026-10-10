/// Offline daily quotes: Indonesian proverbs, well-known figures, and a few
/// house lines about work and data. One per day, stable for the whole day.
library;

typedef Quote = ({String text, String by});

const quotes = <Quote>[
  (text: 'Ing ngarsa sung tuladha, ing madya mangun karsa, tut wuri handayani.', by: 'Ki Hajar Dewantara'),
  (text: 'Habis gelap terbitlah terang.', by: 'R.A. Kartini'),
  (text: 'Gantungkan cita-citamu setinggi langit.', by: 'Soekarno'),
  (text: 'Sedikit demi sedikit, lama-lama menjadi bukit.', by: 'Peribahasa'),
  (text: 'Perjalanan seribu mil dimulai dengan satu langkah.', by: 'Lao Tzu'),
  (text: 'Tanpa data, kamu hanyalah orang lain yang punya pendapat.', by: 'W. Edwards Deming'),
  (text: 'Catat hari ini, supaya besok tidak perlu mengingat-ingat.', by: 'Lapor Yuk'),
  (text: 'Di mana ada kemauan, di situ ada jalan.', by: 'Peribahasa'),
  (text: 'Bukan karena sulit kita tidak berani; karena tidak berani, semuanya jadi sulit.', by: 'Seneca'),
  (text: 'Sukses adalah jumlah dari usaha kecil yang diulang setiap hari.', by: 'Robert Collier'),
  (text: 'Belajarlah dari ilmu padi, makin berisi makin merunduk.', by: 'Peribahasa'),
  (text: 'Mulailah dari tempatmu berdiri. Gunakan yang kamu punya. Lakukan yang kamu bisa.', by: 'Arthur Ashe'),
  (text: 'Selesai lebih baik daripada sempurna.', by: 'Pepatah'),
  (text: 'Berat sama dipikul, ringan sama dijinjing.', by: 'Peribahasa'),
  (text: 'Disiplin adalah jembatan antara tujuan dan pencapaian.', by: 'Jim Rohn'),
  (text: 'Data yang rapi adalah awal dari keputusan yang baik.', by: 'Lapor Yuk'),
  (text: 'Tidak masalah seberapa lambat kamu berjalan, asalkan tidak berhenti.', by: 'Konfusius'),
  (text: 'Hemat pangkal kaya, rajin pangkal pandai.', by: 'Peribahasa'),
  (text: 'Keberuntungan adalah saat persiapan bertemu kesempatan.', by: 'Seneca'),
  (text: 'Kerjakan yang kecil dengan sungguh-sungguh; yang besar akan menyusul.', by: 'Lapor Yuk'),
  (text: 'Akar pendidikan itu pahit, tetapi buahnya manis.', by: 'Aristoteles'),
  (text: 'Bersatu kita teguh, bercerai kita runtuh.', by: 'Peribahasa'),
  (text: 'Jangan tunda sampai besok apa yang bisa dikerjakan hari ini.', by: 'Benjamin Franklin'),
  (text: 'Fokus pada kemajuan, bukan kesempurnaan.', by: 'Pepatah'),
  (text: 'Pendidikan adalah senjata paling ampuh untuk mengubah dunia.', by: 'Nelson Mandela'),
  (text: 'Tak ada rotan, akar pun jadi.', by: 'Peribahasa'),
  (text: 'Satu langkah setiap hari tetap lebih jauh daripada diam.', by: 'Lapor Yuk'),
  (text: 'Apa yang diukur, itulah yang bisa dikelola.', by: 'Peter Drucker'),
  (text: 'Bekerja keras dalam diam, biarkan hasil yang berbicara.', by: 'Pepatah'),
  (text: 'Sambil menyelam minum air.', by: 'Peribahasa'),
  (text: 'Kesabaran itu pahit, tetapi buahnya manis.', by: 'Jean-Jacques Rousseau'),
  (text: 'Istirahatlah bila lelah, tapi jangan berhenti.', by: 'Pepatah'),
  (text: 'Angka yang jujur bercerita lebih lantang dari seribu kata.', by: 'Lapor Yuk'),
  (text: 'Air tenang menghanyutkan.', by: 'Peribahasa'),
  (text: 'Yang penting bukan seberapa sering jatuh, tapi seberapa sering bangkit.', by: 'Pepatah'),
  (text: 'Waktu adalah pedang; jika tak kau gunakan, ia memotongmu.', by: 'Pepatah Arab'),
  (text: 'Integritas adalah melakukan hal yang benar meski tak ada yang melihat.', by: 'Pepatah'),
  (text: 'Rencanakan pekerjaanmu, lalu kerjakan rencanamu.', by: 'Pepatah'),
  (text: 'Hari libur untuk mengisi ulang; Senin kita mulai lagi.', by: 'Lapor Yuk'),
  (text: 'Ilmu tanpa amal bagai pohon tak berbuah.', by: 'Peribahasa'),
  (text: 'Rajin bekerja tidak pernah membuat orang miskin.', by: 'Pepatah'),
  (text: 'Lakukan dengan hati, hasilnya akan terasa.', by: 'Lapor Yuk'),
];

/// Same quote all day; [offset] lets the user flip to the next one.
Quote quoteOfDay(DateTime now, {int offset = 0}) {
  final day = DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch ~/ 86400000;
  // Stride 5 is coprime with the list length, so every quote comes round.
  return quotes[(day * 5 + offset) % quotes.length];
}
