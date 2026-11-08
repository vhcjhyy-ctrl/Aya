part of 'settings_screen.dart';

extension SettingsAboutSection on _SettingsScreenState {
  List<Widget> _buildAboutSection(ThemeData theme) {
    final isAr = TranslationService.isArabic;
    final primary = theme.colorScheme.primary;

    return [
      SettingsSectionHeader(
        icon: Icons.info_outline,
        title: isAr ? "عن التطبيق" : "About Qalam Muslim",
      ),
      Card(
        color: theme.cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.info_outline, color: primary),
              title: Text(
                isAr ? "حول تطبيق قلم مسلم" : "About Qalam Muslim",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                isAr
                    ? "معلومات الإصدار والميزات والتراخيص"
                    : "App version, features, and software licenses",
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AboutScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ];
  }
}
