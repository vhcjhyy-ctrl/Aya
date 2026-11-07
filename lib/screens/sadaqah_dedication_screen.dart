import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SadaqahDedicationScreen extends StatefulWidget {
  final Future<void> Function() onContinue;
  const SadaqahDedicationScreen({super.key, required this.onContinue});

  @override
  State<SadaqahDedicationScreen> createState() => _SadaqahDedicationScreenState();
}

class _SadaqahDedicationScreenState extends State<SadaqahDedicationScreen> {
  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;
  bool _spoken = false;
  bool _speechUnavailable = false;
  bool _continuing = false;

  static const String _spokenText =
      'هذا التطبيق قلم مسلم، صدقة جارية على روح جدتي سعدية محمد قشطة، '
      'وعيد الزبلاوي، وأحمد السيد السيسي. '
      'نسأل الله أن يرحمهم رحمة واسعة، ويغفر لهم، ويعفو عنهم، '
      'وينوّر قبورهم، ويوسّع مدخلهم، ويجعل مثواهم الجنة. '
      'نرجو منكم الدعاء لهم بالرحمة والمغفرة.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted) unawaited(_speakDedication());
      });
    });
  }

  Future<void> _speakDedication() async {
    if (_speaking || _continuing) return;
    setState(() {
      _speaking = true;
      _speechUnavailable = false;
    });
    try {
      await _tts.stop();
      await _tts.setLanguage('ar');
      await _tts.setSpeechRate(0.43);
      await _tts.setPitch(0.96);
      await _tts.setVolume(0.9);
      await _tts.awaitSpeakCompletion(true);
      await _tts.speak(_spokenText);
      _spoken = true;
    } catch (error) {
      debugPrint('Dedication speech unavailable: $error');
      _speechUnavailable = true;
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  Future<void> _continue() async {
    if (_continuing) return;
    setState(() => _continuing = true);
    try {
      await _tts.stop();
    } catch (_) {}
    await widget.onContinue();
  }

  @override
  void dispose() {
    unawaited(_tts.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            PositionedDirectional(
              top: -100,
              end: -80,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary.withValues(alpha: 0.07),
                ),
              ),
            ),
            PositionedDirectional(
              bottom: -120,
              start: -90,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFC5A45B).withValues(alpha: 0.08),
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
                  children: [
                    Center(
                      child: Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.primary.withValues(alpha: 0.10),
                          border: Border.all(
                            color: const Color(0xFFC5A45B).withValues(alpha: 0.55),
                            width: 1.4,
                          ),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          size: 38,
                          color: Color(0xFFC5A45B),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'قَلَم مُسْلِم',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 31,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'رِفْقَةٌ لِلْقُرْآنِ وَالذِّكْرِ وَالْعِلْمِ النَّافِع',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.8,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        color: scheme.surface,
                        border: Border.all(
                          color: const Color(0xFFC5A45B).withValues(alpha: 0.5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.12 : 0.045,
                            ),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.volunteer_activism_rounded,
                                color: Color(0xFFC5A45B),
                                size: 19,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'إهداء وصدقة جارية',
                                style: TextStyle(
                                  color: Color(0xFFC5A45B),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'هذا التطبيق «قلم مسلم» صدقة جارية على روح',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 17,
                              height: 1.8,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 15),
                          _dedicatedName(scheme, 'جدتي سعدية محمد قشطة'),
                          const SizedBox(height: 9),
                          _dedicatedName(scheme, 'عيد الزبلاوي'),
                          const SizedBox(height: 9),
                          _dedicatedName(scheme, 'أحمد السيد السيسي'),
                          const SizedBox(height: 19),
                          Divider(color: scheme.outlineVariant),
                          const SizedBox(height: 17),
                          Text(
                            'اللهم ارحمهم رحمةً واسعة، واغفر لهم، واعفُ عنهم، '
                            'وأكرم نُزُلهم، ووسّع مُدخلهم، ونوّر قبورهم، '
                            'واجعل قبورهم روضةً من رياض الجنة، '
                            'واجمعنا بهم في مستقر رحمتك.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 16,
                              height: 2,
                            ),
                          ),
                          const SizedBox(height: 13),
                          Text(
                            'نسألكم الدعاء لهم بالرحمة والمغفرة.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _speaking
                                ? Icons.volume_up_rounded
                                : _speechUnavailable
                                    ? Icons.volume_off_rounded
                                    : Icons.record_voice_over_rounded,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _speaking
                                  ? 'يجري الآن إلقاء الإهداء صوتيًا…'
                                  : _speechUnavailable
                                      ? 'تعذّر تشغيل صوت الهاتف؛ نص الإهداء ظاهر ويمكنك المتابعة.'
                                      : _spoken
                                          ? 'تم إلقاء الإهداء. يمكنك إعادة سماعه.'
                                          : 'سيُقرأ الإهداء بصوت الهاتف عند توفر الصوت العربي.',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'إعادة سماع الإهداء',
                            onPressed: _speaking ? null : _speakDedication,
                            icon: const Icon(Icons.replay_rounded),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 19),
                    FilledButton.icon(
                      onPressed: _continuing ? null : _continue,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(
                        _continuing ? 'جارٍ المتابعة…' : 'الدخول إلى قلم مسلم',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(17),
                        ),
                      ),
                    ),
                    const SizedBox(height: 11),
                    Text(
                      'نسأل الله القبول، وأن يجعل هذا العمل علمًا نافعًا وأجرًا باقيًا.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dedicatedName(ColorScheme scheme, String name) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        name,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
