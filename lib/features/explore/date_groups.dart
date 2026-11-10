import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_underline_tabs.dart';

// 탐색 목록을 날짜로 묶는다(사용자 요청 2026-11-01). 최근 7일은 하루씩, 그보다 앞의 이번 달은 한 주(월~일)씩,
// 지난달부터는 한 달씩, 지난해부터는 한 해씩(아직 1년치가 없어 해 묶음은 기능만 있다). 기준은 한국 시간.
// 하루 묶음은 펼쳐 두고 글 카드를 바로 보인다. 주·달·해 묶음은 「지난 논문」처럼 머리(「2026년 10월 · 12일치」)만 보이다 누르면
// 날짜 줄(큰 날짜 숫자·요일, 「5건 · OpenAI 외」)을 흰 카드에 모아 펼치고, 날짜 줄을 누르면 그날 글 카드가 그 자리에서 펼쳐진다
// (사용자 요청 2026-11-01). 하루 묶음이 없으면 맨 위 묶음을 펼쳐 둔다.
// 펼친 하루도 앞 [fold]개만 보이고 나머지는 「N건 더 보기」로 그 자리에서 연다. 펼치고 접기는 220ms(동작 줄이기면 바로) + 선택 틱.

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
  if (day.year == today.year && day.month == today.month) {
    return (DateUnit.week, weekStart(at));
  }
  if (day.year == today.year) {
    return (DateUnit.month, DateTime.utc(day.year, day.month));
  }
  return (DateUnit.year, DateTime.utc(day.year));
}

/// 묶는다. 묶음은 최근부터(하루 → 주 → 달 → 해 순으로 자연히 이어진다), 묶음 안은 받은 순서 그대로(점수 순·최신순은 부르는 쪽이 정한다)
List<DateGroup<T>> groupByDate<T>(
  Iterable<T> items,
  DateTime Function(T) at,
  DateTime now,
) {
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
      return (
        switch (_kstDay(now).difference(s).inDays) {
          0 => '오늘',
          1 => '어제',
          _ => '${s.month}월 ${s.day}일 ${_weekdays[s.weekday - 1]}',
        },
        null,
      );
    case DateUnit.week:
      final e = s.add(const Duration(days: 6));
      final range = '${s.month}월 ${s.day}일 ~ ${e.month}월 ${e.day}일';
      return weekStart(now).difference(s).inDays == 7
          ? ('지난주', range)
          : (range, null);
    case DateUnit.month:
      return ('${s.year}년 ${s.month}월', null);
    case DateUnit.year:
      return ('${s.year}년', null);
  }
}

class DateGroups<T> extends StatefulWidget {
  const DateGroups({
    super.key,
    required this.items,
    required this.at,
    required this.now,
    required this.builder,
    this.tag,
    this.fold = 5,
    this.showDayHeaders = true,
  });
  final List<T> items;
  final DateTime Function(T) at;
  final String Function(T)?
  tag; // 날짜 줄의 「OpenAI 외」에 쓸 이름(출처 등). 그날 가장 많은 이름, 같으면 앞의 것
  final DateTime now;
  final Widget Function(BuildContext context, List<T> rows)
  builder; // 한 묶음의 보이는 행들 → 카드(들)
  final int fold; // 펼친 하루에서 처음 보이는 개수. 1개만 남으면 접지 않는다
  final bool showDayHeaders; // 간결한 카드 목록에서도 지난 주·달 펼침 동작은 유지한다

  @override
  State<DateGroups<T>> createState() => _DateGroupsState<T>();
}

class _DateGroupsState<T> extends State<DateGroups<T>> {
  final _open = <DateKey>{}; // 펼친 주·달·해와 그 안에서 펼친 날
  final _all = <DateKey>{}; // 「더 보기」로 다 연 묶음
  var _seeded = false; // 최근 7일 글이 없으면 처음 한 번 맨 위 날을 펼쳐 둔다(빈 날짜 줄만 보이지 않게)
  final _nextKey = GlobalKey(); // 맨 위 날의 「다른 날짜 보기」가 미끄러져 갈 두 번째 묶음

