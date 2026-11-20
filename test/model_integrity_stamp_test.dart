import 'package:flutter_test/flutter_test.dart';
import 'package:aya_app/services/model_integrity_stamp.dart';

void main() {
  group('ModelIntegrityStamp', () {
    const hash = 'f5b14da98939b60bbe1019a964eba656407e1e0b64f1fe3003ff6d650e93bfec';
    const bytes = 527502816;
    const modifiedAtMicros = 1794000000123456;

    test('accepts a stamp matching the verified model metadata', () {
      final stamp = ModelIntegrityStamp.encode(
        sha256: hash,
        byteLength: bytes,
        modifiedAtMicros: modifiedAtMicros,
      );

      expect(
        ModelIntegrityStamp.matches(
          stamp,
          sha256: hash,
          byteLength: bytes,
          modifiedAtMicros: modifiedAtMicros,
        ),
        isTrue,
      );
    });

    test('invalidates the stamp when the model size changes', () {
      final stamp = ModelIntegrityStamp.encode(
        sha256: hash,
        byteLength: bytes,
        modifiedAtMicros: modifiedAtMicros,
      );

      expect(
        ModelIntegrityStamp.matches(
          stamp,
          sha256: hash,
          byteLength: bytes + 1,
          modifiedAtMicros: modifiedAtMicros,
        ),
        isFalse,
      );
    });

    test('invalidates the stamp when the modification time changes', () {
      final stamp = ModelIntegrityStamp.encode(
        sha256: hash,
        byteLength: bytes,
        modifiedAtMicros: modifiedAtMicros,
      );

      expect(
        ModelIntegrityStamp.matches(
          stamp,
          sha256: hash,
          byteLength: bytes,
          modifiedAtMicros: modifiedAtMicros + 1,
        ),
        isFalse,
      );
    });

    test('rejects a different digest', () {
      final stamp = ModelIntegrityStamp.encode(
        sha256: hash,
        byteLength: bytes,
        modifiedAtMicros: modifiedAtMicros,
      );

      expect(
        ModelIntegrityStamp.matches(
          stamp,
          sha256: List<String>.filled(64, '0').join(),
          byteLength: bytes,
          modifiedAtMicros: modifiedAtMicros,
        ),
        isFalse,
      );
    });

    test('rejects legacy and malformed marker contents', () {
      expect(
        ModelIntegrityStamp.matches(
          hash,
          sha256: hash,
          byteLength: bytes,
          modifiedAtMicros: modifiedAtMicros,
        ),
        isFalse,
      );
      expect(
        ModelIntegrityStamp.matches(
          'qalam-model-integrity-v2\n$hash\nnot-a-size\n$modifiedAtMicros',
          sha256: hash,
          byteLength: bytes,
          modifiedAtMicros: modifiedAtMicros,
        ),
        isFalse,
      );
    });
  });
}
