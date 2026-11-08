import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/storage_service.dart';
import '../services/database_service.dart';

/// Backup and restore personal Qalam Muslim data before reinstalling the app.
class BackupService {
  static Future<Map<String, dynamic>> exportData() async {
    final storage = await StorageService.getInstance();
    final db = await DatabaseService.getInstance();

    final hadithBookmarks =
        storage.getStringList('hadith_bookmarks') ?? <String>[];
    final legacyQuranBookmarks =
        storage.getStringList('quran_bookmarks') ?? <String>[];

    // Current Quran bookmarks live in SQLite, not SharedPreferences.
    final quranBookmarks = (await storage.getBookmarks())
        .map((item) => <String, dynamic>{
              'surahNumber': item['surahNumber'],
              'surahName': item['surahName'],
              'ayahNumber': item['ayahNumber'],
            })
        .toList();

    // Custom dhikr entries also live in SQLite.
    final customDhikrs = (await storage.getCustomDhikrs())
        .map((item) => <String, dynamic>{
              'id': item['id']?.toString(),
              'name': item['name']?.toString() ?? '',
              'arabic': item['arabic']?.toString() ?? '',
              'translation': item['translation']?.toString() ?? '',
              'target': item['target'] is num
                  ? (item['target'] as num).toInt()
                  : 33,
              'currentCount': item['currentCount'] is num
                  ? (item['currentCount'] as num).toInt()
                  : 0,
            })
        .toList();

    final settings = <String, dynamic>{};
    const stringKeys = <String>[
      'prayer_method',
      'prayer_school',
      'adhan_alert_mode',
      'pre_adhan_alert_mode',
      'quran_font',
      'theme_preset',
      'lang_code',
      'reading_mode',
      'bottom_navbar_style',
      'adhan_reciter',
      'notification_lang',
      'athan_stop_gesture',
      'nawawi40_favorites_v1',
    ];
    for (final key in stringKeys) {
      final value = storage.getString(key);
      if (value.isNotEmpty) settings[key] = value;
    }

    const intKeys = <String>[
      'calc_method',
      'asr_method',
      'first_day_of_week',
      'pre_adhan_duration',
      'focus_lock_duration',
    ];
    for (final key in intKeys) {
      final value = storage.getInt(key, defaultValue: -999);
      if (value != -999) settings[key] = value;
    }

    const doubleKeys = <String>['custom_fajr_angle', 'custom_isha_angle'];
    for (final key in doubleKeys) {
      final value = storage.getDouble(key, defaultValue: -1.0);
      if (value != -1.0) settings[key] = value;
    }

    const boolKeys = <String>[
      'morning_azkar_reminder',
      'evening_azkar_reminder',
      'todays_verse_reminder',
      'ramadan_imsak_enabled',
      'ramadan_iftar_enabled',
      'islamic_events_enabled',
      'swipe_surah_navigation',
      'hide_full_surah_disclaimer',
      'use_24h_format',
      'continuous_play',
      'setting_continuous_play',
      'setting_hide_continuous_borders',
      'setting_auto_bookmark',
      'setting_immersive_reader',
      'auto_bookmark',
      'keep_screen_awake',
    ];
    for (final key in boolKeys) {
      settings[key] = storage.getBool(key);
    }

    // Preserve the current worship checklist, fasting log, and location.
    final now = DateTime.now();
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    const appDataKeys = <String>[
      'worship_hajj_checklist_v1',
      'worship_umrah_checklist_v1',
      'worship_sadaqah_checklist_v1',
      'worship_fasting_log_v1',
    ];
    // Preserve every daily worship record, not only today's checklist.
    final dailyKeys = StorageService.prefs.getKeys()
        .where((key) => key.startsWith('worship_daily_'))
        .toList(growable: false);
    final appData = <String, String>{};
    for (final key in <String>{...appDataKeys, ...dailyKeys}) {
      final value = storage.getString(key);
      if (value.isNotEmpty) appData[key] = value;
    }

    // Preserve the last-read ayah for each surah, not only the global position.
    final lastReadBySurah = <String, int>{};
    for (var surah = 1; surah <= 114; surah++) {
      final ayah = storage.getLastReadAyahForSurah(surah);
      if (ayah != null && ayah > 0) {
        lastReadBySurah['$surah'] = ayah;
      }
    }
    final lastRead = storage.getLastReadPosition();
    final lastAudio = storage.getLastAudioPosition();
    final lastAudioTimestamp = storage.getLastAudioTimestamp();

    final rawTracker = await db.getPrayerTrackerRange(
      '2020-01-01',
      '2030-01-01',
    );
    final tracker = rawTracker.map((row) {
      return row.map(
        (key, value) => MapEntry(
          key,
          value is int ? value : int.tryParse(value.toString()) ?? 0,
        ),
      );
    }).toList();

    return <String, dynamic>{
      'version': 2,
      'app': 'qalam-muslim',
      'exported_at': now.toIso8601String(),
      'hadith_bookmarks': hadithBookmarks,
      'quran_bookmarks': legacyQuranBookmarks,
      'quran_bookmarks_v2': quranBookmarks,
      'settings': settings,
      'custom_azkar': storage.getStringList('custom_dhikrs') ?? <String>[],
      'custom_dhikrs_v2': customDhikrs,
      'location': storage.getLocation(),
      'last_read_position': lastRead,
      'last_read_positions_by_surah': lastReadBySurah,
      'last_audio_position': lastAudio,
      'last_audio_timestamp_ms': lastAudioTimestamp,
      'app_data': appData,
      'prayer_tracker': tracker,
    };
  }

