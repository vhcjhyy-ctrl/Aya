import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:path_provider/path_provider.dart';

/// Optional on-device conversational model for Qalam Muslim.
/// The GGUF file is downloaded once; no API key or hosted inference is used.
class LocalAiAssistantService {
  static const String modelFileName = 'Qwen3.5-0.8B-Q4_K_M.gguf';
  static const int expectedModelBytes = 527502816;
  static const String expectedModelSha256 =
      'f5b14da98939b60bbe1019a964eba656407e1e0b64f1fe3003ff6d650e93bfec';
  static const String modelUrl =
      'https://huggingface.co/lmstudio-community/Qwen3.5-0.8B-GGUF/resolve/7925ccdc665d4efdb1034791e6b553e11128e6f8/$modelFileName';

  final LlamaController _controller = LlamaController();
  bool _loaded = false;
  bool _disposed = false;
  bool _gpuAccelerationEnabled = false;
  String? _loadedPath;
  bool _cancelDownloadRequested = false;
  HttpClient? _downloadClient;
  HttpClientRequest? _activeRequest;

  bool get isLoaded => _loaded;
  bool get gpuAccelerationEnabled => _gpuAccelerationEnabled;

  Future<String> _modelPath() async {
    final directory = await getApplicationSupportDirectory();
    final modelsDirectory = Directory('${directory.path}/qalam-muslim-models');
    if (!await modelsDirectory.exists()) {
      await modelsDirectory.create(recursive: true);
    }
    return '${modelsDirectory.path}/$modelFileName';
  }

  Future<bool> isModelDownloaded() async {
    final path = await _modelPath();
    final file = File(path);
    if (!await file.exists() || await file.length() != expectedModelBytes) {
      return false;
    }

    // Cache successful verification to avoid hashing 528 MB on every app open.
    final marker = File('$path.sha256');
    if (await marker.exists() &&
        (await marker.readAsString()).trim() == expectedModelSha256) {
      return true;
    }

    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() != expectedModelSha256) return false;
    await marker.writeAsString(expectedModelSha256, flush: true);
    return true;
  }

  Future<void> cancelDownload() async {
    _cancelDownloadRequested = true;
    _activeRequest?.abort(
      const HttpException('أُلغي تنزيل نموذج المساعد بناءً على طلب المستخدم.'),
    );
    _downloadClient?.close(force: true);
  }

  Future<String> downloadModel({
    required void Function(double progress) onProgress,
  }) async {
    final path = await _modelPath();
    final target = File(path);
    if (await isModelDownloaded()) {
      onProgress(1);
      return path;
    }

    final partial = File('$path.part');
    if (await partial.exists()) await partial.delete();

    _cancelDownloadRequested = false;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    _downloadClient = client;
    try {
      final request = await client.getUrl(Uri.parse(modelUrl));
      _activeRequest = request;
      if (_cancelDownloadRequested) {
        throw StateError('أُلغي تنزيل نموذج المساعد.');
      }
      request.followRedirects = true;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'QalamMuslim/1.6.0 (Android)',
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'تعذّر تنزيل نموذج المساعد (HTTP ${response.statusCode}).',
          uri: Uri.parse(modelUrl),
        );
      }

      final total = response.contentLength;
      var received = 0;
      final sink = partial.openWrite();
      try {
        await for (final chunk in response.timeout(const Duration(minutes: 2))) {
          if (_cancelDownloadRequested) {
            throw StateError('أُلغي تنزيل نموذج المساعد.');
          }
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            onProgress((received / total).clamp(0.0, 1.0));
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (_cancelDownloadRequested) {
        throw StateError('أُلغي تنزيل نموذج المساعد.');
      }
      final actualLength = await partial.length();
      if (actualLength != expectedModelBytes ||
          (total > 0 && actualLength != total)) {
        throw const FileSystemException(
          'ملف النموذج غير مكتمل. أعد تنزيله مع اتصال مستقر.',
        );
      }

      final digest = await sha256.bind(partial.openRead()).first;
      if (digest.toString() != expectedModelSha256) {
        throw const FileSystemException(
          'فشل التحقق من سلامة نموذج المساعد (SHA-256). أعد التنزيل من المصدر الرسمي.',
        );
      }

      if (await target.exists()) await target.delete();
      await partial.rename(path);
      await File('$path.sha256').writeAsString(expectedModelSha256, flush: true);
      onProgress(1);
      return path;
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    } finally {
      _activeRequest = null;
      _downloadClient = null;
      client.close(force: true);
    }
  }

  Future<void> loadModel() async {
    if (_disposed) throw StateError('تم إغلاق محرك المساعد. أعد فتح شاشة التسميع.');
    final path = await _modelPath();
    if (_loaded && _loadedPath == path) return;
    if (_loaded) await unload();

    if (!await isModelDownloaded()) {
      throw StateError('نموذج المساعد غير موجود على الجهاز.');
    }

    // A short context is intentional to reduce RAM pressure on older phones.
    // Use Vulkan only when the device reports a supported configuration;
    // if native GPU initialization fails, retry once on CPU.
    var recommendedGpuLayers = 0;
    try {
      final gpuInfo = await _controller.detectGpu();
      recommendedGpuLayers = gpuInfo.recommendedGpuLayers;
    } catch (_) {
      recommendedGpuLayers = 0;
    }

    try {
      await _controller.loadModel(
        modelPath: path,
        threads: 4,
        contextSize: 1024,
        gpuLayers: recommendedGpuLayers,
      );
      _gpuAccelerationEnabled = recommendedGpuLayers > 0;
    } catch (_) {
      if (recommendedGpuLayers <= 0) rethrow;
      await _controller.loadModel(
        modelPath: path,
        threads: 4,
        contextSize: 1024,
        gpuLayers: 0,
      );
      _gpuAccelerationEnabled = false;
    }

    _loaded = true;
    _loadedPath = path;
  }

  Stream<String> generateReply(List<Map<String, String>> messages) {
    if (!_loaded) {
      return Stream.error(StateError('لم يتم تحميل نموذج المساعد بعد.'));
    }
    return _controller.generateChat(
      messages: messages
          .map(
            (message) => ChatMessage(
              role: message['role']!,
              content: message['content']!,
            ),
          )
          .toList(),
      template: 'chatml',
      temperature: 0.45,
      maxTokens: 220,
    );
  }

  Future<void> stop() => _controller.stop();

  Future<void> unload() async {
    if (_disposed) return;
    _disposed = true;
    await _controller.dispose();
    _loaded = false;
    _gpuAccelerationEnabled = false;
    _loadedPath = null;
  }

  Future<void> dispose() async {
    await unload();
  }
}
