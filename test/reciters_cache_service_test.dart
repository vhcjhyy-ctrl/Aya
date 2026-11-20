import 'package:flutter_test/flutter_test.dart';
import 'package:aya_app/services/reciters_cache_service.dart';

void main() {
  group('RecitersCacheService', () {
    test('parses real MP3Quran moshaf rows and attaches the requested riwayah', () {
      final parsed = RecitersCacheService.parseRecitersForRiwayah(
        {
          'reciters': [
            {
              'id': 7,
              'name': 'قارئ تجريبي',
              'moshaf': [
                {
                  'id': 15,
                  'name': 'رواية حفص عن عاصم - مرتل',
                  'server': 'https://server7.mp3quran.net/example/',
                  'surah_total': 114,
                  'surah_list': '1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112,113,114',
                  'moshaf_type': 116,
                },
                {
                  'id': 16,
                  'name': 'رواية حفص عن عاصم - مجود',
                  'server': 'https://server8.mp3quran.net/example/',
                  'surah_total': 114,
                  'moshaf_type': 117,
                },
                {
                  'id': 17,
                  'name': 'مصدر غير آمن',
                  'server': 'http://example.invalid/',
                  'surah_total': 114,
                },
              ],
            },
          ],
        },
        1,
      );

      expect(parsed, hasLength(1));
      expect(parsed.single['name'], 'قارئ تجريبي');
      final moshaf = parsed.single['moshaf'] as List<Map<String, dynamic>>;
      expect(moshaf, hasLength(2));
      expect(moshaf.every((entry) => entry['rewaya_id'] == 1), isTrue);
      expect(
        moshaf.every(
          (entry) => (entry['server'] as String).startsWith('https://'),
        ),
        isTrue,
      );
    });

    test('detects whether a moshaf has a recording for the selected surah', () {
      final partialMoshaf = {
        'surah_total': 83,
        'surah_list': '1,6,13,14,15,18,19,20,25,29,30,31,32,34,35,36,37',
      };

      expect(
        RecitersCacheService.moshafHasSurah(partialMoshaf, 18),
        isTrue,
      );
      expect(
        RecitersCacheService.moshafHasSurah(partialMoshaf, 2),
        isFalse,
      );
      expect(
        RecitersCacheService.moshafHasSurah(partialMoshaf, 114),
        isFalse,
      );
    });

    test('filters reciters and moshafs to those containing the selected surah', () {
      final filtered = RecitersCacheService.filterRecitersForSurah(
        [
          {
            'id': 1,
            'name': 'قارئ متاح',
            'moshaf': [
              {
                'server': 'https://server1.example/',
                'surah_list': '1,2,3',
              },
              {
                'server': 'https://server2.example/',
                'surah_list': '4,5,6',
              },
            ],
          },
          {
            'id': 2,
            'name': 'قارئ غير متاح',
            'moshaf': [
              {
                'server': 'https://server3.example/',
                'surah_list': '7,8,9',
              },
            ],
          },
        ],
        2,
      );

      expect(filtered, hasLength(1));
      expect(filtered.single['name'], 'قارئ متاح');
      final moshafs = filtered.single['moshaf'] as List<Map<String, dynamic>>;
      expect(moshafs, hasLength(1));
      expect(moshafs.single['server'], 'https://server1.example/');
    });

    test('keeps older moshaf rows when the surah list is unavailable', () {
      expect(
        RecitersCacheService.moshafHasSurah(
          {'surah_total': 114},
          114,
        ),
        isTrue,
      );
      expect(
        RecitersCacheService.moshafHasSurah(
          {'surah_total': 83},
          18,
        ),
        isTrue,
      );
    });

    test('filters by riwayah before deduplicating reciter names', () {
      final all = [
        {
          'id': 1,
          'name': 'قارئ واحد',
          'moshaf': [
            {
              'server': 'https://server1.example/',
              'rewaya_id': 1,
            },
            {
              'server': 'https://server2.example/',
              'rewaya_id': 2,
            },
          ],
        },
        {
          'id': 1,
          'name': 'قارئ واحد',
          'moshaf': [
            {
              'server': 'https://server3.example/',
              'rewaya_id': 1,
            },
          ],
        },
        {
          'id': 2,
          'name': 'قارئ آخر',
          'moshaf': [
            {
              'server': 'https://server4.example/',
              'rewaya_id': 2,
            },
          ],
        },
      ];

      final hafs = RecitersCacheService.filterRecitersForRiwayah(all, 1);
      expect(hafs, hasLength(1));
      expect(hafs.single['name'], 'قارئ واحد');
      final moshaf = hafs.single['moshaf'] as List<Map<String, dynamic>>;
      expect(moshaf.map((entry) => entry['server']).toSet(), {
        'https://server1.example/',
        'https://server3.example/',
      });
    });
  });
}
