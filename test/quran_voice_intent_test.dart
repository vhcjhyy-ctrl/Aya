import 'package:flutter_test/flutter_test.dart';
import 'package:aya_app/models/offline_surahs.dart';
import 'package:aya_app/services/quran_voice_intent.dart';

void main() {
  group('QuranVoiceIntent', () {
    test('resolves a spoken Arabic surah name', () {
      expect(QuranVoiceIntent.findSurahNumber('سورة البقرة'), 2);
      expect(QuranVoiceIntent.findSurahNumber('حفظت سورة البقرة اليوم'), 2);
    });

    test('resolves names with hamza variants', () {
      expect(QuranVoiceIntent.findSurahNumber('سورة آل عمران'), 3);
    });

    test('recognizes start, stop, repeat, and next commands', () {
      expect(
        QuranVoiceIntent.parseCommand('ابدأ التسميع'),
        QuranVoiceCommand.start,
      );
      expect(
        QuranVoiceIntent.parseCommand('قف'),
        QuranVoiceCommand.pauseRecitation,
      );
      expect(
        QuranVoiceIntent.parseCommand('اقف'),
        QuranVoiceCommand.pauseRecitation,
      );
      expect(
        QuranVoiceIntent.parseCommand('استنى'),
        QuranVoiceCommand.pauseRecitation,
      );
      expect(
        QuranVoiceIntent.parseCommand('استني'),
        QuranVoiceCommand.pauseRecitation,
      );
      expect(
        QuranVoiceIntent.parseCommand('تمهل'),
        QuranVoiceCommand.pauseRecitation,
      );
      expect(
        QuranVoiceIntent.parseCommand('اقفل المساعد'),
        QuranVoiceCommand.stop,
      );
      expect(
        QuranVoiceIntent.parseCommand('كرر الآية'),
        QuranVoiceCommand.repeat,
      );
      expect(
        QuranVoiceIntent.parseCommand('كمل'),
        QuranVoiceCommand.next,
      );
    });

    test('removes a trailing pause command from recognized recitation', () {
      expect(
        QuranVoiceIntent.stripTrailingPauseCommand('الحمد لله رب العالمين قف'),
        'الحمد لله رب العالمين',
      );
      expect(
        QuranVoiceIntent.stripTrailingPauseCommand('اقف'),
        isEmpty,
      );
    });

    test('resolves every bundled Arabic surah name', () {
      for (final surah in allOfflineSurahs) {
        expect(
          QuranVoiceIntent.findSurahNumber(surah.name),
          surah.number,
          reason: 'Failed to resolve a bundled surah name',
        );
      }
    });

    test('supports ending the session with a natural phrase', () {
      expect(
        QuranVoiceIntent.parseCommand('من فضلك انهي الجلسة'),
        QuranVoiceCommand.stop,
      );
    });

    test('recognizes verbal memorized and review decisions', () {
      expect(
        QuranVoiceIntent.parseCommand('سجلها في الحفظ'),
        QuranVoiceCommand.markMemorized,
      );
      expect(
        QuranVoiceIntent.parseCommand('احفظها'),
        QuranVoiceCommand.markMemorized,
      );
      expect(
        QuranVoiceIntent.parseCommand('أحتاج مراجعة'),
        QuranVoiceCommand.needsReview,
      );
      expect(
        QuranVoiceIntent.parseCommand('خليها مراجعة'),
        QuranVoiceCommand.needsReview,
      );
      expect(
        QuranVoiceIntent.parseCommand('سجلها للمراجعة'),
        QuranVoiceCommand.needsReview,
      );
      expect(
        QuranVoiceIntent.parseCommand('أتممت المراجعة'),
        QuranVoiceCommand.markMemorized,
      );
    });

    test('does not invent an unknown surah', () {
      expect(QuranVoiceIntent.findSurahNumber('سورة غير موجودة'), isNull);
    });
  });
}
