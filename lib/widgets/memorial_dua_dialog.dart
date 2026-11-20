import 'package:flutter/material.dart';
import '../services/translation_service.dart';

/// A short family memorial supplication displayed once on every fresh launch.
class MemorialDuaDialog extends StatelessWidget {
  final VoidCallback onContinue;

  const MemorialDuaDialog({
    super.key,
    required this.onContinue,
  });

  static const Color _gold = Color(0xFFE5C158);

  @override
  Widget build(BuildContext context) {
    final isArabic = TranslationService.isArabic;
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.cardColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: _gold.withValues(alpha: 0.48), width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.volunteer_activism_rounded,
                  color: _gold,
                  size: 30,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isArabic ? 'دعاء لجدّتي وأجدادي' : 'A prayer for my grandparents',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _gold,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                isArabic
                    ? 'نسأل الله أن يتغمّدهم بواسع رحمته ومغفرته'
                    : 'May Allah grant them His mercy and forgiveness',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 18),
              _PrayerParagraph(
                text:
                    'اللهم اغفر لجدتي سعدية محمد قشطة، وارحمها رحمةً واسعة، وعافها واعفُ عنها، وأكرم نُزُلها، ووسّع مُدخلها، واغسلها بالماء والثلج والبرد، ونقِّها من الخطايا كما يُنقّى الثوب الأبيض من الدنس.',
              ),
              const SizedBox(height: 12),
              _PrayerParagraph(
                text:
                    'اللهم اغفر لجدي عيد الزبلاوي، وارحمه رحمةً واسعة، وعافه واعفُ عنه، وأكرم نُزُله، ووسّع مُدخله، واغسله بالماء والثلج والبرد، ونقِّه من الخطايا كما يُنقّى الثوب الأبيض من الدنس.',
              ),
              const SizedBox(height: 12),
              _PrayerParagraph(
                text:
                    'اللهم اغفر لجدي أحمد السيد السيسي، وارحمه رحمةً واسعة، وعافه واعفُ عنه، وأكرم نُزُله، ووسّع مُدخله، واغسله بالماء والثلج والبرد، ونقِّه من الخطايا كما يُنقّى الثوب الأبيض من الدنس.',
              ),
              const SizedBox(height: 12),
              _PrayerParagraph(
                text:
                    'اللهم آنس وحشتهم، ونوّر قبورهم، واجعلها روضةً من رياض الجنة، وارفع درجاتهم في المهديين، واجمعنا بهم في جنات النعيم.',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onContinue,
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: Text(isArabic ? 'آمين، متابعة' : 'Ameen, Continue'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: const Color(0xFF201A0B),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrayerParagraph extends StatelessWidget {
  final String text;

  const _PrayerParagraph({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _gold.withValues(alpha: 0.20)),
      ),
      child: Text(
        text,
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge?.copyWith(
          height: 1.9,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

const Color _gold = Color(0xFFE5C158);
