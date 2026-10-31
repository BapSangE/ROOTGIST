import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/repository.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_row_head.dart';

// S05 보관함 (HANDOFF 7.7). 저장 단위만으로 그리므로 네트워크 없이 동작한다. 논문·공식 소식·모델을 함께 담는다.
// 빼면 행이 흐려지며 접히고(220ms) 그다음 지운다. 되돌리면 같은 자리에 다시 펼쳐진다.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _leaving = <String>{}; // 접히는 중
  final _arriving = <String>{}; // 되돌려 펼쳐지는 중

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: bookmarks,
      builder: (context, saved, _) {
        final list = saved.values.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));
        final secondary = RgText.bodySmall.copyWith(color: RgColors.textSecondary);
        return ListView(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: RgSpace.bottomScrollInset),
          children: [
            ChromeTextScale(
              child: SizedBox(
                height: RgSpace.topBar,
                child: Padding(
                  padding: const EdgeInsets.only(left: RgSpace.gutterText, right: RgSpace.gutterCard),
                  child: Row(children: [
                    Expanded(child: Semantics(header: true, child: Text('보관함', style: RgText.display))),
                    if (list.isNotEmpty)
                      Semantics(
                        button: true,
                        child: RgPressable(
                          onTap: () => _confirmClear(context, list.length),
                          // 외곽선 알약(보이는 34, 누르는 44)
                          child: Container(
                            height: RgSpace.minTouch,
                            alignment: Alignment.center,
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 34),
                              padding: const EdgeInsets.symmetric(horizontal: RgSpace.s14, vertical: RgSpace.s6),
                              decoration: BoxDecoration(
                                color: RgColors.surfaceRaised,
                                borderRadius: BorderRadius.circular(RgRadius.pill),
                                border: Border.all(color: RgColors.borderDefault),
                              ),
                              child: Text('전체 비우기', style: secondary.copyWith(height: 1.3, fontWeight: FontWeight.w500, color: RgColors.textBody)),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
            if (list.isEmpty)
              // 8.1 빈 목록: 카드 없이 제목 + 설명 + 행동 1개.
              Padding(
                padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s24, RgSpace.gutterText, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('아직 저장한 게 없어요', style: RgText.titleCard),
                  const SizedBox(height: RgSpace.s6),
                  KeepAllText('논문·소식·모델의 북마크를 누르면 여기에 모여요', style: secondary),
                  const SizedBox(height: RgSpace.s20),
                  _OutlineButton(label: '오늘의 논문 보기', onTap: () => context.go('/home')),
                ]),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s8, RgSpace.gutterText, RgSpace.s20),
                child: Text('이 기기에 저장한 항목 ${list.length}개', style: RgText.meta.copyWith(fontSize: 15, color: RgColors.textSecondary)),
              ),
              RgCard(
                child: Column(children: [
                  for (final (i, b) in list.indexed)
                    _Collapsible(
                      key: ValueKey(b.id),
                      leaving: _leaving.contains(b.id),
                      arriving: _arriving.contains(b.id),
                      onGone: () => _removed(context, b),
                      onShown: () => _arriving.remove(b.id),
                      child: RgListRow(
                      showDivider: i < list.length - 1,
                      onTap: () => context.push(b.path),
                      // 다른 목록과 같은 옅은 원 북마크(저장됨 = 검정 원)
                      trailing: RgBookmarkButton(
                        saved: true,
                        variant: RgCircleVariant.neutral,
                        visualSize: 36,
                        strongHaptic: true, // 보관함에서 빼는 건 조금 더 또렷한 진동
                        onTap: _leaving.contains(b.id) ? null : () => setState(() => _leaving.add(b.id)),
                      ),
                      // 통일 머리 줄: 출처에 대표 색이 있으면 출처 칩(공식 소식·모델), 없으면 종류 칩(논문) → 제목
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _head(b),
                        const SizedBox(height: RgSpace.s6),
                        KeepAllText(b.title, style: RgText.titleList),
                      ]),
                    ),
                    ),
                ]),
              ),
              const SizedBox(height: RgSpace.s12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s6, children: [
                  Padding(
                    padding: EdgeInsets.only(top: 1.5),
                    child: RgIcon('info', size: 14, color: RgColors.textSecondary),
                  ),
                  Expanded(
                    child: KeepAllText(
                      '인터넷 연결이 없어도 저장한 목록은 볼 수 있어요. 요약과 번역은 연결된 뒤에 불러와요.',
                      perSentence: true, style: RgText.caption.copyWith(color: RgColors.textSecondary),
                    ),
                  ),
                ]),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _head(Bookmark b) {
    final saved = '${b.savedAt.month}월 ${b.savedAt.day}일 저장';
    return brandOf(b.source) != null
        ? RgRowHead(chip: RgChip(b.source, source: b.source), meta: '${_kindKo(b.kind)} · $saved')
        : RgRowHead(chip: RgChip(_kindKo(b.kind)), meta: '${b.source} · $saved');
  }

  // 접힌 뒤 지우고 4초 동안 되돌릴 수 있다. 되돌리면 그 행은 펼쳐지며 돌아온다.
  void _removed(BuildContext context, Bookmark b) {
    _leaving.remove(b.id);
    toggleBookmark(b.id, b.title, source: b.source, kind: b.kind);
    // 검정 알림(테마 snackBarTheme). 탭바가 Scaffold.bottomNavigationBar라 알림은 그 위에 저절로 뜬다.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('보관함에서 뺐어요'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '되돌리기',
          onPressed: () {
            if (mounted) setState(() => _arriving.add(b.id));
            restoreBookmark(b);
          },
        ),
      ));
  }

  Future<void> _confirmClear(BuildContext context, int n) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: RgColors.overlayDim,
      builder: (d) => AlertDialog(
        backgroundColor: RgColors.surfaceRaised,
        content: Text('저장한 항목 $n개를 모두 뺄까요?', style: RgText.bodySummary),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('모두 빼기')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    _leaving.clear();
    ScaffoldMessenger.of(context).hideCurrentSnackBar(); // 이전 해제의 「되돌리기」가 비운 목록을 되살리지 않게
    bookmarks.value = {};
  }
}

