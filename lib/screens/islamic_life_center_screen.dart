import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/storage_service.dart';
import 'fiqh/fiqh_screen.dart';

class IslamicLifeCenterScreen extends StatefulWidget {
  final StorageService storage;

  const IslamicLifeCenterScreen({super.key, required this.storage});

  @override
  State<IslamicLifeCenterScreen> createState() =>
      _IslamicLifeCenterScreenState();
}

class _IslamicLifeCenterScreenState extends State<IslamicLifeCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final TextEditingController _fastingNote = TextEditingController();

  static const List<String> _dailyTasks = [
    'المحافظة على الصلوات المفروضة',
    'ورد من القرآن الكريم',
    'أذكار الصباح',
    'أذكار المساء',
    'أذكار ما بعد الصلاة',
    'الصلاة على النبي ﷺ',
    'صلة رحم أو برّ والدين',
    'صدقة أو عمل معروف',
    'استغفار ودعاء',
    'محاسبة النفس قبل النوم',
  ];

  static const List<Map<String, String>> _hajjSteps = [
    {'title': 'التعرّف على نوع النسك', 'detail': 'الإفراد أو القِران أو التمتّع، ومعرفة ما يتعلق بكل نسك قبل السفر.'},
    {'title': 'الإحرام من الميقات', 'detail': 'التهيؤ للإحرام والنية والتلبية من الميقات المحدد بحسب طريق الحاج.'},
    {'title': 'الوقوف بعرفة', 'detail': 'الوقوف بعرفة في وقته الشرعي، وهو ركن الحج الأعظم.'},
    {'title': 'مزدلفة', 'detail': 'أداء ما يتعلق بالمبيت أو الحضور في مزدلفة مع مراعاة الرخص والأحوال.'},
    {'title': 'أعمال يوم النحر', 'detail': 'رمي جمرة العقبة والهدي والحلق أو التقصير وفق نوع النسك والأحكام.'},
    {'title': 'طواف الإفاضة والسعي', 'detail': 'إتمام الطواف والسعي إذا كان السعي مطلوبًا في نسك الحاج.'},
    {'title': 'أيام منى ورمي الجمرات', 'detail': 'اتباع الترتيب والأوقات المعتمدة لرمي الجمرات وأعمال أيام التشريق.'},
    {'title': 'طواف الوداع', 'detail': 'القيام به عند وجوبه، مع مراعاة الاستثناءات والرخص الشرعية.'},
  ];

  static const List<Map<String, String>> _umrahSteps = [
    {'title': 'الإحرام من الميقات', 'detail': 'الاغتسال والتأهب للإحرام والنية من الميقات المناسب.'},
    {'title': 'التلبية', 'detail': 'الإكثار من التلبية المشروعة حتى الشروع في الطواف.'},
    {'title': 'الطواف بالبيت', 'detail': 'الطواف سبعة أشواط مع مراعاة آداب الطواف وسلامة المعتمر.'},
    {'title': 'ركعتا الطواف', 'detail': 'صلاة ركعتين بعد الطواف حيث يتيسر دون مزاحمة أو إيذاء.'},
    {'title': 'السعي بين الصفا والمروة', 'detail': 'السعي سبعة أشواط يبدأ بالصفا وينتهي بالمروة.'},
    {'title': 'الحلق أو التقصير', 'detail': 'الحلق أو التقصير لإتمام التحلل من العمرة.'},
  ];

  static const List<String> _sadaqahIdeas = [
    'المساهمة في سقاية ماء أو توفيره للمحتاجين',
    'دعم تعليم القرآن أو تعليم علم نافع موثوق',
    'المشاركة في وقف نافع أو دعم مشروع مستدام',
    'المساهمة في تجهيز مكتبة أو مورد تعليمي',
    'غرس شجرة نافعة والعناية بها',
    'دعم رعاية مريض أو محتاج عبر جهة موثوقة',
    'نشر مادة علمية موثقة مع ذكر مصدرها',
    'تعليم مهارة نافعة يستفيد منها الآخرون',
    'المشاركة في إصلاح مرفق ينتفع به الناس',
    'الدلالة على الخير ومساعدة من يحتاج إلى العون',
  ];

  static const List<Map<String, String>> _pillars = [
    {'title': 'الشهادتان', 'detail': 'شهادة أن لا إله إلا الله وأن محمدًا رسول الله؛ أصل الإسلام ومعنى التوحيد واتباع الرسول ﷺ.'},
    {'title': 'إقامة الصلاة', 'detail': 'المحافظة على الصلوات المفروضة في أوقاتها، وتعلّم شروطها وأركانها وواجباتها.'},
    {'title': 'إيتاء الزكاة', 'detail': 'حق واجب في المال بشروطه وأنصبته ومقاديره، وتُراجع تفاصيله بحسب نوع المال والحال.'},
    {'title': 'صوم رمضان', 'detail': 'صيام شهر رمضان عبادة مفروضة، وتُتعلّم أحكام الصيام والرخص والمفطرات من مصدر موثوق.'},
    {'title': 'حج البيت', 'detail': 'حج بيت الله لمن استطاع إليه سبيلًا، مع تعلّم المناسك والاستعداد قبل السفر.'},
  ];

  late final String _todayKey;
  Set<String> _dailyDone = {};
  Set<int> _hajjDone = {};
  Set<int> _umrahDone = {};
  Set<int> _sadaqahDone = {};
  List<Map<String, String>> _fastingRecords = [];
  bool _isHajj = true;
  String _fastType = 'قضاء رمضان';
  DateTime _fastDate = DateTime.now();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _todayKey = _dateKey(DateTime.now());
    _tabs = TabController(length: 6, vsync: this);
    _loadProgress();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _fastingNote.dispose();
    super.dispose();
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _formatDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  Set<int> _decodeIntSet(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is List) {
        return value
            .map((item) => int.tryParse(item.toString()))
            .whereType<int>()
            .toSet();
      }
    } catch (_) {}
    return {};
  }

  Set<String> _decodeStringSet(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is List) {
        return value.map((item) => item.toString()).toSet();
      }
    } catch (_) {}
    return {};
  }

  Future<void> _loadProgress() async {
    _dailyDone = _decodeStringSet(widget.storage.getString(
      'worship_daily_${_todayKey}',
      defaultValue: '[]',
    ));
    _hajjDone = _decodeIntSet(widget.storage.getString(
      'worship_hajj_checklist_v1',
      defaultValue: '[]',
    ));
    _umrahDone = _decodeIntSet(widget.storage.getString(
      'worship_umrah_checklist_v1',
      defaultValue: '[]',
    ));
    _sadaqahDone = _decodeIntSet(widget.storage.getString(
      'worship_sadaqah_checklist_v1',
      defaultValue: '[]',
    ));

    try {
      final decoded = jsonDecode(widget.storage.getString(
        'worship_fasting_log_v1',
        defaultValue: '[]',
      ));
      if (decoded is List) {
        _fastingRecords = decoded
            .whereType<Map>()
            .map((item) => <String, String>{
                  'date': (item['date'] ?? '').toString(),
                  'type': (item['type'] ?? 'نافلة').toString(),
                  'note': (item['note'] ?? '').toString(),
                })
            .where((item) => item['date']!.isNotEmpty)
            .toList()
          ..sort((a, b) => b['date']!.compareTo(a['date']!));
      }
    } catch (_) {
      _fastingRecords = [];
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveSet(String key, Set<int> values) async {
    await widget.storage.setString(
      key,
      jsonEncode(values.toList()..sort()),
    );
  }

  Future<void> _toggleDaily(String task, bool checked) async {
    setState(() {
      checked ? _dailyDone.add(task) : _dailyDone.remove(task);
    });
    await widget.storage.setString(
      'worship_daily_${_todayKey}',
      jsonEncode(_dailyDone.toList()..sort()),
    );
  }

  Future<void> _toggleChecklist(String kind, int index, bool checked) async {
    final values = kind == 'hajj'
        ? _hajjDone
        : kind == 'umrah'
            ? _umrahDone
            : _sadaqahDone;
    setState(() {
      checked ? values.add(index) : values.remove(index);
    });
    final key = kind == 'hajj'
        ? 'worship_hajj_checklist_v1'
        : kind == 'umrah'
            ? 'worship_umrah_checklist_v1'
            : 'worship_sadaqah_checklist_v1';
    await _saveSet(key, values);
  }

  Future<void> _chooseFastDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _fastDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: 'اختر تاريخ الصيام',
    );
    if (chosen != null && mounted) {
      setState(() => _fastDate = DateTime(chosen.year, chosen.month, chosen.day));
    }
  }

  Future<void> _addFastingRecord() async {
    final key = _dateKey(_fastDate);
    if (_fastingRecords.any(
      (item) => item['date'] == key && item['type'] == _fastType,
    )) {
      _message('هذا اليوم مسجّل بالفعل ضمن هذا النوع.');
      return;
    }
    setState(() {
      _fastingRecords.add({
        'date': key,
        'type': _fastType,
        'note': _fastingNote.text.trim(),
      });
      _fastingRecords.sort((a, b) => b['date']!.compareTo(a['date']!));
      _fastingNote.clear();
    });
    await _persistFasting();
  }

  Future<void> _removeFast(Map<String, String> record) async {
    setState(() => _fastingRecords.remove(record));
    await _persistFasting();
  }

  Future<void> _persistFasting() async {
    await widget.storage.setString(
      'worship_fasting_log_v1',
      jsonEncode(_fastingRecords),
    );
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _openFiqh() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FiqhScreen(storage: widget.storage),
      ),
    );
  }

  Widget _sectionCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(15),
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }

  Widget _intro({
    required IconData icon,
    required String title,
    required String description,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return _sectionCard(
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
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
    );
  }

  Widget _progressCard({
    required String title,
    required int done,
    required int total,
    IconData icon = Icons.check_circle_outline_rounded,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final progress = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${done} / ${total}',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(scheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, int count, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return _sectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
      child: Column(
        children: [
          Icon(icon, color: scheme.primary, size: 19),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dailyTab() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _intro(
          icon: Icons.today_rounded,
          title: 'متابعة أعمال اليوم',
          description: 'قائمة شخصية لتذكيرك بالأعمال التي تريد المحافظة عليها. سجّل ما أنجزته دون تكلف.',
        ),
        const SizedBox(height: 12),
        _progressCard(
          title: 'إنجازات اليوم',
          done: _dailyDone.length,
          total: _dailyTasks.length,
          icon: Icons.insights_rounded,
        ),
        const SizedBox(height: 12),
        _sectionCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: _dailyTasks.map((task) => CheckboxListTile(
              value: _dailyDone.contains(task),
              onChanged: (value) => _toggleDaily(task, value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                task,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              dense: true,
            )).toList(),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'هذه القائمة للتنظيم الشخصي وليست مقياسًا لقبول العمل أو ثوابه.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _fastingTab() {
    final scheme = Theme.of(context).colorScheme;
    final qadaa = _fastingRecords.where((r) => r['type'] == 'قضاء رمضان').length;
    final voluntary = _fastingRecords.where((r) => r['type'] == 'صيام تطوع').length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _intro(
          icon: Icons.nights_stay_rounded,
          title: 'سجل الصيام',
          description: 'دوّن أيام القضاء أو صيام التطوع، واحتفظ بسجلّك على هذا الجهاز.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _statTile('أيام القضاء', qadaa, Icons.event_available_rounded)),
            const SizedBox(width: 9),
            Expanded(child: _statTile('صيام التطوع', voluntary, Icons.stars_rounded)),
            const SizedBox(width: 9),
            Expanded(child: _statTile('الإجمالي', _fastingRecords.length, Icons.calendar_month_rounded)),
          ],
        ),
        const SizedBox(height: 12),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'نوع الصيام المسجّل',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('قضاء رمضان'),
                    selected: _fastType == 'قضاء رمضان',
                    onSelected: (_) => setState(() => _fastType = 'قضاء رمضان'),
                  ),
                  ChoiceChip(
                    label: const Text('صيام تطوع'),
                    selected: _fastType == 'صيام تطوع',
                    onSelected: (_) => setState(() => _fastType = 'صيام تطوع'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _chooseFastDate,
                icon: const Icon(Icons.date_range_rounded),
                label: Text('التاريخ: ${_formatDate(_dateKey(_fastDate))}'),
              ),
              TextField(
                controller: _fastingNote,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة اختيارية',
                  hintText: 'مثال: يوم قضاء أو نذر…',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _addFastingRecord,
                icon: const Icon(Icons.add_rounded),
                label: const Text('تسجيل يوم الصيام'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'سجل الأيام',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),
        if (_fastingRecords.isEmpty)
          _sectionCard(
            child: Text(
              'لم تسجّل أيام صيام بعد. أضف أول يوم من النموذج أعلاه.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          )
        else
          ..._fastingRecords.map((record) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _sectionCard(
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record['type'] ?? '',
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              _formatDate(record['date'] ?? ''),
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                            if ((record['note'] ?? '').isNotEmpty)
                              Text(
                                record['note']!,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'حذف السجل',
                        onPressed: () => _removeFast(record),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ),
              )),
        const SizedBox(height: 6),
        Text(
          'تسجيل الأيام أداة تنظيمية فقط؛ راجع أهل العلم في أحكام القضاء والرخص والفدية بحسب حالتك.',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 11,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _pilgrimageTab() {
    final scheme = Theme.of(context).colorScheme;
    final steps = _isHajj ? _hajjSteps : _umrahSteps;
    final done = _isHajj ? _hajjDone : _umrahDone;
    final kind = _isHajj ? 'hajj' : 'umrah';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _intro(
          icon: Icons.mosque_rounded,
          title: 'دليل الحج والعمرة',
          description: 'قائمة متابعة تمهيدية للمناسك، تحفظ علامات الإنجاز على جهازك.',
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('الحج'),
              icon: Icon(Icons.landscape_rounded),
            ),
            ButtonSegment(
              value: false,
              label: Text('العمرة'),
              icon: Icon(Icons.account_balance_rounded),
            ),
          ],
          selected: {_isHajj},
          onSelectionChanged: (selection) =>
              setState(() => _isHajj = selection.first),
        ),
        const SizedBox(height: 12),
        _progressCard(
          title: _isHajj ? 'متابعة أعمال الحج' : 'متابعة أعمال العمرة',
          done: done.length,
          total: steps.length,
          icon: Icons.checklist_rounded,
        ),
        const SizedBox(height: 12),
        ...List.generate(steps.length, (index) {
          final item = steps[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _sectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: CheckboxListTile(
                value: done.contains(index),
                onChanged: (value) => _toggleChecklist(kind, index, value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  item['title']!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: Text(
                  item['detail']!,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
                dense: true,
              ),
            ),
          );
        }),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            'تنبيه علمي: هذا ملخّص تنظيمي عام، وليس دليلًا تفصيليًا للفتوى. قد يختلف ترتيب بعض الأعمال وأحكامها باختلاف نوع النسك والقدرة والرخص والمذهب؛ ارجع إلى دليل رسمي موثوق أو عالم مؤهل.',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 11,
              height: 1.65,
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _openFiqh,
          icon: const Icon(Icons.menu_book_rounded),
          label: const Text('فتح مكتبة الفقه والأحكام'),
        ),
      ],
    );
  }

  Widget _sadaqahTab() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _intro(
          icon: Icons.volunteer_activism_rounded,
          title: 'أبواب الخير والصدقة الجارية',
          description: 'أفكار لأعمال نافعة يمكن التخطيط لها ومتابعة ما بدأت به.',
        ),
        const SizedBox(height: 12),
        _sectionCard(
          child: Column(
            children: [
              const Text(
                'إِذَا مَاتَ الإِنْسَانُ انْقَطَعَ عَنْهُ عَمَلُهُ إِلَّا مِنْ ثَلَاثَةٍ: '
                'صَدَقَةٍ جَارِيَةٍ، أَوْ عِلْمٍ يُنْتَفَعُ بِهِ، '
                'أَوْ وَلَدٍ صَالِحٍ يَدْعُو لَهُ.',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: 'Amiri',
                  fontSize: 17,
                  height: 1.9,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'صحيح مسلم 1631 • رواية أبي هريرة رضي الله عنه',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('https://sunnah.com/muslim:1631'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('التحقق من نص الحديث'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _progressCard(
          title: 'أفكار اخترتها للمتابعة',
          done: _sadaqahDone.length,
          total: _sadaqahIdeas.length,
          icon: Icons.favorite_border_rounded,
        ),
        const SizedBox(height: 8),
        ...List.generate(_sadaqahIdeas.length, (index) => CheckboxListTile(
              value: _sadaqahDone.contains(index),
              onChanged: (value) => _toggleChecklist('sadaqah', index, value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                _sadaqahIdeas[index],
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              dense: true,
            )),
        const SizedBox(height: 8),
        Text(
          'اختيار الفكرة لا يعني اكتمال تنفيذها أو ضمان استمرار نفعها؛ تحقّق من الجهات والمشروعات قبل المساهمة.',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 11,
            height: 1.6,
          ),
        ),
      ],
    );
  }

  Widget _pillarsTab() {
    final scheme = Theme.of(context).colorScheme;
    const icons = [
      Icons.verified_rounded,
      Icons.mosque_rounded,
      Icons.volunteer_activism_rounded,
      Icons.nights_stay_rounded,
      Icons.foundation_rounded,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _intro(
          icon: Icons.foundation_rounded,
          title: 'أركان الإسلام الخمسة',
          description: 'بطاقات موجزة للتذكير، ويمكن الرجوع إلى أبواب الفقه للتفصيل.',
        ),
        const SizedBox(height: 12),
        ...List.generate(_pillars.length, (index) {
          final item = _pillars[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _sectionCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primary.withValues(alpha: 0.10),
                    foregroundColor: scheme.primary,
                    child: Icon(icons[index], size: 19),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${index + 1}. ${item['title']}',
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item['detail']!,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: _openFiqh,
          icon: const Icon(Icons.menu_book_rounded),
          label: const Text('التعلّم من مكتبة الفقه'),
        ),
      ],
    );
  }

  Widget _janazahTab() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        _intro(
          icon: Icons.local_florist_rounded,
          title: 'الدعاء للمتوفّى',
          description: 'تذكير بالدعاء للراحلين بالرحمة والمغفرة، ومنهم من أُهدي إليهم هذا التطبيق.',
        ),
        const SizedBox(height: 12),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'اللهم اغفر لهم وارحمهم، وعافهم واعفُ عنهم، وأكرم نُزُلهم، '
                'ووسّع مُدخلهم، واغسلهم بالماء والثلج والبرد، ونقّهم من الخطايا '
                'كما يُنقّى الثوب الأبيض من الدنس.',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontFamily: 'Amiri',
                  fontSize: 17,
                  height: 2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'صياغة دعاء للجمع مستلهمة من الدعاء النبوي للميت في صحيح مسلم 963a؛ واللفظ المروي في المصدر يأتي بصيغة المفرد.',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse('https://sunnah.com/muslim/11/109'),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('مصدر الدعاء: صحيح مسلم 963a'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(const ClipboardData(
                    text: 'اللهم اغفر لهم وارحمهم، وعافهم واعفُ عنهم، وأكرم نُزُلهم، ووسّع مُدخلهم، واغسلهم بالماء والثلج والبرد، ونقّهم من الخطايا كما يُنقّى الثوب الأبيض من الدنس.',
                  ));
                  _message('نُسخ الدعاء إلى الحافظة.');
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('نسخ الدعاء'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تذكير',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'من أعمال البر للمتوفّى: الدعاء والاستغفار، والصدقة، وقضاء الحقوق والديون عنه وفق الضوابط الشرعية. وتفاصيل غسل الميت وتكفينه وصلاة الجنازة والحقوق المتعلقة بالتركة تُؤخذ من أهل العلم والجهات المختصة.',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 12,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _openFiqh,
          icon: const Icon(Icons.menu_book_rounded),
          label: const Text('فتح أبواب الفقه للمزيد'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'مركز العبادات والحياة الإسلامية',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.today_rounded), text: 'أعمال اليوم'),
            Tab(icon: Icon(Icons.nights_stay_rounded), text: 'الصيام'),
            Tab(icon: Icon(Icons.mosque_rounded), text: 'الحج والعمرة'),
            Tab(icon: Icon(Icons.favorite_rounded), text: 'الصدقة'),
            Tab(icon: Icon(Icons.foundation_rounded), text: 'الأركان'),
            Tab(icon: Icon(Icons.volunteer_activism_rounded), text: 'الجنائز والدعاء'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _dailyTab(),
                _fastingTab(),
                _pilgrimageTab(),
                _sadaqahTab(),
                _pillarsTab(),
                _janazahTab(),
              ],
            ),
    );
  }
}