  static Future<int> importData(Map<String, dynamic> data) async {
    final storage = await StorageService.getInstance();
    final db = await DatabaseService.getInstance();
    var imported = 0;

    // New structured backup format plus compatibility with older v1 files.
    final hadithBookmarks =
        (data['hadith_bookmarks'] as List?)?.cast<String>() ??
        (data['bookmarks'] as List?)?.cast<String>() ??
        <String>[];
    if (hadithBookmarks.isNotEmpty) {
      await storage.setStringList('hadith_bookmarks', hadithBookmarks);
      imported++;
    }

    final legacyQuranBookmarks =
        (data['quran_bookmarks'] as List?)?.cast<String>() ?? <String>[];
    if (legacyQuranBookmarks.isNotEmpty) {
      await storage.setStringList('quran_bookmarks', legacyQuranBookmarks);
      imported++;
    }

    final structuredBookmarks = data['quran_bookmarks_v2'] as List? ?? [];
    var restoredBookmarks = 0;
    for (final item in structuredBookmarks) {
      if (item is! Map) continue;
      final surah = int.tryParse((item['surahNumber'] ?? '').toString());
      final ayah = int.tryParse((item['ayahNumber'] ?? '').toString());
      final name = (item['surahName'] ?? '').toString();
      if (surah == null || ayah == null || surah < 1 || surah > 114 || ayah < 1) {
        continue;
      }
      await storage.addBookmark(surah, name, ayah);
      restoredBookmarks++;
    }
    if (restoredBookmarks > 0) imported++;

    final settings = data['settings'] as Map<String, dynamic>? ?? {};
    for (final entry in settings.entries) {
      final value = entry.value;
      if (value is String) {
        await storage.setString(entry.key, value);
      } else if (value is bool) {
        await storage.setBool(entry.key, value);
      } else if (value is num) {
        if (entry.key == 'custom_fajr_angle' ||
            entry.key == 'custom_isha_angle' ||
            value is double) {
          await storage.setDouble(entry.key, value.toDouble());
        } else {
          await storage.setInt(entry.key, value.toInt());
        }
      }
    }
    if (settings.isNotEmpty) imported++;

    // Keep old text-list backups working.
    final legacyAzkar =
        (data['custom_azkar'] as List?)?.cast<String>() ?? <String>[];
    if (legacyAzkar.isNotEmpty) {
      await storage.setStringList('custom_dhikrs', legacyAzkar);
      imported++;
    }

    final customDhikrs = data['custom_dhikrs_v2'] as List? ?? [];
    var restoredDhikrs = 0;
    for (final item in customDhikrs) {
      if (item is! Map) continue;
      final id = (item['id'] ?? '').toString();
      final name = (item['name'] ?? '').toString();
      final arabic = (item['arabic'] ?? '').toString();
      if (id.isEmpty || name.isEmpty || arabic.isEmpty) continue;
      final target = item['target'] is num
          ? (item['target'] as num).toInt()
          : 33;
      final currentCount = item['currentCount'] is num
          ? (item['currentCount'] as num).toInt()
          : 0;
      await db.addCustomDhikr(
        id: id,
        name: name,
        arabic: arabic,
        translation: (item['translation'] ?? '').toString(),
        target: target,
        currentCount: currentCount,
      );
      restoredDhikrs++;
    }
    if (restoredDhikrs > 0) imported++;

    final location = data['location'];
    if (location is Map) {
      final latitude = location['latitude'];
      final longitude = location['longitude'];
      if (latitude is num && longitude is num) {
        await storage.setLocation(
          (location['city'] ?? '').toString(),
          (location['country'] ?? '').toString(),
          latitude.toDouble(),
          longitude.toDouble(),
          (location['source'] ?? 'backup').toString(),
        );
        imported++;
      }
    }

    final lastRead = data['last_read_position'];
    if (lastRead is Map) {
      final surah = int.tryParse((lastRead['surah'] ?? '').toString());
      final ayah = int.tryParse((lastRead['ayah'] ?? '').toString());
      if (surah != null && ayah != null && surah >= 1 && surah <= 114 && ayah > 0) {
        await storage.saveLastReadPosition(surah, ayah);
        imported++;
      }
    }

    final lastReadBySurah =
        data['last_read_positions_by_surah'] as Map? ?? {};
    var restoredReadPositions = 0;
    for (final entry in lastReadBySurah.entries) {
      final surah = int.tryParse(entry.key.toString());
      final ayah = int.tryParse(entry.value.toString());
      if (surah == null ||
          ayah == null ||
          surah < 1 ||
          surah > 114 ||
          ayah < 1) {
        continue;
      }
      await storage.saveLastReadPosition(surah, ayah);
      restoredReadPositions++;
    }
    if (restoredReadPositions > 0) imported++;

    final lastAudio = data['last_audio_position'];
    if (lastAudio is Map) {
      final surah = int.tryParse((lastAudio['surah'] ?? '').toString());
      final ayah = int.tryParse((lastAudio['ayah'] ?? '').toString());
      final reciter = (lastAudio['reciter'] ?? '').toString();
      final surahName = (lastAudio['surahName'] ?? '').toString();
      if (surah != null && ayah != null && reciter.isNotEmpty) {
        await storage.saveLastAudioPosition(
          surah,
          ayah,
          reciter,
          surahName,
        );
        final timestamp = data['last_audio_timestamp_ms'];
        if (timestamp is num) {
          await storage.saveLastAudioTimestamp(timestamp.toInt());
        }
        imported++;
      }
    }

    final appData = data['app_data'] as Map<String, dynamic>? ?? {};
    for (final entry in appData.entries) {
      if (entry.value is String && entry.key.startsWith('worship_')) {
        await storage.setString(entry.key, entry.value as String);
      }
    }
    if (appData.isNotEmpty) imported++;

    final tracker = data['prayer_tracker'] as List? ?? [];
    var restoredTracker = 0;
    for (final item in tracker) {
      if (item is! Map) continue;
      final date = (item['date'] ?? '').toString();
      if (date.isEmpty) continue;
      for (final prayer in <String>['fajr', 'dhuhr', 'asr', 'maghrib', 'isha']) {
        final value = item[prayer];
        if (value == null) continue;
        final status = value is int ? value : int.tryParse(value.toString()) ?? 0;
        if (status > 0) {
          await db.updatePrayerTracker(date, prayer, status);
          restoredTracker++;
        }
      }
    }
    if (restoredTracker > 0) imported++;

    return imported;
  }

  static Future<String> exportToFile() async {
    final data = await exportData();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/qalam_muslim_backup.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    return file.path;
  }

  static Future<void> shareBackup() async {
    final path = await exportToFile();
    final file = XFile(path, mimeType: 'application/json');
    await SharePlus.instance.share(
      ShareParams(files: [file], text: 'Qalam Muslim backup'),
    );
  }

  /// Read a JSON backup selected by the user.
  static Future<String?> readBackupFromPath(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// Read legacy default backups and the current backup file.
  static Future<String?> readDefaultBackup() async {
    final dir = await getApplicationDocumentsDirectory();
    for (final name in <String>[
      'qalam_muslim_backup.json',
      'aya_backup.json',
    ]) {
      final file = File('${dir.path}/$name');
      if (await file.exists()) return await file.readAsString();
    }
    final downloads = Directory('/storage/emulated/0/Download');
    if (await downloads.exists()) {
      for (final name in <String>[
        'qalam_muslim_backup.json',
        'aya_backup.json',
      ]) {
        final file = File('${downloads.path}/$name');
        if (await file.exists()) return await file.readAsString();
      }
    }
    return null;
  }
}