  // 시안: 맨 위 날짜 오른쪽 「다른 날짜 보기 ›」 → 다음 날짜 묶음으로 부드럽게 스크롤(동작 줄이기면 바로)
  void _toNext() {
    final target = _nextKey.currentContext;
    if (target == null) return;
    HapticFeedback.selectionClick();
    Scrollable.ensureVisible(
      target,
      duration: RgMotion.of(context, RgMotion.base),
      curve: RgMotion.curve,
    );
  }

  void _toggle(Set<DateKey> set, DateKey k) {
    HapticFeedback.selectionClick();
    setState(() => set.contains(k) ? set.remove(k) : set.add(k));
  }

  @override
  Widget build(BuildContext context) {
    final d = RgMotion.of(context, RgMotion.base);
    final groups = groupByDate(widget.items, widget.at, widget.now);
    final noDays = groups.every((g) => g.unit != DateUnit.day);
    if (!_seeded && groups.isNotEmpty) {
      _seeded = true;
      if (noDays) _open.add((DateUnit.day, _byDay(groups.first.rows).first.$1));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, g) in groups.indexed)
          ...() {
            final (label, range) = dateLabel(g, widget.now);
            if (g.unit == DateUnit.day) {
              return [
                if (widget.showDayHeaders)
                  DateHeader(
                    key: i == 1 ? _nextKey : null,
                    label: '${g.start.month}월 ${g.start.day}일',
                    range: range,
                    count: '${g.rows.length}건',
                    open: true,
                    onMore: i == 0 && groups.length > 1 ? _toNext : null,
                  ),
                if (widget.showDayHeaders)
                  _rows(g.key, g.rows)
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: RgSpace.s12),
                    child: _rows(g.key, g.rows),
                  ),
              ];
            }
            final fixed = noDays && i == 0; // 늘 펼친 묶음(누르지 않는다)
            final open = fixed || _open.contains(g.key);
            final days = _byDay(g.rows);
            return [
              DateHeader(
                key: i == 1 ? _nextKey : null,
                label: label,
                range: range,
                count: '${days.length}일치',
                open: open,
                onTap: fixed ? null : () => _toggle(_open, g.key),
              ),
              AnimatedSize(
                duration: d,
                curve: RgMotion.curve,
                alignment: Alignment.topCenter,
                child: open
                    ? _days(days)
                    : const SizedBox(width: double.infinity),
              ),
            ];
          }(),
      ],
    );
  }

  // 한 묶음 안을 한국 날짜로 나눈다(최근 날부터, 날 안은 받은 순서)
  List<(DateTime, List<T>)> _byDay(List<T> rows) {
    final out = <DateTime, List<T>>{};
    for (final r in rows) {
      out.putIfAbsent(_kstDay(widget.at(r)), () => []).add(r);
    }
    final keys = out.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final k in keys) (k, out[k]!)];
  }

  // 날짜 줄을 흰 카드에 모은다. 펼친 날은 그 줄에서 카드를 끊고 아래에 그날 글 카드를 놓은 뒤 남은 줄로 카드를 다시 잇는다(카드 안에 카드를 겹치지 않게)
  Widget _days(List<(DateTime, List<T>)> days) {
    final out = <Widget>[];
    var run = <Widget>[];
    void flush() {
      if (run.isEmpty) return;
      out.add(RgCard(child: Column(children: run)));
      run = [];
    }

    for (final (j, (day, rows)) in days.indexed) {
      final key = (DateUnit.day, day);
      final open = _open.contains(key);
      run.add(
        _DayLine(
          day: day,
          count: rows.length,
          sub: _summary(rows),
          open: open,
          last: open || j == days.length - 1,
          onTap: () => _toggle(_open, key),
        ),
      );
      if (open) {
        flush();
        out.add(
          Padding(
            padding: const EdgeInsets.only(
              top: RgSpace.s12,
              bottom: RgSpace.s20,
            ),
            child: _rows(key, rows),
          ),
        );
      }
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: out,
    );
  }

  // 「OpenAI 외」: 그날 가장 많은 이름(같으면 앞의 것), 다른 이름이 더 있으면 「외」
  String? _summary(List<T> rows) {
    final tag = widget.tag;
    if (tag == null) return null;
    final counts = <String, int>{};
    for (final r in rows) {
      counts.update(tag(r), (c) => c + 1, ifAbsent: () => 1);
    }
    final top = counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    return counts.length > 1 ? '$top 외' : top;
  }

  // 하루치 글 카드: 앞 [fold]개 + 「N건 더 보기」
  Widget _rows(DateKey key, List<T> rows) {
    final more = rows.length > widget.fold + 1 ? rows.length - widget.fold : 0;
    final all = _all.contains(key);
    return AnimatedSize(
      duration: RgMotion.of(context, RgMotion.base),
      curve: RgMotion.curve,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.builder(
            context,
            more > 0 && !all ? rows.take(widget.fold).toList() : rows,
          ),
          if (more > 0)
            _MoreButton(open: all, more: more, onTap: () => _toggle(_all, key)),
        ],
      ),
    );
  }
}

