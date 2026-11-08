part of 'settings_screen.dart';

extension SettingsAboutSection on _SettingsScreenState {
  List<Widget> _buildAboutSection(ThemeData theme) {
    final isAr = TranslationService.isArabic;
    final primary = theme.colorScheme.primary;

    return [
      SettingsSectionHeader(
        icon: Icons.info_outline,
        title: isAr ? 'عن التطبيق' : 'About the app',
      ),
      Card(
        color: theme.cardColor.withValues(alpha: 0.7),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: (theme.textTheme.bodyLarge?.color ?? Colors.white)
                .withValues(alpha: 0.1),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: ListTile(
              leading: Icon(Icons.info_outline, color: primary),
              title: Text(
                isAr ? 'حول قلم مسلم' : 'About Qalam Muslim',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                isAr
                    ? 'معلومات الإصدار والمصدر المفتوح والتراخيص'
                    : 'Version, open-source code, and license information',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AboutScreen()),
                );
              },
            ),
          ),
        ),
      ),
    ];
  }
}
