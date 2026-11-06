import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/fiqh_data.dart';
import '../models/fiqh_model.dart';
import '../services/database_service.dart';
import '../services/hadith_database_service.dart';
import '../services/translation_service.dart';
import '../utils/text_helpers.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final List<_AssistantTurn> _turns = [
    _AssistantTurn(
      text: TranslationService.isArabic
          ? 'مرحبًا بك في سؤالك. اكتب مسألتك، وسأبحث في القرآن والأحاديث ومكتبة الفقه داخل التطبيق، وأعرض لك النصوص والمراجع المتاحة.'
          : 'Welcome to Ask. Enter your question and I will search the Quran, Hadith, and the app’s fiqh library, then show the available texts and references.',
    ),
  ];

  bool _isSearching = false;
  String _status = '';
  static Future<void>? _arabicHadithSeed;
  static Future<void>? _englishHadithSeed;

  static const List<String> _coreHadithBooks = [
    'bukhari',
    'muslim',
    'abudawud',
    'tirmidhi',
    'nasai',
    'ibnmajah',
  ];

  static const Map<String, String> _bookNames = {
    'bukhari': 'صحيح البخاري',
    'muslim': 'صحيح مسلم',
    'abudawud': 'سنن أبي داود',
    'tirmidhi': 'جامع الترمذي',
    'nasai': 'سنن النسائي',
    'ibnmajah': 'سنن ابن ماجه',
  };

  static const Map<String, String> _bookNamesEnglish = {
    'bukhari': 'Sahih al-Bukhari',
    'muslim': 'Sahih Muslim',
    'abudawud': 'Sunan Abu Dawud',
    'tirmidhi': 'Jami at-Tirmidhi',
    'nasai': 'Sunan an-Nasa’i',
    'ibnmajah': 'Sunan Ibn Majah',
  };

  static const Set<String> _stopWords = {
    'ما', 'ماذا', 'هل', 'هو', 'هي', 'عن', 'من', 'في', 'على', 'الى', 'إلى',
    'مع', 'كيف', 'متى', 'اين', 'أين', 'كان', 'كانت', 'حكم', 'حكمه',
    'وما', 'وهو', 'الذي', 'التي', 'هذا', 'هذه', 'ذلك', 'تلك', 'لي', 'لنا',
    'the', 'what', 'how', 'does', 'is', 'are', 'of', 'in', 'on', 'to', 'for',
  };

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<String> _keywords(String question) {
    final normalized = question
        .replaceAll(RegExp(r'[؟?!،,.;:()\[\]{}"“”]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final words = normalized
        .split(' ')
        .map((word) => word.trim())
        .where((word) => word.length >= 3 && !_stopWords.contains(word))
        .toList();

    final unique = <String>[];
    for (final word in words.reversed) {
      if (!unique.contains(word)) unique.add(word);
    }
    return unique.reversed.take(4).toList();
  }

  String _normalizeSearchText(String value) {
    return stripTashkeel(value)
        .toLowerCase()
        .replaceAll(RegExp(r'[^\u0600-\u06FFa-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<_FiqhMatch> _searchFiqhTopics(
    String question,
    List<String> keywords,
  ) {
    final normalizedQuestion = _normalizeSearchText(question);
    final terms = keywords
        .map(_normalizeSearchText)
        .where((term) => term.length >= 2)
        .toSet()
        .toList();
    final isArabic = TranslationService.isArabic;
    final matches = <_FiqhMatch>[];

    for (final topic in FiqhData.topics) {
      final title = _normalizeSearchText(topic.getTitle(isArabic));
      final summary = _normalizeSearchText(topic.getSummary(isArabic));
      final topicKeywords = topic.keywords
          .map(_normalizeSearchText)
          .where((word) => word.isNotEmpty)
          .toList();
      final sectionsText = topic.sections
          .expand((section) => <String>[
                section.getTitle(isArabic),
                section.getContent(isArabic),
                ...section.getBulletPoints(isArabic),
              ])
          .map(_normalizeSearchText)
          .join(' ');

      var topicScore = 0;
      for (final term in terms) {
        if (title.contains(term)) topicScore += 3;
        if (summary.contains(term)) topicScore += 2;
        if (topicKeywords.any((keyword) => keyword.contains(term) || term.contains(keyword))) {
          topicScore += 3;
        }
        if (sectionsText.contains(term)) topicScore += 1;
      }

      FiqhFaq? bestFaq;
      var bestFaqScore = 0;
      for (final faq in topic.faqs) {
        final faqQuestion = _normalizeSearchText(faq.getQuestion(isArabic));
        final faqAnswer = _normalizeSearchText(faq.getAnswer(isArabic));
        var score = 0;

        if (normalizedQuestion.length >= 7 &&
            (faqQuestion.contains(normalizedQuestion) ||
                normalizedQuestion.contains(faqQuestion))) {
          score += 12;
        }

        for (final term in terms) {
          if (faqQuestion.contains(term)) {
            score += 5;
          } else if (faqAnswer.contains(term)) {
            score += 1;
          }
        }

        if (score > bestFaqScore) {
          bestFaq = faq;
          bestFaqScore = score;
        }
      }

      if (bestFaq != null && bestFaqScore >= 5) {
        matches.add(
          _FiqhMatch(
            topic: topic,
            faq: bestFaq,
            score: bestFaqScore + topicScore,
          ),
        );
      } else if (topicScore >= 6) {
        matches.add(
          _FiqhMatch(
            topic: topic,
            score: topicScore,
          ),
        );
      }
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches.take(3).toList();
  }

  Future<void> _ensureHadithBooks(
    DatabaseService database,
    String lang, {
    void Function(String message)? onProgress,
  }) async {
    Future<void> seed() async {
      for (final bookId in _coreHadithBooks) {
        if (await database.hadith.isHadithBookDownloaded(bookId, lang)) {
          continue;
        }

        final bookName = lang == 'ara'
            ? (_bookNames[bookId] ?? bookId)
            : (_bookNamesEnglish[bookId] ?? bookId);
        onProgress?.call(
          lang == 'ara'
              ? 'إعداد فهرس $bookName...'
              : 'Indexing $bookName...',
        );

        try {
          final json = await rootBundle.loadString(
            'assets/hadith/$lang-$bookId.json',
          );
          final hadiths = await HadithDatabaseService.parseHadithJson(json);
          await database.hadith.insertHadithBook(bookId, lang, hadiths);
        } catch (_) {
          // A missing or damaged collection is skipped; no replacement narration is invented.
        }
      }
    }

    if (lang == 'ara') {
      _arabicHadithSeed ??= seed();
      await _arabicHadithSeed;
    } else {
      _englishHadithSeed ??= seed();
      await _englishHadithSeed;
    }
  }

  Future<void> _ask([String? suppliedQuestion]) async {
    final question = (suppliedQuestion ?? _controller.text).trim();
    if (question.isEmpty || _isSearching) return;

    _controller.clear();
    setState(() {
      _turns.add(_AssistantTurn(text: question, isUser: true));
      _isSearching = true;
      _status = TranslationService.isArabic
          ? 'أبحث في المصادر الإسلامية المحلية...'
          : 'Searching the local Islamic sources...';
    });
    _scrollToBottom();

    try {
      final database = await DatabaseService.getInstance();
      final lang = TranslationService.isArabic ? 'ara' : 'eng';
      await _ensureHadithBooks(
        database,
        lang,
        onProgress: (message) {
          if (mounted) setState(() => _status = message);
        },
      );

      final keywords = _keywords(question);
      final searchTerms = keywords.isEmpty ? <String>[question] : keywords;
      final fiqhMatches = _searchFiqhTopics(question, keywords);
      final ayahRows = <String, Map<String, dynamic>>{};
      final ayahScores = <String, int>{};
      final hadithRows = <String, Map<String, dynamic>>{};
      final hadithScores = <String, int>{};

      for (final term in searchTerms) {
        try {
          final matches = await database.searchAyahs(term);
          for (final row in matches.take(18)) {
            final key = '${row['surah_number']}:${row['ayah_number']}';
            ayahRows[key] = row;
            ayahScores[key] = (ayahScores[key] ?? 0) + 1;
          }
        } catch (_) {}
      }

      for (final term in searchTerms) {
        try {
          final matches = await database.hadith.searchAllHadiths(lang, term, 14);
          for (final row in matches) {
            final key = '${row['book_id']}:${row['hadith_number']}:${row['id']}';
            hadithRows[key] = row;
            hadithScores[key] = (hadithScores[key] ?? 0) + 1;
          }
        } catch (_) {}
      }

      final rankedAyahs = ayahRows.entries.toList()
        ..sort((a, b) => (ayahScores[b.key] ?? 0).compareTo(ayahScores[a.key] ?? 0));
      final rankedHadiths = hadithRows.entries.toList()
        ..sort((a, b) => (hadithScores[b.key] ?? 0).compareTo(hadithScores[a.key] ?? 0));

      final ayahs = rankedAyahs.take(4).map((entry) => entry.value).toList();
      final hadiths = rankedHadiths.take(4).map((entry) => entry.value).toList();

      final hasAnyEvidence =
          ayahs.isNotEmpty || hadiths.isNotEmpty || fiqhMatches.isNotEmpty;
      final responseText = !hasAnyEvidence
          ? (TranslationService.isArabic
              ? 'لم أعثر على جواب مطابق في مكتبة الفقه أو نصوص القرآن والأحاديث المتاحة محليًا. جرّب صياغة السؤال بكلمات أوضح. لا أختلق حكمًا شرعيًا عند غياب الدليل.'
              : 'No close answer was found in the local fiqh library, Quran, or hadith texts. Try clearer wording. I will not invent a religious ruling without a source.')
          : (fiqhMatches.isNotEmpty
              ? (TranslationService.isArabic
                  ? 'وجدت مادة فقهية ذات صلة من مكتبة التطبيق، وأرفقت معها مواضع الأدلة المتاحة. راجع التنبيه بشأن اختلاف المسائل الفقهية.'
                  : 'I found relevant material in the app’s fiqh library and included its available evidence references. Review the note about differences in fiqh rulings.')
              : (TranslationService.isArabic
                  ? 'عُثر على نصوص ذات صلة بسؤالك. راجع الآيات والأحاديث ومراجعها أدناه؛ هذه نتائج بحث موثقة وليست فتوى مستقلة.'
                  : 'Relevant source texts were found. Review the verses, narrations, and references below. These are retrieved sources, not an independent fatwa.'));

      if (!mounted) return;
      setState(() {
        _turns.add(
          _AssistantTurn(
            text: responseText,
            ayahs: ayahs,
            hadiths: hadiths,
            fiqhMatches: fiqhMatches,
          ),
        );
        _isSearching = false;
        _status = '';
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _turns.add(
          _AssistantTurn(
            text: TranslationService.isArabic
                ? 'تعذّر إكمال البحث الآن. تأكد من توفر مساحة تخزين كافية ثم حاول مرة أخرى.'
                : 'The search could not be completed. Check available storage and try again.',
          ),
        );
        _isSearching = false;
        _status = '';
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _hadithBookName(dynamic rawBookId) {
    final bookId = rawBookId?.toString().replaceFirst(RegExp(r'^(ara|eng)_'), '') ?? '';
    return TranslationService.isArabic
        ? (_bookNames[bookId] ?? bookId)
        : (_bookNamesEnglish[bookId] ?? bookId);
  }

  String _hadithGrade(Map<String, dynamic> hadith) {
    final rawGrades = hadith['grades'];
    List<dynamic> grades = [];
    try {
      if (rawGrades is List) {
        grades = rawGrades;
      } else if (rawGrades is String && rawGrades.isNotEmpty) {
        final decoded = jsonDecode(rawGrades);
        if (decoded is List) grades = decoded;
      }
    } catch (_) {}

    final labels = grades
        .map((grade) => grade is Map
            ? (grade['grade']?.toString() ?? '')
            : grade.toString())
        .where((label) => label.trim().isNotEmpty)
        .toSet()
        .toList();

    if (labels.isNotEmpty) return labels.take(2).join('، ');

    final bookId = hadith['book_id']
            ?.toString()
            .replaceFirst(RegExp(r'^(ara|eng)_'), '') ??
        '';
    if (bookId == 'bukhari' || bookId == 'muslim') {
      return TranslationService.isArabic ? 'صحيح' : 'Sahih';
    }

    return TranslationService.isArabic
        ? 'لم تُسجل درجة لهذا الحديث في البيانات المحلية'
        : 'No grade is recorded for this narration in the local data';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = TranslationService.isArabic;
    final gold = const Color(0xFFE5C158);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: gold.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.auto_awesome, color: gold, size: 21),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic ? 'سؤالك' : 'Ask',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                Text(
                  isArabic ? 'مساعد البحث الإسلامي' : 'Islamic source assistant',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.textTheme.bodySmall?.color,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              children: [
                _buildSourceNotice(theme),
                const SizedBox(height: 14),
                for (final turn in _turns) _buildTurn(theme, turn),
                if (_isSearching)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _status,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_turns.length == 1 && !_isSearching) ...[
                  const SizedBox(height: 8),
                  Text(
                    isArabic ? 'جرّب أن تسأل عن:' : 'Try asking about:',
                    style: TextStyle(
                      color: theme.textTheme.bodyMedium?.color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      isArabic ? 'الوضوء' : 'Ablution',
                      isArabic ? 'الصلاة' : 'Prayer',
                      isArabic ? 'الزكاة' : 'Zakat',
                      isArabic ? 'الصيام' : 'Fasting',
                    ].map((label) {
                      return ActionChip(
                        label: Text(label),
                        onPressed: () => _ask(label),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          _buildComposer(theme),
        ],
      ),
    );
  }

  Widget _buildSourceNotice(ThemeData theme) {
    final isArabic = TranslationService.isArabic;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isArabic
                  ? 'يبحث «سؤالك» في نصوص القرآن والأحاديث المخزّنة داخل التطبيق، ويعرض المصدر بدل اختلاق إجابة. لا يغني عن سؤال أهل العلم في النوازل والفتاوى.'
                  : 'Ask searches Quranic text and hadith stored in the app and shows its sources instead of inventing an answer. It does not replace qualified scholarly guidance.',
              style: TextStyle(
                height: 1.5,
                fontSize: 12,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurn(ThemeData theme, _AssistantTurn turn) {
    final isArabic = TranslationService.isArabic;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: turn.isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: turn.isUser
                ? AlignmentDirectional.centerStart
                : AlignmentDirectional.centerEnd,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              decoration: BoxDecoration(
                color: turn.isUser
                    ? theme.colorScheme.primary
                    : theme.cardColor,
                borderRadius: BorderRadius.circular(17),
                border: turn.isUser
                    ? null
                    : Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
              ),
              child: Text(
                turn.text,
                textAlign: TextAlign.start,
                style: TextStyle(
                  height: 1.55,
                  color: turn.isUser
                      ? theme.colorScheme.onPrimary
                      : theme.textTheme.bodyLarge?.color,
                ),
              ),
            ),
          ),
          if (turn.ayahs.isNotEmpty ||
              turn.hadiths.isNotEmpty ||
              turn.fiqhMatches.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (turn.fiqhMatches.isNotEmpty) ...[
              _sectionTitle(theme, isArabic ? 'من مكتبة الفقه الإسلامي' : 'From the fiqh library'),
              const SizedBox(height: 8),
              for (final match in turn.fiqhMatches) _buildFiqhCard(theme, match),
            ],
            if (turn.ayahs.isNotEmpty) ...[
              _sectionTitle(theme, isArabic ? 'من القرآن الكريم' : 'From the Quran'),
              const SizedBox(height: 8),
              for (final ayah in turn.ayahs) _buildAyahCard(theme, ayah),
            ],
            if (turn.hadiths.isNotEmpty) ...[
              const SizedBox(height: 6),
              _sectionTitle(theme, isArabic ? 'من السنة النبوية' : 'From Hadith'),
              const SizedBox(height: 8),
              for (final hadith in turn.hadiths) _buildHadithCard(theme, hadith),
            ],
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'تنبيه: عرض النصوص لا يساوي تحرير الحكم الشرعي أو جمع جميع أدلته.'
                  : 'Note: Retrieved texts are not a complete legal ruling or a survey of all evidence.',
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFiqhCard(ThemeData theme, _FiqhMatch match) {
    final isArabic = TranslationService.isArabic;
    final topic = match.topic;
    final title = topic.getTitle(isArabic);
    final gold = const Color(0xFFE5C158);
    final evidence = topic.evidences.take(3).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      color: theme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                color: gold,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            if (match.faq != null) ...[
              Text(
                match.faq!.getQuestion(isArabic),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                match.faq!.getAnswer(isArabic),
                style: TextStyle(
                  height: 1.65,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
            ] else ...[
              Text(
                topic.getSummary(isArabic),
                style: TextStyle(
                  height: 1.6,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              if (topic.sections.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  topic.sections.first.getTitle(isArabic),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  topic.sections.first.getContent(isArabic),
                  style: TextStyle(
                    height: 1.55,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
              ],
            ],
            if (evidence.isNotEmpty) ...[
              const SizedBox(height: 10),
              Divider(color: theme.dividerColor.withValues(alpha: 0.45)),
              Text(
                isArabic ? 'المراجع المذكورة في الموضوع:' : 'References listed in this topic:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(height: 4),
              for (final item in evidence)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        item.type == 'quran' ? Icons.menu_book : Icons.library_books,
                        size: 14,
                        color: gold,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.reference,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'المصدر: مادة فقهية داخل التطبيق. قد تختلف بعض المسائل باختلاف المذاهب وأقوال أهل العلم.'
                  : 'Source: fiqh material bundled with the app. Some rulings differ across schools and scholarly opinions.',
              style: TextStyle(
                fontSize: 10,
                height: 1.5,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) {
    return Row(
      children: [
        const Icon(Icons.menu_book, size: 17, color: Color(0xFFE5C158)),
        const SizedBox(width: 7),
        Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: theme.textTheme.bodyLarge?.color,
          ),
        ),
      ],
    );
  }

  Widget _buildAyahCard(ThemeData theme, Map<String, dynamic> ayah) {
    final surah = ayah['surah_name']?.toString() ?? 'القرآن الكريم';
    final number = ayah['ayah_number']?.toString() ?? '';
    final text = ayah['text_arabic']?.toString() ?? '';
    final translation = ayah['text_english']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Amiri',
                fontSize: 22,
                height: 1.8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              TranslationService.isArabic
                  ? 'سورة $surah — الآية $number'
                  : '$surah — Verse $number',
              style: const TextStyle(
                color: Color(0xFFE5C158),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            if (!TranslationService.isArabic && translation.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(translation),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHadithCard(ThemeData theme, Map<String, dynamic> hadith) {
    final lang = TranslationService.isArabic ? 'arabic' : 'english';
    final text = hadith[lang]?.toString() ?? '';
    final book = _hadithBookName(hadith['book_id']);
    final number = hadith['hadith_number']?.toString() ?? '';
    final gold = const Color(0xFFE5C158);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              text.isEmpty
                  ? (TranslationService.isArabic
                      ? 'لم يتوفر نص الحديث باللغة المختارة.'
                      : 'Hadith text is unavailable in this language.')
                  : text,
              textAlign: TranslationService.isArabic
                  ? TextAlign.right
                  : TextAlign.left,
              style: TextStyle(
                fontFamily: TranslationService.isArabic ? 'Amiri' : null,
                fontSize: TranslationService.isArabic ? 19 : 15,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              TranslationService.isArabic
                  ? '$book — حديث رقم $number'
                  : '$book — Hadith $number',
              style: TextStyle(
                color: gold,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              TranslationService.isArabic
                  ? 'درجة الحديث: ${_hadithGrade(hadith)}'
                  : 'Grade: ${_hadithGrade(hadith)}',
              style: TextStyle(
                fontSize: 11,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer(ThemeData theme) {
    final isArabic = TranslationService.isArabic;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.35)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _ask(),
                decoration: InputDecoration(
                  hintText: isArabic ? 'اكتب سؤالك هنا...' : 'Write your question...',
                  filled: true,
                  fillColor: theme.cardColor,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _isSearching ? null : () => _ask(),
              icon: _isSearching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              tooltip: isArabic ? 'إرسال السؤال' : 'Send question',
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantTurn {
  final String text;
  final bool isUser;
  final List<Map<String, dynamic>> ayahs;
  final List<Map<String, dynamic>> hadiths;
  final List<_FiqhMatch> fiqhMatches;

  const _AssistantTurn({
    required this.text,
    this.isUser = false,
    this.ayahs = const [],
    this.hadiths = const [],
    this.fiqhMatches = const [],
  });
}

class _FiqhMatch {
  final FiqhTopic topic;
  final FiqhFaq? faq;
  final int score;

  const _FiqhMatch({
    required this.topic,
    this.faq,
    required this.score,
  });
}
