part of 'surah_reader_screen.dart';

extension SurahReaderData on _SurahReaderScreenState {
  Future<void> _fetchDynamicReciters(
    String scriptType, {
    StateSetter? modalSetState,
  }) async {
    // MP3Quran API v3 provides real recitation servers for every riwayah,
    // including Hafs. Do not use fabricated/static edition IDs here.
    int riwayahId = 1;
    switch (scriptType) {
      case 'warsh':
        riwayahId = 2;
        break;
      case 'qaloon':
        riwayahId = 5;
        break;
      case 'shuba':
        riwayahId = 15;
        break;
      case 'duri':
        riwayahId = 13;
        break;
      case 'susi':
        riwayahId = 7;
        break;
      case 'bazzi':
        riwayahId = 4;
        break;
      case 'qunbul':
        riwayahId = 6;
        break;
      case 'hisham':
        riwayahId = 19;
        break;
      case 'ibn-dhakwan':
        riwayahId = 16;
        break;
    }

    if (mounted) {
      setState(() => _isLoadingReciters = true);
      if (modalSetState != null) modalSetState(() {});
    }
    try {
      final filteredReciters = await RecitersCacheService.getRecitersForRiwayah(
        riwayahId,
      );

      if (mounted) {
        setState(() {
          // Flatten every available moshaf into its own selectable source.
          // One reciter may have both murattal and mujawwad recordings.
          _dynamicReciters = filteredReciters.expand((reciter) {
            final moshafs = reciter['moshaf'] as List? ?? const [];
            return moshafs.whereType<Map>().where((moshaf) {
              final server = (moshaf['server'] ?? '').toString();
              return server.startsWith('https://');
            }).map((moshaf) => <String, dynamic>{
              'name': reciter['name']?.toString() ?? '',
              'moshaf': [Map<String, dynamic>.from(moshaf)],
            });
          }).toList()
            ..sort((a, b) {
              final nameCompare = (a['name'] as String).compareTo(
                b['name'] as String,
              );
              if (nameCompare != 0) return nameCompare;
              final aMoshaf = (a['moshaf'] as List).first as Map;
              final bMoshaf = (b['moshaf'] as List).first as Map;
              return (aMoshaf['name'] ?? '').toString().compareTo(
                (bMoshaf['name'] ?? '').toString(),
              );
            });
          _isLoadingReciters = false;

          // Keep the saved choice only when its actual server exists in
          // the newly selected riwayah; otherwise select a real available source.
          final currentReciter = widget.storage.getString('default_reciter');
          final currentServer = currentReciter.startsWith('mp3quran_server_')
              ? currentReciter.substring(16)
              : '';
          final availableServers = _dynamicReciters.map((reciter) {
            final moshaf = (reciter['moshaf'] as List).first as Map;
            return (moshaf['server'] ?? '').toString();
          }).toSet();
          if (_dynamicReciters.isNotEmpty &&
              !availableServers.contains(currentServer)) {
            final firstMoshaf = (_dynamicReciters.first['moshaf'] as List).first as Map;
            final server = (firstMoshaf['server'] ?? '').toString();
            widget.storage.setString('default_reciter', 'mp3quran_server_$server');
          }
        });
        if (modalSetState != null) modalSetState(() {});
      }
    } catch (e) {
      if (mounted) {
        updateState(() => _isLoadingReciters = false);
        if (modalSetState != null) modalSetState(() {});
      }
    }
  }

  Future<void> _loadAllSurahs() async {
    try {
      final list = await ApiService.fetchSurahList();
      updateState(() {
        _allSurahs = list;
      });
    } catch (_) {}
  }

  Future<void> _ensureTafsirLoaded() async {
    if (_tafsirLoaded) return;
    final hasContent = _ayahList.any((a) => a.tafseer.isNotEmpty);
    if (hasContent) return;

    try {
      final tafsirEdition = widget.storage.getString(
        'default_tafsir',
        defaultValue: 'ar.muyassar',
      );
      await ApiService.fetchTafsirForSurah(
        _currentSurah.number,
        _ayahList,
        tafsirEdition: tafsirEdition,
      );
    } catch (_) {}
    _tafsirLoaded = true;
    updateState(() {});
  }

  Future<void> _loadAyahs() async {
    updateState(() {
      _isLoading = true;
      _tafsirLoaded = false;
    });
    try {
      final tafsirEdition = widget.storage.getString(
        'default_tafsir',
        defaultValue: 'ar.muyassar',
      );
      final translationEdition = widget.translationEdition ??
          widget.storage.getString(
            'default_translation',
            defaultValue: 'en.sahih',
          );
      _translationEdition = translationEdition;

      List<Ayah> list;
      if (_quranScriptType == 'hafs') {
        list = await ApiService.fetchSurahDetails(
          _currentSurah.number,
          tafsirEdition: tafsirEdition,
          translationEdition: translationEdition,
        );
      } else {
        list = await LocalQuranService.getSurahAyahs(
          _currentSurah.number,
          _quranScriptType,
        );
        final dbList = await ApiService.fetchSurahDetails(
          _currentSurah.number,
          tafsirEdition: tafsirEdition,
          translationEdition: translationEdition,
        );
        for (int i = 0; i < list.length; i++) {
          if (i < dbList.length) {
            list[i].translation = dbList[i].translation;
            list[i].tafseer = dbList[i].tafseer;
          }
        }
      }
      updateState(() {
        _ayahList = list;
        _isLoading = false;
      });
      // Compute hizb/juz range once after load (fix #5).
      _computeHizbRangeText();
      // Discard recognizers from the previous surah so they are rebuilt
      // fresh for new ayahs. Within a surah, itemBuilder reuses them (fix #1).
      for (var recs in _pageRecognizers.values) {
        for (var r in recs) { r.dispose(); }
      }
      _pageRecognizers.clear();
      _pageKeys.clear();
      _ayahKeys.clear();

      if (widget.initialAyahNumber != null && widget.initialAyahNumber! > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToAyah(widget.initialAyahNumber!);
        });
      } else if (!widget.isInsidePager) {
        final lastAyahInSurah = widget.storage.getLastReadAyahForSurah(
          _currentSurah.number,
        );
        if (lastAyahInSurah != null && lastAyahInSurah > 2) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToAyah(lastAyahInSurah);
          });
        }
      }
      // If user is already in tafsir mode, lazy-load it now
      if (_readingMode == 'tafseer') {
        unawaited(_ensureTafsirLoaded());
      }
    } catch (e) {
      if (mounted) {
        updateState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${TranslationService.t('failed_load_verses')}: $e'),
          ),
        );
      }
    }
  }
}
