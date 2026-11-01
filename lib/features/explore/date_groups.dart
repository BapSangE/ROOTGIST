import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_pressable.dart';

// 탐색 목록을 날짜로 묶는다(사용자 요청 2026-11-01). 최근 7일은 하루씩, 그보다 앞의 이번 달은 한 주(월~일)씩,
// 지난달부터는 한 달씩, 지난해부터는 한 해씩(아직 1년치가 없어 해 묶음은 기능만 있다). 기준은 한국 시간.
// 하루 묶음은 펼쳐 두고 주·달·해 묶음은 머리만 보이다 누르면 펼친다(하루 묶음이 없으면 맨 위 묶음을 펼친다).
// 펼친 묶음도 앞 [fold]개만 보이고 나머지는 「N건 더 보기」로 그 자리에서 연다. 펼치고 접기는 220ms(동작 줄이기면 바로) + 선택 틱.

enum DateUnit { day, week, month, year }

typedef DateKey = (DateUnit, DateTime);

class DateGroup<T> {
  DateGroup(this.unit, this.start, this.rows);
  final DateUnit unit;
  final DateTime start; // 그 날·주(월요일)·달(1일)·해(1월 1일)의 0시, 한국 날짜를 UTC 값으로
  final List<T> rows;
  DateKey get key => (unit, start);
}

DateTime _kstDay(DateTime utc) {
  final k = utc.toUtc().add(const Duration(hours: 9));
  return DateTime.utc(k.year, k.month, k.day);
}

/// 그 주 월요일(한국 날짜)
DateTime weekStart(DateTime utc) {
  final day = _kstDay(utc);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// 글 하나가 들어갈 묶음
DateKey dateKey(DateTime at, DateTime now) {
  final day = _kstDay(at), today = _kstDay(now);
  if (today.difference(day).inDays < 7) return (DateUnit.day, day);
  if (day.year == today.year && day.month == today.month) return (DateUnit.week, weekStart(at));
  if (day.year == today.year) return (DateUnit.month, DateTime.utc(day.year, day.month));
  return (DateUnit.year, DateTime.utc(day.year));
}

/// 묶는다. 묶음은 최근부터(하루 → 주 → 달 → 해 순으로 자연히 이어진다), 묶음 안은 받은 순서 그대로(점수 순·최신순은 부르는 쪽이 정한다)
List<DateGroup<T>> groupByDate<T>(Iterable<T> items, DateTime Function(T) at, DateTime now) {
  final out = <DateKey, List<T>>{};
  for (final i in items) {
    out.putIfAbsent(dateKey(at(i), now), () => []).add(i);
  }
  final keys = out.keys.toList()..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final k in keys) DateGroup(k.$1, k.$2, out[k]!)];
}

const _weekdays = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];

/// 머리 글자: (굵은 이름, 옆의 옅은 범위). 「오늘」 「어제」 「10월 28일 수요일」 / 「지난주 10월 19일 ~ 10월 25일」 / 「9월」 / 「2025년」
(String, String?) dateLabel(DateGroup g, DateTime now) {
  final s = g.start;
  switch (g.unit) {
    case DateUnit.day:
      return (switch (_kstDay(now).difference(s).inDays) { 0 => '오늘', 1 => '어제', _ => '${s.month}월 ${s.day}일 ${_weekdays[s.weekday - 1]}' }, null);
    case DateUnit.week:
      final e = s.add(const Duration(days: 6));
      final range = '${s.month}월 ${s.day}일 ~ ${e.month}월 ${e.day}일';
      return weekStart(now).difference(s).inDays == 7 ? ('지난주', range) : (range, null);
    case DateUnit.month:
      return ('${s.month}월', null);
    case DateUnit.year:
      return ('${s.year}년', null);
  }
}

class DateGroups<T> extends StatefulWidget {
  const DateGroups({super.key, required this.items, required this.at, required this.now, required this.builder, this.fold = 5});
  final List<T> items;
  final DateTime Function(T) at;
  final DateTime now;
  final Widget Function(BuildContext context, List<T> rows) builder; // 한 묶음의 보이는 행들 → 카드(들)
  final int fold; // 펼친 묶음에서 처음 보이는 개수. 1개만 남으면 접지 않는다

