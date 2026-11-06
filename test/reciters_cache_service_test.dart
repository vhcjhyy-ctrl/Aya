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
