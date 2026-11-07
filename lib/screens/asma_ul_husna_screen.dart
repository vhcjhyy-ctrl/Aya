import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/storage_service.dart';

class _AllahName {
  final String arabic;
  final String transliteration;
  final String slug;
  final String meaning;
  final String meaningAr;
  final String meaningFr;
  final String explanation;

  const _AllahName({
    required this.arabic,
    required this.transliteration,
    required this.slug,
    required this.meaning,
    required this.meaningAr,
    required this.meaningFr,
    required this.explanation,
  });

  factory _AllahName.fromJson(Map<String, dynamic> json) => _AllahName(
        arabic: (json['arabic'] ?? '').toString(),
        transliteration: (json['transliteration'] ?? '').toString(),
        slug: (json['slug'] ?? '').toString(),
        meaning: (json['meaning'] ?? '').toString(),
        meaningAr: (json['meaningAr'] ?? '').toString(),
        meaningFr: (json['meaningFr'] ?? '').toString(),
        explanation: (json['explanation'] ?? '').toString(),
      );
}

class AsmaUlHusnaScreen extends StatefulWidget {
  final StorageService storage;

  const AsmaUlHusnaScreen({super.key, required this.storage});

  @override
  State<AsmaUlHusnaScreen> createState() => _AsmaUlHusnaScreenState();
}

