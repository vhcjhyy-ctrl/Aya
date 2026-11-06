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
import '../services/reciters_cache_service.dart';
import '../services/local_ai_assistant_service.dart';
import '../services/quran_voice_intent.dart';

enum _AssistantPhase {
  idle,
  askingWhatMemorized,
  askingStart,
  reciting,
  awaitingFeedback,
}

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
  bool _blindRecallMode = false;
  bool _commandMode = false;
  String _selectedReciter = '';
  List<Map<String, dynamic>> _referenceReciters = [];
  bool _loadingReferenceReciters = false;

  final LocalAiAssistantService _localAssistant = LocalAiAssistantService();
  bool _assistantReady = false;
  bool _assistantBusy = false;
  bool _assistantConversationActive = false;
  bool _assistantListening = false;
  bool _assistantSpeaking = false;
  bool _assistantResultProcessing = false;
  bool _assistantFinalResultHandled = true;
  bool _assistantManualRecognitionStop = false;
  int _assistantNoSpeechRetries = 0;
  double _assistantDownloadProgress = 0;
  String _assistantModelStatus = 'مساعد محلي، بلا مفتاح API';
  _AssistantPhase _assistantPhase = _AssistantPhase.idle;
  final List<Map<String, String>> _assistantHistory = [];
  final List<Map<String, String>> _assistantTranscript = [];


  Ayah? get _ayah => _ayahs.isEmpty ? null : _ayahs[_index];
  String get _recordKey => _surah.toString() + ':' + (_ayah?.numberInSurah.toString() ?? '0');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _surah = widget.storage.getInt('sheikh_selected_surah', defaultValue: 1);
    _dailyTarget = widget.storage.getInt('hifz_daily_target', defaultValue: 5);
    _repeatReference = widget.storage.getBool('hifz_repeat_reference', defaultValue: false);
    _selectedReciter = widget.storage.getString(
      'hifz_reference_reciter',
      defaultValue: '',
    );
    _loadRecords();
    _loadSurah(_surah);
    _loadReferenceReciters();
    _initSpeech();
    _initTts();
  }

  Future<void> _loadReferenceReciters() async {
    if (mounted) setState(() => _loadingReferenceReciters = true);
    try {
      final reciters = await RecitersCacheService.getRecitersForRiwayah(1);
      final sources = <Map<String, dynamic>>[];
      for (final reciter in reciters) {
        final moshafs = reciter['moshaf'] as List? ?? const [];
        for (final rawMoshaf in moshafs) {
          if (rawMoshaf is! Map) continue;
          final moshaf = Map<String, dynamic>.from(rawMoshaf);
          final server = (moshaf['server'] ?? '').toString().trim();
          if (!server.startsWith('https://')) continue;
          sources.add({
            'name': (reciter['name'] ?? '').toString(),
            'moshaf_name': (moshaf['name'] ?? '').toString(),
            'server': server,
          });
        }
      }

      sources.sort((a, b) {
        final nameCompare = (a['name'] as String).compareTo(b['name'] as String);
        if (nameCompare != 0) return nameCompare;
        return (a['moshaf_name'] as String).compareTo(
          b['moshaf_name'] as String,
        );
      });

      final savedServer = widget.storage.getString(
        'hifz_reference_reciter',
        defaultValue: '',
      );
      final servers = sources.map((source) => source['server'] as String).toSet();
      final selected = servers.contains(savedServer)
          ? savedServer
          : (sources.isNotEmpty ? sources.first['server'] as String : '');

      if (selected.isNotEmpty && selected != savedServer) {
        await widget.storage.setString('hifz_reference_reciter', selected);
      }

      if (!mounted) return;
      setState(() {
        _referenceReciters = sources;
        _selectedReciter = selected;
        _loadingReferenceReciters = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _referenceReciters = [];
        _loadingReferenceReciters = false;
        _status = 'تعذّر تحميل مصادر التلاوة. تحقق من الاتصال ثم أعد فتح الشاشة.';
      });
    }
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
            final dialogueTimedOut = _assistantListening &&
                !_assistantFinalResultHandled &&
                _assistantConversationActive &&
                _assistantPhase != _AssistantPhase.reciting;
            final recitationTimedOut = _assistantConversationActive &&
                _assistantPhase == _AssistantPhase.reciting &&
                _listening &&
                !_assistantResultProcessing &&
                !_assistantManualRecognitionStop;
            setState(() {
              _listening = false;
              if (_assistantListening) _assistantListening = false;
              if (_commandMode) {
                _commandMode = false;
                _status = 'لم ألتقط أمرًا صوتيًا. اضغط زر الميكروفون وحاول مجددًا.';
              }
              if (recitationTimedOut) {
                _assistantPhase = _AssistantPhase.awaitingFeedback;
                _assistantResultProcessing = true;
                _status = 'لم يلتقط الهاتف تلاوة واضحة. أعد المحاولة.';
              }
              // Final speech results are compared in onResult only.
              // Comparing here can accidentally treat a voice command as Quran recitation.
            });
            if (dialogueTimedOut) {
              _assistantFinalResultHandled = true;
              if (_assistantNoSpeechRetries < 2) {
                _assistantNoSpeechRetries++;
                unawaited(_assistantSpeakAndListen(
                  'لم أسمع إجابتك بوضوح. خذ وقتك وتحدث مرة أخرى.',
                ));
              } else {
                _assistantNoSpeechRetries = 0;
                _status = 'لم أسمع إجابة. اضغط ابدأ الحوار الصوتي للمحاولة مجددًا.';
                if (mounted) setState(() {});
              }
            }
            if (recitationTimedOut) {
              unawaited(_assistantSpeakAndListen(
                'لم ألتقط تلاوة واضحة في هذه المحاولة. قد تكون خدمة التعرف الصوتي توقفت أو لم تسمع الكلمات. هل تعيد المحاولة؟ قل كرر.',
              ));
            }
          } else if (status == 'listening') {
            setState(() => _listening = true);
          }
        },
        onError: (_) {
          _assistantFinalResultHandled = true;
          if (mounted) setState(() {
            _listening = false;
            _assistantListening = false;
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
      await _tts.awaitSpeakCompletion(true);
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

  Future<void> _cancelVoiceAssistantDownload() async {
    await _localAssistant.cancelDownload();
    if (mounted) {
      setState(() {
        _assistantModelStatus = 'تم طلب إلغاء التنزيل...';
      });
    }
  }

  Future<void> _prepareVoiceAssistant() async {
    if (_assistantBusy) return;
    if (!_speechReady || !_ttsReady) {
      _toast('تأكد من جاهزية الميكروفون والصوت العربي في الهاتف أولًا.');
      return;
    }
    if (_assistantReady) {
      await _startVoiceAssistant();
      return;
    }

    setState(() {
      _assistantBusy = true;
      _assistantDownloadProgress = 0;
      _assistantModelStatus = 'جارٍ تجهيز المساعد المحلي...';
    });
    try {
      if (!await _localAssistant.isModelDownloaded()) {
        setState(() => _assistantModelStatus = 'تنزيل النموذج لأول مرة — نحو 528 ميجابايت');
        await _localAssistant.downloadModel(
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _assistantDownloadProgress = progress;
              _assistantModelStatus =
                  'تنزيل النموذج ${(progress * 100).round()}%';
            });
          },
        );
      }
      if (!mounted) return;
      setState(() => _assistantModelStatus = 'جارٍ تحميل النموذج في ذاكرة الهاتف...');
      await _localAssistant.loadModel();
      if (!mounted) return;
      setState(() {
        _assistantReady = true;
        _assistantModelStatus = 'المساعد جاهز على هذا الجهاز';
      });
      await _startVoiceAssistant();
    } catch (error) {
      if (mounted) {
        final cancelled = error.toString().contains('أُلغي تنزيل نموذج المساعد');
        setState(() {
          _assistantModelStatus = cancelled
              ? 'أُلغي تنزيل نموذج المساعد.'
              : 'تعذّر تجهيز المساعد: ' + error.toString();
        });
        if (!cancelled) {
          _toast('تحقق من مساحة التخزين والاتصال ثم أعد المحاولة.');
        }
      }
    } finally {
      if (mounted) setState(() => _assistantBusy = false);
    }
  }

  Future<void> _startVoiceAssistant() async {
    _assistantHistory.clear();
    _assistantTranscript.clear();
    _assistantNoSpeechRetries = 0;
    _assistantFinalResultHandled = true;
    _assistantConversationActive = true;
    _assistantPhase = _AssistantPhase.askingWhatMemorized;
    await _assistantSpeakAndListen(
      'السلام عليكم يا مهندس أحمد محمد. أنا مساعدك الصوتي في قلم مسلم. '
      'سنتابع الحفظ والمراجعة خطوة بخطوة. ماذا حفظت اليوم؟ اذكر اسم السورة.',
    );
  }

  void _addAssistantTranscript(String role, String content) {
    _assistantTranscript.add({'role': role, 'content': content});
    if (_assistantTranscript.length > 10) {
      _assistantTranscript.removeRange(0, _assistantTranscript.length - 10);
    }
    if (mounted) setState(() {});
  }

  Future<void> _assistantSpeak(String message) async {
    if (!_ttsReady) {
      _toast(message);
      return;
    }
    if (mounted) setState(() => _assistantSpeaking = true);
    try {
      await _tts.stop();
      await _tts.speak(message);
    } finally {
      if (mounted) setState(() => _assistantSpeaking = false);
    }
  }

  Future<void> _resumeAssistantListening() async {
    if (!_assistantConversationActive ||
        _assistantListening ||
        _assistantSpeaking ||
        _assistantPhase == _AssistantPhase.reciting) {
      return;
    }
    _assistantNoSpeechRetries = 0;
    await _listenForAssistantReply();
  }

  Future<void> _assistantSpeakAndListen(String message) async {
    if (!_assistantConversationActive) return;
    _addAssistantTranscript('assistant', message);
    await _assistantSpeak(message);
    if (_assistantConversationActive) {
      await _listenForAssistantReply();
    }
  }

  Future<void> _listenForAssistantReply() async {
    if (!_assistantConversationActive || !_speechReady) return;
    try {
      await _speech.stop();
      if (!mounted || !_assistantConversationActive) return;
      _assistantFinalResultHandled = false;
      setState(() {
        _assistantListening = true;
        _listening = true;
        _status = 'المساعد يستمع إليك...';
      });
      await _speech.listen(
        localeId: _locale,
        listenFor: const Duration(seconds: 18),
        pauseFor: const Duration(seconds: 3),
        onResult: (event) {
          if (!mounted) return;
          setState(() => _recognized = event.recognizedWords);
          if (event.finalResult && !_assistantFinalResultHandled) {
            _assistantFinalResultHandled = true;
            _assistantNoSpeechRetries = 0;
            setState(() {
              _assistantListening = false;
              _listening = false;
            });
            unawaited(_handleAssistantInput(event.recognizedWords));
          }
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _assistantListening = false;
        _listening = false;
        _status = 'تعذّر الاستماع. اضغط زر بدء الحوار وحاول مرة أخرى.';
      });
    }
  }

  Future<void> _handleAssistantInput(String rawInput) async {
    if (!_assistantConversationActive) return;
    final input = rawInput.trim();
    if (input.isEmpty) {
      await _assistantSpeakAndListen('لم أسمع إجابتك بوضوح. تحدث مرة أخرى من فضلك.');
      return;
    }
    _addAssistantTranscript('user', input);

    final command = QuranVoiceIntent.parseCommand(input);
    if (command == QuranVoiceCommand.stop) {
      await _stopVoiceAssistant();
      return;
    }

    if (_assistantPhase == _AssistantPhase.askingWhatMemorized) {
      final surahNumber = QuranVoiceIntent.findSurahNumber(input);
      if (surahNumber != null) {
        await _selectAssistantSurah(surahNumber);
        return;
      }
      await _assistantDiscuss(
        input,
        followUp: 'بعد ردك، اسأل المهندس أحمد محمد مرة أخرى عن اسم السورة التي يريد تسميعها.',
      );
      return;
    }

    if (_assistantPhase == _AssistantPhase.askingStart) {
      if (command == QuranVoiceCommand.start) {
        await _startAssistantRecitation();
        return;
      }
      final otherSurah = QuranVoiceIntent.findSurahNumber(input);
      if (otherSurah != null) {
        await _selectAssistantSurah(otherSurah);
        return;
      }
      await _assistantDiscuss(
        input,
        followUp: 'أجب عن سؤاله أو حديثه بإيجاز وبأسلوب مشجع، ثم اسأله هل يبدأ التسميع من أول آية أم يختار سورة أخرى.',
      );
      return;
    }

    if (_assistantPhase == _AssistantPhase.awaitingFeedback) {
      switch (command) {
        case QuranVoiceCommand.repeat:
          await _startAssistantRecitation();
          return;
        case QuranVoiceCommand.showAyah:
          setState(() => _showText = true);
          await _assistantSpeakAndListen(
            'أظهرت نص الآية على الشاشة. راجعها، ثم قل كرر لإعادة التسميع أو التالي للمتابعة.',
          );
          return;
        case QuranVoiceCommand.hideAyah:
          setState(() => _showText = false);
          await _assistantSpeakAndListen('أخفيت نص الآية. قل كرر عندما تكون مستعدًا.');
          return;
        case QuranVoiceCommand.next:
          if (_index >= _ayahs.length - 1) {
            _assistantPhase = _AssistantPhase.askingWhatMemorized;
            await _assistantSpeakAndListen(
              'وصلنا إلى آخر آية في السورة. أحسنت في إكمال الجلسة. ما السورة التي تريد مراجعتها بعد ذلك؟',
            );
            return;
          }
          await _move(1);
          _assistantPhase = _AssistantPhase.askingStart;
          await _assistantSpeakAndListen(
            'انتقلنا إلى الآية ${_ayah?.numberInSurah ?? 1}. هل نبدأ تسميعها؟ قل ابدأ.',
          );
          return;
        case QuranVoiceCommand.previous:
          await _move(-1);
          _assistantPhase = _AssistantPhase.askingStart;
          await _assistantSpeakAndListen(
            'عدنا إلى الآية ${_ayah?.numberInSurah ?? 1}. هل تعيد تسميعها؟ قل ابدأ.',
          );
          return;
        case QuranVoiceCommand.start:
          await _startAssistantRecitation();
          return;
        case QuranVoiceCommand.markMemorized:
          await _memorized();
          await _assistantSpeakAndListen(
            'سجلت الآية في محفوظاتك، وحددت موعد مراجعتها وفق خطة المراجعة المتباعدة. هل ننتقل إلى الآية التالية؟',
          );
          return;
        case QuranVoiceCommand.needsReview:
          await _needsReview();
          await _assistantSpeakAndListen(
            'سجلت هذه الآية للمراجعة القريبة، وحددت تذكير المراجعة بعد اثنتي عشرة ساعة. هل تعيد التسميع أم ننتقل؟',
          );
          return;
        case QuranVoiceCommand.stop:
        case QuranVoiceCommand.unknown:
          await _assistantDiscuss(
            input,
            followUp: 'أجب بإيجاز عن كلامه دون اختراع آيات أو إصدار فتوى، ثم اسأله هل يريد إعادة الآية أو إظهارها أو الانتقال إلى التالية.',
          );
          return;
      }
    }

    if (_assistantPhase == _AssistantPhase.reciting) {
      await _assistantSpeakAndListen('استمر في التسميع، أو قل قف لإيقاف الجلسة.');
      return;
    }
  }

  Future<void> _selectAssistantSurah(int number) async {
    await _loadSurah(number);
    if (!mounted || _ayahs.isEmpty) return;
    final surah = allOfflineSurahs.firstWhere(
      (item) => item.number == number,
      orElse: () => allOfflineSurahs.first,
    );
    setState(() {
      _blindRecallMode = true;
      _showText = false;
      _assistantPhase = _AssistantPhase.askingStart;
    });
    await _assistantSpeakAndListen(
      'تمام يا مهندس أحمد محمد. اخترت ${surah.name}. '
      'هل نبدأ من أول آية؟ قل ابدأ التسميع، أو اذكر سورة أخرى.',
    );
  }

  Future<void> _startAssistantRecitation() async {
    if (_ayah == null) {
      await _assistantSpeakAndListen('لم تُحمّل آيات السورة بعد. اختر السورة أولًا.');
      return;
    }
    setState(() {
      _assistantPhase = _AssistantPhase.reciting;
      _assistantResultProcessing = false;
      _assistantManualRecognitionStop = false;
      _recognized = '';
      _result = null;
      _showText = false;
      _status = 'استمع إلى تلاوتك للآية الحالية...';
    });
    await _start();
  }

  Future<void> _finishAssistantRecitation(String recognizedText) async {
    if (_assistantResultProcessing || !_assistantConversationActive ||
        _assistantPhase != _AssistantPhase.reciting || _ayah == null) {
      return;
    }
    _assistantResultProcessing = true;
    _assistantManualRecognitionStop = false;
    if (recognizedText.trim().isEmpty) {
      setState(() {
        _assistantPhase = _AssistantPhase.awaitingFeedback;
        _status = 'لم يلتقط الهاتف كلامًا واضحًا. أعد المحاولة.';
      });
      _assistantResultProcessing = false;
      await _assistantSpeakAndListen(
        'لم ألتقط تلاوة واضحة، وهذا لا يعني أنك أخطأت. تأكد من قرب الهاتف ثم قل كرر لإعادة المحاولة.',
      );
      return;
    }
    final normalizedCommand = QuranVoiceIntent.parseCommand(recognizedText);
    if (normalizedCommand == QuranVoiceCommand.stop) {
      _assistantResultProcessing = false;
      await _stopVoiceAssistant();
      return;
    }

    final result = QuranRecitationMatcher.compare(
      expected: _ayah!.text,
      recognized: recognizedText,
    );
    setState(() {
      _recognized = recognizedText;
      _result = result;
      _listening = false;
      _assistantListening = false;
      _assistantPhase = _AssistantPhase.awaitingFeedback;
      _status = 'انتهت المقارنة اللفظية التقريبية. راجع ملاحظات المساعد.';
    });
    await _saveAssistantAttempt(result);

    final missing = result.missingWords.take(5).join('، ');
    final extra = result.extraWords.take(5).join('، ');
    String feedback;
    if (result.missingWords.isEmpty && result.extraWords.isEmpty &&
        result.outOfOrderWords.isEmpty) {
      feedback =
          'أحسنت. التقط الهاتف كلمات الآية كاملة في هذه المحاولة. '
          'هذا فحص لفظي آلي فقط، وليس تقييمًا للتجويد أو المخارج. '
          'هل ننتقل إلى الآية التالية أم تعيدها؟';
    } else if (result.missingWords.isEmpty &&
        result.extraWords.isEmpty &&
        result.outOfOrderWords.isNotEmpty) {
      final positions = result.outOfOrderWords
          .take(4)
          .map(
            (issue) =>
                'موضع ${issue.position}: التقط الهاتف «${issue.recognizedWord}» بدل «${issue.expectedWord}»',
          )
          .join('، ');
      feedback =
          'الكلمات التي التقطها الهاتف موجودة، لكن ترتيب بعضها مختلف ويحتاج مراجعة: $positions. '
          'قد يكون هذا من خطأ التعرف الصوتي. هل تريد إظهار الآية أم إعادة المحاولة؟';
    } else {
      final details = <String>[];
      if (missing.isNotEmpty) details.add('كلمات لم يلتقطها الهاتف: $missing');
      if (extra.isNotEmpty) details.add('وكلمات إضافية التقطها: $extra');
      feedback =
          'توقف هنا للمراجعة يا مهندس أحمد محمد. ${details.join('، ')}. '
          'قد يكون الاختلاف من التعرف الصوتي نفسه، لذلك لا أعدّه حكمًا بأنك أخطأت في القرآن. '
          'هل تريد إعادة الآية، أم إظهار النص، أم الانتقال؟';
    }
    _assistantResultProcessing = false;
    await _assistantSpeakAndListen(feedback);
  }

  Future<void> _saveAssistantAttempt(QuranRecitationComparison result) async {
    final record = _record(_recordKey);
    final existing = record['attempts'];
    final attempts = existing is List
        ? List<dynamic>.from(existing)
        : <dynamic>[];
    attempts.add({
      'at': DateTime.now().millisecondsSinceEpoch,
      'similarityPercent': result.similarityPercent,
      'matchedWords': result.matchedWords,
      'expectedWords': result.expectedWords,
      'missingWords': result.missingWords,
      'extraWords': result.extraWords,
      'outOfOrderWords': result.outOfOrderWords.map((issue) => issue.toJson()).toList(),
    });
    if (attempts.length > 20) {
      attempts.removeRange(0, attempts.length - 20);
    }
    record['attempts'] = attempts;
    record['lastAttemptAt'] = DateTime.now().millisecondsSinceEpoch;
    _records[_recordKey] = record;
    await _save();
  }

  Future<void> _assistantDiscuss(
    String userMessage, {
    required String followUp,
  }) async {
    const systemPrompt = '''
أنت المساعد الصوتي المحلي لتطبيق قلم مسلم. تخاطب المستخدم باحترام وتناديه عند الحاجة: المهندس أحمد محمد.
تحدث بالعربية الواضحة وبأسلوب إنساني هادئ، واستمع إلى سياق الحوار ولا تكرر التحية في كل رد.
مهم جدًا:
- لا تخترع آيات قرآنية ولا تكتب نصًا قرآنيًا من ذاكرتك. مصدر نص الآية هو المصحف المدمج في التطبيق فقط.
- لا تحكم على صحة التلاوة أو التجويد أو المخارج؛ نتيجة التعرف الصوتي تقريبية وقد يخطئ الهاتف.
- لا تصدر فتاوى. عند السؤال الشرعي وجّه المستخدم إلى مصدر موثوق أو عالم مؤهل.
- دورك المساندة في الحفظ، التشجيع، تنظيم المراجعة، والإجابة العامة المختصرة.
''';
    _assistantHistory.add({'role': 'user', 'content': userMessage});
    if (_assistantHistory.length > 10) {
      _assistantHistory.removeRange(0, _assistantHistory.length - 10);
    }

    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': '$systemPrompt\n\nحالة الجلسة: $followUp',
      },
      ..._assistantHistory,
    ];
    final response = StringBuffer();
    try {
      await for (final token in _localAssistant.generateReply(messages)) {
        response.write(token);
      }
    } catch (_) {
      response.write(
        'أفهم ما تقوله، لكن تعذّر عليّ توليد رد الآن. يمكننا متابعة التسميع أو إعادة المحاولة.',
      );
    }

    var reply = response
        .toString()
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
        .trim();
    if (reply.isEmpty) {
      reply = 'أنا معك. هل نتابع الحفظ أم تريد أن نتحدث قليلًا عن خطتك؟';
    }
    _assistantHistory.add({'role': 'assistant', 'content': reply});
    if (_assistantHistory.length > 10) {
      _assistantHistory.removeRange(0, _assistantHistory.length - 10);
    }
    await _assistantSpeakAndListen(reply);
  }

  Future<void> _stopVoiceAssistant() async {
    _assistantConversationActive = false;
    _assistantPhase = _AssistantPhase.idle;
    _assistantListening = false;
    _assistantSpeaking = false;
    _assistantFinalResultHandled = true;
    _assistantNoSpeechRetries = 0;
    await _speech.stop();
    await _tts.stop();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _status = 'انتهت جلسة المساعد الصوتي.';
    });
    _toast('انتهت جلسة المساعد الصوتي. النموذج ما زال محمّلًا حتى تغلق الشاشة.');
  }

  Widget _voiceAssistantCard(ThemeData theme) {
    final scheme = theme.colorScheme;
    final progress = _assistantBusy && _assistantDownloadProgress > 0
        ? _assistantDownloadProgress
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.forum_rounded, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'المساعد الصوتي الذكي',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'حوار عربي محلي · لا يحتاج مفتاح API',
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (_assistantReady)
                  Icon(Icons.check_circle, color: scheme.primary),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              _assistantModelStatus,
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
            if (_assistantBusy) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress),
              if (_assistantModelStatus.startsWith('تنزيل النموذج'))
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: _cancelVoiceAssistantDownload,
                    icon: const Icon(Icons.close_rounded, size: 17),
                    label: const Text('إلغاء التنزيل'),
                  ),
                ),
            ],
            const SizedBox(height: 10),
            if (_assistantConversationActive) ...[
              OutlinedButton.icon(
                onPressed: _stopVoiceAssistant,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('إنهاء الحوار'),
              ),
              if (!_assistantListening &&
                  !_assistantSpeaking &&
                  _assistantPhase != _AssistantPhase.reciting)
                FilledButton.tonalIcon(
                  onPressed: _resumeAssistantListening,
                  icon: const Icon(Icons.mic_rounded),
                  label: const Text('استمع مجددًا'),
                ),
            ] else
              FilledButton.icon(
                onPressed: _assistantBusy ? null : _prepareVoiceAssistant,
                icon: Icon(
                  _assistantBusy
                      ? Icons.downloading_rounded
                      : Icons.mic_rounded,
                ),
                label: Text(
                  _assistantBusy
                      ? 'جارٍ تجهيز المساعد...'
                      : (_assistantReady
                          ? 'ابدأ الحوار الصوتي'
                          : 'تنزيل وتجهيز المساعد'),
                ),
              ),
            if (_assistantTranscript.isNotEmpty) ...[
              const Divider(height: 22),
              ..._assistantTranscript.map((line) {
                final isAssistant = line['role'] == 'assistant';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Align(
                    alignment: isAssistant
                        ? AlignmentDirectional.centerStart
                        : AlignmentDirectional.centerEnd,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 310),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isAssistant
                            ? scheme.surfaceContainerHighest
                            : scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        line['content'] ?? '',
                        textAlign: TextAlign.start,
                        style: const TextStyle(fontSize: 12, height: 1.45),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
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
    _commandMode = false;
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
            if (event.finalResult) _listening = false;
          });
          if (event.finalResult) {
            if (_commandMode) {
              _commandMode = false;
              unawaited(_handleVoiceCommand(event.recognizedWords));
            } else if (_assistantConversationActive &&
                _assistantPhase == _AssistantPhase.reciting) {
              unawaited(_finishAssistantRecitation(event.recognizedWords));
            } else {
              _compare();
            }
          }
        },
      );
    } catch (_) {
      if (mounted) setState(() {
        _listening = false;
        _status = 'لم يبدأ الميكروفون. تحقق من إذن التسجيل.';
      });
    }
  }

  Future<void> _startVoiceCommand() async {
    if (!_speechReady) {
      _toast('خدمة الأوامر الصوتية العربية غير متاحة على هذا الجهاز.');
      return;
    }
    await _player.stop();
    await _tts.stop();
    _commandMode = true;
    setState(() {
      _recognized = '';
      _listening = true;
      _status = 'استمع إلى أمر قصير: التالي، السابق، كرر، أظهر الآية، أو ابدأ التسميع.';
    });
    try {
      await _speech.listen(
        localeId: _locale,
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 2),
        onResult: (event) {
          if (!mounted) return;
          setState(() {
            _recognized = event.recognizedWords;
            if (event.finalResult) _listening = false;
          });
          if (event.finalResult && _commandMode) {
            _commandMode = false;
            unawaited(_handleVoiceCommand(event.recognizedWords));
          }
        },
      );
    } catch (_) {
      _commandMode = false;
      if (mounted) setState(() {
        _listening = false;
        _status = 'تعذّر تشغيل الأوامر الصوتية. تحقق من إذن الميكروفون.';
      });
    }
  }

  Future<void> _handleVoiceCommand(String rawCommand) async {
    final command = rawCommand
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .trim()
        .toLowerCase();
    if (command.isEmpty) {
      _toast('لم ألتقط أمرًا واضحًا. حاول مرة أخرى.');
      return;
    }
    if (command.contains('التالي') || command.contains('بعدها')) {
      await _move(1);
      return;
    }
    if (command.contains('السابق') || command.contains('قبل')) {
      await _move(-1);
      return;
    }
    if (command.contains('كرر') || command.contains('اعاده') || command.contains('استمع') || command.contains('شغل')) {
      await _playReference();
      return;
    }
    if (command.contains('اخف') || command.contains('اخفي')) {
      setState(() => _showText = false);
      await _announce('أخفيت نص الآية. ابدأ التسميع من حفظك.');
      return;
    }
    if (command.contains('اظهر') || command.contains('اعرض')) {
      setState(() => _showText = true);
      await _announce('أظهرت نص الآية.');
      return;
    }
    if (command.contains('ابدأ') || command.contains('سمع') || command.contains('تسميع')) {
      await _start();
      return;
    }
    await _announce('لم أفهم الأمر. قل التالي، السابق، كرر، أظهر الآية، أخف الآية، أو ابدأ التسميع.');
  }

  Future<void> _announce(String message) async {
    _toast(message);
    if (_ttsReady) {
      await _tts.stop();
      await _tts.speak(message);
    }
  }

  void _compare() {
    if (_ayah == null || _recognized.trim().isEmpty) return;
    _result = QuranRecitationMatcher.compare(expected: _ayah!.text, recognized: _recognized);
    _status = 'اكتملت المقارنة اللفظية. راجع الكلمات أدناه.';
  }

  Future<void> _stop() async {
    if (_assistantConversationActive &&
        _assistantPhase == _AssistantPhase.reciting) {
      _assistantManualRecognitionStop = true;
    }
    await _speech.stop();
    if (_assistantConversationActive &&
        _assistantPhase == _AssistantPhase.reciting) {
      await _finishAssistantRecitation(_recognized);
      return;
    }
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
    if (_selectedReciter.isEmpty) {
      _toast('لم يتوفر قارئ مرجعي بعد. تحقق من الاتصال ثم أعد المحاولة.');
      return;
    }
    final url = ApiService.buildSurahAudioUrl(
      _surah,
      reciter: 'mp3quran_server_$_selectedReciter',
    );
    if (url.isEmpty) {
      _toast('رابط التلاوة غير متاح لهذا المصدر.');
      return;
    }
    try {
      await _player.setReleaseMode(
        _repeatReference ? ReleaseMode.loop : ReleaseMode.stop,
      );
      await _player.play(UrlSource(url));
      _toast('بدأ تشغيل السورة كاملة من مصدر القارئ المرجعي.');
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
      _showText = !_blindRecallMode;
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
    final currentRecord = _record(_recordKey);
    final oldStage = currentRecord['stage'] as int? ?? -1;
    const days = [1, 3, 7, 14, 30];
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final lastReviewedAt = currentRecord['lastReviewedAt'] as int? ?? 0;
    final alreadyReviewedToday =
        lastReviewedAt >= todayStart && lastReviewedAt <= now.millisecondsSinceEpoch;
    final stage = (alreadyReviewedToday ? oldStage : oldStage + 1)
        .clamp(0, days.length - 1)
        .toInt();
    _records[_recordKey] = {
      ..._record(_recordKey),
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
      ..._record(_recordKey),
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
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = DateTime.fromMillisecondsSinceEpoch(now);
    final dayStart = DateTime(start.year, start.month, start.day).millisecondsSinceEpoch;
    return _records.values.where((value) {
      if (value is! Map) return false;
      final reviewedAt = value['lastReviewedAt'] as int? ?? 0;
      return reviewedAt >= dayStart && reviewedAt <= now;
    }).length;
  }

  Future<void> _changeTarget(int step) async {
    _dailyTarget = (_dailyTarget + step).clamp(1, 30).toInt();
    await widget.storage.setInt('hifz_daily_target', _dailyTarget);
    if (mounted) setState(() {});
  }

  Future<void> _openEntry(MapEntry<String, Map<String, dynamic>> entry) async {
    _blindRecallMode = false;
    await _loadSurah(entry.value['surah'] as int? ?? 1, ayahNumber: entry.value['ayah'] as int? ?? 1);
    if (!mounted) return;
    setState(() => _showText = true);
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
    _blindRecallMode = true;
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
    _assistantConversationActive = false;
    _assistantListening = false;
    _assistantSpeaking = false;
    _assistantFinalResultHandled = true;
    unawaited(_localAssistant.cancelDownload());
    _speech.cancel();
    _tts.stop();
    _player.dispose();
    unawaited(_localAssistant.dispose());
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
        _voiceAssistantCard(theme),
        const SizedBox(height: 10),
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.record_voice_over_rounded, color: scheme.primary),
            ),
            title: const Text('مساعد التسميع الصوتي', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('الشيخ أحمد محمد · مساعد آلي'),
          trailing: IconButton(
            tooltip: 'الأوامر الصوتية',
            onPressed: _listening ? null : _startVoiceCommand,
            icon: const Icon(Icons.mic_external_on_outlined),
          ),
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
        if (_loadingReferenceReciters)
          const LinearProgressIndicator(minHeight: 2)
        else if (_referenceReciters.isEmpty)
          OutlinedButton.icon(
            onPressed: _loadReferenceReciters,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('تعذّر تحميل القراء — أعد المحاولة'),
          )
        else
          DropdownButtonFormField<String>(
            value: _selectedReciter,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'اختر القارئ المرجعي',
              helperText: 'مصادر تلاوة حقيقية من MP3Quran',
              prefixIcon: Icon(Icons.record_voice_over_outlined),
            ),
            items: _referenceReciters.map((source) {
              final name = (source['name'] ?? '').toString();
              final moshaf = (source['moshaf_name'] ?? '').toString();
              final label = moshaf.isEmpty ? name : '$name · $moshaf';
              return DropdownMenuItem<String>(
                value: source['server'] as String,
                child: Text(label, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (value) async {
              if (value == null) return;
              await _player.stop();
              setState(() => _selectedReciter = value);
              await widget.storage.setString('hifz_reference_reciter', value);
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
                    title: const Text('تكرار التلاوة المرجعية'),
                    subtitle: const Text('يكرر تسجيل السورة المرجعية كاملة حتى توقفه يدويًا'),
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
                    if (_result!.outOfOrderWords.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        'كلمات التقطها الهاتف بترتيب مختلف:',
                        style: TextStyle(
                          color: scheme.tertiary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ..._result!.outOfOrderWords.take(4).map(
                        (issue) => Text(
                          'الموضع ${issue.position}: «${issue.recognizedWord}» بدل «${issue.expectedWord}»',
                          style: TextStyle(color: scheme.tertiary, fontSize: 14),
                        ),
                      ),
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