  @override
  State<DateGroups<T>> createState() => _DateGroupsState<T>();
}

class _DateGroupsState<T> extends State<DateGroups<T>> {
  final _open = <DateKey>{}; // 펼친 주·달·해
  final _all = <DateKey>{}; // 「더 보기」로 다 연 묶음

  void _toggle(Set<DateKey> set, DateKey k) {
    HapticFeedback.selectionClick();
    setState(() => set.contains(k) ? set.remove(k) : set.add(k));
  }

  @override
  Widget build(BuildContext context) {
    final d = RgMotion.of(context, RgMotion.base);
    final groups = groupByDate(widget.items, widget.at, widget.now);
    final noDays = groups.every((g) => g.unit != DateUnit.day);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, g) in groups.indexed) ...() {
        final fixed = g.unit == DateUnit.day || (noDays && i == 0); // 늘 펼친 묶음(누르지 않는다)
        final open = fixed || _open.contains(g.key);
        final more = g.rows.length > widget.fold + 1 ? g.rows.length - widget.fold : 0;
        final all = _all.contains(g.key);
        final (label, range) = dateLabel(g, widget.now);
        return [
          DateHeader(label: label, range: range, count: g.rows.length, open: open, onTap: fixed ? null : () => _toggle(_open, g.key)),
          AnimatedSize(
            duration: d,
            curve: RgMotion.curve,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    widget.builder(context, more > 0 && !all ? g.rows.take(widget.fold).toList() : g.rows),
                    if (more > 0) _MoreButton(open: all, more: more, onTap: () => _toggle(_all, g.key)),
                  ]),
          ),
        ];
      }(),
    ]);
  }
}

// 묶음 머리: 「어제 ……… 4건」 「지난주  10월 19일 ~ 10월 25일 ……… 12건 ⌄」. 접히는 묶음은 누르면 펼친다
class DateHeader extends StatelessWidget {
  const DateHeader({super.key, required this.label, this.range, required this.count, required this.open, this.onTap});
  final String label;
  final String? range;
  final int count;
  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final d = RgMotion.of(context, RgMotion.base);
    final row = Container(
      constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
      padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s24, RgSpace.gutterText, RgSpace.s12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: RgSpace.s8, children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: label, style: RgText.titleList.copyWith(fontWeight: FontWeight.w700, color: RgColors.textPrimary)),
                if (range != null) TextSpan(text: '  $range', style: RgText.meta.copyWith(color: RgColors.textSecondary)),
              ]),
            ),
          ),
        ),
        Text('$count건', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
        if (onTap != null)
          AnimatedRotation(
            turns: open ? -0.25 : 0.25, // 펼침 ▲ / 접힘 ▼
            duration: d,
            curve: RgMotion.curve,
            child: RgIcon('chevron-right', size: 16, color: RgColors.textSecondary),
          ),
      ]),
    );
    if (onTap == null) return row;
    return Semantics(button: true, expanded: open, child: RgPressable(onTap: onTap, child: row));
  }
}

// 카드 아래 가운데 흰 알약 「N건 더 보기 ⌄」 / 「접기 ⌃」(누르는 높이 44)
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.open, required this.more, required this.onTap});
  final bool open;
  final int more;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = RgMotion.of(context, RgMotion.base);
    return Padding(
      padding: const EdgeInsets.only(top: RgSpace.s12),
      child: Center(
        child: Semantics(
          button: true,
          expanded: open,
          child: RgPressable(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
              padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20),
              decoration: BoxDecoration(color: RgColors.surfaceCard, borderRadius: BorderRadius.circular(RgRadius.pill), boxShadow: RgShadow.card),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: RgSpace.s4, children: [
                Flexible(child: Text(open ? '접기' : '$more건 더 보기', style: RgText.meta.copyWith(fontWeight: FontWeight.w600, color: RgColors.textBody))),
                AnimatedRotation(
                  turns: open ? -0.25 : 0.25,
                  duration: d,
                  curve: RgMotion.curve,
                  child: RgIcon('chevron-right', size: 16, color: RgColors.textBody),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
