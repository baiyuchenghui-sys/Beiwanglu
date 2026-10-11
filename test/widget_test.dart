import 'package:daily_little_universe/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('首页显示自定义励志话语并提供编辑入口', (tester) async {
    final store = UniverseStore()..homeMotto = '今天也要向前一步';

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(store: store, onGo: (_) {}),
      ),
    );
    expect(find.text('今天也要向前一步'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑励志话语'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '写一句鼓励自己的话'), findsOneWidget);
    expect(find.text('今天也要向前一步'), findsWidgets);
  });

  testWidgets('安排页先显示每日安排，且切换项位于待办事项之前', (tester) async {
    final store = UniverseStore();
    final today = dayKey(DateTime.now());
    store.todos = [
      {
        'id': 1,
        'title': '长期目标',
        'date': today,
        'start_time': null,
        'end_time': null,
        'priority': '普通',
        'is_done': 0,
        'kind': '计划',
        'parent_id': null,
      },
      {
        'id': 2,
        'title': '每天阅读',
        'date': today,
        'start_time': null,
        'end_time': null,
        'priority': '普通',
        'is_done': 0,
        'kind': '每日',
        'weekdays': '1,2,3,4,5,6,7',
        'parent_id': null,
      },
    ];

    await tester.pumpWidget(MaterialApp(home: PlanPage(store: store)));
    final dailyChip = find.widgetWithText(ChoiceChip, '每日安排');
    final planChip = find.widgetWithText(ChoiceChip, '待办事项');
    expect(
      tester.getTopLeft(dailyChip).dx,
      lessThan(tester.getTopLeft(planChip).dx),
    );
    expect(tester.widget<ChoiceChip>(dailyChip).selected, isTrue);
    expect(find.text('每天阅读'), findsOneWidget);
    expect(find.text('长期目标'), findsNothing);

    await tester.tap(planChip);
    await tester.pump();
    expect(find.text('长期目标'), findsOneWidget);
    expect(find.text('每天阅读'), findsNothing);
  });

  testWidgets('过去开始的待办事项不显示逾期标记', (tester) async {
    final store = UniverseStore();
    final yesterday = dayKey(DateTime.now().subtract(const Duration(days: 1)));
    store.todos = [
      {
        'id': 1,
        'title': '尚未完成的事情',
        'date': yesterday,
        'start_time': '09:00',
        'end_time': null,
        'priority': '普通',
        'is_done': 0,
        'kind': '计划',
        'parent_id': null,
      },
    ];

    await tester.pumpWidget(MaterialApp(home: PlanPage(store: store)));
    await tester.tap(find.widgetWithText(ChoiceChip, '待办事项'));
    await tester.pump();

    expect(find.text('尚未完成的事情'), findsOneWidget);
    expect(find.textContaining('逾期'), findsNothing);
  });
}
