/// A word-order mismatch found when the recognized words are all present.
class QuranWordOrderIssue {
  final int position;
  final String expectedWord;
  final String recognizedWord;

  const QuranWordOrderIssue({
    required this.position,
    required this.expectedWord,
    required this.recognizedWord,
  });

  Map<String, dynamic> toJson() => {
        'position': position,
        'expected': expectedWord,
        'recognized': recognizedWord,
      };
}

/// Text matching only; this does not assess tajweed or articulation.
class QuranRecitationComparison {
  final int matchedWords;
  final int expectedWords;
  final List<String> missingWords;
  final List<String> extraWords;
  final List<QuranWordOrderIssue> outOfOrderWords;

  const QuranRecitationComparison({
    required this.matchedWords,
    required this.expectedWords,
    required this.missingWords,
    required this.extraWords,
    this.outOfOrderWords = const [],
  });

  int get similarityPercent =>
      expectedWords == 0 ? 0 : (matchedWords * 100 / expectedWords).round();
}

class QuranRecitationMatcher {
  static List<String> normalizeWords(String text) {
    final value = text
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED]'), '')
        .replaceAll('ـ', '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ٱ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'[^\u0621-\u064A\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return value.isEmpty ? const [] : value.split(' ');
  }

  static QuranRecitationComparison compare({
    required String expected,
    required String recognized,
  }) {
    final a = normalizeWords(expected);
    final b = normalizeWords(recognized);
    final n = a.length;
    final m = b.length;
    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));

    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        dp[i][j] = a[i] == b[j]
            ? 1 + dp[i + 1][j + 1]
            : (dp[i + 1][j] >= dp[i][j + 1]
                ? dp[i + 1][j]
                : dp[i][j + 1]);
      }
    }

    final expectedCounts = <String, int>{};
    final recognizedCounts = <String, int>{};
    for (final word in a) {
      expectedCounts.update(word, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final word in b) {
      recognizedCounts.update(word, (count) => count + 1, ifAbsent: () => 1);
    }
    final sameWordsInDifferentOrder = n == m &&
        expectedCounts.length == recognizedCounts.length &&
        expectedCounts.entries.every(
          (entry) => recognizedCounts[entry.key] == entry.value,
        ) &&
        a.asMap().entries.any((entry) => entry.value != b[entry.key]);

    final outOfOrder = <QuranWordOrderIssue>[];
    if (sameWordsInDifferentOrder) {
      for (var index = 0; index < n; index++) {
        if (a[index] != b[index]) {
          outOfOrder.add(
            QuranWordOrderIssue(
              position: index + 1,
              expectedWord: a[index],
              recognizedWord: b[index],
            ),
          );
        }
      }
    }

    final missing = <String>[];
    final extra = <String>[];
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (a[i] == b[j]) {
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        missing.add(a[i++]);
      } else {
        extra.add(b[j++]);
      }
    }
    while (i < n) {
      missing.add(a[i++]);
    }
    while (j < m) {
      extra.add(b[j++]);
    }

    if (sameWordsInDifferentOrder) {
      missing.clear();
      extra.clear();
    }

    return QuranRecitationComparison(
      matchedWords: dp[0][0],
      expectedWords: n,
      missingWords: missing,
      extraWords: extra,
      outOfOrderWords: outOfOrder,
    );
  }
}