import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../tokens.dart';
import '../typography.dart';
import 'rg_buttons.dart';
import 'rg_card.dart';

// 당겨서 새로고침(2026-11-11)이 다시 부를 것들. Reloadable은 스스로 들어오고, Reloadable이 아닌 칸
// (홈의 소식·모델, 혜택 카드)은 initState에서 넣고 dispose에서 뺀다. 탭은 IndexedStack이라 다른 탭 목록도 함께 새로 받는다.
final pullRefreshers = <Future<void> Function()>{};

Future<void> refreshAll() => Future.wait([for (final f in pullRefreshers.toList()) f().catchError((Object _) {})]);

// 화면 하나의 요청. 「다시 시도」와 fixture 스위치 변경 때 새로 부른다.
class Reloadable<T> extends ChangeNotifier {
  Reloadable(this._load) : future = _start(_load) {
    fixtureMode.addListener(reload);
    pullRefreshers.add(refresh);
  }
  final Future<T> Function() _load;
  Future<T> future;

  // 화면이 다시 그려져 FutureBuilder가 붙기 전에 실패해도 처리 안 된 오류로 새지 않게 한다.
  // 오류는 그대로 FutureBuilder에 전달된다.
  static Future<T> _start<T>(Future<T> Function() load) => load()..ignore();

  // 다시 시도·fixture 바꾸기: 빈 자리 표시부터 다시. generation을 FutureBuilder 키로 쓰면 지난 값을 들고 있지 않는다
  // (당겨서 새로고침은 generation을 그대로 두어, 바꾸는 한 프레임에도 보던 내용을 유지한다).
  int generation = 0;

  void reload() {
    generation++;
    future = _start(_load);
    notifyListeners();
  }

  // 당겨서 새로고침: 받는 동안은 보던 내용을 그대로 두고(빈 자리 표시로 바꾸지 않는다), 다 받으면 바꾼다. 실패하면 그대로.
  Future<void> refresh() async {
    try {
      final v = await _load();
      future = Future.value(v);
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    fixtureMode.removeListener(reload);
    pullRefreshers.remove(refresh);
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
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 0;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

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

// 당겨서 새로고침 감싸개(2026-11-11 iOS 방식으로 다시): 당기면 목록이 내려가며 위에 빈 자리가 생기고, 그 자리에서 돌림표가
// 당긴 만큼 채워지다가 72를 넘기면 가벼운 진동과 함께 돌기 시작한다. 새로 받는 동안 56만큼 자리를 벌려 둔 채 돌고, 끝나면 닫힌다.
// (전에는 Material 새로고침이라 돌림표가 글 위에 떠 있었다.) 세로 목록에서만(가로 칩 줄은 무시).
// iOS 튕김 스크롤은 목록이 스스로 내려가니 새로 받는 동안만 모자란 만큼 밀어 두고, 튕기지 않는 스크롤(안드로이드)은 끈 거리의 절반만큼 민다.
// edgeOffset: 목록이 상태바 아래부터 시작하는 화면(홈)은 그만큼 아래에서 돌림표를 그린다.
class RgRefresh extends StatefulWidget {
  const RgRefresh({super.key, required this.child, this.edgeOffset = 0});
  final Widget child;
  final double edgeOffset;

  static const trigger = 72.0; // 이만큼 당기면 새로고침
  static const hold = 56.0; // 새로 받는 동안 벌려 두는 자리

  @override
  State<RgRefresh> createState() => _RgRefreshState();
}

class _RgRefreshState extends State<RgRefresh> with SingleTickerProviderStateMixin {
  late final _shift = AnimationController.unbounded(vsync: this); // 목록을 직접 민 거리
  final _bounce = ValueNotifier<double>(0); // 튕김 스크롤로 목록이 이미 내려간 거리
  double _pull = 0; // 튕기지 않는 스크롤에서 위 끝을 넘어 끈 거리
  bool _refreshing = false;

  double get _gap => _bounce.value + _shift.value;

  @override
  void dispose() {
    _shift.dispose();
    _bounce.dispose();
    super.dispose();
  }

  void _settle(double to) =>
      _shift.animateTo(to, duration: RgMotion.of(context, RgMotion.base), curve: Curves.easeOutCubic);

  Future<void> _start() async {
    _refreshing = true;
    HapticFeedback.lightImpact();
    setState(() {});
    // 너무 빨리 끝나도 돌림표가 깜빡이고 사라지지 않게 잠깐은 돈다
    await Future.wait([refreshAll(), Future<void>.delayed(const Duration(milliseconds: 500))]);
    if (!mounted) return;
    _refreshing = false;
    setState(() {});
    if (_pull == 0) _settle(0);
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final dragging = switch (n) {
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null,
      OverscrollNotification(:final dragDetails) => dragDetails != null,
      ScrollStartNotification(:final dragDetails) => dragDetails != null,
      _ => false,
    };
    _bounce.value = n.metrics.pixels < n.metrics.minScrollExtent ? n.metrics.minScrollExtent - n.metrics.pixels : 0;
    if (n is OverscrollNotification && dragging && n.overscroll < 0) {
      _pull += -n.overscroll;
      _shift.value = _refreshing ? math.max(RgRefresh.hold, _pull / 2) : _pull / 2;
    } else if (n is ScrollEndNotification) {
      _pull = 0;
      _settle(_refreshing ? math.max(0, RgRefresh.hold - _bounce.value) : 0);
    } else if (_refreshing && _pull == 0) {
      // 튕겨 돌아오는 동안 목록이 hold보다 올라가지 않게 모자란 만큼만 받친다(이어지게)
      _shift.value = math.max(0, RgRefresh.hold - _bounce.value);
    }
    if (!_refreshing && dragging && _gap >= RgRefresh.trigger) _start();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final color = RgColors.textSecondary;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_shift, _bounce]),
              builder: (context, _) {
                final gap = _gap;
                if (gap < 1) return const SizedBox.shrink();
                return Positioned(
                  top: widget.edgeOffset,
                  left: 0,
                  right: 0,
                  height: gap,
                  child: IgnorePointer(
                    child: OverflowBox(
                      maxHeight: double.infinity,
                      child: Center(
                      child: Opacity(
                        opacity: (gap / 40).clamp(0.0, 1.0),
                        child: _refreshing
                            ? CupertinoActivityIndicator(radius: 10, color: color)
                            : CupertinoActivityIndicator.partiallyRevealed(
                                radius: 10,
                                color: color,
                                progress: (gap / RgRefresh.trigger).clamp(0.0, 1.0),
                              ),
                      ),
                    ),
                    ),
                  ),
                );
              },
            ),
            AnimatedBuilder(
              animation: _shift,
              builder: (context, child) => Transform.translate(offset: Offset(0, _shift.value), child: child),
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}
