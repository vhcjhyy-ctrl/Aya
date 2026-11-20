import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:aya_app/services/database_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('schema bootstrap preserves pre-seeded Quran tables and is repeatable', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);

    // Emulate the legacy bundled seed DB: Quran tables exist already, but
    // the database file has not yet had the current schema version applied.
    await db.execute('''
      CREATE TABLE surahs (
        number INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        englishName TEXT NOT NULL,
        englishNameTranslation TEXT NOT NULL,
        numberOfAyahs INTEGER NOT NULL,
        revelationType TEXT NOT NULL
      )
    ''');
    await db.insert('surahs', {
      'number': 1,
      'name': 'الفاتحة',
      'englishName': 'Al-Fatiha',
      'englishNameTranslation': 'The Opening',
      'numberOfAyahs': 7,
      'revelationType': 'Meccan',
    });

    await db.execute('''
      CREATE TABLE ayahs (
        id INTEGER PRIMARY KEY,
        surah_number INTEGER NOT NULL,
        ayah_number INTEGER NOT NULL,
        global_number INTEGER NOT NULL,
        text_arabic TEXT NOT NULL,
        text_english TEXT NOT NULL,
        tafsir TEXT,
        juz INTEGER,
        hizb INTEGER
      )
    ''');
    await db.insert('ayahs', {
      'id': 1,
      'surah_number': 1,
      'ayah_number': 1,
      'global_number': 1,
      'text_arabic': 'الرَّحْمَٰنِ',
      'text_english': 'The Most Merciful',
      'tafsir': null,
      'juz': 1,
      'hizb': 1,
    });

    await DatabaseService.ensureSchemaForTesting(db);

    final surahs = await db.query('surahs');
    expect(surahs, hasLength(1));
    expect(surahs.single['name'], 'الفاتحة');

    final ayahs = await db.query('ayahs');
    expect(ayahs, hasLength(1));
    expect(ayahs.single['text_arabic_clean'], 'الرحمن');
    expect(ayahs.single['page'], 1);

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final tableNames = tables.map((row) => row['name']).toSet();
    expect(tableNames, containsAll({
      'prayer_times_cache',
      'bookmarks',
      'custom_dhikrs',
      'monthly_prayer_cache',
      'audio_downloads',
      'hadith_books',
      'hadiths',
      'hadiths_fts',
      'prayer_tracker',
      'hadith_translations',
    }));

    // Bootstrapping a second time must not throw or erase Quran rows.
    await DatabaseService.ensureSchemaForTesting(db);
    expect(await db.query('surahs'), hasLength(1));
    expect(await db.query('ayahs'), hasLength(1));
  });
}
