/// Text matching only; this does not assess tajweed or articulation.
class QuranRecitationComparison {
  final int matchedWords;
  final int expectedWords;
  final List<String> missingWords;
  final List<String> extraWords;

  const QuranRecitationComparison({
    required this.matchedWords,
    required this.expectedWords,
    required this.missingWords,
    required this.extraWords,
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

    return QuranRecitationComparison(
      matchedWords: dp[0][0],
      expectedWords: n,
      missingWords: missing,
      extraWords: extra,
    );
  }
}