part of 'settings_screen.dart';

extension SettingsAboutSection on _SettingsScreenState {
  List<Widget> _buildAboutSection(ThemeData theme) {
    final isAr = TranslationService.isArabic;
    final primary = theme.colorScheme.primary;

    return [
      // Section About & Support
      SettingsSectionHeader(
        icon: Icons.info_outline,
        title: isAr ? "عن التطبيق" : "About Qalam Muslim",
      ),
      Card(
        color: theme.cardColor.withValues(alpha: 0.7),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)
                .withValues(alpha: 0.1),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.info_outline, color: primary),
                  title: Text(
                    isAr ? "حول تطبيق قلم مسلم" : "About Qalam Muslim",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    isAr ? "معلومات الإصدار والميزات والتراخيص" : "App version, features, and software licenses",
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
