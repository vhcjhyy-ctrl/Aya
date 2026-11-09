import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/translation_service.dart';
import '../version.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static final Uri _sourceUri = Uri.parse(
    'https://github.com/vhcjhyy-ctrl/Aya/tree/qalam-muslim-enhancements',
  );

  Future<void> _openSource() async {
    if (await canLaunchUrl(_sourceUri)) {
      await launchUrl(_sourceUri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = TranslationService.isArabic;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          isArabic ? 'حول قلم مسلم' : 'About Qalam Muslim',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.primaryColor.withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.mosque, size: 80, color: Color(0xFFE5C158)),
            ),
            const SizedBox(height: 24),
            Text(
              isArabic ? 'قلم مسلم' : 'Qalam Muslim',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isArabic ? 'الإصدار $appVersion' : 'Version $appVersion',
              style: TextStyle(
                fontSize: 16,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 32),
            Card(
              color: theme.cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  isArabic
                      ? 'يجمع قلم مسلم أدوات إسلامية تساعدك في قراءة القرآن الكريم، ومتابعة الأذكار والحديث ومواقيت الصلاة، مع مزايا تعمل دون اتصال بالإنترنت.'
                      : 'Qalam Muslim brings together tools for Quran reading, Hadith, daily remembrance, prayer times, and other Islamic resources, with core features available offline.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.6,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _sectionHeader(theme, isArabic ? 'الميزات' : 'Features'),
            const SizedBox(height: 12),
            _featureCard(
              theme,
              Icons.wifi_off,
              isArabic
                  ? 'قرآن وحديث وأذكار ومواقيت صلاة مع دعم الاستخدام دون إنترنت'
                  : 'Quran, Hadith, Azkar, and prayer times with offline support',
            ),
            _featureCard(
              theme,
              Icons.menu_book,
              isArabic
                  ? 'قراءات قرآنية متعددة وتلاوات متزامنة مع الآيات'
                  : 'Multiple Quranic readings and verse-synchronized recitations',
            ),
            _featureCard(
              theme,
              Icons.library_books,
              isArabic
                  ? 'مكتبة حديث مع البحث والتخريج والشرح'
                  : 'Hadith library with search, grading, and explanations',
            ),
            _featureCard(
              theme,
              Icons.access_alarm,
              isArabic
                  ? 'مواقيت الصلاة والأذان والتنبيهات'
                  : 'Prayer times, Adhan, and reminders',
            ),
            _featureCard(
              theme,
              Icons.widgets,
              isArabic
                  ? 'أدوات للشاشة الرئيسية للآيات والأذكار ومواقيت الصلاة'
                  : 'Home-screen widgets for verses, remembrance, and prayer times',
            ),
            const SizedBox(height: 32),
            _sectionHeader(theme, isArabic ? 'مشروع مفتوح المصدر' : 'Open-source project'),
            const SizedBox(height: 12),
            Card(
              color: theme.cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                    child: Text(
                      isArabic
                          ? 'الشيفرة المصدرية متاحة للعامة. يتضمن المستودع ملف الترخيص وإشعارات حقوق المكونات مفتوحة المصدر المستخدمة في المشروع.'
                          : 'The source code is publicly available. The repository includes the applicable license and notices for open-source components used by the project.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.6,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.code, color: Color(0xFFE5C158)),
                    title: Text(
                      isArabic ? 'عرض الشيفرة المصدرية' : 'View source code',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text('github.com/vhcjhyy-ctrl/Aya'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: _openSource,
                  ),
                  ListTile(
                    leading: const Icon(Icons.description_outlined, color: Color(0xFFE5C158)),
                    title: Text(
                      isArabic ? 'الترخيص' : 'License',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      isArabic
                          ? 'MIT مع الاحتفاظ بإشعارات حقوق المكونات وتراخيصها'
                          : 'MIT, with third-party copyright and license notices retained',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Text(
              isArabic ? 'مشروع مفتوح المصدر • ٢٠٢٦' : 'Open-source project • 2026',
              style: TextStyle(
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
              style: TextStyle(
                fontFamily: 'Amiri',
                fontSize: 18,
                color: const Color(0xFFE5C158).withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String title) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: theme.textTheme.bodyLarge?.color,
        ),
      ),
    );
  }

  Widget _featureCard(ThemeData theme, IconData icon, String text) {
    return Card(
      color: theme.cardColor,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFE5C158).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFFE5C158), size: 20),
        ),
        title: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            color: theme.textTheme.bodyLarge?.color,
          ),
        ),
      ),
    );
  }
}
