import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Nawawi Arabic bundle contains 42 sourced hadith entries', () async {
    final raw = await rootBundle.loadString(
      'assets/data/nawawi_40_hadith_ar.json',
    );
    final decoded = jsonDecode(raw);

    expect(decoded, isA<List>());
    final items = decoded as List<dynamic>;
    expect(items, hasLength(42));

    final numbers = <int>[];
    for (final rawItem in items) {
      expect(rawItem, isA<Map>());
      final item = Map<String, dynamic>.from(rawItem as Map);
      final citation = Map<String, dynamic>.from(item['citation'] as Map);

      expect((item['title'] ?? '').toString().trim(), isNotEmpty);
      expect((item['hadith'] ?? '').toString().trim(), isNotEmpty);
      expect((citation['narrator'] ?? '').toString().trim(), isNotEmpty);
      expect((citation['collection'] ?? '').toString().trim(), isNotEmpty);

      final source = Uri.tryParse(
        (citation['sunnah_url'] ?? '').toString(),
      );
      expect(source, isNotNull);
      expect(source!.scheme, 'https');
      expect(source.host, 'sunnah.com');

      numbers.add((citation['number'] as num).toInt());
    }

    expect(numbers, List<int>.generate(42, (index) => index + 1));
  });
}
