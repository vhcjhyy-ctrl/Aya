import 'dart:math';

/// Local khatmah plan, adapted for the bundled 604-page Madinah mushaf.
class KhatmahPlan {
  final int startJuz;
  final int startPage;
  final int durationDays;
  final String startDate;
  final List<int> completedDays;

  const KhatmahPlan({
    required this.startJuz,
    required this.startPage,
    required this.durationDays,
    required this.startDate,
    required this.completedDays,
  });

  factory KhatmahPlan.create({
    required int startJuz,
    required int startPage,
    required int durationDays,
    DateTime? startedAt,
  }) {
    final date = startedAt ?? DateTime.now();
    return KhatmahPlan(
      startJuz: startJuz.clamp(1, 30).toInt(),
      startPage: startPage.clamp(1, 604).toInt(),
      durationDays: durationDays.clamp(1, 365).toInt(),
      startDate: _dateKey(date),
      completedDays: const [],
    );
  }

  factory KhatmahPlan.fromJson(Map<String, dynamic> json) {
    final rawDays = json['completedDays'] as List? ?? const [];
    final days = rawDays
        .whereType<num>()
        .map((day) => day.toInt())
        .where((day) => day >= 1 && day <= 365)
        .toSet()
        .toList()
      ..sort();
    return KhatmahPlan(
      startJuz: ((json['startJuz'] as num?)?.toInt() ?? 1).clamp(1, 30).toInt(),
      startPage: ((json['startPage'] as num?)?.toInt() ?? 1).clamp(1, 604).toInt(),
      durationDays:
          ((json['durationDays'] as num?)?.toInt() ?? 30).clamp(1, 365).toInt(),
      startDate: (json['startDate'] ?? _dateKey(DateTime.now())).toString(),
      completedDays: days,
    );
  }

  Map<String, dynamic> toJson() => {
        'startJuz': startJuz,
        'startPage': startPage,
        'durationDays': durationDays,
        'startDate': startDate,
        'completedDays': completedDays,
      };

  int get totalPages => max(1, 605 - startPage);
  int get pagesPerDay => max(1, (totalPages / durationDays).ceil());
  int get completedCount => completedDays.length;
  int get remainingSessions => max(0, durationDays - completedCount);
  double get progress => (completedCount / durationDays).clamp(0.0, 1.0).toDouble();
  DateTime get beginsOn => DateTime.parse(startDate);

  int dayNumberAt(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final first = DateTime(beginsOn.year, beginsOn.month, beginsOn.day);
    return (normalized.difference(first).inDays + 1).clamp(1, durationDays).toInt();
  }

  int get currentDay => dayNumberAt(DateTime.now());
  bool isCompleted(int day) => completedDays.contains(day);

  int pageStartForDay(int day) {
    final safeDay = day.clamp(1, durationDays).toInt();
    return min(604, startPage + (safeDay - 1) * pagesPerDay);
  }

  int pageEndForDay(int day) {
    final first = pageStartForDay(day);
    return min(604, first + pagesPerDay - 1);
  }

  KhatmahPlan setDayCompleted(int day, bool completed) {
    final safeDay = day.clamp(1, durationDays).toInt();
    final days = <int>{...completedDays};
    if (completed) {
      days.add(safeDay);
    } else {
      days.remove(safeDay);
    }
    final sorted = days.toList()..sort();
    return KhatmahPlan(
      startJuz: startJuz,
      startPage: startPage,
      durationDays: durationDays,
      startDate: startDate,
      completedDays: sorted,
    );
  }

