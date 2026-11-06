import 'dart:async';
import 'dart:math';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/offline_surahs.dart';
import '../models/quran_models.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/quran_recitation_matcher.dart';

class SheikhAhmedScreen extends StatefulWidget {
  final StorageService storage;
  const SheikhAhmedScreen({super.key, required this.storage});

  @override
  State<SheikhAhmedScreen> createState() => _SheikhAhmedScreenState();
}

class _SheikhAhmedScreenState extends State<SheikhAhmedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();

  int _surah = 1;
  int _index = 0;
  List<Ayah> _ayahs = [];
  bool _loading = true;
  bool _showText = true;
  bool _speechReady = false;
  bool _listening = false;
  bool _ttsReady = false;
  String _locale = 'ar-EG';
  String _status = 'يُجهّز التعرف الصوتي...';
  String _recognized = '';
  QuranRecitationComparison? _result;
  Map<String, dynamic> _records = {};
  int _dailyTarget = 5;
  bool _repeatReference = false;
  String _selectedReciter = 'ar.alafasy';

  Ayah? get _ayah => _ayahs.isEmpty ? null : _ayahs[_index];
  String get _recordKey => _surah.toString() + ':' + (_ayah?.numberInSurah.toString() ?? '0');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _surah = widget.storage.getInt('sheikh_selected_surah', defaultValue: 1);
    _dailyTarget = widget.storage.getInt('hifz_daily_target', defaultValue: 5);
    _repeatReference = widget.storage.getBool('hifz_repeat_reference', defaultValue: false);
    final savedReciter = widget.storage.getString('default_reciter', defaultValue: 'ar.alafasy');
    _selectedReciter = availableReciters.any((reciter) => reciter.id == savedReciter)
        ? savedReciter
        : 'ar.alafasy';
    _loadRecords();
    _loadSurah(_surah);
    _initSpeech();
    _initTts();
  }

  Future<void> _loadRecords() async {
    try {
      final value = jsonDecode(widget.storage.getString('qalam_hifz_progress_v1', defaultValue: '{}'));
      if (value is Map) _records = Map<String, dynamic>.from(value);
    } catch (_) {
      _records = {};
    }
    if (mounted) setState(() {});
  }

  Future<void> _initSpeech() async {
    try {
      final ready = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'notListening' || status == 'done') {
            setState(() {
              _listening = false;
              _compare();
            });
          } else if (status == 'listening') {
            setState(() => _listening = true);
          }
        },
        onError: (_) {
          if (mounted) setState(() {
            _listening = false;
            _status = 'تعذّر التعرف على الصوت. تحقق من إذن الميكروفون وخدمة التعرف العربية.';
          });
        },
      );
      if (!ready) {
        if (mounted) setState(() {
          _speechReady = false;
          _status = 'خدمة التعرف الصوتي غير متاحة على هذا الجهاز.';
        });
        return;
      }
      var locale = 'ar-EG';
      try {
        final available = await _speech.locales();
        final arabic = available.where((v) => v.localeId.toLowerCase().startsWith('ar')).toList();
        if (arabic.isNotEmpty) {
          final egyptian = arabic.where((v) => v.localeId.toLowerCase() == 'ar-eg').toList();
          locale = egyptian.isNotEmpty ? egyptian.first.localeId : arabic.first.localeId;
        }
      } catch (_) {}
      if (mounted) setState(() {
        _speechReady = true;
        _locale = locale;
        _status = 'جاهز للتسميع بالعربية. ابدأ ثم اقرأ آية واحدة.';
      });
    } catch (_) {
      if (mounted) setState(() {
        _speechReady = false;
        _status = 'لم يتمكن الهاتف من تشغيل خدمة التعرف الصوتي.';
      });
    }
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('ar-EG');
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(1.0);
      _ttsReady = true;
    } catch (_) {
      _ttsReady = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _speakHelp() async {
    if (!_ttsReady) {
      _toast('ثبّت صوتًا عربيًا في إعدادات تحويل النص إلى كلام بالهاتف.');
      return;
    }
    await _tts.stop();
    await _tts.speak('مرحبًا بك في مساعد التسميع في قلم مسلم. اختر السورة والقارئ، ثم أخفِ الآية وابدأ التسميع. سأعرض مقارنة لفظية تقريبية، وليست حكمًا على التجويد.');
  }

  Future<void> _speakResult() async {
    final result = _result;
    if (!_ttsReady || result == null) return;
    await _tts.stop();
    await _tts.speak(
      'نسبة التطابق اللفظي التقريبية ${result.similarityPercent} بالمئة. '
      'التقط الهاتف ${result.matchedWords} كلمة من أصل ${result.expectedWords}. '
      'راجع الكلمات التي لم يلتقطها، فقد يخطئ التعرف الصوتي في ألفاظ القرآن.',
    );
  }

  Future<void> _loadSurah(int number, {int ayahNumber = 1}) async {
    if (mounted) setState(() {
      _loading = true;
      _surah = number;
      _index = 0;
      _recognized = '';
      _result = null;
    });
    await widget.storage.setInt('sheikh_selected_surah', number);
    try {
      final values = await ApiService.fetchSurahDetails(number);
      if (!mounted) return;
      final found = values.indexWhere((v) => v.numberInSurah == ayahNumber);
      setState(() {
        _ayahs = values;
        _index = found < 0 ? 0 : found;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ayahs = [];
        _loading = false;
      });
      _toast('تعذّر تحميل آيات السورة من قاعدة بيانات التطبيق.');
    }
  }

  Future<void> _start() async {
    if (!_speechReady || _ayah == null) {
      _toast('خدمة التعرف العربية غير جاهزة. فعّلها وثبّت اللغة العربية في إعدادات الهاتف.');
      return;
    }
    await _player.stop();
    await _tts.stop();
    setState(() {
      _recognized = '';
      _result = null;
      _showText = false;
      _status = 'الهاتف يستمع إلى تلاوتك الآن...';
      _listening = true;
    });
    try {
      await _speech.listen(
        localeId: _locale,
        onResult: (event) {
          if (!mounted) return;
          setState(() {
            _recognized = event.recognizedWords;
            if (event.finalResult) {
              _compare();
              _listening = false;
            }
          });
        },
      );
    } catch (_) {
      if (mounted) setState(() {
        _listening = false;
        _status = 'لم يبدأ الميكروفون. تحقق من إذن التسجيل.';
      });
    }
  }

  void _compare() {
    if (_ayah == null || _recognized.trim().isEmpty) return;
    _result = QuranRecitationMatcher.compare(expected: _ayah!.text, recognized: _recognized);
    _status = 'اكتملت المقارنة اللفظية. راجع الكلمات أدناه.';
  }

  Future<void> _stop() async {
    await _speech.stop();
    if (mounted) setState(() {
      _listening = false;
      _compare();
    });
  }

  Future<void> _playReference() async {
    final current = _ayah;
    if (current == null) return;
    await _speech.stop();
    await _tts.stop();
    final reciter = _selectedReciter;
    final url = ApiService.buildAyahAudioUrl(
      current.number,
      _surah,
      current.numberInSurah,
      reciter: reciter,
    );
    try {
      await _player.setReleaseMode(
        _repeatReference ? ReleaseMode.loop : ReleaseMode.stop,
      );
      await _player.play(UrlSource(url));
    } catch (_) {
      _toast('تعذّر تشغيل التلاوة المرجعية. تحقق من اتصال الإنترنت.');
    }
  }

  Future<void> _move(int step) async {
    if (_ayahs.isEmpty) return;
    await _speech.stop();
    await _player.stop();
    final next = (_index + step).clamp(0, _ayahs.length - 1).toInt();
    setState(() {
      _index = next;
      _recognized = '';
      _result = null;
      _showText = true;
      _listening = false;
      _status = 'آية جديدة. استعد للتسميع.';
    });
  }

  Map<String, dynamic> _record(String key) {
    final value = _records[key];
    return value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  }

  Future<void> _save() async {
    await widget.storage.setString('qalam_hifz_progress_v1', jsonEncode(_records));
    if (mounted) setState(() {});
  }

  Future<void> _memorized() async {
    if (_ayah == null) return;
    final oldStage = _record(_recordKey)['stage'] as int? ?? -1;
    const days = [1, 3, 7, 14, 30];
    final stage = (oldStage + 1).clamp(0, days.length - 1).toInt();
    final now = DateTime.now();
    _records[_recordKey] = {
      'status': 'memorized',
      'stage': stage,
      'lastReviewedAt': now.millisecondsSinceEpoch,
      'dueAt': now.add(Duration(days: days[stage])).millisecondsSinceEpoch,
      'surah': _surah,
      'ayah': _ayah!.numberInSurah,
    };
    await _save();
    _toast('أُضيفت الآية إلى سجل الحفظ. موعد المراجعة بعد ' + days[stage].toString() + ' يومًا.');
  }

  Future<void> _needsReview() async {
    if (_ayah == null) return;
    final now = DateTime.now();
    _records[_recordKey] = {
      'status': 'review',
      'stage': 0,
      'lastReviewedAt': now.millisecondsSinceEpoch,
      'dueAt': now.add(const Duration(hours: 12)).millisecondsSinceEpoch,
      'surah': _surah,
      'ayah': _ayah!.numberInSurah,
    };
    await _save();
    _toast('سُجلت الآية للمراجعة القريبة.');
  }

  List<MapEntry<String, Map<String, dynamic>>> get _history {
    final result = _records.entries
        .where((entry) => entry.value is Map)
        .map((entry) => MapEntry(entry.key, Map<String, dynamic>.from(entry.value as Map)))
        .toList();
    result.sort((a, b) => a.key.compareTo(b.key));
    return result;
  }

  List<MapEntry<String, Map<String, dynamic>>> get _due {
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = _history.where((entry) => (entry.value['dueAt'] as int? ?? 0) <= now).toList();
    result.sort((a, b) => (a.value['dueAt'] as int? ?? 0).compareTo(b.value['dueAt'] as int? ?? 0));
    return result;
  }

  int get _memorizedCount => _records.values.where((v) => v is Map && v['status'] == 'memorized').length;
  int get _reviewCount => _records.values.where((v) => v is Map && v['status'] == 'review').length;

  int get _reviewedToday {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    return _records.values.where((v) => v is Map && (v['lastReviewedAt'] as int? ?? 0) >= start).length;
  }

  Future<void> _changeTarget(int step) async {
    _dailyTarget = (_dailyTarget + step).clamp(1, 30).toInt();
    await widget.storage.setInt('hifz_daily_target', _dailyTarget);
    if (mounted) setState(() {});
  }

  Future<void> _openEntry(MapEntry<String, Map<String, dynamic>> entry) async {
    await _loadSurah(entry.value['surah'] as int? ?? 1, ayahNumber: entry.value['ayah'] as int? ?? 1);
    _tabs.animateTo(0);
  }

  Future<void> _startRandomReview() async {
    final candidates = _history
        .where((entry) => entry.value['status'] == 'memorized')
        .toList();
    if (candidates.isEmpty) {
      _toast('احفظ بعض الآيات أولًا، ثم ابدأ الاختبار العشوائي.');
      return;
    }
    candidates.shuffle(Random());
    await _openEntry(candidates.first);
    if (!mounted) return;
    setState(() => _showText = false);
    _toast('اختبار عشوائي: سمّع الآية من حفظك دون النظر إلى النص.');
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _speech.cancel();
    _tts.stop();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الشيخ أحمد محمد', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _speakHelp, tooltip: 'تعليمات صوتية', icon: const Icon(Icons.volume_up_outlined)),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.mic_none_rounded), text: 'التسميع'),
            Tab(icon: Icon(Icons.auto_stories_rounded), text: 'خطة الحفظ'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_tasmee(theme), _hifz(theme)],
      ),
    );
  }

  Widget _tasmee(ThemeData theme) {
    final scheme = theme.colorScheme;
    final current = _ayah;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.record_voice_over_rounded, color: scheme.primary),
            ),
            title: const Text('مساعد التسميع الصوتي', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('الشيخ أحمد محمد · مساعد آلي'),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: _surah,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'اختر السورة', prefixIcon: Icon(Icons.menu_book_outlined)),
          items: allOfflineSurahs.map((s) => DropdownMenuItem<int>(
            value: s.number,
            child: Text(s.number.toString() + '. ' + s.name),
          )).toList(),
          onChanged: (value) {
            if (value != null) _loadSurah(value);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedReciter,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'اختر القارئ المرجعي',
            prefixIcon: Icon(Icons.record_voice_over_outlined),
          ),
          items: availableReciters.map((reciter) => DropdownMenuItem<String>(
            value: reciter.id,
            child: Text(reciter.nameAr, overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (value) async {
            if (value == null) return;
            await _player.stop();
            setState(() => _selectedReciter = value);
            await widget.storage.setString('default_reciter', value);
          },
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ))
        else if (current == null)
          const Card(child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('لا توجد آيات متاحة لهذه السورة حاليًا.'),
          ))
        else ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('الآية ' + current.numberInSurah.toString(), style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)),
                      Text('من ' + _ayahs.length.toString()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_showText)
                    SelectableText(
                      current.text,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Amiri', fontSize: 25, height: 2, color: theme.textTheme.bodyLarge?.color),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('الآية مخفية. حاول تسميعها من حفظك.', textAlign: TextAlign.center),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _showText = !_showText),
                        icon: Icon(_showText ? Icons.visibility_off : Icons.visibility),
                        label: Text(_showText ? 'إخفاء الآية' : 'إظهار الآية'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _playReference,
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('استمع للقارئ'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('جلسة التسميع', style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary)),
                  const SizedBox(height: 6),
                  Text(_status, style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _listening ? _stop : (_speechReady ? _start : null),
                    icon: Icon(_listening ? Icons.stop_circle_outlined : Icons.mic_rounded),
                    label: Text(_listening ? 'إيقاف الاستماع' : 'ابدأ التسميع'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _repeatReference,
                    title: const Text('تكرار الآية للحفظ'),
                    subtitle: const Text('يكرر صوت القارئ حتى توقفه يدويًا'),
                    secondary: const Icon(Icons.repeat_rounded),
                    onChanged: (value) async {
                      setState(() => _repeatReference = value);
                      await widget.storage.setBool('hifz_repeat_reference', value);
                      await _player.setReleaseMode(
                        value ? ReleaseMode.loop : ReleaseMode.stop,
                      );
                    },
                  ),
                  if (_recognized.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('النص الذي التقطه الهاتف:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text(_recognized, textAlign: TextAlign.right, style: const TextStyle(fontSize: 18, height: 1.7)),
                  ],
                  if (_result != null) ...[
                    const Divider(height: 25),
                    Row(
                      children: [
                        Expanded(child: Text('التطابق اللفظي التقريبي', style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary))),
                        Text(_result!.similarityPercent.toString() + '%', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: scheme.primary)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(_result!.matchedWords.toString() + ' كلمة متطابقة من ' + _result!.expectedWords.toString()),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        onPressed: _ttsReady ? _speakResult : null,
                        icon: const Icon(Icons.volume_up_outlined, size: 18),
                        label: const Text('استمع إلى التقييم الصوتي'),
                      ),
                    ),
                    if (_result!.missingWords.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('كلمات لم يلتقطها الهاتف:', style: TextStyle(color: scheme.error, fontWeight: FontWeight.bold)),
                      Text(_result!.missingWords.join(' • '), style: TextStyle(color: scheme.error, fontSize: 16)),
                    ],
                    if (_result!.extraWords.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text('كلمات إضافية في النص المتعرف عليه:', style: TextStyle(color: scheme.tertiary, fontWeight: FontWeight.bold)),
                      Text(_result!.extraWords.join(' • '), style: TextStyle(color: scheme.tertiary, fontSize: 16)),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonalIcon(onPressed: _memorized, icon: const Icon(Icons.check_circle_outline), label: const Text('أتممت المراجعة')),
                        OutlinedButton.icon(onPressed: _needsReview, icon: const Icon(Icons.replay), label: const Text('أحتاج إلى مراجعة')),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          Card(
            color: scheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(13),
              child: Text(
                'تنبيه: المقارنة تعتمد على تحويل الصوت إلى نص بواسطة خدمة الهاتف، وقد تخطئ في ألفاظ القرآن. النسبة ليست تقييمًا للتجويد أو المخارج، ولا تغني عن التسميع على معلّم متقن.',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: _index > 0 ? () => _move(-1) : null,
                icon: const Icon(Icons.chevron_right),
                label: const Text('الآية السابقة'),
              )),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(
                onPressed: _index < _ayahs.length - 1 ? () => _move(1) : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('الآية التالية'),
              )),
            ],
          ),
        ],
      ],
    );
  }

  Widget _hifz(ThemeData theme) {
    final scheme = theme.colorScheme;
    final due = _due;
    final percent = (_reviewedToday / _dailyTarget).clamp(0.0, 1.0).toDouble();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ورد الحفظ اليومي', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    IconButton(onPressed: () => _changeTarget(-1), icon: const Icon(Icons.remove_circle_outline)),
                    Text(_dailyTarget.toString() + ' آيات', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(onPressed: () => _changeTarget(1), icon: const Icon(Icons.add_circle_outline)),
                    const Spacer(),
                    Text(_reviewedToday.toString() + ' / ' + _dailyTarget.toString()),
                  ],
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: percent, minHeight: 9),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _stat('المحفوظ', _memorizedCount, Icons.bookmark_added_outlined, scheme)),
            const SizedBox(width: 8),
            Expanded(child: _stat('للمراجعة', _reviewCount, Icons.replay_circle_filled_outlined, scheme)),
            const SizedBox(width: 8),
            Expanded(child: _stat('المستحق الآن', due.length, Icons.notifications_active_outlined, scheme)),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: due.isEmpty ? null : () => _openEntry(due.first),
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('ابدأ مراجعة المستحق'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _memorizedCount == 0 ? null : _startRandomReview,
          icon: const Icon(Icons.shuffle_rounded),
          label: const Text('اختبار عشوائي من محفوظاتك'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        ),
        const SizedBox(height: 17),
        Text('سجل الحفظ والمراجعة', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 7),
        if (_history.isEmpty)
          const Card(child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('لم تسجل آيات بعد. من تبويب التسميع اختر «أتممت المراجعة» أو «أحتاج إلى مراجعة».'),
          ))
        else
          ..._history.map((entry) {
            final parts = entry.key.split(':');
            final surahNo = int.tryParse(parts.first) ?? 1;
            final ayahNo = int.tryParse(parts.last) ?? 1;
            final surah = allOfflineSurahs.firstWhere(
              (item) => item.number == surahNo,
              orElse: () => allOfflineSurahs.first,
            );
            final saved = entry.value['status'] == 'memorized';
            final dueAt = entry.value['dueAt'] as int? ?? 0;
            final label = dueAt <= DateTime.now().millisecondsSinceEpoch
                ? 'مستحقة للمراجعة الآن'
                : 'المراجعة القادمة: ' + DateTime.fromMillisecondsSinceEpoch(dueAt).toLocal().toString().substring(0, 10);
            return Card(
              child: ListTile(
                leading: Icon(saved ? Icons.check_circle : Icons.replay_circle_filled, color: saved ? scheme.primary : scheme.tertiary),
                title: Text(surah.name + ' · آية ' + ayahNo.toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(label),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => _openEntry(entry),
              ),
            );
          }),
      ],
    );
  }

  Widget _stat(String label, int value, IconData icon, ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 5),
        child: Column(
          children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(height: 6),
            Text(value.toString(), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}