// 날짜 줄(「지난 논문」의 날짜 줄과 같은 모양): 왼쪽 큰 날짜 숫자 + 요일, 가운데 「5건」 + 「OpenAI 외」, 오른쪽 ⌄(누르면 그날 글이 펼쳐져 ⌃)
class _DayLine extends StatelessWidget {
  const _DayLine({
    required this.day,
    required this.count,
    this.sub,
    required this.open,
    required this.last,
    required this.onTap,
  });
  final DateTime day;
  final int count;
  final String? sub;
  final bool open;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final weekday = _weekdays[day.weekday - 1];
    return Semantics(
      label:
          '${day.month}월 ${day.day}일 $weekday, $count건${sub == null ? '' : ', $sub'}',
      expanded: open,
      excludeSemantics: true,
      child: RgListRow(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        crossAxisAlignment: CrossAxisAlignment.center,
        showDivider: !last,
        onTap: onTap,
        trailing: Padding(
          padding: const EdgeInsets.only(left: RgSpace.s4),
          child: AnimatedRotation(
            turns: open ? -0.25 : 0.25, // 펼침 ▲ / 접힘 ▼
            duration: RgMotion.of(context, RgMotion.base),
            curve: RgMotion.curve,
            child: RgIcon(
              'chevron-right',
              size: 20,
              color: RgColors.textTertiary,
            ),
          ),
        ),
        child: Row(
          spacing: RgSpace.s16,
          children: [
            SizedBox(
              width: 46,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${day.day}',
                    style: RgText.titleDetail.copyWith(
                      fontSize: 24,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: RgColors.textPrimary,
                    ),
                  ),
                  Text(
                    weekday,
                    style: RgText.caption.copyWith(
                      fontSize: 12,
                      color: RgColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count건',
                    style: RgText.titleList.copyWith(
                      color: RgColors.textPrimary,
                    ),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: RgSpace.s2),
                    Text(
                      sub!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RgText.meta.copyWith(
                        color: RgColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 묶음 머리: 「어제 ……… 4건」 「지난주  10월 19일 ~ 10월 25일 ……… 5일치 ⌄」 「2026년 10월 ……… 12일치 ⌄」. 접히는 묶음은 누르면 펼친다
class DateHeader extends StatelessWidget {
  const DateHeader({
    super.key,
    required this.label,
    this.range,
    required this.count,
    required this.open,
    this.onTap,
    this.onMore,
    this.moreLabel = '다른 날짜 보기',
  });
  final String label;
  final String? range;
  final String moreLabel;
  final String count; // 「4건」 「12일치」
  final bool open;
  final VoidCallback? onTap;
  final VoidCallback? onMore; // 있으면 개수 대신 「다른 날짜 보기 ›」(시안 탐색-논문·소식)

  @override
  Widget build(BuildContext context) {
    final d = RgMotion.of(context, RgMotion.base);
    final row = Container(
      constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
      padding: const EdgeInsets.fromLTRB(
        RgSpace.gutterText,
        RgSpace.s24,
        RgSpace.gutterText,
        RgSpace.s16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: RgSpace.s8,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: label,
                      style: RgText.titleList.copyWith(
                        fontSize: 24,
                        height: 25 / 24,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.48,
                        color: RgColors.textPrimary,
                      ),
                    ),
                    if (range != null)
                      TextSpan(
                        text: '  $range',
                        style: RgText.meta.copyWith(
                          color: RgColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (onMore case final more?)
            Semantics(
              button: true,
              child: RgPressable(
                onTap: more,
                child: Container(
                  constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
                  padding: const EdgeInsets.only(left: RgSpace.s8),
                  alignment: Alignment.bottomRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        moreLabel,
                        style: RgText.homeMore.copyWith(
                          color: RgColors.textSecondary,
                        ),
                      ),
                      RgIcon(
                        'chevron-right',
                        size: 12,
                        color: RgColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Text(
              count,
              style: RgText.bodySmall.copyWith(color: RgColors.textSecondary),
            ),
          if (onTap != null)
            AnimatedRotation(
              turns: open ? -0.25 : 0.25, // 펼침 ▲ / 접힘 ▼
              duration: d,
              curve: RgMotion.curve,
              child: RgIcon(
                'chevron-right',
                size: 16,
                color: RgColors.textSecondary,
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      expanded: open,
      child: RgPressable(onTap: onTap, child: row),
    );
  }
}

// 카드 아래 가운데 흰 알약 「N건 더 보기 ⌄」 / 「접기 ⌃」(누르는 높이 44)
class _MoreButton extends StatelessWidget {
  const _MoreButton({
    required this.open,
    required this.more,
    required this.onTap,
  });
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
              decoration: BoxDecoration(
                color: RgColors.fillNeutral,
                borderRadius: BorderRadius.circular(RgRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: RgSpace.s4,
                children: [
                  Flexible(
                    child: Text(
                      open ? '접기' : '$more건 더 보기',
                      style: RgText.meta.copyWith(
                        fontWeight: FontWeight.w600,
                        color: RgColors.textBody,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? -0.25 : 0.25,
                    duration: d,
                    curve: RgMotion.curve,
                    child: RgIcon(
                      'chevron-right',
                      size: 16,
                      color: RgColors.textBody,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// 탐색의 보조 탭. 16/25 글자 아래 2pt 선, 화면 전체에 옅은 경계.
// 다른 화면의 밑줄 탭에는 영향을 주지 않는다.
class ExploreSectionTabs extends StatelessWidget {
  const ExploreSectionTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onTap,
    this.information = const {},
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onTap;
  final Set<int> information;

  @override
  Widget build(BuildContext context) => RgUnderlineTabs.explore(
    labels: labels,
    selected: selected,
    onTap: onTap,
    information: information,
  );
}

// 출처·논문 주제는 알약 없이 글자로 고른다. 작은 글자도 44pt 영역에서 누를 수 있다.
class ExploreTextFilters extends StatelessWidget {
  const ExploreTextFilters({
    super.key,
    required this.labels,
    required this.selected,
    required this.onTap,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => ChromeTextScale(
    child: Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: RgColors.borderDefault)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, label) in labels.indexed)
              Semantics(
                button: true,
                selected: i == selected,
                child: RgPressable(
                  onTap: () {
                    if (i != selected) HapticFeedback.selectionClick();
                    onTap(i);
                  },
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: RgSpace.minTouch,
                      minWidth: RgSpace.minTouch,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: RgSpace.s10,
                      vertical: RgSpace.s8,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: RgText.meta.copyWith(
                        fontSize: 14,
                        height: 25 / 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.28,
                        color: i == selected
                            ? RgColors.textPrimary
                            : RgColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
