import '../models/offline_surahs.dart';
import 'quran_recitation_matcher.dart';

enum QuranVoiceCommand {
  start,
  stop,
  pauseRecitation,
  next,
  previous,
  repeat,
  showAyah,
  hideAyah,
  markMemorized,
  needsReview,
  unknown,
}

/// Arabic voice-intent helpers. Surah names are resolved against the app's
/// bundled Quran catalogue; the language model is not asked to invent a match.
class QuranVoiceIntent {
  static const Set<String> _pausePhrases = {
    'وقف التسميع',
    'اوقف التسميع',
    'توقف عن التسميع',
    'وقف التلاوه',
    'اوقف التلاوه',
  };

  static const Set<String> _pauseCommands = {
    'قف',
    'وقف',
    'اقف',
    'توقف',
    'ايقاف',
    'استني',
    'استنى',
    'انتظر',
    'تمهل',
  };

  static String normalize(String text) {
    return QuranRecitationMatcher.normalizeWords(text)
        .join(' ')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ٱ', 'ا')
        .replaceAll('ى', 'ي')
        .trim();
  }

  static int? findSurahNumber(String spokenText) {
    final spoken = normalize(spokenText).split(' ');
    if (spoken.isEmpty) return null;

    for (final surah in allOfflineSurahs) {
      final nameWords = QuranRecitationMatcher.normalizeWords(surah.name)
          .where((word) => word != 'سوره')
          .toList();
      if (nameWords.isEmpty || nameWords.length > spoken.length) continue;

      for (var start = 0; start <= spoken.length - nameWords.length; start++) {
        var matches = true;
        for (var offset = 0; offset < nameWords.length; offset++) {
          if (spoken[start + offset] != nameWords[offset]) {
            matches = false;
            break;
          }
        }
        if (matches) return surah.number;
      }
    }
    return null;
  }

  static String stripTrailingPauseCommand(String spokenText) {
    final trimmed = spokenText.trim();
    if (trimmed.isEmpty) return '';
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.isEmpty) return '';

    final normalizedPhrase = normalize(trimmed);
    for (final pausePhrase in _pausePhrases) {
      final normalizedPausePhrase = normalize(pausePhrase);
      if (normalizedPhrase == normalizedPausePhrase) return '';
      if (normalizedPhrase.endsWith(' ' + normalizedPausePhrase)) {
        final count = normalizedPausePhrase.split(' ').length;
        return words.take(words.length - count).join(' ').trim();
      }
    }

    if (_pauseCommands.contains(normalize(words.last))) {
      words.removeLast();
    }
    return words.join(' ').trim();
  }

  static QuranVoiceCommand parseCommand(String spokenText) {
    final phrase = normalize(spokenText);
    final words = phrase.split(' ').where((word) => word.isNotEmpty).toSet();

    if (phrase.contains('انهاء الجلسه') ||
        phrase.contains('انهي الجلسه') ||
        phrase.contains('انهاء الحوار') ||
        phrase.contains('انهي الحوار') ||
        phrase.contains('اقفل المساعد') ||
        phrase.contains('اقفل الجلسه')) {
      return QuranVoiceCommand.stop;
    }
    if (_pauseCommands.contains(phrase) ||
        _pauseCommands.any((command) => phrase.endsWith(' ' + command)) ||
        _pausePhrases.any(
          (pausePhrase) => phrase == pausePhrase ||
              phrase.endsWith(' ' + pausePhrase),
        )) {
      return QuranVoiceCommand.pauseRecitation;
    }
    if (words.any(const {'التالي', 'كمل', 'اكمل', 'تابع'}.contains) ||
        phrase.contains('الايه التاليه')) {
      return QuranVoiceCommand.next;
    }
    if (words.any(const {'السابق', 'ارجع', 'قبلي'}.contains) ||
        phrase.contains('الايه السابقه')) {
      return QuranVoiceCommand.previous;
    }
    if (words.any(const {'كرر', 'اعاده', 'اعد', 'تاني'}.contains) ||
        phrase.contains('مره اخرى')) {
      return QuranVoiceCommand.repeat;
    }
    if (words.any(const {'اظهر', 'اعرض', 'اكشف'}.contains)) {
      return QuranVoiceCommand.showAyah;
    }
    if (words.any(const {'اخف', 'اخفي', 'اخفاء'}.contains)) {
      return QuranVoiceCommand.hideAyah;
    }
    if (words.any(const {'ابدا', 'ابدأ', 'سمع', 'يلا'}.contains) ||
        phrase.contains('ابدأ التسميع') ||
        phrase.contains('ابدا التسميع')) {
      return QuranVoiceCommand.start;
    }
    if (phrase.contains('اتممت المراجعه')) {
      return QuranVoiceCommand.markMemorized;
    }
    if (words.any(const {'راجعها', 'راجع', 'مراجعه', 'صعبه'}.contains) ||
        phrase.contains('احتاج مراجعه') ||
        phrase.contains('تحتاج مراجعه') ||
        phrase.contains('خليها مراجعه') ||
        phrase.contains('سجلها للمراجعه')) {
      return QuranVoiceCommand.needsReview;
    }
    if (words.any(const {
      'احفظها',
      'احفظ',
      'حفظتها',
      'سجلها',
      'سجل',
      'اتقنتها',
      'اتقنت',
      'اتممت',
    }.contains) ||
        phrase.contains('سجلها في الحفظ') ||
        phrase.contains('اضفها للمحفوظ') ||
        phrase.contains('اتممت المراجعه')) {
      return QuranVoiceCommand.markMemorized;
    }
    return QuranVoiceCommand.unknown;
  }
}
