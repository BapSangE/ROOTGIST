import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/unread.dart' show clock;
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_bottom_sheet.dart';
import '../../design/widgets/rg_pressable.dart';

// 수집 일정 안내: 온보딩 마지막 장, 홈 위 「다음 수집」 알약, 그 알약이 여는 시트가 같은 문구를 쓴다.
// 실제 일정(.github/workflows, supabase/migrations/20261103090000_cron_dispatch.sql):
//   KST 05:00 daily-batch(논문 → 공식 소식·화제·모델), KST 12:00 official-news(공식 소식·화제·모델, 2026-11-11에 14:17에서 당김: 미국 오후 발표가 KST 10시쯤 끝나 4시간 넘게 기다릴 까닭이 없다),
//   매시 정각·30분 x-posts(X 계정 새 글, Supabase pg_cron이 깨운다: 20261111130000_cron_on_the_hour.sql). X 글 번역도 그 실행에서 바로 붙는다(2026-11-10, 소식 배치는 빠진 것만 다시 채운다).
// 요약까지 끝나 화면에 보이는 건 그보다 30분~1시간 뒤라 「아침 6시쯤·오후 1시쯤」으로 안내한다(설정 › 사용 방법 문답과 같게).
// 일·월요일 다이제스트는 HF 토·일요일분이라 늘 비어 있다(실데이터 2026-10-25~11-09 일·월 0편, 화~토 10편).

/// 「아침 6시쯤」 「오후 1시쯤」: 소식이 화면에 올라오는 대략의 시각(KST)
const collectHours = [6, 13];

/// 주말에 논문이 비는 이유(홈·탐색의 빈 날 안내, 시트, 온보딩이 같은 문장).
const weekendPaperReason = '주말에는 arXiv와 Hugging Face에 새 논문이 거의 올라오지 않아요.';

/// 다음 수집 시각 이름(KST). 6시 전이면 「오늘 아침 6시쯤」, 13시 전이면 「오후 1시쯤」, 그 뒤면 「내일 아침 6시쯤」.
String nextCollectLabel(DateTime now) {
  final h = now.toUtc().add(const Duration(hours: 9)).hour;
  if (h < collectHours[0]) return '오늘 아침 6시쯤';
  if (h < collectHours[1]) return '오후 1시쯤';
  return '내일 아침 6시쯤';
}

// 홈 맨 위 오른쪽 알약: 「다음 수집 오후 1시쯤」. 누르면 일정·주말 안내 시트(눌림 0.98 → 시트가 아래에서 올라온다).
// 홈은 탭을 오가도 살아 있어서 1분마다 다시 그려 경계(6시·13시)를 넘으면 글자가 바뀐다.
class NextCollectPill extends StatefulWidget {
  const NextCollectPill({super.key});

  @override
  State<NextCollectPill> createState() => _NextCollectPillState();
}

class _NextCollectPillState extends State<NextCollectPill> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = nextCollectLabel(clock());
    return Semantics(
      button: true,
      label: '다음 수집 $label, 수집 일정 보기',
      excludeSemantics: true,
      child: RgPressable(
        onTap: () => showCollectScheduleSheet(context), // 진동은 시트가 연다
        // 누르는 영역은 44, 보이는 알약은 32
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
          child: Center(
            child: Container(
              height: 32,
              padding: const EdgeInsets.only(left: RgSpace.s12, right: RgSpace.s8),
              decoration: BoxDecoration(color: RgHome.chip, borderRadius: BorderRadius.circular(RgRadius.pill)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: RgSpace.s2,
                children: [
                  // 시각이 넘어가 글자가 바뀌면 살짝 바뀐다(150ms, 동작 줄이기면 바로)
                  Flexible(
                    child: AnimatedSwitcher(
                      duration: RgMotion.of(context, RgMotion.fast),
                      child: Text(
                        '다음 수집 $label',
                        key: ValueKey(label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RgText.caption.copyWith(fontWeight: FontWeight.w600, color: RgColors.textBody),
                      ),
                    ),
                  ),
                  RgIcon('chevron-right', size: 12, color: RgColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 「언제 새로 올라와요?」 시트: 하루 두 번의 시각과 그때 오는 것, 주말에 논문이 비는 이유.
Future<void> showCollectScheduleSheet(BuildContext context) => showRgBottomSheet<void>(
  context,
  builder: (sheet) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: RgSpace.s4),
      Semantics(header: true, child: Text('언제 새로 올라와요?', style: RgText.titleSection)),
      const SizedBox(height: RgSpace.s10),
      KeepAllText('하루 두 번 새 소식을 모으고, X 글은 30분마다 받아요. 몇십 분 늦어질 수 있어요.', perSentence: true, style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
      const SizedBox(height: RgSpace.s16),
      const CollectTimes(),
      const SizedBox(height: RgSpace.s20),
      Semantics(
        header: true,
        child: Text('주말에는 논문이 비어요', style: RgText.bodySmall.copyWith(fontWeight: FontWeight.w700)),
      ),
      const SizedBox(height: RgSpace.s6),
      KeepAllText('$weekendPaperReason 그래서 일요일과 월요일 아침에는 가장 최근 논문을 대신 보여 드려요. 회사들도 주말에는 발표가 적어 소식이 뜸해요.', perSentence: true, style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
    ],
  ),
);

/// 시각 세 줄(시트·온보딩 그림이 함께 쓴다). appear(0~1)를 주면 줄마다 조금씩 늦게 떠오른다.
class CollectTimes extends StatelessWidget {
  const CollectTimes({super.key, this.appear = 1});
  final double appear;

  static const rows = [
    ('아침 6시쯤', '논문 · 공식 소식 · 개발자 화제 · 모델'),
    ('오후 1시쯤', '공식 소식 · 개발자 화제 · 모델'),
    ('30분마다', 'X 글 · 혜택·한도 소식(바로 번역해요)'),
  ];

  @override
  Widget build(BuildContext context) {
    Widget row(int i, String time, String what) {
      // 줄마다 0.2만큼 늦게 시작해 셋째 줄도 appear=1에서 다 떠오른다
      final t = ((appear - i * 0.2) / 0.6).clamp(0.0, 1.0);
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: RgSpace.s12,
            children: [
              SizedBox(
                width: 78,
                child: Text(
                  time,
                  style: RgText.bodySmall.copyWith(fontWeight: FontWeight.w700, color: RgColors.textPrimary),
                ),
              ),
              Expanded(
                child: KeepAllText(what, style: RgText.bodySmall.copyWith(color: RgColors.textBody)),
              ),
            ],
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: RgSpace.s10, children: [for (final (i, (time, what)) in rows.indexed) row(i, time, what)]);
  }
}
