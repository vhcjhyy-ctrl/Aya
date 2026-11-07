import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/database_service.dart';
import '../services/local_spiritual_planner_service.dart';
import '../services/storage_service.dart';
import 'quran_screen.dart';

class WirdQadaaScreen extends StatefulWidget {
  final StorageService storage;
  final int initialTab;

  const WirdQadaaScreen({
    super.key,
    required this.storage,
    this.initialTab = 0,
  });

  @override
  State<WirdQadaaScreen> createState() => _WirdQadaaScreenState();
}

class _WirdQadaaScreenState extends State<WirdQadaaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  KhatmahPlan? _plan;
  QadaaTrackerState _qadaa = QadaaTrackerState.empty();
  bool _loading = true;
  bool _creatingPlan = false;
  bool _showCreateForm = false;
  int _selectedJuz = 1;
  int _durationDays = 30;

  static const _prayerLabels = <String, String>{
    'fajr': 'الفجر',
    'dhuhr': 'الظهر',
    'asr': 'العصر',
    'maghrib': 'المغرب',
    'isha': 'العشاء',
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _loadLocalState();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadLocalState() async {
    try {
      final planJson = widget.storage.getString('qalam_khatmah_plan_v1');
      if (planJson.isNotEmpty) {
        final decoded = jsonDecode(planJson);
        if (decoded is Map) {
          _plan = KhatmahPlan.fromJson(Map<String, dynamic>.from(decoded));
        }
      }
    } catch (error) {
      debugPrint('Khatmah plan restore failed: $error');
    }

    try {
      final qadaaJson = widget.storage.getString('qalam_qadaa_tracker_v1');
      if (qadaaJson.isNotEmpty) {
        final decoded = jsonDecode(qadaaJson);
        if (decoded is Map) {
          _qadaa = QadaaTrackerState.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      }
    } catch (error) {
      debugPrint('Qadaa tracker restore failed: $error');
    }

    if (!mounted) return;
    setState(() {
      _showCreateForm = _plan == null;
      _loading = false;
    });
  }

  Future<void> _persistPlan(KhatmahPlan plan) async {
    await widget.storage.setString(
      'qalam_khatmah_plan_v1',
      jsonEncode(plan.toJson()),
    );
    if (mounted) setState(() => _plan = plan);
  }

  Future<void> _persistQadaa(QadaaTrackerState state) async {
    await widget.storage.setString(
      'qalam_qadaa_tracker_v1',
      jsonEncode(state.toJson()),
    );
    if (mounted) setState(() => _qadaa = state);
  }

  Future<void> _createPlan() async {
    if (_creatingPlan) return;
    if (_plan != null) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('بدء خطة ختمة جديدة؟'),
          content: const Text(
            'سيتم استبدال الخطة الحالية بالخطة الجديدة. '
            'سيبقى سجل الصلوات والصيام دون تغيير.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('إنشاء الخطة'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }

    setState(() => _creatingPlan = true);
    try {
      final db = await DatabaseService.getInstance();
      final startPage = await db.getFirstPageForJuz(_selectedJuz);
      if (!mounted) return;
      if (startPage == null) {
        _showMessage(
          'لم أعثر على بداية الجزء في قاعدة المصحف المحلية. '
          'افتح المصحف مرة واحدة ثم حاول مجددًا.',
        );
        return;
      }

      final plan = KhatmahPlan.create(
        startJuz: _selectedJuz,
        startPage: startPage,
        durationDays: _durationDays,
      );
      await _persistPlan(plan);
      if (!mounted) return;
      setState(() => _showCreateForm = false);
      _showMessage('تم إنشاء خطة الختمة وحفظها على جهازك.');
    } catch (error) {
      _showMessage('تعذّر إنشاء الخطة: ' + error.toString());
    } finally {
      if (mounted) setState(() => _creatingPlan = false);
    }
  }

  Future<void> _toggleToday() async {
    final plan = _plan;
    if (plan == null) return;
    final updated = plan.setDayCompleted(
      plan.currentDay,
      !plan.isCompleted(plan.currentDay),
    );
    await _persistPlan(updated);
    _showMessage(
      updated.isCompleted(updated.currentDay)
          ? 'تم تسجيل ورد اليوم.'
          : 'أُعيد ورد اليوم إلى قائمة الإنجاز.',
    );
  }

  Future<int?> _askPositiveCount({
    required String title,
    String hint = 'العدد',
  }) async {
    final controller = TextEditingController(text: '1');
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final count = int.tryParse(controller.text.trim());
              Navigator.pop(
                dialogContext,
                count != null && count > 0 ? count : null,
              );
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _addPrayerDebt(String key) async {
    final count = await _askPositiveCount(
      title: 'إضافة فائتة: ' + (_prayerLabels[key] ?? key),
      hint: 'عدد الصلوات',
    );
    if (count == null) return;
    await _persistQadaa(_qadaa.addPrayerDebt(key, count));
  }

  Future<void> _completePrayer(String key) async {
    final next = _qadaa.completePrayer(key);
    if (identical(next, _qadaa)) {
      _showMessage('لا يوجد فائت مسجل لهذه الصلاة.');
      return;
    }
    await _persistQadaa(next);
  }

  Future<void> _addFastDebt() async {
    final count = await _askPositiveCount(
      title: 'إضافة أيام صيام للقضاء',
      hint: 'عدد الأيام',
    );
    if (count == null) return;
    await _persistQadaa(_qadaa.addFastDebt(count));
  }

  Future<void> _completeFast() async {
    final next = _qadaa.completeFast();
    if (identical(next, _qadaa)) {
      _showMessage('لا توجد أيام صيام مسجلة للقضاء.');
      return;
    }
    await _persistQadaa(next);
  }

  Future<void> _completeFullPrayerDay() async {
    final next = _qadaa.completeFullPrayerDay();
    if (identical(next, _qadaa)) {
      _showMessage('لا توجد صلوات متبقية مسجلة.');
      return;
    }
    await _persistQadaa(next);
  }

  Future<void> _setDailyGoal(int value) async {
    await _persistQadaa(_qadaa.setDailyGoal(value));
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openQuran() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuranScreen(storage: widget.storage),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('رحلة القرآن والقضاء'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.menu_book_rounded), text: 'خطة الختمة'),
            Tab(icon: Icon(Icons.checklist_rounded), text: 'متابعة القضاء'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _buildKhatmahTab(theme, scheme),
                _buildQadaaTab(theme, scheme),
              ],
            ),
    );
  }

  Widget _buildKhatmahTab(ThemeData theme, ColorScheme scheme) {
    final plan = _plan;
    if (_showCreateForm || plan == null) {
      return _buildCreatePlanForm(theme, scheme);
    }

    final day = plan.currentDay;
    final done = plan.isCompleted(day);
    final pageStart = plan.pageStartForDay(day);
    final pageEnd = plan.pageEndForDay(day);
    final lastDay = (day + 4).clamp(1, plan.durationDays).toInt();
    final upcoming = <int>[for (var i = day; i <= lastDay; i++) i];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          color: scheme.primaryContainer.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'ختمة من الجزء ' + plan.startJuz.toString(),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'خطة جديدة',
                      onPressed: () => setState(() => _showCreateForm = true),
                      icon: const Icon(Icons.edit_calendar_rounded),
                    ),
                  ],
                ),
                Text(
                  'بدأت في ' +
                      DateFormat('yyyy/MM/dd').format(plan.beginsOn) +
                      ' · ' +
                      plan.durationDays.toString() +
                      ' يومًا',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: plan.progress,
                            strokeWidth: 7,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                          Center(
                            child: Text(
                              plan.progress * 100.round() .toString() + '%',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.completedCount.toString() +
                                ' من ' +
                                plan.durationDays.toString() +
                                ' ورد',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'المتبقي ' + plan.remainingSessions.toString() + ' ورد',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: plan.progress),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.today_rounded, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ورد اليوم · اليوم ' + day.toString(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (done)
                      const Chip(
                        avatar: Icon(Icons.check_circle_rounded, size: 16),
                        label: Text('مكتمل'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'من صفحة ' +
                      pageStart.toString() +
                      ' إلى صفحة ' +
                      pageEnd.toString(),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  (pageEnd - pageStart + 1).toString() +
                      ' صفحة تقريبًا حسب بداية الجزء المختار.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _openQuran,
                  icon: const Icon(Icons.menu_book_rounded),
                  label: const Text('فتح المصحف'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _toggleToday,
                  icon: Icon(
                    done ? Icons.undo_rounded : Icons.task_alt_rounded,
                  ),
                  label: Text(done ? 'إلغاء إكمال ورد اليوم' : 'أتممت ورد اليوم'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'الأوراد القادمة',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...upcoming.map((sessionDay) {
          final first = plan.pageStartForDay(sessionDay);
          final last = plan.pageEndForDay(sessionDay);
          final completed = plan.isCompleted(sessionDay);
          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 7),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: completed
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                child: completed
                    ? Icon(Icons.check_rounded, color: scheme.primary)
                    : Text(sessionDay.toString()),
              ),
              title: Text('اليوم ' + sessionDay.toString()),
              subtitle: Text('صفحات ' + first.toString() + '–' + last.toString()),
              trailing: completed
                  ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                  : const Icon(Icons.schedule_rounded),
            ),
          );
        }),
        const SizedBox(height: 8),
        Text(
          'الخطة تقديرية مبنية على صفحات المصحف المدمج. يمكنك متابعة القراءة '
          'وتسجيل إنجاز الورد يدويًا، وتُحفظ بياناتك على هذا الجهاز.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildCreatePlanForm(ThemeData theme, ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          color: scheme.primaryContainer.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_stories_rounded, size: 34, color: scheme.primary),
                const SizedBox(height: 10),
                Text(
                  'أنشئ خطة ختمتك',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'اختر الجزء الذي تبدأ منه والمدة التي تناسبك. '
                  'سيُقسّم التطبيق الصفحات المتبقية إلى ورد يومي.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          value: _selectedJuz,
          decoration: const InputDecoration(
            labelText: 'بداية الختمة',
            prefixIcon: Icon(Icons.bookmark_outline_rounded),
            border: OutlineInputBorder(),
          ),
          items: List.generate(
            30,
            (index) => DropdownMenuItem(
              value: index + 1,
              child: Text('الجزء ' + (index + 1).toString()),
            ),
          ),
          onChanged: (value) {
            if (value != null) setState(() => _selectedJuz = value);
          },
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          value: _durationDays,
          decoration: const InputDecoration(
            labelText: 'مدة الختمة',
            prefixIcon: Icon(Icons.calendar_month_rounded),
            border: OutlineInputBorder(),
          ),
          items: const [7, 15, 30, 40, 45, 60, 90].map((days) {
            return DropdownMenuItem(
              value: days,
              child: Text(days.toString() + ' يومًا'),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) setState(() => _durationDays = value);
          },
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _creatingPlan ? null : _createPlan,
          icon: _creatingPlan
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow_rounded),
          label: Text(_creatingPlan ? 'جارٍ إنشاء الخطة...' : 'ابدأ الخطة'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
        ),
        if (_plan != null) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _showCreateForm = false),
            child: const Text('العودة إلى خطتي الحالية'),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'يعتمد تحديد بداية الجزء على بيانات المصحف المحلية؛ لا يلزم اتصال بالإنترنت.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildQadaaTab(ThemeData theme, ColorScheme scheme) {
    final totalRemaining = _qadaa.remainingPrayers + _qadaa.remainingFasts;
    final totalCompleted = _qadaa.completedPrayers + _qadaa.fastsCompleted;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          color: scheme.primaryContainer.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'متابعة القضاء الشخصية',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'سجّل الأعداد التي قدّرتها بنفسك، ثم حدّثها كلما أتممت قضاءً. '
                  'التطبيق لا يقدّر ما يلزمك شرعًا.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _metric(
                        theme,
                        'المتبقي',
                        totalRemaining.toString(),
                        Icons.hourglass_bottom_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metric(
                        theme,
                        'تم إنجازه',
                        totalCompleted.toString(),
                        Icons.check_circle_outline_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metric(
                        theme,
                        'سلسلة الأيام',
                        _qadaa.currentStreak().toString(),
                        Icons.local_fire_department_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'الصلوات',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _completeFullPrayerDay,
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: const Text('يوم كامل'),
            ),
          ],
        ),
        ..._prayerLabels.entries.map((entry) {
          final owed = _qadaa.prayerOwed[entry.key] ?? 0;
          final completed = _qadaa.completedForPrayer(entry.key);
          final remaining = _qadaa.remainingForPrayer(entry.key);
          final progress = owed == 0 ? 0.0 : completed / owed;
          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.value,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        'المتبقي ' + remaining.toString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        completed.toString() + ' من ' + owed.toString(),
                        style: theme.textTheme.bodySmall,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'إضافة فائت',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _addPrayerDebt(entry.key),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                      ),
                      FilledButton.tonalIcon(
                        onPressed:
                            remaining > 0 ? () => _completePrayer(entry.key) : null,
                        icon: const Icon(Icons.check_rounded, size: 17),
                        label: const Text('قضيت'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                'الصيام',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _addFastDebt,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('إضافة أيام'),
            ),
          ],
        ),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.nights_stay_rounded, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'أيام الصيام المتبقية: ' + _qadaa.remainingFasts.toString(),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'تم قضاء ' +
                            _qadaa.fastsCompleted.toString() +
                            ' من ' +
                            _qadaa.fastsOwed.toString(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: _qadaa.remainingFasts > 0 ? _completeFast : null,
                  child: const Text('قضيت يومًا'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'هدفك اليومي من أعمال القضاء',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                DropdownButton<int>(
                  value: _qadaa.dailyGoal,
                  items: [1, 2, 3, 5, 7, 10].map((value) {
                    return DropdownMenuItem(
                      value: value,
                      child: Text(value.toString()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) _setDailyGoal(value);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'سجل الإنجاز الأخير',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        if (_qadaa.logs.isEmpty)
          Text(
            'سيظهر هنا ما تسجّله من إنجازات.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          ..._qadaa.logs.take(8).map((log) {
            final date =
                DateTime.fromMillisecondsSinceEpoch(log.completedAt).toLocal();
            final label = log.type == 'fast'
                ? 'قضاء صيام'
                : log.type == 'fullDay'
                    ? 'قضاء يوم كامل'
                    : 'قضاء ' + (_prayerLabels[log.label] ?? log.label);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.check_circle_outline, color: scheme.primary),
              title: Text(label),
              subtitle: Text(DateFormat('yyyy/MM/dd · HH:mm').format(date)),
              trailing: Text('+' + log.count.toString()),
            );
          }),
      ],
    );
  }

  Widget _metric(
    ThemeData theme,
    String label,
    String value,
    IconData icon,
  ) {
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: scheme.primary, size: 18),
          const SizedBox(height: 5),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
