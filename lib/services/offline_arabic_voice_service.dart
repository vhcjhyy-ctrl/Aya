import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Offline Arabic speech recognition and speech synthesis for Qalam Muslim.
///
/// ASR uses multilingual Whisper Tiny with Arabic transcription.
/// TTS uses Supertonic 3 in Arabic mode; its OpenRAIL-M use terms are
/// displayed and accepted before model download.
/// Models are downloaded on demand after the user enables the assistant.
class OfflineArabicVoiceService {
  static const int _whisperArchiveBytes = 116204861;
  static const int _supertonicArchiveBytes = 128774318;
  static const String _supertonicArchiveSha256 =
      '82fa96f91c4ef8abaae3a14a3f4153facf88bed821d1f7331cec2700f432c427';

  static const String _whisperArchiveName =
      'sherpa-onnx-whisper-tiny.tar.bz2';
  static const String _supertonicArchiveName =
      'sherpa-onnx-supertonic-3-tts-int8-2026-05-11.tar.bz2';

  static const String _whisperUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'
      'sherpa-onnx-whisper-tiny.tar.bz2';
  static const String _supertonicUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
      'sherpa-onnx-supertonic-3-tts-int8-2026-05-11.tar.bz2';

  static const int _sampleRate = 16000;
  static const double _speechRmsThreshold = 0.012;
  static const Duration _endpointSilence = Duration(milliseconds: 1350);
  static const Duration _defaultMaxListen = Duration(seconds: 24);

  final AudioRecorder _recorder = AudioRecorder();

  sherpa.OfflineRecognizer? _recognizer;
  sherpa.OfflineTts? _tts;
  Directory? _modelDirectory;
  HttpClient? _activeHttpClient;
  Future<void>? _initialization;
  Future<void> Function()? _activeStop;

  bool _ready = false;
  bool _disposed = false;
  bool _isListening = false;
  bool _cancelDownloadRequested = false;

  bool get isReady => _ready;
  bool get isRecognitionReady => !_disposed && _recognizer != null;
  bool get isSynthesisReady => !_disposed && _tts != null;
  bool get isListening => _isListening;

