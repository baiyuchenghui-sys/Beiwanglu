import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = UniverseStore();
  await store.initialize();
  runApp(UniverseApp(store: store));
}

class UniverseApp extends StatelessWidget {
  const UniverseApp({super.key, required this.store});
  final UniverseStore store;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (_, __) => MaterialApp(
      title: '每日小宇宙',
      debugShowCheckedModeBanner: false,
      themeMode: store.themeMode,
      theme: universeTheme(Brightness.light),
      darkTheme: universeTheme(Brightness.dark),
      home: AppShell(store: store),
    ),
  );
}

ThemeData universeTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF183B67),
    brightness: brightness,
    surface: dark ? const Color(0xFF101826) : const Color(0xFFF7F9FC),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF172235) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1C2940) : const Color(0xFFF1F4F8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}

class UniverseStore extends ChangeNotifier with WidgetsBindingObserver {
  Database? _database;
  Timer? _dayTimer;
  String? _loadedDay;
  List<Map<String, dynamic>> todos = [],
      notes = [],
      workouts = [],
      transactions = [],
      entertainment = [];
  String theme = 'system';
  int weekStart = 1;
  double monthlyBudget = 0;
  double openingBalance = 0;
  int monthStartDay = 1;
  Database get db => _database!;
  ThemeMode get themeMode => theme == 'light'
      ? ThemeMode.light
      : theme == 'dark'
      ? ThemeMode.dark
      : ThemeMode.system;
  Future<void> initialize() async {
    final databaseDirectory = await getDatabasesPath();
    _database = await openDatabase(
      join(databaseDirectory, 'daily_little_universe.db'),
      version: 3,
      onCreate: (db, _) async {
        await db.execute(
          "CREATE TABLE todos(id INTEGER PRIMARY KEY AUTOINCREMENT,title TEXT NOT NULL,date TEXT NOT NULL,start_time TEXT,end_time TEXT,priority TEXT NOT NULL,is_done INTEGER NOT NULL DEFAULT 0,repeat TEXT NOT NULL DEFAULT '一次',parent_id INTEGER,kind TEXT NOT NULL DEFAULT '计划',weekdays TEXT NOT NULL DEFAULT '1,2,3,4,5,6,7',completed_at TEXT,created_at TEXT NOT NULL)",
        );
        await db.execute(
          'CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT,content TEXT NOT NULL,updated_at TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE workouts(id INTEGER PRIMARY KEY AUTOINCREMENT,type TEXT NOT NULL,duration INTEGER NOT NULL,date TEXT NOT NULL,note TEXT)',
        );
        await db.execute(
          'CREATE TABLE transactions(id INTEGER PRIMARY KEY AUTOINCREMENT,kind TEXT NOT NULL,amount REAL NOT NULL,category TEXT NOT NULL,date TEXT NOT NULL,note TEXT)',
        );
        await db.execute(
          'CREATE TABLE entertainment(id INTEGER PRIMARY KEY AUTOINCREMENT,title TEXT NOT NULL,kind TEXT NOT NULL,status TEXT NOT NULL,progress TEXT,rating REAL,note TEXT)',
        );
        await db.execute(
          'CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)',
        );
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE todos ADD COLUMN repeat TEXT NOT NULL DEFAULT '一次'",
          );
          await db.execute('ALTER TABLE todos ADD COLUMN parent_id INTEGER');
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE todos ADD COLUMN kind TEXT NOT NULL DEFAULT '计划'",
          );
          await db.execute(
            "ALTER TABLE todos ADD COLUMN weekdays TEXT NOT NULL DEFAULT '1,2,3,4,5,6,7'",
          );
          await db.execute('ALTER TABLE todos ADD COLUMN completed_at TEXT');
          await db.execute(
            "UPDATE todos SET kind='每日' WHERE repeat='每天' AND parent_id IS NULL",
          );
          await db.execute(
            "UPDATE todos SET kind='每日记录' WHERE parent_id IS NOT NULL",
          );
          await db.update('todos', {
            'completed_at': dayKey(DateTime.now()),
          }, where: "kind='计划' AND is_done=1");
        }
      },
    );
    await _default('theme', 'system');
    await _default('week_start', '1');
    await _default('monthly_budget', '0');
    await _default('opening_balance', '0');
    await _default('month_start_day', '1');
    await refresh();
    WidgetsBinding.instance.addObserver(this);
    _dayTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_loadedDay != dayKey(DateTime.now())) refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _default(String key, String value) => db.insert('settings', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  Future<String> _setting(String key) async =>
      (await db.query(
            'settings',
            where: 'key=?',
            whereArgs: [key],
          )).first['value']
          as String;
  Future<void> _set(String key, String value) => db.insert('settings', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> refresh() async {
    final today = dayKey(DateTime.now());
    await db.delete(
      'todos',
      where: "kind='计划' AND completed_at IS NOT NULL AND completed_at < ?",
      whereArgs: [today],
    );
    _loadedDay = today;
    todos = await db.query('todos', orderBy: 'date ASC,start_time ASC,id DESC');
    notes = await db.query('notes', orderBy: 'updated_at DESC');
    workouts = await db.query('workouts', orderBy: 'date DESC,id DESC');
    transactions = await db.query('transactions', orderBy: 'date DESC,id DESC');
    entertainment = await db.query('entertainment', orderBy: 'id DESC');
    theme = await _setting('theme');
    weekStart = int.tryParse(await _setting('week_start')) ?? 1;
    monthlyBudget = double.tryParse(await _setting('monthly_budget')) ?? 0;
    openingBalance = double.tryParse(await _setting('opening_balance')) ?? 0;
    monthStartDay =
        int.tryParse(await _setting('month_start_day'))?.clamp(1, 31) ?? 1;
    notifyListeners();
  }

  Future<void> save(
    String table,
    Map<String, dynamic> values, [
    int? id,
  ]) async {
    id == null
        ? await db.insert(table, values)
        : await db.update(table, values, where: 'id=?', whereArgs: [id]);
    await refresh();
  }

  Future<void> delete(String table, int id) async {
    await db.delete(table, where: 'id=?', whereArgs: [id]);
    await refresh();
  }

  Future<void> toggleTodo(Map<String, dynamic> item) async {
    if (item['kind'] == '计划') {
      final done = item['is_done'] != 1;
      await save('todos', {
        'is_done': done ? 1 : 0,
        'completed_at': done ? dayKey(DateTime.now()) : null,
      }, item['id'] as int);
      return;
    }
    final templateId = item['_template_id'] as int?;
    if (templateId != null) {
      final template = todoById(templateId);
      await db.insert('todos', {
        'title': template['title'],
        'date': item['date'],
        'start_time': template['start_time'],
        'end_time': template['end_time'],
        'priority': template['priority'],
        'is_done': 1,
        'repeat': '一次',
        'parent_id': templateId,
        'kind': '每日记录',
        'weekdays': template['weekdays'],
        'created_at': DateTime.now().toIso8601String(),
      });
      await refresh();
      return;
    }
    await save('todos', {
      'is_done': item['is_done'] == 1 ? 0 : 1,
    }, item['id'] as int);
  }

  Map<String, dynamic> todoById(int id) =>
      todos.firstWhere((item) => item['id'] == id);
  Future<void> deleteTodo(Map<String, dynamic> item) async {
    final isTemplate = item['kind'] == '每日' && item['parent_id'] == null;
    if (isTemplate) {
      await db.delete('todos', where: 'parent_id=?', whereArgs: [item['id']]);
    }
    await db.delete('todos', where: 'id=?', whereArgs: [item['id']]);
    await refresh();
  }

  Future<void> setTheme(String value) async {
    await _set('theme', value);
    await refresh();
  }

  Future<void> setWeekStart(int value) async {
    await _set('week_start', '$value');
    await refresh();
  }

  Future<void> setBudget(double value) async {
    await _set('monthly_budget', '$value');
    await refresh();
  }

  Future<void> setOpeningBalance(double value) async {
    await _set('opening_balance', '$value');
    await refresh();
  }

  Future<void> setCurrentBalance(double value) async {
    await setOpeningBalance(value - totalIncome + totalExpense);
  }

  Future<void> setMonthStartDay(int value) async {
    await _set('month_start_day', '$value');
    await refresh();
  }

  Future<void> updateFinanceSettings(
    double budget,
    double balance,
    int startDay,
  ) async {
    final adjustedOpeningBalance = balance - totalIncome + totalExpense;
    await db.transaction((txn) async {
      for (final entry in {
        'monthly_budget': '$budget',
        'opening_balance': '$adjustedOpeningBalance',
        'month_start_day': '$startDay',
      }.entries) {
        await txn.insert('settings', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    await refresh();
  }

  Future<void> clearAll() async {
    for (final table in [
      'todos',
      'notes',
      'workouts',
      'transactions',
      'entertainment',
    ]) {
      await db.delete(table);
    }
    await _set('monthly_budget', '0');
    await _set('opening_balance', '0');
    await _set('month_start_day', '1');
    await refresh();
  }

  List<Map<String, dynamic>> plansForDate(String date) {
    final plans = todos
        .where(
          (item) =>
              item['kind'] == '计划' &&
              (item['date'] as String).compareTo(date) <= 0,
        )
        .map(Map<String, dynamic>.from)
        .toList();
    plans.sort((a, b) {
      final completion = _completionOrder(a, b);
      if (completion != 0) return completion;
      final byDate = (a['date'] as String).compareTo(b['date'] as String);
      return byDate != 0 ? byDate : _timeOrder(a, b);
    });
    return plans;
  }

  List<Map<String, dynamic>> dailyForDate(String date) {
    final templates = todos.where(
      (item) =>
          item['kind'] == '每日' &&
          dailyRunsOnDate(
            item['date'] as String,
            item['weekdays'] as String,
            date,
          ),
    );
    final result = <Map<String, dynamic>>[];
    for (final template in templates) {
      if (template['date'] == date) {
        result.add(Map<String, dynamic>.from(template));
        continue;
      }
      final record = todos.where(
        (item) => item['parent_id'] == template['id'] && item['date'] == date,
      );
      if (record.isNotEmpty) {
        result.add(Map<String, dynamic>.from(record.first));
      } else {
        result.add({
          ...template,
          'date': date,
          'is_done': 0,
          '_template_id': template['id'],
        });
      }
    }
    result.sort((a, b) {
      final completion = _completionOrder(a, b);
      return completion != 0 ? completion : _timeOrder(a, b);
    });
    return result;
  }

  List<Map<String, dynamic>> todosForDate(String date) => [
    ...dailyForDate(date),
    ...plansForDate(date),
  ];

  List<Map<String, dynamic>> get todayTodos =>
      todosForDate(dayKey(DateTime.now()));
  DateTime get periodStart => periodStartFor(DateTime.now(), monthStartDay);
  DateTime get periodEnd => nextPeriodStart(periodStart, monthStartDay);
  List<Map<String, dynamic>> get monthTransactions => transactions
      .where(
        (x) =>
            (x['date'] as String).compareTo(dayKey(periodStart)) >= 0 &&
            (x['date'] as String).compareTo(dayKey(periodEnd)) < 0,
      )
      .toList();
  double get monthExpense => monthTransactions
      .where((x) => x['kind'] == '支出')
      .fold(0, (sum, x) => sum + (x['amount'] as num).toDouble());
  double get monthIncome => monthTransactions
      .where((x) => x['kind'] == '收入')
      .fold(0, (sum, x) => sum + (x['amount'] as num).toDouble());
  double get totalIncome => transactions
      .where((x) => x['kind'] == '收入')
      .fold(0, (sum, x) => sum + (x['amount'] as num).toDouble());
  double get totalExpense => transactions
      .where((x) => x['kind'] == '支出')
      .fold(0, (sum, x) => sum + (x['amount'] as num).toDouble());
  double get currentBalance => openingBalance + totalIncome - totalExpense;
  int get weeklyWorkouts {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: (now.weekday - weekStart + 7) % 7));
    return workouts
        .where((x) => !parseDay(x['date'] as String).isBefore(start))
        .length;
  }

  int get streak {
    final days = workouts.map((x) => x['date'] as String).toSet();
    var d = DateTime.now();
    var count = 0;
    while (days.contains(dayKey(d))) {
      count++;
      d = d.subtract(const Duration(days: 1));
    }
    return count;
  }
}

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';
DateTime parseDay(String s) => DateTime.parse(s);
String money(num value) => '¥${value.toStringAsFixed(2)}';

int _completionOrder(Map<String, dynamic> a, Map<String, dynamic> b) =>
    (a['is_done'] == 1 ? 1 : 0).compareTo(b['is_done'] == 1 ? 1 : 0);

int _timeInMinutes(Object? value) {
  if (value == null || value == '') return -1; // 全天安排排在具体时段之前。
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch('$value');
  if (match == null) return 1440;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return 1440;
  return hour * 60 + minute;
}

int _timeOrder(Map<String, dynamic> a, Map<String, dynamic> b) {
  final byTime = _timeInMinutes(a['start_time'])
      .compareTo(_timeInMinutes(b['start_time']));
  if (byTime != 0) return byTime;
  return (a['id'] as int? ?? 0).compareTo(b['id'] as int? ?? 0);
}

DateTime _cycleDay(int year, int month, int startDay) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, startDay.clamp(1, lastDay));
}

DateTime periodStartFor(DateTime now, int startDay) {
  final thisMonth = _cycleDay(now.year, now.month, startDay);
  return now.isBefore(thisMonth)
      ? _cycleDay(now.year, now.month - 1, startDay)
      : thisMonth;
}

DateTime nextPeriodStart(DateTime start, int startDay) =>
    _cycleDay(start.year, start.month + 1, startDay);

bool dailyRunsOnDate(String startDate, String weekdays, String date) =>
    startDate.compareTo(date) <= 0 &&
    weekdays.split(',').contains('${parseDay(date).weekday}');

const weekdayLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
String weekdaySummary(String value) {
  final days = value.split(',').toSet();
  if (days.length == 7) return '每天';
  if (days.length == 5 && ['1', '2', '3', '4', '5'].every(days.contains))
    return '工作日';
  return [
    for (var day = 1; day <= 7; day++)
      if (days.contains('$day')) weekdayLabels[day - 1],
  ].join('、');
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store});
  final UniverseStore store;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(store: widget.store, onGo: (i) => setState(() => index = i)),
      PlanPage(store: widget.store),
      FitnessPage(store: widget.store),
      FinancePage(store: widget.store),
      MorePage(store: widget.store),
    ];
    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.check_circle_outline),
            label: '安排',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            label: '健身',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: '收支',
          ),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: '更多'),
        ],
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (action != null) action!,
      ],
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
    child: Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.button,
    required this.onTap,
  });
  final IconData icon;
  final String title, button;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.add),
            label: Text(button),
          ),
        ],
      ),
    ),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.store, required this.onGo});
  final UniverseStore store;
  final ValueChanged<int> onGo;
  @override
  Widget build(BuildContext context) {
    final plans = store.todayTodos;
    final done = plans.where((x) => x['is_done'] == 1).length;
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        PageHeader(
          '每日小宇宙',
          subtitle: '${DateTime.now().month}月${DateTime.now().day}日 · 把注意力留给今天',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TodayHero(
            done: done,
            total: plans.length,
            onTap: () => onGo(1),
          ),
        ),
        const SectionLabel('快速备忘录'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: NoteCard(store: store),
        ),
        const SectionLabel('生活摘要'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.35,
            children: [
              SummaryCard(
                icon: Icons.directions_run_rounded,
                color: const Color(0xFF347D68),
                label: '本周运动',
                value: '${store.weeklyWorkouts} 次',
                note: store.streak > 0 ? '连续 ${store.streak} 天' : '今天也可以开始',
                onTap: () => onGo(2),
              ),
              SummaryCard(
                icon: Icons.pie_chart_outline,
                color: const Color(0xFF9B633E),
                label: '本期支出',
                value: money(store.monthExpense),
                note: store.monthlyBudget > 0
                    ? '预算余 ${money(store.monthlyBudget - store.monthExpense)}'
                    : '尚未设预算',
                onTap: () => onGo(3),
              ),
              SummaryCard(
                icon: Icons.sports_esports_outlined,
                color: const Color(0xFF6656A8),
                label: '待娱乐内容',
                value:
                    '${store.entertainment.where((x) => x['status'] != '已完成').length} 项',
                note: '留给放松的时间',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EntertainmentPage(store: store),
                  ),
                ),
              ),
              SummaryCard(
                icon: Icons.task_alt_outlined,
                color: const Color(0xFF27628A),
                label: '今日完成',
                value: '$done / ${plans.length}',
                note: plans.isEmpty ? '添加第一件事' : '稳步推进',
                onTap: () => onGo(1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class TodayHero extends StatelessWidget {
  const TodayHero({
    super.key,
    required this.done,
    required this.total,
    required this.onTap,
  });
  final int done, total;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = total == 0 ? 0.0 : done / total;
    return Card(
      color: Theme.of(context).colorScheme.primary,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今日安排',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      total == 0 ? '今天还没有安排' : '已完成 $done / $total',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: p,
                        minHeight: 7,
                        backgroundColor: Colors.white24,
                        color: const Color(0xFF8BCAE7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NoteCard extends StatefulWidget {
  const NoteCard({super.key, required this.store});
  final UniverseStore store;
  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  late final TextEditingController controller;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(
      text: widget.store.notes.isEmpty
          ? ''
          : widget.store.notes.first['content'] as String,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: '记下一闪而过的想法……',
              border: InputBorder.none,
              filled: false,
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              final content = controller.text.trim();
              if (content.isEmpty && widget.store.notes.isEmpty) return;
              await widget.store.save(
                'notes',
                {
                  'content': content,
                  'updated_at': DateTime.now().toIso8601String(),
                },
                widget.store.notes.isEmpty
                    ? null
                    : widget.store.notes.first['id'] as int,
              );
              if (mounted) toast(context, '备忘录已保存');
            },
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.note,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String label, value, note;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const Spacer(),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            Text(
              note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}

class PlanPage extends StatefulWidget {
  const PlanPage({super.key, required this.store});
  final UniverseStore store;
  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  late DateTime selectedDate;
  bool showDaily = true;
  @override
  void initState() {
    super.initState();
    selectedDate = DateTime.now();
  }

  Future<void> _pickDate(BuildContext pageContext) async {
    final date = await showDatePicker(
      context: pageContext,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) setState(() => selectedDate = date);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final items = showDaily
        ? store.dailyForDate(dayKey(selectedDate))
        : store.plansForDate(dayKey(selectedDate));
    final isToday = dayKey(selectedDate) == dayKey(DateTime.now());
    final completed = items.where((item) => item['is_done'] == 1).length;
    return Scaffold(
      body: Column(
        children: [
          PageHeader(
            showDaily ? '每日安排' : '待办事项',
            subtitle:
                '${selectedDate.month}月${selectedDate.day}日 · ${items.isEmpty ? '从一件小事开始' : '完成 $completed / ${items.length}'}',
            action: isToday
                ? null
                : TextButton(
                    onPressed: () =>
                        setState(() => selectedDate = DateTime.now()),
                    child: const Text('今天'),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('每日安排'),
                  selected: showDaily,
                  onSelected: (_) => setState(() => showDaily = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('待办事项'),
                  selected: !showDaily,
                  onSelected: (_) => setState(() => showDaily = false),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => setState(
                      () => selectedDate = selectedDate.subtract(
                        const Duration(days: 1),
                      ),
                    ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(context),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.calendar_month_outlined, size: 19),
                            const SizedBox(width: 8),
                            Text(
                              '${selectedDate.year}年${selectedDate.month}月${selectedDate.day}日',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(
                      () => selectedDate = selectedDate.add(
                        const Duration(days: 1),
                      ),
                    ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.event_available_outlined,
                    title: showDaily
                        ? '这一天没有每日安排'
                        : isToday
                        ? '今天还没有待办事项'
                        : '这一天还没有待办事项',
                    button: showDaily ? '添加每日安排' : '添加待办事项',
                    onTap: () => todoEditor(
                      context,
                      store,
                      null,
                      selectedDate,
                      showDaily,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) =>
                        TodoTile(store: store, item: items[i]),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            todoEditor(context, store, null, selectedDate, showDaily),
        icon: const Icon(Icons.add),
        label: Text(showDaily ? '添加每日安排' : '添加待办事项'),
      ),
    );
  }
}

class TodoTile extends StatelessWidget {
  const TodoTile({super.key, required this.store, required this.item});
  final UniverseStore store;
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) {
    final recurring = item['kind'] != '计划';
    final templateId = item['_template_id'] ?? item['parent_id'];
    final editable = templateId == null
        ? item
        : store.todoById(templateId as int);
    return Opacity(
      opacity: item['is_done'] == 1 ? 0.5 : 1,
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 4,
          ),
          leading: Checkbox(
            value: item['is_done'] == 1,
            onChanged: (_) => store.toggleTodo(item),
            shape: const CircleBorder(),
          ),
          title: Text(
            item['title'] as String,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              decoration: item['is_done'] == 1
                  ? TextDecoration.lineThrough
                  : null,
            ),
          ),
          subtitle: Text(
            '${item['start_time'] ?? '全天'}${item['end_time'] == null ? '' : ' – ${item['end_time']}'} · ${item['priority']}${recurring ? ' · ${weekdaySummary(editable['weekdays'] as String)}' : ''}',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: () => actions(
              context,
              onEdit: () => todoEditor(context, store, editable),
              deleteLabel: recurring ? '删除整项每日安排' : '删除',
              onDelete: () async {
                if (recurring) {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialog) => AlertDialog(
                      title: const Text('删除整项每日安排？'),
                      content: const Text('该安排和已保存的每日勾选记录都会删除。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialog, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                }
                await store.deleteTodo(editable);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class FitnessPage extends StatelessWidget {
  const FitnessPage({super.key, required this.store});
  final UniverseStore store;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        const PageHeader('健身计划', subtitle: '用身体的感受记录坚持'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Metric(label: '本周运动', value: '${store.weeklyWorkouts} 次'),
              const SizedBox(width: 12),
              Metric(label: '连续打卡', value: '${store.streak} 天'),
            ],
          ),
        ),
        const SectionLabel('训练记录'),
        Expanded(
          child: store.workouts.isEmpty
              ? EmptyState(
                  icon: Icons.fitness_center_outlined,
                  title: '记录你的第一次运动',
                  button: '添加打卡',
                  onTap: () => workoutEditor(context, store),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
                  itemCount: store.workouts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final x = store.workouts[i];
                    final note = x['note'] as String? ?? '';
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(workoutIcon(x['type'] as String)),
                        ),
                        title: Text(
                          x['type'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${x['date']} · ${x['duration']} 分钟${note.isEmpty ? '' : '\n$note'}',
                        ),
                        isThreeLine: note.isNotEmpty,
                        trailing: IconButton(
                          icon: const Icon(Icons.more_horiz),
                          onPressed: () => actions(
                            context,
                            onEdit: () => workoutEditor(context, store, x),
                            onDelete: () =>
                                store.delete('workouts', x['id'] as int),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => workoutEditor(context, store),
      icon: const Icon(Icons.add),
      label: const Text('运动打卡'),
    ),
  );
}

class Metric extends StatelessWidget {
  const Metric({super.key, required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}

class FinancePage extends StatefulWidget {
  const FinancePage({super.key, required this.store});
  final UniverseStore store;
  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  String filter = '全部';
  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final list = s.monthTransactions
        .where((x) => filter == '全部' || x['kind'] == filter)
        .toList();
    final remaining = s.monthlyBudget - s.monthExpense;
    return Scaffold(
      body: Column(
        children: [
          PageHeader(
            '收支情况',
            subtitle:
                '统计周期 ${dayKey(s.periodStart)} 至 ${dayKey(s.periodEnd.subtract(const Duration(days: 1)))}',
            action: IconButton(
              onPressed: () => budgetEditor(context, s),
              icon: const Icon(Icons.tune),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              color: Theme.of(context).colorScheme.primary,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前余额',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary
                            .withValues(alpha: .8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      money(s.currentBalance),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.monthlyBudget == 0
                          ? '本期预算尚未设置'
                          : '本期预算剩余 ${money(remaining)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary
                            .withValues(alpha: .78),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FinanceStat(
                            label: '本期收入',
                            value: money(s.monthIncome),
                          ),
                        ),
                        Expanded(
                          child: FinanceStat(
                            label: '本期支出',
                            value: money(s.monthExpense),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: ['全部', '收入', '支出']
                  .map(
                    (v) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(v),
                        selected: filter == v,
                        onSelected: (_) => setState(() => filter = v),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: '本期还没有${filter == '全部' ? '' : filter}流水',
                    button: '记一笔',
                    onTap: () => transactionEditor(context, s),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        TransactionTile(store: s, item: list[i]),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => transactionEditor(context, s),
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
    );
  }
}

class FinanceStat extends StatelessWidget {
  const FinanceStat({super.key, required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .7),
        ),
      ),
      Text(
        value,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.store, required this.item});
  final UniverseStore store;
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) {
    final income = item['kind'] == '收入';
    final note = item['note'] as String? ?? '';
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (income ? Colors.teal : Colors.orange).withValues(
            alpha: .16,
          ),
          child: Icon(
            income ? Icons.south_west : Icons.north_east,
            color: income ? Colors.teal : Colors.orange,
          ),
        ),
        title: Text(
          item['category'] as String,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('${item['date']}${note.isEmpty ? '' : ' · $note'}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${income ? '+' : '-'}${money(item['amount'] as num)}',
              style: TextStyle(
                color: income
                    ? Colors.teal
                    : Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_horiz),
              onPressed: () => actions(
                context,
                onEdit: () => transactionEditor(context, store, item),
                onDelete: () => store.delete('transactions', item['id'] as int),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MorePage extends StatelessWidget {
  const MorePage({super.key, required this.store});
  final UniverseStore store;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const PageHeader('更多', subtitle: '留出空间，也管理好自己的节奏'),
      const SectionLabel('娱乐与沉淀'),
      MenuCard(
        icon: Icons.sports_esports_outlined,
        title: '游戏娱乐',
        subtitle: '游戏、影视、书籍和其他内容',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EntertainmentPage(store: store)),
        ),
      ),
      const SectionLabel('数据与偏好'),
      MenuCard(
        icon: Icons.tune_outlined,
        title: '数据与设置',
        subtitle: '主题、周起始日与本机数据',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SettingsPage(store: store)),
        ),
      ),
      const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          '所有内容仅保存于这台设备，不会上传至网络。',
          style: TextStyle(color: Colors.grey),
        ),
      ),
    ],
  );
}

class MenuCard extends StatelessWidget {
  const MenuCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
    child: Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    ),
  );
}

class EntertainmentPage extends StatelessWidget {
  const EntertainmentPage({super.key, required this.store});
  final UniverseStore store;
  @override
  Widget build(BuildContext context) {
    const states = ['想体验', '进行中', '已完成'];
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('游戏娱乐'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '想体验'),
              Tab(text: '进行中'),
              Tab(text: '已完成'),
            ],
          ),
        ),
        body: TabBarView(
          children: states.map((state) {
            final list = store.entertainment
                .where((x) => x['status'] == state)
                .toList();
            return list.isEmpty
                ? EmptyState(
                    icon: Icons.auto_awesome_outlined,
                    title: state == '想体验' ? '收藏下一段放松时光' : '这里暂时是空的',
                    button: '添加内容',
                    onTap: () => entertainmentEditor(context, store),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final x = list[i];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(entertainmentIcon(x['kind'] as String)),
                          ),
                          title: Text(
                            x['title'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${x['kind']}${(x['progress'] as String? ?? '').isEmpty ? '' : ' · ${x['progress']}'}${x['rating'] == null ? '' : ' · ${x['rating']} 分'}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.more_horiz),
                            onPressed: () => actions(
                              context,
                              onEdit: () =>
                                  entertainmentEditor(context, store, x),
                              onDelete: () =>
                                  store.delete('entertainment', x['id'] as int),
                            ),
                          ),
                        ),
                      );
                    },
                  );
          }).toList(),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => entertainmentEditor(context, store),
          icon: const Icon(Icons.add),
          label: const Text('添加内容'),
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store});
  final UniverseStore store;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('数据与设置')),
    body: ListView(
      children: [
        const SectionLabel('显示偏好'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: ['system', 'light', 'dark']
                .map(
                  (v) => RadioListTile<String>(
                    value: v,
                    groupValue: store.theme,
                    onChanged: (x) => store.setTheme(x!),
                    title: Text(
                      v == 'system'
                          ? '跟随系统'
                          : v == 'light'
                          ? '浅色模式'
                          : '深色模式',
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SectionLabel('计划偏好'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: SwitchListTile(
            value: store.weekStart == 1,
            onChanged: (v) => store.setWeekStart(v ? 1 : 7),
            title: const Text('周一作为每周第一天'),
            subtitle: const Text('影响健身本周统计的起始日'),
          ),
        ),
        const SectionLabel('本机数据'),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('清空全部数据'),
            subtitle: const Text('此操作不可撤销，仅会清空这台设备上的内容'),
            onTap: () => confirmClear(context, store),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            '每日小宇宙不会登录、联网或同步数据。卸载应用或在系统设置中清除应用数据，会删除本机内容。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}

class DateField extends StatelessWidget {
  const DateField({super.key, required this.controller});
  final TextEditingController controller;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    readOnly: true,
    decoration: const InputDecoration(
      labelText: '日期',
      suffixIcon: Icon(Icons.calendar_today_outlined),
    ),
    onTap: () async {
      final value = await showDatePicker(
        context: context,
        initialDate: DateTime.tryParse(controller.text) ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (value != null) controller.text = dayKey(value);
    },
  );
}

Future<void> editor(
  BuildContext context, {
  required String title,
  required List<Widget> Function(void Function(void Function()) set) fields,
  required Future<bool> Function() save,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheet) => StatefulBuilder(
    builder: (sheet, set) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.of(sheet).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(sheet).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            ...fields(set).expand((x) => [x, const SizedBox(height: 10)]),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  if (await save() && sheet.mounted) Navigator.pop(sheet);
                },
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);
Future<void> todoEditor(
  BuildContext c,
  UniverseStore s, [
  Map<String, dynamic>? x,
  DateTime? initialDate,
  bool daily = false,
]) async {
  final title = TextEditingController(text: x?['title'] as String? ?? '');
  final date = TextEditingController(
    text: x?['date'] as String? ?? dayKey(initialDate ?? DateTime.now()),
  );
  final start = TextEditingController(text: x?['start_time'] as String? ?? '');
  final end = TextEditingController(text: x?['end_time'] as String? ?? '');
  var priority = x?['priority'] as String? ?? '普通';
  daily = x == null ? daily : x['kind'] == '每日';
  final selectedDays = (x?['weekdays'] as String? ?? '1,2,3,4,5,6,7')
      .split(',')
      .where((day) => day.isNotEmpty)
      .toSet();
  await editor(
    c,
    title: x == null
        ? daily
              ? '添加每日安排'
              : '添加待办事项'
        : daily
        ? '编辑每日安排'
        : '编辑待办事项',
    fields: (set) => [
      TextField(
        controller: title,
        decoration: const InputDecoration(labelText: '计划内容'),
      ),
      DateField(controller: date),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: start,
              decoration: const InputDecoration(labelText: '开始时间，如 09:00'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: end,
              decoration: const InputDecoration(labelText: '结束时间，如 10:00'),
            ),
          ),
        ],
      ),
      DropdownButtonFormField(
        value: priority,
        decoration: const InputDecoration(labelText: '优先级'),
        items: [
          '重要',
          '普通',
          '低',
        ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) => set(() => priority = v!),
      ),
      if (daily) ...[
        const Text('重复日期', style: TextStyle(fontWeight: FontWeight.w700)),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilterChip(
              label: const Text('工作日'),
              selected:
                  selectedDays.length == 5 &&
                  ['1', '2', '3', '4', '5'].every(selectedDays.contains),
              onSelected: (_) => set(() {
                selectedDays
                  ..clear()
                  ..addAll(['1', '2', '3', '4', '5']);
              }),
            ),
            FilterChip(
              label: const Text('每天'),
              selected: selectedDays.length == 7,
              onSelected: (_) => set(() {
                selectedDays
                  ..clear()
                  ..addAll(['1', '2', '3', '4', '5', '6', '7']);
              }),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (var day = 1; day <= 7; day++)
              FilterChip(
                label: Text(weekdayLabels[day - 1]),
                selected: selectedDays.contains('$day'),
                onSelected: (checked) => set(() {
                  if (checked) {
                    selectedDays.add('$day');
                  } else {
                    selectedDays.remove('$day');
                  }
                }),
              ),
          ],
        ),
      ],
    ],
    save: () async {
      if (title.text.trim().isEmpty || (daily && selectedDays.isEmpty))
        return false;
      await s.save('todos', {
        'title': title.text.trim(),
        'date': date.text,
        'start_time': start.text.isEmpty ? null : start.text,
        'end_time': end.text.isEmpty ? null : end.text,
        'priority': priority,
        'repeat': daily ? '每天' : '一次',
        'parent_id': x?['parent_id'],
        'kind': daily ? '每日' : '计划',
        'weekdays': (selectedDays.toList()..sort()).join(','),
        'completed_at': x?['completed_at'],
        'is_done': x?['is_done'] ?? 0,
        'created_at': x?['created_at'] ?? DateTime.now().toIso8601String(),
      }, x?['id'] as int?);
      return true;
    },
  );
}

Future<void> workoutEditor(
  BuildContext c,
  UniverseStore s, [
  Map<String, dynamic>? x,
]) async {
  final duration = TextEditingController(text: '${x?['duration'] ?? ''}');
  final date = TextEditingController(
    text: x?['date'] as String? ?? dayKey(DateTime.now()),
  );
  final note = TextEditingController(text: x?['note'] as String? ?? '');
  var type = x?['type'] as String? ?? '力量训练';
  await editor(
    c,
    title: x == null ? '运动打卡' : '编辑记录',
    fields: (set) => [
      DropdownButtonFormField(
        value: type,
        decoration: const InputDecoration(labelText: '运动类型'),
        items: [
          '力量训练',
          '跑步',
          '骑行',
          '瑜伽',
          '球类',
          '其他',
        ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) => set(() => type = v!),
      ),
      TextField(
        controller: duration,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: '运动时长（分钟）'),
      ),
      DateField(controller: date),
      TextField(
        controller: note,
        maxLines: 2,
        decoration: const InputDecoration(labelText: '训练感受（可选）'),
      ),
    ],
    save: () async {
      final value = int.tryParse(duration.text);
      if (value == null || value <= 0) return false;
      await s.save('workouts', {
        'type': type,
        'duration': value,
        'date': date.text,
        'note': note.text.trim(),
      }, x?['id'] as int?);
      return true;
    },
  );
}

Future<void> transactionEditor(
  BuildContext c,
  UniverseStore s, [
  Map<String, dynamic>? x,
]) async {
  final amount = TextEditingController(text: x?['amount']?.toString() ?? '');
  final category = TextEditingController(text: x?['category'] as String? ?? '');
  final date = TextEditingController(
    text: x?['date'] as String? ?? dayKey(DateTime.now()),
  );
  final note = TextEditingController(text: x?['note'] as String? ?? '');
  var kind = x?['kind'] as String? ?? '支出';
  await editor(
    c,
    title: x == null ? '记一笔' : '编辑流水',
    fields: (set) => [
      DropdownButtonFormField(
        value: kind,
        decoration: const InputDecoration(labelText: '类型'),
        items: [
          '支出',
          '收入',
        ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) => set(() => kind = v!),
      ),
      TextField(
        controller: amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: '金额（元）'),
      ),
      TextField(
        controller: category,
        decoration: const InputDecoration(labelText: '分类，如 餐饮 / 工资'),
      ),
      DateField(controller: date),
      TextField(
        controller: note,
        decoration: const InputDecoration(labelText: '备注（可选）'),
      ),
    ],
    save: () async {
      final value = double.tryParse(amount.text);
      if (value == null || value <= 0 || category.text.trim().isEmpty)
        return false;
      await s.save('transactions', {
        'kind': kind,
        'amount': value,
        'category': category.text.trim(),
        'date': date.text,
        'note': note.text.trim(),
      }, x?['id'] as int?);
      return true;
    },
  );
}

Future<void> entertainmentEditor(
  BuildContext c,
  UniverseStore s, [
  Map<String, dynamic>? x,
]) async {
  final title = TextEditingController(text: x?['title'] as String? ?? '');
  final progress = TextEditingController(text: x?['progress'] as String? ?? '');
  final rating = TextEditingController(text: x?['rating']?.toString() ?? '');
  final note = TextEditingController(text: x?['note'] as String? ?? '');
  var kind = x?['kind'] as String? ?? '游戏';
  var status = x?['status'] as String? ?? '想体验';
  await editor(
    c,
    title: x == null ? '添加娱乐内容' : '编辑娱乐内容',
    fields: (set) => [
      TextField(
        controller: title,
        decoration: const InputDecoration(labelText: '名称'),
      ),
      DropdownButtonFormField(
        value: kind,
        decoration: const InputDecoration(labelText: '类型'),
        items: [
          '游戏',
          '影视',
          '书籍',
          '其他',
        ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) => set(() => kind = v!),
      ),
      DropdownButtonFormField(
        value: status,
        decoration: const InputDecoration(labelText: '状态'),
        items: [
          '想体验',
          '进行中',
          '已完成',
        ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: (v) => set(() => status = v!),
      ),
      TextField(
        controller: progress,
        decoration: const InputDecoration(labelText: '进度，如 第 3 章 / 50%（可选）'),
      ),
      TextField(
        controller: rating,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: '评分 0–10（可选）'),
      ),
      TextField(
        controller: note,
        maxLines: 2,
        decoration: const InputDecoration(labelText: '感想（可选）'),
      ),
    ],
    save: () async {
      final rate = rating.text.isEmpty ? null : double.tryParse(rating.text);
      if (title.text.trim().isEmpty ||
          (rating.text.isNotEmpty && (rate == null || rate < 0 || rate > 10)))
        return false;
      await s.save('entertainment', {
        'title': title.text.trim(),
        'kind': kind,
        'status': status,
        'progress': progress.text.trim(),
        'rating': rate,
        'note': note.text.trim(),
      }, x?['id'] as int?);
      return true;
    },
  );
}

Future<void> budgetEditor(BuildContext c, UniverseStore s) async {
  final amount = TextEditingController(
    text: s.monthlyBudget == 0 ? '' : s.monthlyBudget.toStringAsFixed(0),
  );
  final balance = TextEditingController(
    text: s.currentBalance.toStringAsFixed(2),
  );
  var startDay = s.monthStartDay;
  await editor(
    c,
    title: '收支设置',
    fields: (set) => [
      TextField(
        controller: amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: '每期总预算（元）'),
        autofocus: true,
      ),
      TextField(
        controller: balance,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: '当前余额（元）',
          helperText: '可直接修正，之后仍随收入与支出变化',
        ),
      ),
      DropdownButtonFormField<int>(
        initialValue: startDay,
        decoration: const InputDecoration(
          labelText: '每月统计周期起始日',
          helperText: '例如选 15 日，则每期从 15 日起；短月自动取月末',
        ),
        items: [
          for (var day = 1; day <= 31; day++)
            DropdownMenuItem(value: day, child: Text('每月 $day 日')),
        ],
        onChanged: (value) {
          if (value != null) set(() => startDay = value);
        },
      ),
    ],
    save: () async {
      final budget = amount.text.trim().isEmpty
          ? 0.0
          : double.tryParse(amount.text);
      final balanceValue = double.tryParse(balance.text);
      if (budget == null ||
          !budget.isFinite ||
          budget < 0 ||
          balanceValue == null ||
          !balanceValue.isFinite)
        return false;
      await s.updateFinanceSettings(budget, balanceValue, startDay);
      return true;
    },
  );
}

void actions(
  BuildContext c, {
  required VoidCallback onEdit,
  required Future<void> Function() onDelete,
  String deleteLabel = '删除',
}) {
  showModalBottomSheet(
    context: c,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('编辑'),
            onTap: () {
              Navigator.pop(sheet);
              onEdit();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: Text(deleteLabel, style: const TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(sheet);
              await onDelete();
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> confirmClear(BuildContext c, UniverseStore s) async {
  final yes = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      title: const Text('清空所有数据？'),
      content: const Text('计划、备忘录、健身、收支和娱乐记录将被永久删除，且无法恢复。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(d, true),
          child: const Text('确认清空'),
        ),
      ],
    ),
  );
  if (yes == true) {
    await s.clearAll();
    if (c.mounted) toast(c, '本机数据已清空');
  }
}

void toast(BuildContext c, String message) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(message)));
IconData workoutIcon(String t) => t == '跑步'
    ? Icons.directions_run
    : t == '骑行'
    ? Icons.directions_bike
    : t == '瑜伽'
    ? Icons.self_improvement
    : t == '球类'
    ? Icons.sports_basketball_outlined
    : Icons.fitness_center;
IconData entertainmentIcon(String t) => t == '游戏'
    ? Icons.sports_esports_outlined
    : t == '影视'
    ? Icons.movie_outlined
    : t == '书籍'
    ? Icons.menu_book_outlined
    : Icons.auto_awesome_outlined;
