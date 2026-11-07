import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../services/translation_service.dart';

/// Fetches the full reciter list from mp3quran.net API v3 once,
/// caches it to disk, and serves filtered results by riwayah.
///
/// On first access the service fetches all riwayat then all reciters
/// for each riwayah with controlled concurrency.  Results are written
/// to `reciters_cache.json` in the app documents directory.
///
/// Callers that currently import the 405 KB `reciters_data.dart` bundle
/// should route through this service instead so the list stays up to date.
class RecitersCacheService {
  RecitersCacheService._();

  static final ValueNotifier<bool> loadingNotifier = ValueNotifier(false);

  static List<Map<String, dynamic>>? _allReciters;

  /// True once the cache has been loaded (from disk or network).
  static bool get isLoaded => _allReciters != null;

  // ── Public API ──────────────────────────────────────────────────────────

  /// Return reciters whose moshaf list includes entries matching [riwayahId],
  /// loading from disk cache or network on first call.
  /// Results are deduplicated by reciter name.
  static final Map<String, List<Map<String, dynamic>>> _riwayahCache = {};

  static Future<List<Map<String, dynamic>>> getRecitersForRiwayah(
    int riwayahId, {
    int? surahNumber,
  }) async {
    if (surahNumber != null && (surahNumber < 1 || surahNumber > 114)) {
      throw RangeError.range(surahNumber, 1, 114, 'surahNumber');
    }
    final cacheKey = '${riwayahId}:${surahNumber ?? 0}';
    final cached = _riwayahCache[cacheKey];
    if (cached != null) {
      return List<Map<String, dynamic>>.from(cached);
    }

    loadingNotifier.value = true;
    final client = http.Client();
    try {
      final lang = TranslationService.isArabic ? 'ar' : 'eng';
      final query = <String, String>{
        'language': lang,
        'rewaya': riwayahId.toString(),
        if (surahNumber != null) 'sura': surahNumber.toString(),
      };
      final uri = Uri.https('mp3quran.net', '/api/v3/reciters', query);
      final response = await client.get(uri).timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        throw http.ClientException(
          'MP3Quran returned HTTP ${response.statusCode}',
          uri,
        );
      }

      final payload = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
      final parsed = parseRecitersForRiwayah(payload, riwayahId);
      final result = surahNumber == null
          ? parsed
          : filterRecitersForSurah(parsed, surahNumber);
      _riwayahCache[cacheKey] = result;
      return List<Map<String, dynamic>>.from(result);
    } catch (error) {
      if (surahNumber == null) rethrow;

      // If the catalogue endpoint cannot apply its sura filter, fall back
      // to the full riwayah list and use each moshaf's surah_list locally.
      debugPrint('MP3Quran sura-filter request failed; using local filtering: $error');
      final unfiltered = await getRecitersForRiwayah(riwayahId);
      final fallback = filterRecitersForSurah(unfiltered, surahNumber);
      _riwayahCache[cacheKey] = fallback;
      return List<Map<String, dynamic>>.from(fallback);
    } finally {
      client.close();
      loadingNotifier.value = false;
    }
  }

  /// Keep only reciters with a catalogued recording for [surahNumber].
  /// The API's `sura` parameter reduces the response; this local filter
  /// protects the picker if a server returns a wider catalogue.
  @visibleForTesting
  static List<Map<String, dynamic>> filterRecitersForSurah(
    Iterable<Map<String, dynamic>> reciters,
    int surahNumber,
  ) {
    final result = <Map<String, dynamic>>[];
    for (final reciter in reciters) {
      final rawMoshafs = reciter['moshaf'] as List? ?? const [];
      final matchingMoshafs = rawMoshafs
          .where((raw) => raw is Map &&
              moshafHasSurah(Map<String, dynamic>.from(raw), surahNumber))
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      if (matchingMoshafs.isEmpty) continue;
      result.add({
        ...reciter,
        'moshaf': matchingMoshafs,
      });
    }
    return result;
  }

  /// Parse the response from the MP3Quran endpoint already filtered by
  /// `rewaya`. Its documented moshaf objects carry server and moshaf_type,
  /// but do not consistently include rewaya_id, so attach the requested ID.
  @visibleForTesting
  static List<Map<String, dynamic>> parseRecitersForRiwayah(
    Map<String, dynamic> payload,
    int riwayahId,
  ) {
    final source = (payload['reciters'] as List?) ?? const [];
    final grouped = <String, Map<String, dynamic>>{};

    for (final rawReciter in source) {
      if (rawReciter is! Map) continue;
      final reciter = Map<String, dynamic>.from(rawReciter);
      final name = (reciter['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      final rawMoshaf = reciter['moshaf'] as List? ?? const [];
      final matchingMoshaf = <Map<String, dynamic>>[];
      for (final rawEntry in rawMoshaf) {
        if (rawEntry is! Map) continue;
        final entry = Map<String, dynamic>.from(rawEntry);
        final server = (entry['server'] ?? '').toString().trim();
        if (!server.startsWith('https://')) continue;
        entry['rewaya_id'] = riwayahId;
        matchingMoshaf.add(entry);
      }
      if (matchingMoshaf.isEmpty) continue;

      final key = (reciter['id'] ?? name).toString();
      final target = grouped.putIfAbsent(
        key,
        () => {
          'id': reciter['id'],
          'name': name,
          'moshaf': <Map<String, dynamic>>[],
        },
      );
      final existing = target['moshaf'] as List<Map<String, dynamic>>;
      final knownServers = existing
          .map((entry) => entry['server']?.toString() ?? '')
          .toSet();
      for (final entry in matchingMoshaf) {
        final server = entry['server']?.toString() ?? '';
        if (knownServers.add(server)) existing.add(entry);
      }
    }

    final result = grouped.values.toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return result;
  }

  /// Whether a moshaf publishes the requested surah.
  ///
  /// MP3Quran includes [surah_list] as a comma-separated list. This matters
  /// because some reciters have recordings for only a subset of the Quran.
  @visibleForTesting
  static bool moshafHasSurah(
    Map<String, dynamic> moshaf,
    int surahNumber,
  ) {
    if (surahNumber < 1 || surahNumber > 114) return false;

    final rawList = moshaf['surah_list'];
    if (rawList is String && rawList.trim().isNotEmpty) {
      return rawList
          .split(',')
          .any((value) => int.tryParse(value.trim()) == surahNumber);
    }

    if (rawList is List && rawList.isNotEmpty) {
      return rawList.any(
        (value) => int.tryParse(value.toString().trim()) == surahNumber,
      );
    }

    // Older API/cache rows may omit surah_list. Keep unknown rows available
    // rather than hiding a reciter whose catalogue metadata is incomplete.
    return true;
  }

  /// Filter a riwayah before deduplicating names so another API row
  /// for the same reciter cannot hide a matching recording.
  @visibleForTesting
  static List<Map<String, dynamic>> filterRecitersForRiwayah(
    Iterable<Map<String, dynamic>> all,
    int riwayahId,
  ) {
    final grouped = <String, Map<String, dynamic>>{};
    for (final reciter in all) {
      final name = (reciter['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final raw = reciter['moshaf'] as List? ?? const [];
      final matching = raw.where((entry) {
        final m = entry as Map;
        return int.tryParse(m['rewaya_id']?.toString() ?? '') == riwayahId;
      }).map((entry) => Map<String, dynamic>.from(entry as Map)).toList();
      if (matching.isEmpty) continue;
      final target = grouped.putIfAbsent(
        name,
        () => {'name': name, 'moshaf': <Map<String, dynamic>>[]},
      );
      final current = target['moshaf'] as List<Map<String, dynamic>>;
      final servers = current.map((m) => m['server']?.toString() ?? '').toSet();
      for (final m in matching) {
        final server = m['server']?.toString() ?? '';
        if (server.isNotEmpty && servers.add(server)) current.add(m);
      }
    }
    final result = grouped.values.toList()
      ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return result;
  }

  /// Return all reciters across all riwayat (for the download picker).
  static Future<List<Map<String, dynamic>>> getAllReciters() async {
    return List<Map<String, dynamic>>.from(await _ensureLoaded());
  }

  /// Re-fetch everything from the API and overwrite the disk cache.
  static Future<void> refresh() async {
    loadingNotifier.value = true;
    _allReciters = null;
    _riwayahCache.clear();
    try {
      _allReciters = await _fetchAll();
      await _writeCache(_allReciters!);
    } finally {
      loadingNotifier.value = false;
    }
  }

  // ── Internals ───────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> _ensureLoaded() async {
    if (_allReciters != null) return _allReciters!;

    // 1. Try disk cache
    final cached = await _readCache();
    if (cached != null) {
      _allReciters = List<Map<String, dynamic>>.from(cached);
      return _allReciters!;
    }

    // 2. Fetch from API
    loadingNotifier.value = true;
    try {
      _allReciters = await _fetchAll();
      await _writeCache(_allReciters!);
      return _allReciters!;
    } finally {
      loadingNotifier.value = false;
    }
  }

  static Future<List<Map<String, dynamic>>> _fetchAll() async {
    final lang = TranslationService.isArabic ? 'ar' : 'eng';
    final client = http.Client();
    final all = <Map<String, dynamic>>[];

    try {
      // 1. Try single comprehensive endpoint (fetches all reciters and all moshafs instantly)
      final uri = Uri.parse('https://mp3quran.net/api/v3/reciters?language=$lang');
      final res = await client.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final list = (data['reciters'] as List?) ?? [];
        for (final r in list) {
          all.add(Map<String, dynamic>.from(r as Map));
        }
        if (all.isNotEmpty) return all;
      }

      // 2. Fallback to per-riwayah endpoints if needed
      final riwayatUri = Uri.parse(
        'https://mp3quran.net/api/v3/riwayat?language=$lang',
      );
      final riwayatRes = await client.get(riwayatUri).timeout(const Duration(seconds: 10));
      if (riwayatRes.statusCode == 200) {
        final riwayatData = jsonDecode(utf8.decode(riwayatRes.bodyBytes))
            as Map<String, dynamic>;
        final riwayatList = (riwayatData['riwayat'] as List?) ?? [];
        final seen = <String>{};

        for (int i = 0; i < riwayatList.length; i += 2) {
          final batch = <Future<void>>[];
          for (int j = i; j < i + 2 && j < riwayatList.length; j++) {
            final rw = riwayatList[j] as Map<String, dynamic>;
            final riwayahId = rw['id'] as int;
            batch.add(_fetchRecitersForRiwayah(client, riwayahId, lang, all, seen));
          }
          await Future.wait(batch);
          if (i + 2 < riwayatList.length) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
          }
        }
      }
    } finally {
      client.close();
    }

    return all;
  }

  static Future<void> _fetchRecitersForRiwayah(
    http.Client client,
    int riwayahId,
    String lang,
    List<Map<String, dynamic>> sink,
    Set<String> seen,
  ) async {
    try {
      final uri = Uri.parse(
        'https://mp3quran.net/api/v3/reciters?language=$lang&rewaya=$riwayahId',
      );
      final res = await client.get(uri);
      if (res.statusCode != 200) return;

      final data = jsonDecode(utf8.decode(res.bodyBytes))
          as Map<String, dynamic>;
      final reciters = (data['reciters'] as List?) ?? [];

      for (final r in reciters) {
        // Dedup by name across riwayat — the same reciter often records
        // in multiple Qira'at and the API returns them under each riwayah.
        if (seen.add(r['name'] as String)) {
          sink.add(Map<String, dynamic>.from(r as Map));
        }
      }
    } catch (_) {
      // Skip this riwayah — the rest will still be available
    }
  }

  // ── Disk cache ──────────────────────────────────────────────────────────

  static Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/reciters_cache.json');
  }

  static Future<List<Map<String, dynamic>>?> _readCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      // Invalidate cache after 7 days or if it's from before the dedup fix
      final cacheVersion = decoded['_v'] as int? ?? 0;
      if (cacheVersion < 4) return null;
      final cachedAt = decoded['_cached_at'] as int? ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - cachedAt >
          const Duration(days: 7).inMilliseconds) {
        return null;
      }
      final list = (decoded['reciters'] as List?) ?? [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(List<Map<String, dynamic>> reciters) async {
    try {
      final file = await _cacheFile();
      final wrapper = {
        '_v': 4,
        '_cached_at': DateTime.now().millisecondsSinceEpoch,
        'reciters': reciters,
      };
      await file.writeAsString(jsonEncode(wrapper));
    } catch (_) {}
  }
}