  static String _dateKey(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class QadaaLogEntry {
  final String type;
  final String label;
  final int count;
  final int completedAt;

  const QadaaLogEntry({
    required this.type,
    required this.label,
    required this.count,
    required this.completedAt,
  });

  factory QadaaLogEntry.fromJson(Map<String, dynamic> json) => QadaaLogEntry(
        type: (json['type'] ?? 'prayer').toString(),
        label: (json['label'] ?? '').toString(),
        count: ((json['count'] as num?)?.toInt() ?? 1).clamp(1, 1000).toInt(),
        completedAt: (json['completedAt'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'label': label,
        'count': count,
        'completedAt': completedAt,
      };
}

/// Device-local tracker adapted from the qadaa workflow in Khatmah.
class QadaaTrackerState {
  static const prayerKeys = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];

  final Map<String, int> prayerOwed;
  final Map<String, int> prayerCompleted;
  final int fastsOwed;
  final int fastsCompleted;
  final int dailyGoal;
  final List<QadaaLogEntry> logs;

  const QadaaTrackerState({
    required this.prayerOwed,
    required this.prayerCompleted,
    required this.fastsOwed,
    required this.fastsCompleted,
    required this.dailyGoal,
    required this.logs,
  });

  factory QadaaTrackerState.empty() => QadaaTrackerState(
        prayerOwed: {for (final key in prayerKeys) key: 0},
        prayerCompleted: {for (final key in prayerKeys) key: 0},
        fastsOwed: 0,
        fastsCompleted: 0,
        dailyGoal: 1,
        logs: const [],
      );

  factory QadaaTrackerState.fromJson(Map<String, dynamic> json) {
    Map<String, int> readCounts(String key) {
      final raw = json[key];
      final result = <String, int>{for (final item in prayerKeys) item: 0};
      if (raw is Map) {
        for (final entry in raw.entries) {
          final value = entry.value;
          if (prayerKeys.contains(entry.key.toString()) && value is num) {
            result[entry.key.toString()] = value.toInt().clamp(0, 1000000).toInt();
          }
        }
      }
      return result;
    }

    final rawLogs = json['logs'] as List? ?? const [];
    return QadaaTrackerState(
      prayerOwed: readCounts('prayerOwed'),
      prayerCompleted: readCounts('prayerCompleted'),
      fastsOwed:
          ((json['fastsOwed'] as num?)?.toInt() ?? 0).clamp(0, 1000000).toInt(),
      fastsCompleted:
          ((json['fastsCompleted'] as num?)?.toInt() ?? 0).clamp(0, 1000000).toInt(),
      dailyGoal: ((json['dailyGoal'] as num?)?.toInt() ?? 1).clamp(1, 50).toInt(),
      logs: rawLogs
          .whereType<Map>()
          .map((row) =>
              QadaaLogEntry.fromJson(Map<String, dynamic>.from(row)))
          .toList()
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt)),
    );
  }

  Map<String, dynamic> toJson() => {
        'prayerOwed': prayerOwed,
        'prayerCompleted': prayerCompleted,
        'fastsOwed': fastsOwed,
        'fastsCompleted': fastsCompleted,
        'dailyGoal': dailyGoal,
        'logs': logs.map((entry) => entry.toJson()).toList(),
      };

  int get remainingPrayers => prayerKeys.fold(
        0,
        (sum, key) => sum + remainingForPrayer(key),
      );

  int get completedPrayers =>
      prayerKeys.fold(0, (sum, key) => sum + completedForPrayer(key));

  int remainingForPrayer(String key) =>
      max(0, (prayerOwed[key] ?? 0) - (prayerCompleted[key] ?? 0));

  int completedForPrayer(String key) => prayerCompleted[key] ?? 0;
  int get remainingFasts => max(0, fastsOwed - fastsCompleted);

  QadaaTrackerState addPrayerDebt(String key, int count) {
    if (!prayerKeys.contains(key) || count <= 0) return this;
    final owed = Map<String, int>.from(prayerOwed);
    owed[key] = (owed[key] ?? 0) + count;
    return _copy(prayerOwed: owed);
  }

  QadaaTrackerState completePrayer(
    String key, {
    DateTime? completedAt,
  }) {
    if (!prayerKeys.contains(key) || remainingForPrayer(key) <= 0) {
      return this;
    }
    final completed = Map<String, int>.from(prayerCompleted);
    completed[key] = (completed[key] ?? 0) + 1;
    return _copy(
      prayerCompleted: completed,
      logs: _withLog(
        QadaaLogEntry(
          type: 'prayer',
          label: key,
          count: 1,
          completedAt:
              (completedAt ?? DateTime.now()).millisecondsSinceEpoch,
        ),
      ),
    );
  }

  QadaaTrackerState completeFullPrayerDay({DateTime? completedAt}) {
    final completed = Map<String, int>.from(prayerCompleted);
    var count = 0;
    for (final key in prayerKeys) {
      if (remainingForPrayer(key) > 0) {
        completed[key] = (completed[key] ?? 0) + 1;
        count++;
      }
    }
    if (count == 0) return this;
    return _copy(
      prayerCompleted: completed,
      logs: _withLog(
        QadaaLogEntry(
          type: 'fullDay',
          label: 'يوم كامل من الصلوات',
          count: count,
          completedAt:
              (completedAt ?? DateTime.now()).millisecondsSinceEpoch,
        ),
      ),
    );
  }

  QadaaTrackerState addFastDebt(int count) {
    if (count <= 0) return this;
    return _copy(fastsOwed: fastsOwed + count);
  }

  QadaaTrackerState completeFast({DateTime? completedAt}) {
    if (remainingFasts <= 0) return this;
    return _copy(
      fastsCompleted: fastsCompleted + 1,
      logs: _withLog(
        QadaaLogEntry(
          type: 'fast',
          label: 'يوم صيام',
          count: 1,
          completedAt:
              (completedAt ?? DateTime.now()).millisecondsSinceEpoch,
        ),
      ),
    );
  }

  QadaaTrackerState setDailyGoal(int goal) =>
      _copy(dailyGoal: goal.clamp(1, 50).toInt());

  int currentStreak({DateTime? now}) {
    final counts = _completedByDate();
    final today = now ?? DateTime.now();
    var cursor = DateTime(today.year, today.month, today.day);
    if ((counts[_dateKey(cursor)] ?? 0) < dailyGoal) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    if ((counts[_dateKey(cursor)] ?? 0) < dailyGoal) return 0;
    var streak = 0;
    while ((counts[_dateKey(cursor)] ?? 0) >= dailyGoal) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int longestStreak() {
    final counts = _completedByDate();
    final dates = counts.keys.where((key) => counts[key]! >= dailyGoal).toList()
      ..sort();
    var longest = 0;
    var current = 0;
    DateTime? previous;
    for (final key in dates) {
      final parts = key.split('-').map(int.parse).toList();
      final date = DateTime(parts[0], parts[1], parts[2]);
      if (previous != null && date.difference(previous).inDays == 1) {
        current++;
      } else {
        current = 1;
      }
      longest = max(longest, current);
      previous = date;
    }
    return longest;
  }

  Map<String, int> _completedByDate() {
    final counts = <String, int>{};
    for (final log in logs) {
      final date =
          DateTime.fromMillisecondsSinceEpoch(log.completedAt).toLocal();
      final key = _dateKey(date);
      counts[key] = (counts[key] ?? 0) + log.count;
    }
    return counts;
  }

  QadaaTrackerState _copy({
    Map<String, int>? prayerOwed,
    Map<String, int>? prayerCompleted,
    int? fastsOwed,
    int? fastsCompleted,
    int? dailyGoal,
    List<QadaaLogEntry>? logs,
  }) =>
      QadaaTrackerState(
        prayerOwed: prayerOwed ?? this.prayerOwed,
        prayerCompleted: prayerCompleted ?? this.prayerCompleted,
        fastsOwed: fastsOwed ?? this.fastsOwed,
        fastsCompleted: fastsCompleted ?? this.fastsCompleted,
        dailyGoal: dailyGoal ?? this.dailyGoal,
        logs: logs ?? this.logs,
      );

  List<QadaaLogEntry> _withLog(QadaaLogEntry entry) {
    final result = [entry, ...logs];
    return result.length > 100 ? result.sublist(0, 100) : result;
  }

  static String _dateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
