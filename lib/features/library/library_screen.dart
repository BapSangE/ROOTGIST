import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/repository.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_pressable.dart';

// S05 보관함 (HANDOFF 7.7). 저장 단위만으로 그리므로 네트워크 없이 동작한다. 논문·공식 소식·모델을 함께 담는다.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

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
                  padding: const EdgeInsets.only(left: RgSpace.gutterText, right: RgSpace.s12),
                  child: Row(children: [
                    Expanded(child: Semantics(header: true, child: Text('보관함', style: RgText.titleDetail))),
                    if (list.isNotEmpty)
                      Semantics(
                        button: true,
                        child: RgPressable(
                          onTap: () => _confirmClear(context, list.length),
                          child: Container(
                            height: RgSpace.minTouch,
                            padding: const EdgeInsets.symmetric(horizontal: RgSpace.s8),
                            alignment: Alignment.center,
                            child: Text('전체 비우기', style: secondary.copyWith(fontWeight: FontWeight.w500)),
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
                padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s4, RgSpace.gutterText, RgSpace.s24),
                child: Text('이 기기에 저장한 항목 ${list.length}개', style: secondary),
              ),
              RgCard(
                child: Column(children: [
                  for (final (i, b) in list.indexed)
                    RgListRow(
                      showDivider: i < list.length - 1,
                      // 논문은 쉘 위로, 소식·모델은 탐색 탭 안의 상세로
                      onTap: () => b.kind == 'paper' ? context.push(b.path) : context.go(b.path),
                      trailing: RgBookmarkButton(
                        saved: true,
                        variant: RgCircleVariant.plain,
                        onTap: () => _remove(context, b),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        KeepAllText(b.title, style: RgText.titleList),
                        const SizedBox(height: RgSpace.s4),
                        Text(
                          '${_kindKo(b.kind)} · ${b.source} · ${b.savedAt.month}월 ${b.savedAt.day}일 저장',
                          style: RgText.meta.copyWith(color: RgColors.textSecondary),
                        ),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: RgSpace.s12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s6, children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1.5),
                    child: RgIcon('info', size: 14, color: RgColors.textSecondary),
                  ),
                  Expanded(
                    child: KeepAllText(
                      '인터넷 연결이 없어도 저장한 목록은 볼 수 있어요. 요약과 번역은 연결된 뒤에 불러와요.',
                      style: RgText.caption.copyWith(height: 17 / 12, color: RgColors.textSecondary),
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

  // 해제는 즉시 지우고 4초 동안 되돌릴 수 있다.
  void _remove(BuildContext context, Bookmark b) {
    toggleBookmark(b.id, b.title, source: b.source, kind: b.kind);
    final bottom = MediaQuery.paddingOf(context).bottom;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('보관함에서 뺐어요'),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        // 떠 있는 탭바(64) 위로
        margin: EdgeInsets.fromLTRB(RgSpace.gutterCard, 0, RgSpace.gutterCard, (bottom > 30 ? bottom : 30) + 64 + RgSpace.s8),
        action: SnackBarAction(label: '되돌리기', onPressed: () => restoreBookmark(b)),
      ));
  }

  Future<void> _confirmClear(BuildContext context, int n) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: RgColors.overlayDim,
      builder: (d) => AlertDialog(
        backgroundColor: RgColors.surfaceCard,
        content: Text('저장한 항목 $n개를 모두 뺄까요?', style: RgText.bodySummary),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('모두 빼기')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
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
            color: RgColors.surfaceCard,
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
