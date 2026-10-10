import '../core/dates.dart';

class Todo {
  Todo({
    this.id,
    required this.title,
    this.note = '',
    this.due,
    this.dueMinutes,
    this.important = false,
    this.done = false,
    this.doneAt,
    required this.createdAt,
  });

  final int? id;
  final String title;
  final String note;

  /// Calendar day the task is due (date only), or null for "someday".
  final DateTime? due;

  /// Optional time on [due], minutes after midnight. Gets a reminder.
  final int? dueMinutes;
  final bool important;
  final bool done;
  final DateTime? doneAt;
  final DateTime createdAt;

  DateTime? get dueAt =>
      due == null ? null : DateTime(due!.year, due!.month, due!.day, (dueMinutes ?? 0) ~/ 60, (dueMinutes ?? 0) % 60);

  bool isOverdue(DateTime now) {
    if (done || due == null) return false;
    if (dueMinutes != null) return dueAt!.isBefore(now);
    return dateOnly(due!).isBefore(dateOnly(now));
  }

  Todo copyWith({
    int? id,
    String? title,
    String? note,
    DateTime? due,
    bool clearDue = false,
    int? dueMinutes,
    bool clearTime = false,
    bool? important,
    bool? done,
  }) {
    final d = done ?? this.done;
    return Todo(
      id: id ?? this.id,
      title: title ?? this.title,
      note: note ?? this.note,
      due: clearDue ? null : (due ?? this.due),
      dueMinutes: clearDue || clearTime ? null : (dueMinutes ?? this.dueMinutes),
      important: important ?? this.important,
      done: d,
      doneAt: d ? (this.done ? doneAt : DateTime.now()) : null,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'title': title,
    'note': note,
    'due': due == null ? null : isoDate(due!),
    'due_minutes': dueMinutes,
    'important': important ? 1 : 0,
    'done': done ? 1 : 0,
    'done_at': doneAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  factory Todo.fromRow(Map<String, Object?> r) => Todo(
    id: r['id'] as int,
    title: r['title'] as String,
    note: r['note'] as String? ?? '',
    due: r['due'] == null ? null : parseIso(r['due'] as String),
    dueMinutes: r['due_minutes'] as int?,
    important: (r['important'] as int? ?? 0) == 1,
    done: (r['done'] as int? ?? 0) == 1,
    doneAt: r['done_at'] == null ? null : DateTime.parse(r['done_at'] as String),
    createdAt: DateTime.parse(r['created_at'] as String),
  );
}