class _AsmaUlHusnaScreenState extends State<AsmaUlHusnaScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Random _random = Random();
  List<_AllahName> _names = [];
  Set<String> _favorites = {};
  bool _loading = true;
  bool _favoritesOnly = false;
  bool _quizMode = false;
  String _query = '';

  List<int> _quizQuestions = [];
  List<List<int>> _quizOptions = [];
  int _quizStep = 0;
  int _quizScore = 0;
  int? _quizChoice;

  @override
  void initState() {
    super.initState();
    _loadNames();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNames() async {
    try {
      final raw = await rootBundle.loadString('assets/data/names99.json');
      final decoded = jsonDecode(raw) as List;
      final loaded = decoded
          .whereType<Map>()
          .map((row) => _AllahName.fromJson(
                Map<String, dynamic>.from(row),
              ))
          .where((item) =>
              item.arabic.isNotEmpty && item.slug.isNotEmpty)
          .toList();
      final saved = widget.storage.getStringList('asma_favorites_v1') ?? [];
      if (!mounted) return;
      setState(() {
        _names = loaded;
        _favorites = saved.toSet();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('تعذّر تحميل بيانات الأسماء المحفوظة: ' + error.toString());
    }
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .trim();
  }

  List<_AllahName> get _filteredNames {
    final query = _normalize(_query);
    return _names.where((item) {
      if (_favoritesOnly && !_favorites.contains(item.slug)) return false;
      if (query.isEmpty) return true;
      return _normalize(item.arabic).contains(query) ||
          _normalize(item.transliteration).contains(query) ||
          _normalize(item.meaning).contains(query) ||
          _normalize(item.meaningAr).contains(query);
    }).toList();
  }

  Future<void> _toggleFavorite(_AllahName item) async {
    final next = Set<String>.from(_favorites);
    if (next.contains(item.slug)) {
      next.remove(item.slug);
    } else {
      next.add(item.slug);
    }
    setState(() => _favorites = next);
    await widget.storage.setStringList(
      'asma_favorites_v1',
      next.toList()..sort(),
    );
  }

  void _startQuiz() {
    if (_names.length < 4) {
      _showMessage('لا توجد بيانات كافية لبدء الاختبار.');
      return;
    }
    final questions = List<int>.generate(_names.length, (index) => index)
      ..shuffle(_random);
    final selectedQuestions = questions.take(10).toList();
    final options = <List<int>>[];

    for (final questionIndex in selectedQuestions) {
      final distractors = List<int>.generate(_names.length, (index) => index)
        ..remove(questionIndex)
        ..shuffle(_random);
      final choices = <int>[
        questionIndex,
        ...distractors.take(3),
      ]..shuffle(_random);
      options.add(choices);
    }

    setState(() {
      _quizQuestions = selectedQuestions;
      _quizOptions = options;
      _quizStep = 0;
      _quizScore = 0;
      _quizChoice = null;
      _quizMode = true;
    });
  }

  void _chooseAnswer(int answerIndex) {
    if (_quizChoice != null) return;
    final correct = _quizQuestions[_quizStep];
    setState(() {
      _quizChoice = answerIndex;
      if (answerIndex == correct) _quizScore++;
    });
  }

  void _nextQuestion() {
    if (_quizStep + 1 >= _quizQuestions.length) {
      setState(() => _quizMode = false);
      _showQuizResult();
      return;
    }
    setState(() {
      _quizStep++;
      _quizChoice = null;
    });
  }

  Future<void> _showQuizResult() async {
    final total = _quizQuestions.length;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('نتيجة الاختبار'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _quizScore >= 7
                  ? Icons.emoji_events_rounded
                  : Icons.auto_awesome_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              _quizScore.toString() + ' من ' + total.toString(),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            const Text('أحسنت في المراجعة والتعلّم.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إغلاق'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _startQuiz();
            },
            child: const Text('اختبار جديد'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('أسماء الله الحسنى'),
        actions: [
          if (!_loading && !_quizMode)
            IconButton(
              tooltip: 'اختبار الحفظ',
              onPressed: _startQuiz,
              icon: const Icon(Icons.quiz_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _quizMode
              ? _buildQuiz(theme, scheme)
              : _buildLibrary(theme, scheme),
    );
  }

  Widget _buildLibrary(ThemeData theme, ColorScheme scheme) {
    final filtered = _filteredNames;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم أو المعنى...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح البحث',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              FilterChip(
                selected: !_favoritesOnly,
                label: const Text('كل الأسماء'),
                onSelected: (_) => setState(() => _favoritesOnly = false),
              ),
              const SizedBox(width: 8),
              FilterChip(
                selected: _favoritesOnly,
                avatar: const Icon(Icons.favorite_rounded, size: 16),
                label: Text('المفضلة (' + _favorites.length.toString() + ')'),
                onSelected: (_) => setState(() => _favoritesOnly = true),
              ),
              const Spacer(),
              Text(
                filtered.length.toString() + ' / ' + _names.length.toString(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _favoritesOnly && _favorites.isEmpty
                        ? 'لم تضف أسماء إلى المفضلة بعد.'
                        : 'لا توجد نتائج مطابقة.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final favorite = _favorites.contains(item.slug);
                    return Card(
                      elevation: 0,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        leading: CircleAvatar(
                          backgroundColor: scheme.primaryContainer,
                          child: Text(
                            (index + 1).toString(),
                            style: TextStyle(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          item.arabic,
                          textDirection: TextDirection.rtl,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Amiri',
                          ),
                        ),
                        subtitle: Text(
                          item.meaningAr,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: favorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
                          onPressed: () => _toggleFavorite(item),
                          icon: Icon(
                            favorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: favorite ? scheme.error : scheme.onSurfaceVariant,
                          ),
                        ),
                        children: [
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.transliteration,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text('المعنى المختصر: ' + item.meaningAr),
                                if (item.explanation.isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    item.explanation,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 5),
                                Text(
                                  item.meaning,
                                  textDirection: TextDirection.ltr,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'المعاني هنا موجزة للتعلّم والتذكّر، وليست تفسيرًا مستقلًا أو مرجعًا للأحكام الشرعية.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuiz(ThemeData theme, ColorScheme scheme) {
    if (_quizQuestions.isEmpty) return const SizedBox.shrink();
    final questionIndex = _quizQuestions[_quizStep];
    final question = _names[questionIndex];
    final options = _quizOptions[_quizStep];
    final answered = _quizChoice != null;

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'اختبار أسماء الله الحسنى',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              (_quizStep + 1).toString() + ' / ' + _quizQuestions.length.toString(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: (_quizStep + 1) / _quizQuestions.length,
        ),
        const SizedBox(height: 20),
        Card(
          elevation: 0,
          color: scheme.primaryContainer.withValues(alpha: 0.55),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.lightbulb_outline_rounded, size: 30),
                const SizedBox(height: 12),
                Text(
                  'اختر الاسم الذي يوافق هذا المعنى:',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  question.meaningAr,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        ...options.map((optionIndex) {
          final option = _names[optionIndex];
          final isCorrect = optionIndex == questionIndex;
          final selected = _quizChoice == optionIndex;
          Color? background;
          Color? foreground;
          if (answered && isCorrect) {
            background = scheme.primaryContainer;
            foreground = scheme.onPrimaryContainer;
          } else if (selected && !isCorrect) {
            background = scheme.errorContainer;
            foreground = scheme.onErrorContainer;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: answered ? null : () => _chooseAnswer(optionIndex),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  backgroundColor: background,
                  foregroundColor: foreground,
                  side: BorderSide(
                    color: answered && isCorrect
                        ? scheme.primary
                        : scheme.outlineVariant,
                  ),
                ),
                child: Text(
                  option.arabic,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontFamily: 'Amiri',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        }),
        if (answered) ...[
          const SizedBox(height: 8),
          Text(
            _quizChoice == questionIndex
                ? 'إجابة صحيحة، أحسنت.'
                : 'الإجابة الصحيحة: ' + question.arabic,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: _quizChoice == questionIndex
                  ? scheme.primary
                  : scheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _nextQuestion,
            child: Text(
              _quizStep + 1 == _quizQuestions.length
                  ? 'عرض النتيجة'
                  : 'السؤال التالي',
            ),
          ),
        ],
        TextButton(
          onPressed: () => setState(() => _quizMode = false),
          child: const Text('العودة إلى قائمة الأسماء'),
        ),
      ],
    );
  }
}
