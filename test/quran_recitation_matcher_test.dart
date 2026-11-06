import 'package:flutter_test/flutter_test.dart';
import 'package:aya_app/services/quran_recitation_matcher.dart';

void main() {
  group('QuranRecitationMatcher', () {
    test('ignores tashkeel and alef variants', () {
      final result = QuranRecitationMatcher.compare(
        expected: 'الرَّحْمَٰنِ الرَّحِيمِ',
        recognized: 'الرحمن الرحيم',
      );
      expect(result.matchedWords, 2);
      expect(result.similarityPercent, 100);
      expect(result.missingWords, isEmpty);
    });

    test('reports omitted and extra words', () {
      final result = QuranRecitationMatcher.compare(
        expected: 'الحمد لله رب العالمين',
        recognized: 'الحمد لله العالمين زيادة',
      );
      expect(result.matchedWords, 3);
      expect(result.missingWords, ['رب']);
      expect(result.extraWords, ['زياده']);
      expect(result.similarityPercent, 75);
    });

    test('identifies word-order changes separately from missing words', () {
      final result = QuranRecitationMatcher.compare(
        expected: 'الحمد لله رب العالمين',
        recognized: 'الحمد رب لله العالمين',
      );
      expect(result.missingWords, isEmpty);
      expect(result.extraWords, isEmpty);
      expect(result.outOfOrderWords, hasLength(2));
      expect(result.outOfOrderWords.first.position, 2);
      expect(result.outOfOrderWords.first.expectedWord, 'لله');
      expect(result.outOfOrderWords.first.recognizedWord, 'رب');
    });

    test('does not report word-order issues for repeated correct wording', () {
      final result = QuranRecitationMatcher.compare(
        expected: 'قل هو الله أحد',
        recognized: 'قل هو الله احد',
      );
      expect(result.outOfOrderWords, isEmpty);
    });

    test('handles empty recognition', () {
      final result = QuranRecitationMatcher.compare(
        expected: 'قل هو الله احد',
        recognized: '',
      );
      expect(result.matchedWords, 0);
      expect(result.missingWords, ['قل', 'هو', 'الله', 'احد']);
      expect(result.similarityPercent, 0);
    });
  });
}