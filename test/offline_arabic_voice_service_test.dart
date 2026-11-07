import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:aya_app/services/offline_arabic_voice_service.dart';

void main() {
  group('OfflineArabicVoiceService', () {
    test('encodes mono PCM16 WAV with a valid RIFF header', () {
      final wav = OfflineArabicVoiceService.encodePcm16Wav(
        Float32List.fromList([0.0, 0.5, -0.5, 1.0]),
        22050,
      );
      final data = ByteData.sublistView(wav);

      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(data.getUint32(24, Endian.little), 22050);
      expect(data.getUint32(28, Endian.little), 44100);
      expect(data.getUint16(22, Endian.little), 1);
      expect(data.getUint16(34, Endian.little), 16);
      expect(data.getUint32(40, Endian.little), 8);
      expect(wav.length, 52);
    });

    test('clamps generated audio samples to the PCM16 range', () {
      final wav = OfflineArabicVoiceService.encodePcm16Wav(
        Float32List.fromList([-1.5, 1.5]),
        16000,
      );
      final data = ByteData.sublistView(wav);

      expect(data.getInt16(44, Endian.little), -32767);
      expect(data.getInt16(46, Endian.little), 32767);
    });
  });
}
