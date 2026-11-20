import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bundled Asma ul Husna data', () {
    late List<dynamic> names;

    setUpAll(() async {
      final source = await File('assets/data/names99.json').readAsString();
      names = jsonDecode(source) as List<dynamic>;
    });

    test('contains 99 names with the fields required by the screen', () {
      expect(names, hasLength(99));
      for (final raw in names) {
        expect(raw, isA<Map<String, dynamic>>());
        final item = raw as Map<String, dynamic>;
        expect((item['arabic'] ?? '').toString(), isNotEmpty);
        expect((item['slug'] ?? '').toString(), isNotEmpty);
        expect((item['meaningAr'] ?? '').toString(), isNotEmpty);
      }
    });

    test('uses unique slugs for local favourites', () {
      final slugs = names
          .map((row) => (row as Map<String, dynamic>)['slug'].toString())
          .toList();
      expect(slugs.toSet(), hasLength(99));
    });
  });
}
