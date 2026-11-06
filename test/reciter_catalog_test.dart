import 'package:flutter_test/flutter_test.dart';
import 'package:aya_app/models/quran_models.dart';
import 'package:aya_app/services/api_service.dart';

void main() {
  test('Qalam exposes at least fifteen selectable Quran reciters', () {
    expect(availableReciters.length, greaterThanOrEqualTo(19));
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

  test('legacy reciter preferences resolve to supported audio edition IDs', () {
    final sudais = ApiService.buildAyahAudioUrl(
      262,
      2,
      255,
      reciter: 'ar.abdurrahmaansudais',
    );
    final abdulbasit = ApiService.buildAyahAudioUrl(
      262,
      2,
      255,
      reciter: 'ar.abdulsamad',
    );
    final shuraim = ApiService.buildSurahAudioUrl(
      2,
      reciter: 'ar.saoodshuraym',
    );

    expect(sudais, contains('/ar.sudais/262.mp3'));
    expect(abdulbasit, contains('/ar.abdulbasit/262.mp3'));
    expect(shuraim, contains('/ar.shuraim/2.mp3'));
  });
}