String _kindKo(String kind) => switch (kind) {
  'news' => '공식 소식',
  'model' => '모델',
  _ => '논문',
};

// 빈 상태 행동: 아웃라인 알약 44 (8.1).
class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: RgPressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s10),
          decoration: BoxDecoration(
            color: RgColors.surfaceRaised,
            borderRadius: BorderRadius.circular(RgRadius.pill),
            border: Border.all(color: RgColors.borderDefault),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(label, style: RgText.bodySmall.copyWith(height: 1.2, fontWeight: FontWeight.w600))),
          ]),
        ),
      ),
    );
  }
}

// 보관함 행이 빠질 때 흐려지며 높이가 접히고(220ms), 되돌리면 펼쳐진다. 「동작 줄이기」면 바로.
class _Collapsible extends StatefulWidget {
  const _Collapsible({
    super.key,
    required this.leaving,
    required this.arriving,
    required this.onGone,
    required this.onShown,
    required this.child,
  });
  final bool leaving, arriving;
  final VoidCallback onGone, onShown;
  final Widget child;

  @override
  State<_Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<_Collapsible> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: RgMotion.base, value: widget.arriving ? 0 : 1);
  late final _t = CurvedAnimation(parent: _c, curve: RgMotion.curve);

  @override
  void initState() {
    super.initState();
    // 펼치기는 첫 프레임 뒤에(그때 「동작 줄이기」를 읽을 수 있다)
    if (widget.arriving) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _c.duration = RgMotion.of(context, RgMotion.base);
        _c.forward().whenComplete(widget.onShown);
      });
    }
  }

  @override
  void didUpdateWidget(_Collapsible old) {
    super.didUpdateWidget(old);
    if (widget.leaving && !old.leaving) {
      _c.duration = RgMotion.of(context, RgMotion.base);
      _c.reverse().whenComplete(() {
        if (mounted) widget.onGone();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
    sizeFactor: _t,
    alignment: Alignment.topCenter,
    child: FadeTransition(opacity: _t, child: widget.child),
  );
}
