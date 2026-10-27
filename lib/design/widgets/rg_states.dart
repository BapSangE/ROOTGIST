import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../tokens.dart';
import '../typography.dart';
import 'rg_buttons.dart';
import 'rg_card.dart';

// 화면 하나의 요청. 「다시 시도」와 fixture 스위치 변경 때 새로 부른다.
class Reloadable<T> extends ChangeNotifier {
  Reloadable(this._load) : future = _start(_load) {
    fixtureMode.addListener(reload);
  }
  final Future<T> Function() _load;
  Future<T> future;

  // 화면이 다시 그려져 FutureBuilder가 붙기 전에 실패해도 처리 안 된 오류로 새지 않게 한다.
  // 오류는 그대로 FutureBuilder에 전달된다.
  static Future<T> _start<T>(Future<T> Function() load) => load()..ignore();

  void reload() {
    future = _start(_load);
    notifyListeners();
  }

  @override
  void dispose() {
    fixtureMode.removeListener(reload);
    super.dispose();
  }
}

// 8.1 로딩: 실제 카드·행 모양 스켈레톤. 불투명도 1.0↔0.6, 1.2초 반복.
class RgSkeleton extends StatefulWidget {
  const RgSkeleton({super.key, required this.child});
  final Widget child;

  @override
  State<RgSkeleton> createState() => _RgSkeletonState();
}

class _RgSkeletonState extends State<RgSkeleton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '불러오는 중',
      child: ExcludeSemantics(
        child: FadeTransition(opacity: Tween(begin: 1.0, end: 0.6).animate(_c), child: widget.child),
      ),
    );
  }
}

// 스켈레톤 막대: fillNeutral, 모서리 6, 높이 = 해당 글자 행간. 막대 자체는 행간 안 가운데 놓는다.
class RgBar extends StatelessWidget {
  const RgBar({super.key, required this.lineHeight, this.widthFactor = 1, this.barHeight});
  final double lineHeight;
  final double widthFactor;
  final double? barHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: lineHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: widthFactor,
          child: Container(
            height: barHeight ?? lineHeight * 0.7,
            decoration: BoxDecoration(color: RgColors.fillNeutral, borderRadius: BorderRadius.circular(6)),
          ),
        ),
      ),
    );
  }
}

// 8.1 오류·오프라인 카드.
class RgErrorCard extends StatelessWidget {
  const RgErrorCard({super.key, required this.error, this.onRetry});
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final e = error is LoadError ? error as LoadError : const LoadError();
    final secondary = RgText.meta.copyWith(color: RgColors.textSecondary);
    return RgCard(
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('불러오지 못했어요', style: RgText.titleCard),
            const SizedBox(height: RgSpace.s6),
            if (e.offline) Text('인터넷 연결을 확인해 주세요', style: secondary),
            if (e.lastSuccessAt != null) Text('마지막 정상 수집 ${kstDateTime(e.lastSuccessAt!)}', style: secondary),
            if (onRetry != null) ...[
              const SizedBox(height: RgSpace.s18),
              RgPrimaryButton(label: '다시 시도', onTap: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}

// 스켈레톤 카드 안의 목록 행 n개(제목 2줄 + 메타 1줄).
class RgSkeletonRows extends StatelessWidget {
  const RgSkeletonRows({super.key, this.count = 3});
  final int count;

  @override
  Widget build(BuildContext context) {
    return RgCard(
      child: Column(children: [
        for (var i = 0; i < count; i++)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            decoration: i < count - 1
                ? BoxDecoration(border: Border(bottom: BorderSide(color: RgColors.dividerCard)))
                : null,
            child: const Column(spacing: RgSpace.s4, children: [
              RgBar(lineHeight: 23),
              RgBar(lineHeight: 23, widthFactor: 0.6),
              RgBar(lineHeight: 20, widthFactor: 0.4),
            ]),
          ),
      ]),
    );
  }
}
