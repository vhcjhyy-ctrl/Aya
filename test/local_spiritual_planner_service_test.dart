import 'package:flutter_test/flutter_test.dart';
import 'package:aya_app/services/local_spiritual_planner_service.dart';

void main() {
  group('KhatmahPlan', () {
    test('distributes the remaining pages over the requested duration', () {
      final plan = KhatmahPlan.create(
        startJuz: 2,
        startPage: 22,
        durationDays: 30,
        startedAt: DateTime(2026, 11, 7),
      );

      expect(plan.totalPages, 583);
      expect(plan.pagesPerDay, 20);
      expect(plan.pageStartForDay(1), 22);
      expect(plan.pageEndForDay(1), 41);
      expect(plan.pageEndForDay(30), 604);
    });

    test('records a completed day once and supports undo', () {
      final plan = KhatmahPlan.create(
        startJuz: 1,
        startPage: 1,
        durationDays: 10,
        startedAt: DateTime(2026, 11, 7),
      );
      final completed = plan.setDayCompleted(1, true);
      expect(completed.completedCount, 1);
      expect(completed.progress, 0.1);
      expect(completed.setDayCompleted(1, true).completedCount, 1);
      expect(completed.setDayCompleted(1, false).completedCount, 0);
    });

    test('round-trips JSON without losing completed sessions', () {
      final plan = KhatmahPlan.create(
        startJuz: 4,
        startPage: 62,
        durationDays: 45,
        startedAt: DateTime(2026, 11, 7),
      ).setDayCompleted(1, true).setDayCompleted(3, true);
      final restored = KhatmahPlan.fromJson(plan.toJson());

      expect(restored.startJuz, 4);
      expect(restored.durationDays, 45);
      expect(restored.completedDays, [1, 3]);
    });
  });

  group('QadaaTrackerState', () {
    test('cannot complete more prayers than the entered debt', () {
      final state = QadaaTrackerState.empty()
          .addPrayerDebt('fajr', 2)
          .completePrayer('fajr', completedAt: DateTime(2026, 11, 7))
          .completePrayer('fajr', completedAt: DateTime(2026, 11, 7))
          .completePrayer('fajr', completedAt: DateTime(2026, 11, 7));

      expect(state.prayerOwed['fajr'], 2);
      expect(state.completedForPrayer('fajr'), 2);
      expect(state.remainingForPrayer('fajr'), 0);
      expect(state.logs.length, 2);
    });

    test('full-day action advances only prayers with remaining debt', () {
      final state = QadaaTrackerState.empty()
          .addPrayerDebt('fajr', 1)
          .addPrayerDebt('dhuhr', 2)
          .completeFullPrayerDay(completedAt: DateTime(2026, 11, 7));

      expect(state.completedForPrayer('fajr'), 1);
      expect(state.completedForPrayer('dhuhr'), 1);
      expect(state.remainingPrayers, 1);
      expect(state.logs.single.count, 2);
    });

    test('tracks fast debt separately from prayer debt', () {
      final state = QadaaTrackerState.empty()
          .addFastDebt(3)
          .completeFast(completedAt: DateTime(2026, 11, 7));

      expect(state.remainingFasts, 2);
      expect(state.fastsCompleted, 1);
      expect(state.remainingPrayers, 0);
    });

    test('calculates a current streak from the daily completion goal', () {
      final now = DateTime(2026, 11, 7, 12);
      var state = QadaaTrackerState.empty().setDailyGoal(2);
      state = state
          .addFastDebt(4)
          .completeFast(completedAt: DateTime(2026, 11, 5, 12))
          .completeFast(completedAt: DateTime(2026, 11, 5, 13))
          .completeFast(completedAt: DateTime(2026, 11, 6, 12))
          .completeFast(completedAt: DateTime(2026, 11, 6, 13));

      expect(state.currentStreak(now: now), 2);
      expect(state.longestStreak(), 2);
    });

    test('round-trips debt and history through JSON', () {
      final state = QadaaTrackerState.empty()
          .addPrayerDebt('isha', 5)
          .completePrayer('isha', completedAt: DateTime(2026, 11, 7))
          .addFastDebt(2)
          .completeFast(completedAt: DateTime(2026, 11, 7));
      final restored = QadaaTrackerState.fromJson(state.toJson());

      expect(restored.remainingForPrayer('isha'), 4);
      expect(restored.remainingFasts, 1);
      expect(restored.logs.length, 2);
    });
  });
}
