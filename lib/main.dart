import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dorar_hadith_flutter/dorar_hadith_flutter.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/storage_service.dart';
import 'services/translation_service.dart';
import 'services/notification_service.dart';
import 'services/api_service.dart';
import 'services/audio_manager.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'theme/app_themes.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep the startup path short and prevent auxiliary services from
  // holding the app on a blank screen if one of them fails.
  try {
    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory('${supportDir.path}/dorar_databases');
    await dbDir.create(recursive: true);
    Directory.current = dbDir.path;
  } catch (error, stackTrace) {
    debugPrint('Qalam Muslim data-directory setup failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  final storage = await StorageService.getInstance();
  TranslationService.setLanguage(
    storage.getString('lang_code', defaultValue: 'ar'),
  );

  runApp(AyaApp(storage: storage));

  // Continue initialization after Flutter has rendered its first frame.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future<void>.microtask(() async {
      try {
        final supportDir = await getApplicationSupportDirectory();
        final dbDir = Directory('${supportDir.path}/dorar_databases');
        await dbDir.create(recursive: true);
        Directory.current = dbDir.path;
        await DorarHadithFlutter.ensureInitialized(databaseDirectory: dbDir);
      } catch (error, stackTrace) {
        debugPrint('Optional hadith service initialization failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }

      try {
        await ApiService.migrateCacheToFiles();
      } catch (error) {
        debugPrint('Cache migration skipped: $error');
      }

      try {
        await AndroidAlarmManager.initialize();
      } catch (error) {
        debugPrint('Alarm manager initialization skipped: $error');
      }

      try {
        await NotificationService().init();
      } catch (error, stackTrace) {
        debugPrint('Notification initialization failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }

      try {
        AudioManager.instance.init(storage);
      } catch (error, stackTrace) {
        debugPrint('Audio service initialization failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    });
  });
}

class AyaApp extends StatefulWidget {
  final StorageService storage;

  const AyaApp({super.key, required this.storage});

  @override
  State<AyaApp> createState() => _AyaAppState();
}

class _AyaAppState extends State<AyaApp> {
  String _activeTheme = 'dark';
  String _langCode = 'ar';

  @override
  void initState() {
    super.initState();
    _activeTheme = widget.storage.getString(
      'theme_preset',
      defaultValue: 'dark',
    );
    _langCode = widget.storage.getString('lang_code', defaultValue: 'ar');
    TranslationService.setLanguage(_langCode);
  }

  void _updateTheme() {
    setState(() {
      _activeTheme = widget.storage.getString(
        'theme_preset',
        defaultValue: 'dark',
      );
      _langCode = widget.storage.getString('lang_code', defaultValue: 'ar');
      TranslationService.setLanguage(_langCode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final themeData = buildThemeData(
          _activeTheme,
          lightDynamic: lightDynamic,
          darkDynamic: darkDynamic,
        ).copyWith(
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: CupertinoPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            },
          ),
        );

        return MaterialApp(
          title: 'Qalam Muslim - Islamic App',
          debugShowCheckedModeBanner: false,
          theme: themeData,
          locale: Locale(TranslationService.currentLanguage),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            return Directionality(
              textDirection: TranslationService.isArabic
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: SplashScreen(
            storage: widget.storage,
            onThemeChanged: _updateTheme,
          ),
        );
      },
    );
  }
}
