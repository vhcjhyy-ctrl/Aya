import 'package:flutter_test/flutter_test.dart';
import 'package:aya_app/models/quran_models.dart';

void main() {
  test('Qalam exposes at least fifteen selectable Quran reciters', () {
    expect(availableReciters.length, greaterThanOrEqualTo(15));
  });

  test('reciter identifiers are unique and usable for audio selection', () {
    final ids = availableReciters.map((reciter) => reciter.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.every((id) => id.trim().isNotEmpty), isTrue);
    expect(
      availableReciters.every(
        (reciter) =>
            reciter.nameAr.trim().isNotEmpty &&
            reciter.nameEn.trim().isNotEmpty,
      ),
      isTrue,
    );
  });
}
