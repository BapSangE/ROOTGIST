import 'dart:async';

import 'package:flutter/material.dart';

import '../tokens.dart';

import 'package:flutter_svg/flutter_svg.dart';

// 눌림 피드백: ripple 대신 불투명도 0.85 (HANDOFF 6장 공통 규칙). 버튼·칩은 97%로 살짝 작아지기도 한다(2026-11-11).
// row: 행·카드는 누르는 동안 98%로 작아지고 4% 어두워진다(100ms). 떼면 살짝 튀며 돌아온다(160ms).
// 짧게 톡 눌러도 눌림이 보이게 최소 130ms는 눌린 모양을 둔다: 스크롤 목록 안에서는 손을 뗄 때에야 누름이 확정돼
// 눌림·놓임이 같은 프레임에 지나가 반응이 없는 것처럼 보였다. 그렇게 늦게 확정된 누름은 들어가는 애니메이션 없이
// 바로 눌린 모양으로 그린다(100ms에 걸쳐 들어가다 90ms에 풀려 거의 안 보였다, 2026-11-11).
// 그래도 카드·행은 누르는 그 프레임에 새 화면·시트가 덮어 눌림이 안 보였다: 짧은 톡이면 눌린 모양을 먼저 90ms 보여 준 뒤 동작한다
// (행만. 탭·북마크·버튼은 바로 반응해야 해서 미루지 않는다). 시계는 화면 프레임(티커)이라 프레임을 따라 흐른다.
// 「동작 줄이기」면 크기는 그대로, 어두워지기만.
class RgPressable extends StatefulWidget {
  const RgPressable({
    super.key,
    required this.onTap,
    required this.child,
    this.row = false,
  });
  final VoidCallback? onTap;
  final Widget child;
  final bool row;

  @override
  State<RgPressable> createState() => _RgPressableState();
}

class _RgPressableState extends State<RgPressable> with SingleTickerProviderStateMixin {
  static const _minPress = Duration(milliseconds: 130);
  bool _pressed = false;
  bool _instant = false; // 누름이 뗄 때에야 확정됨 → 들어가는 애니메이션 없이 바로
  static const _actAfter = Duration(milliseconds: 90); // 짧은 톡: 눌린 모양을 이만큼 보여 준 뒤 동작
  late final _clock = AnimationController(vsync: this, duration: _minPress)..addListener(_tick);
  VoidCallback? _pending; // 짧은 톡의 미룬 동작
  bool _quick = false; // 이번 누름이 짧은 톡이었다(동작을 잠깐 미룬다)
  DateTime? _downAt;
  Timer? _release;

  @override
  void didUpdateWidget(RgPressable old) {
    super.didUpdateWidget(old);
    if (widget.onTap == null) _pressed = false;
  }

  @override
  void dispose() {
    _release?.cancel();
    _clock.dispose();
    super.dispose();
  }

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  void _tick() {
    if (_pending != null && _clock.value * _minPress.inMilliseconds >= _actAfter.inMilliseconds) {
      final act = _pending!;
      _pending = null;
      act();
    }
  }

  void _down() {
    _release?.cancel();
    _clock.stop();
    // 앞의 짧은 톡 동작이 남았으면 지금 한다(빠르게 두 번 눌러도 동작이 사라지지 않게)
    if (_pending case final act?) {
      _pending = null;
      act();
    }
    _downAt = DateTime.now();
    _instant = false;
    _quick = false;
    _set(true);
  }

  // 뗄 때: 눌린 지 130ms가 안 됐으면 남은 시간만큼 기다렸다가 돌아온다
  void _up() {
    final held = _downAt == null ? _minPress : DateTime.now().difference(_downAt!);
    _release?.cancel();
    if (held >= _minPress) return _set(false);
    // 눌림과 놓임이 같은 순간(같은 프레임)이면 눌린 모양을 바로 그린다
    _quick = held < const Duration(milliseconds: 40);
    if (_quick) {
      setState(() => _instant = true);
      _clock.forward(from: 0).then((_) {
        if (mounted) _set(false);
      });
      return;
    }
    _release = Timer(_minPress - held, () {
      if (mounted) _set(false);
    });
  }

  void _tap() {
    if (!_quick || !widget.row) return widget.onTap?.call();
    _quick = false; // 다음 누름(화면 읽기 두 번 탭 등)에 남지 않게
    _pending = widget.onTap;
  }

  Duration get _pressIn => _instant ? Duration.zero : RgMotion.press;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap == null ? null : _tap,
      onTapDown: widget.onTap == null ? null : (_) => _down(),
      onTapUp: widget.onTap == null ? null : (_) => _up(),
      onTapCancel: widget.onTap == null ? null : () {
        _release?.cancel();
        _set(false);
      },
      child: widget.row
          ? AnimatedScale(
              scale: _pressed && !still ? RgMotion.pressScale : 1,
              duration: still ? Duration.zero : (_pressed ? _pressIn : RgMotion.release),
              curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
              child: AnimatedContainer(
                duration: _pressed ? _pressIn : RgMotion.release,
                foregroundDecoration: BoxDecoration(
                  color: _pressed
                      ? RgColors.pressOverlay
                      : const Color(0x00000000),
                ),
                child: widget.child,
              ),
            )
          : AnimatedScale(
              scale: _pressed && !still ? RgMotion.buttonPressScale : 1,
              duration: still ? Duration.zero : (_pressed ? _pressIn : RgMotion.release),
              curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: _pressed ? 0.85 : 1,
                duration: _pressed ? _pressIn : RgMotion.press,
                child: widget.child,
              ),
            ),
    );
  }
}

// assets/icons/<name>.svg 를 지정 색으로.
class RgIcon extends StatelessWidget {
  const RgIcon(this.name, {super.key, this.size = 20, required this.color});
  final String name;
  final double size;
  final Color color;

  static const _referenceIcons = {
    'house': 'reicon-home',
    'compass': 'reicon-compass',
    'settings': 'reicon-settings',
    'bookmark': 'reicon-bookmark-outline',
    'bookmark-filled': 'reicon-bookmark',
    'chevron-left': 'reicon-chevron-left',
    'chevron-right': 'reicon-chevron-right',
    'calendar': 'reicon-calendar',
    'heart': 'reicon-like',
    'thumbs-up': 'reicon-like',
    'message-circle': 'reicon-comment',
    'message-square': 'reicon-comment',
    'download': 'reicon-download',
    'search': 'reicon-search',
    'info': 'reicon-info',
  };

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/${_referenceIcons[name] ?? name}.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}