  Future<void> initialize({
    required void Function(double progress, String status) onProgress,
  }) {
    if (_disposed) {
      return Future<void>.error(
        StateError('محرك الصوت المحلي مغلق. أعد فتح شاشة التسميع.'),
      );
    }
    if (_ready) return Future<void>.value();
    return _initialization ??= _initialize(onProgress).whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _initialize(
    void Function(double progress, String status) onProgress,
  ) async {
    _cancelDownloadRequested = false;
    final support = await getApplicationSupportDirectory();
    final models = Directory(p.join(support.path, 'qalam-offline-voice'));
    await models.create(recursive: true);
    _modelDirectory = models;

    final whisperRoot = Directory(
      p.join(models.path, 'sherpa-onnx-whisper-tiny'),
    );
    final whisperFiles = [
      File(p.join(whisperRoot.path, 'tiny-encoder.int8.onnx')),
      File(p.join(whisperRoot.path, 'tiny-decoder.int8.onnx')),
      File(p.join(whisperRoot.path, 'tiny-tokens.txt')),
    ];

    if (!await _allFilesExist(whisperFiles)) {
      onProgress(0, 'تنزيل محرك التعرف العربي المحلي — Whisper Tiny');
      await _downloadAndExtract(
        url: _whisperUrl,
        archiveName: _whisperArchiveName,
        expectedBytes: _whisperArchiveBytes,
        outputDirectory: models,
        requiredFiles: whisperFiles,
        onProgress: (value) => onProgress(
          value * 0.62,
          'تنزيل محرك التعرف العربي المحلي — Whisper Tiny',
        ),
      );
    } else {
      onProgress(0.62, 'محرك التعرف العربي موجود على الجهاز');
    }

    final supertonicRoot = Directory(
      p.join(models.path, 'sherpa-onnx-supertonic-3-tts-int8-2026-05-11'),
    );
    final supertonicFiles = [
      File(p.join(supertonicRoot.path, 'duration_predictor.int8.onnx')),
      File(p.join(supertonicRoot.path, 'text_encoder.int8.onnx')),
      File(p.join(supertonicRoot.path, 'vector_estimator.int8.onnx')),
      File(p.join(supertonicRoot.path, 'vocoder.int8.onnx')),
      File(p.join(supertonicRoot.path, 'tts.json')),
      File(p.join(supertonicRoot.path, 'unicode_indexer.bin')),
      File(p.join(supertonicRoot.path, 'voice.bin')),
    ];

    if (!await _allFilesExist(supertonicFiles)) {
      onProgress(0.48, 'تنزيل الصوت العربي المحلي — Supertonic 3');
      await _downloadAndExtract(
        url: _supertonicUrl,
        archiveName: _supertonicArchiveName,
        expectedBytes: _supertonicArchiveBytes,
        expectedSha256: _supertonicArchiveSha256,
        outputDirectory: models,
        requiredFiles: supertonicFiles,
        onProgress: (value) => onProgress(
          0.48 + value * 0.52,
          'تنزيل الصوت العربي المحلي — Supertonic 3',
        ),
      );
    }

    if (_cancelDownloadRequested) {
      throw StateError('أُلغي تنزيل محرك الصوت المحلي.');
    }

    onProgress(1, 'جارٍ تحميل محركي التعرف والنطق في ذاكرة الهاتف...');
    sherpa.initBindings();

    final whisperConfig = sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: whisperFiles[0].path,
          decoder: whisperFiles[1].path,
          language: 'ar',
          task: 'transcribe',
        ),
        tokens: whisperFiles[2].path,
        modelType: 'whisper',
        numThreads: 2,
        provider: 'cpu',
        debug: false,
      ),
    );

    _recognizer = await sherpa.OfflineRecognizer.createAsync(whisperConfig);

    try {
      final ttsConfig = sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          supertonic: sherpa.OfflineTtsSupertonicModelConfig(
            durationPredictor: supertonicFiles[0].path,
            textEncoder: supertonicFiles[1].path,
            vectorEstimator: supertonicFiles[2].path,
            vocoder: supertonicFiles[3].path,
            ttsJson: supertonicFiles[4].path,
            unicodeIndexer: supertonicFiles[5].path,
            voiceStyle: supertonicFiles[6].path,
          ),
          numThreads: 2,
          provider: 'cpu',
          debug: false,
        ),
        maxNumSentences: 1,
      );
      _tts = sherpa.OfflineTts(ttsConfig);
    } catch (_) {
      _recognizer?.free();
      _recognizer = null;
      rethrow;
    }

    _ready = true;
    onProgress(1, 'محرك الصوت العربي المحلي جاهز');
  }

  Future<void> cancelDownload() async {
    _cancelDownloadRequested = true;
    _activeHttpClient?.close(force: true);
    await stopListening();
  }

  Future<bool> _allFilesExist(List<File> files) async {
    for (final file in files) {
      if (!await file.exists() || await file.length() == 0) return false;
    }
    return true;
  }

  Future<void> _downloadAndExtract({
    required String url,
    required String archiveName,
    required int expectedBytes,
    required Directory outputDirectory,
    required List<File> requiredFiles,
    required void Function(double progress) onProgress,
    String? expectedSha256,
  }) async {
    // Keep .tar.bz2 as the final extension so archive_io detects the format.
    final archiveFile = File(
      p.join(outputDirectory.path, '.part-$archiveName'),
    );
    if (await archiveFile.exists()) await archiveFile.delete();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    _activeHttpClient = client;
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'QalamMuslim/1.6.0 (Android; sherpa-onnx)',
      );
      final response = await request.close().timeout(
        const Duration(minutes: 2),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'تعذّر تنزيل محرك الصوت (HTTP ${response.statusCode}).',
          uri: Uri.parse(url),
        );
      }
      if (response.contentLength > 0 &&
          response.contentLength != expectedBytes) {
        throw const FileSystemException(
          'حجم أرشيف محرك الصوت لا يطابق الحجم المتوقع.',
        );
      }

      final sink = archiveFile.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.timeout(
          const Duration(minutes: 2),
        )) {
          if (_cancelDownloadRequested) {
            throw StateError('أُلغي تنزيل محرك الصوت المحلي.');
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress((received / expectedBytes).clamp(0.0, 1.0));
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (received != expectedBytes ||
          await archiveFile.length() != expectedBytes) {
        throw const FileSystemException(
          'اكتمل اتصال التنزيل بملف غير مكتمل. أعد المحاولة.',
        );
      }

      if (expectedSha256 != null) {
        final digest = await sha256.bind(archiveFile.openRead()).first;
        if (digest.toString() != expectedSha256) {
          throw const FileSystemException(
            'فشل التحقق من سلامة نموذج النطق العربي.',
          );
        }
      }

      await extractFileToDisk(
        archiveFile.path,
        outputDirectory.path,
        verify: false,
        throwOnError: true,
        maxSize: 768 * 1024 * 1024,
      );

      if (!await _allFilesExist(requiredFiles)) {
        throw const FileSystemException(
          'لم تكتمل ملفات محرك الصوت بعد فك الضغط.',
        );
      }
    } finally {
      _activeHttpClient = null;
      client.close(force: true);
      if (await archiveFile.exists()) await archiveFile.delete();
    }
  }

  Future<String> listen({
    required void Function(bool listening) onListeningChanged,
    Duration maxDuration = _defaultMaxListen,
  }) async {
    if (!_ready || _recognizer == null) {
      throw StateError('محرك التعرف الصوتي المحلي غير جاهز.');
    }
    if (_isListening) {
      throw StateError('التعرف الصوتي يعمل بالفعل.');
    }
    if (!await _recorder.hasPermission()) {
      throw StateError('إذن الميكروفون غير ممنوح للتطبيق.');
    }

    final captured = <Float32List>[];
    final completer = Completer<String>();
    StreamSubscription<Uint8List>? subscription;
    Timer? timeout;
    var heardSpeech = false;
    var silentSeconds = 0.0;
    var finishing = false;

    Future<void> finish([Object? error]) async {
      if (finishing) return;
      finishing = true;
      timeout?.cancel();
      _isListening = false;
      onListeningChanged(false);
      try {
        await _recorder.stop();
      } catch (_) {}
      try {
        await subscription?.cancel();
        if (error != null) {
          if (!completer.isCompleted) completer.completeError(error);
          return;
        }
        if (!heardSpeech || captured.isEmpty) {
          if (!completer.isCompleted) completer.complete('');
          return;
        }
        final samples = _mergeSamples(captured);
        final text = _transcribe(samples);
        if (!completer.isCompleted) completer.complete(text);
      } catch (exception, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(exception, stackTrace);
        }
      }
    }

    try {
      final audioStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );

      _isListening = true;
      _activeStop = () => finish();
      onListeningChanged(true);

      subscription = audioStream.listen(
        (bytes) {
          final samples = _pcm16ToFloat32(bytes);
          if (samples.isEmpty) return;
          captured.add(samples);

          final rms = _calculateRms(samples);
          final chunkDuration = samples.length / _sampleRate;
          if (rms >= _speechRmsThreshold) {
            heardSpeech = true;
            silentSeconds = 0;
          } else if (heardSpeech) {
            silentSeconds += chunkDuration;
          }

          if (heardSpeech &&
              silentSeconds >= _endpointSilence.inMilliseconds / 1000) {
            unawaited(finish());
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          unawaited(finish(error));
        },
      );

      timeout = Timer(maxDuration, () => unawaited(finish()));
      return await completer.future;
    } finally {
      timeout?.cancel();
      _activeStop = null;
      _isListening = false;
      await subscription?.cancel();
    }
  }

  Future<void> stopListening() async {
    final stop = _activeStop;
    if (stop != null) await stop();
  }

  String _transcribe(Float32List samples) {
    final recognizer = _recognizer;
    if (recognizer == null || samples.isEmpty) return '';
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
      recognizer.decode(stream);
      return recognizer.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }

  Future<String> synthesizeToFile(String text) async {
    final tts = _tts;
    final directory = _modelDirectory;
    if (!_ready || tts == null || directory == null) {
      throw StateError('محرك النطق العربي المحلي غير جاهز.');
    }

    final audio = tts.generateWithConfig(
      text: text,
      config: sherpa.OfflineTtsGenerationConfig(
        sid: 0,
        speed: 0.95,
        numSteps: 8,
        extra: const {'lang': 'ar'},
      ),
    );
    if (audio.samples.isEmpty || audio.sampleRate <= 0) {
      throw StateError('لم يتمكن محرك النطق العربي من إنتاج صوت.');
    }

    final file = File(
      p.join(
        directory.path,
        'reply-${DateTime.now().microsecondsSinceEpoch}.wav',
      ),
    );
    await file.writeAsBytes(
      encodePcm16Wav(audio.samples, audio.sampleRate),
      flush: true,
    );
    return file.path;
  }

  Future<void> deleteGeneratedFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static Uint8List encodePcm16Wav(Float32List samples, int sampleRate) {
    final dataLength = samples.length * 2;
    final bytes = Uint8List(44 + dataLength);
    final data = ByteData.sublistView(bytes);

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes[offset + i] = value.codeUnitAt(i);
      }
    }

    writeAscii(0, 'RIFF');
    data.setUint32(4, 36 + dataLength, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    data.setUint32(40, dataLength, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      final normalized = samples[i].clamp(-1.0, 1.0);
      data.setInt16(44 + i * 2, (normalized * 32767).round(), Endian.little);
    }
    return bytes;
  }

  static Float32List _pcm16ToFloat32(Uint8List bytes) {
    final sampleCount = bytes.length ~/ 2;
    final samples = Float32List(sampleCount);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < sampleCount; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }

  static Float32List _mergeSamples(List<Float32List> chunks) {
    var total = 0;
    for (final chunk in chunks) {
      total += chunk.length;
    }
    final merged = Float32List(total);
    var offset = 0;
    for (final chunk in chunks) {
      merged.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return merged;
  }

  static double _calculateRms(Float32List samples) {
    if (samples.isEmpty) return 0;
    var sum = 0.0;
    for (final sample in samples) {
      sum += sample * sample;
    }
    return math.sqrt(sum / samples.length);
  }

  Future<void> dispose() async {
    _disposed = true;
    await stopListening();
    await _recorder.dispose();
    _recognizer?.free();
    _recognizer = null;
    _tts?.free();
    _tts = null;
    _activeHttpClient?.close(force: true);
    _ready = false;
  }
}
