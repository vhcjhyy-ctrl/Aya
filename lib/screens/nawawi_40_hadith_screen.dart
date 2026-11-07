import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/storage_service.dart';

class Nawawi40HadithScreen extends StatefulWidget {
  final StorageService storage;

  const Nawawi40HadithScreen({super.key, required this.storage});

  @override
  State<Nawawi40HadithScreen> createState() => _Nawawi40HadithScreenState();
}

class _Nawawi40HadithScreenState extends State<Nawawi40HadithScreen> {
  final TextEditingController _search = TextEditingController();
  List<_NawawiHadith> _items = [];
  Set<int> _favorites = {};
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (mounted) setState(() => _query = _search.text.trim());
    });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/data/nawawi_40_hadith_ar.json',
      );
      final decoded = jsonDecode(raw) as List<dynamic>;
      final entries = decoded
          .whereType<Map>()
          .map((item) => _NawawiHadith.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((item) => item.hadith.isNotEmpty)
          .toList();

      final saved = widget.storage.getString(
        'nawawi40_favorites_v1',
        defaultValue: '[]',
      );
      final favoriteJson = jsonDecode(saved);
      final favorites = favoriteJson is List
          ? favoriteJson.map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toSet()
          : <int>{};

      if (!mounted) return;
      setState(() {
        _items = entries;
        _favorites = favorites;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('تعذّر تحميل مجموعة الأحاديث: $error');
    }
  }

  String _normalize(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي')
      .trim();

  List<_NawawiHadith> get _filtered {
    final query = _normalize(_query);
    if (query.isEmpty) return _items;
    return _items.where((item) {
      return _normalize(item.title).contains(query) ||
          _normalize(item.hadith).contains(query) ||
          _normalize(item.narrator).contains(query) ||
          _normalize(item.collection).contains(query);
    }).toList();
  }

  Future<void> _toggleFavorite(_NawawiHadith item) async {
    HapticFeedback.selectionClick();
    setState(() {
      if (_favorites.contains(item.number)) {
        _favorites.remove(item.number);
      } else {
        _favorites.add(item.number);
      }
    });
    await widget.storage.setString(
      'nawawi40_favorites_v1',
      jsonEncode(_favorites.toList()..sort()),
    );
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _openSource(_NawawiHadith item) async {
    final uri = Uri.tryParse(item.sourceUrl);
    if (uri == null || !uri.hasScheme || uri.scheme != 'https') {
      _message('رابط المصدر غير صالح.');
      return;
    }
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) _message('تعذّر فتح مصدر الحديث.');
  }

  void _showHadith(_NawawiHadith item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'الحديث ${item.number}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                item.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: SelectableText(
                  item.hadith,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.justify,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 18,
                    height: 2.05,
                    fontFamily: 'Amiri',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _citationRow(scheme, 'الراوي', item.narrator),
              _citationRow(scheme, 'المصدر', item.collection),
              _citationRow(scheme, 'رقم الحديث', item.number.toString()),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _openSource(item),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('فتح التخريج والمصدر'),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.done_rounded),
                label: const Text('تم'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _citationRow(ColorScheme scheme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الأربعون النووية',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 14),
              child: Text(
                '42 حديثًا',
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      colors: [
                        scheme.primary.withValues(alpha: 0.12),
                        const Color(0xFFC5A45B).withValues(alpha: 0.10),
                      ],
                    ),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.menu_book_rounded,
                        color: scheme.primary,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'متون الأحاديث مع بيانات الراوي والمصدر',
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ابحث، احفظ المفضلة، وافتح رابط التخريج لكل حديث.',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'ابحث في الأحاديث أو الراوي أو المصدر…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: _search.clear,
                            icon: const Icon(Icons.close_rounded),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(child: Text('لا توجد بيانات متاحة.'))
                    : visible.isEmpty
                        ? const Center(child: Text('لا توجد نتائج مطابقة.'))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 9),
                            itemBuilder: (context, index) {
                              final item = visible[index];
                              final favorite = _favorites.contains(item.number);
                              return Card(
                                elevation: 0,
                                color: scheme.surface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(color: scheme.outlineVariant),
                                ),
                                child: ListTile(
                                  onTap: () => _showHadith(item),
                                  contentPadding:
                                      const EdgeInsetsDirectional.fromSTEB(
                                    14, 9, 10, 9,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        scheme.primary.withValues(alpha: 0.10),
                                    foregroundColor: scheme.primary,
                                    child: Text('${item.number}'),
                                  ),
                                  title: Text(
                                    item.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Text(
                                      '${item.narrator} • ${item.collection}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  trailing: IconButton(
                                    tooltip: favorite
                                        ? 'إزالة من المفضلة'
                                        : 'إضافة للمفضلة',
                                    onPressed: () => _toggleFavorite(item),
                                    icon: Icon(
                                      favorite
                                          ? Icons.bookmark_rounded
                                          : Icons.bookmark_border_rounded,
                                      color: favorite
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _NawawiHadith {
  final int number;
  final String title;
  final String hadith;
  final String narrator;
  final String collection;
  final String sourceUrl;

  const _NawawiHadith({
    required this.number,
    required this.title,
    required this.hadith,
    required this.narrator,
    required this.collection,
    required this.sourceUrl,
  });

  factory _NawawiHadith.fromJson(Map<String, dynamic> json) {
    final citation = json['citation'] is Map
        ? Map<String, dynamic>.from(json['citation'] as Map)
        : <String, dynamic>{};
    return _NawawiHadith(
      number: (citation['number'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? '').toString(),
      hadith: (json['hadith'] ?? '').toString(),
      narrator: (citation['narrator'] ?? '').toString(),
      collection: (citation['collection'] ?? '').toString(),
      sourceUrl: (citation['sunnah_url'] ?? '').toString(),
    );
  }
}
