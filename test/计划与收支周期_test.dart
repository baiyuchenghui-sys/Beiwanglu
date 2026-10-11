import 'package:daily_little_universe/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('未勾选的计划从开始日期起持续出现', () {
    final store = UniverseStore();
    store.todos = [
      {
        'id': 1,
        'kind': '计划',
        'date': '2026-10-03',
        'title': '长期计划',
        'is_done': 0,
      },
    ];

    expect(store.plansForDate('2026-10-02'), isEmpty);
    expect(store.plansForDate('2026-10-03'), hasLength(1));
    expect(store.plansForDate('2026-11-01'), hasLength(1));
  });

  test('工作日安排只从开始日期起在周一至周五出现', () {
    expect(dailyRunsOnDate('2026-10-05', '1,2,3,4,5', '2026-10-04'), isFalse);
    expect(dailyRunsOnDate('2026-10-05', '1,2,3,4,5', '2026-10-05'), isTrue);
    expect(dailyRunsOnDate('2026-10-05', '1,2,3,4,5', '2026-10-10'), isFalse);
    expect(dailyRunsOnDate('2026-10-05', '2,4', '2026-10-08'), isTrue);
  });

  test('每日安排按开始时间升序排列，完成项排在未完成项后面', () {
    final store = UniverseStore();
    store.todos = [
      {
        'id': 10,
        'kind': '每日',
        'date': '2026-10-01',
        'title': '晚间阅读',
        'weekdays': '1,2,3,4,5,6,7',
        'start_time': '20:00',
        'is_done': 0,
      },
      {
        'id': 20,
        'kind': '每日',
        'date': '2026-10-01',
        'title': '早晨散步',
        'weekdays': '1,2,3,4,5,6,7',
        'start_time': '08:30',
        'is_done': 0,
      },
      {
        'id': 30,
        'kind': '每日',
        'date': '2026-10-01',
        'title': '全天喝水',
        'weekdays': '1,2,3,4,5,6,7',
        'start_time': null,
        'is_done': 0,
      },
      {
        'id': 40,
        'kind': '每日',
        'date': '2026-10-01',
        'title': '已完成晨练',
        'weekdays': '1,2,3,4,5,6,7',
        'start_time': '06:00',
        'is_done': 0,
      },
      {
        'id': 41,
        'kind': '每日记录',
        'parent_id': 40,
        'date': '2026-10-02',
        'title': '已完成晨练',
        'start_time': '06:00',
        'is_done': 1,
      },
    ];

    final items = store.dailyForDate('2026-10-02');
    expect(items.map((item) => item['title']), [
      '全天喝水',
      '早晨散步',
      '晚间阅读',
      '已完成晨练',
    ]);
    expect(items.last['is_done'], 1);
  });

  test('待办事项中已勾选项排在所有未勾选项后面', () {
    final store = UniverseStore();
    store.todos = [
      {
        'id': 1,
        'kind': '计划',
        'date': '2026-10-01',
        'title': '已完成的旧事项',
        'start_time': '07:00',
        'is_done': 1,
      },
      {
        'id': 2,
        'kind': '计划',
        'date': '2026-10-02',
        'title': '待处理的新事项',
        'start_time': '18:00',
        'is_done': 0,
      },
    ];

    expect(store.plansForDate('2026-10-02').map((item) => item['title']), [
      '待处理的新事项',
      '已完成的旧事项',
    ]);
  });

  test('每月 31 日起算时，短月使用月末', () {
    final start = periodStartFor(DateTime(2026, 3, 1), 31);
    expect(dayKey(start), '2026-02-28');
    expect(dayKey(nextPeriodStart(start, 31)), '2026-03-31');
    expect(dayKey(periodStartFor(DateTime(2026, 3, 31), 31)), '2026-03-31');
  });
}
