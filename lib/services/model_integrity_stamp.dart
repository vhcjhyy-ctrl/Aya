/// Versioned metadata for a model file whose SHA-256 was already verified.
/// The stamp lets later launches skip hashing the 528 MB model while
/// invalidating the cached result when its size or modification time changes.
class ModelIntegrityStamp {
  static const String _version = 'qalam-model-integrity-v2';

  static String encode({
    required String sha256,
    required int byteLength,
    required int modifiedAtMicros,
  }) {
    return [
      _version,
      sha256,
      byteLength.toString(),
      modifiedAtMicros.toString(),
    ].join('\n');
  }

  static bool matches(
    String content, {
    required String sha256,
    required int byteLength,
    required int modifiedAtMicros,
  }) {
    final fields = content.split('\n');
    if (fields.length != 4 || fields[0] != _version) return false;
    if (fields[1] != sha256) return false;
    if (int.tryParse(fields[2]) != byteLength) return false;
    if (int.tryParse(fields[3]) != modifiedAtMicros) return false;
    return true;
  }
}
