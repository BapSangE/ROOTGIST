import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/repository.dart';
import '../../design/widgets/rg_buttons.dart';

// 카드·목록 행 오른쪽의 북마크(+ 공유). 피드백: 행마다 회색 아이콘 두 개가 반복돼 시선이 흩어지고 눌리는 버튼인지 안 보였다.
// 그래서 목록·카드에서는 북마크만, 옅은 원(보이는 36, 누르는 44) 위에 둔다. 공유는 상세 화면 상단 바(outline)와
// 상세가 없는 업데이트 카드에서만(share: true).
class ItemActions extends StatelessWidget {
  const ItemActions({
    super.key,
    required this.id,
    required this.title,
    required this.url,
    this.source = 'arXiv',
    this.kind = 'paper',
    this.variant = RgCircleVariant.neutral,
    this.share = false,
    this.visualSize,
    this.circleColor,
    this.iconColor,
  });
  final String id, title, url, source, kind;
  final RgCircleVariant variant;
  final bool share;
  final double? visualSize; // 홈 카드: 원 크기·면·아이콘 색을 시안대로
  final Color? circleColor, iconColor;

  @override
  Widget build(BuildContext context) {
    final compact = variant == RgCircleVariant.neutral; // 목록·카드
    final visual = visualSize ?? (compact ? 36.0 : null);
    return Row(mainAxisSize: MainAxisSize.min, spacing: compact ? 0 : 8, children: [
      if (share)
        RgCircleButton(
          semanticLabel: '공유',
          icon: 'share',
          variant: variant,
          visualSize: visual,
          onTap: () => shareItem(title, url),
        ),
      ValueListenableBuilder(
        valueListenable: bookmarks,
        builder: (_, saved, _) => RgBookmarkButton(
          saved: saved.containsKey(id),
          variant: variant,
          visualSize: visual,
          circleColor: circleColor,
          iconColor: iconColor,
          onTap: () => toggleBookmark(id, title, source: source, kind: kind),
        ),
      ),
    ]);
  }
}

void shareItem(String title, String url) => SharePlus.instance.share(ShareParams(text: '$title\n$url'));

// 논문 목록에는 HF 주소가 없어(PaperItem) 논문 id로 만든다.
String paperUrl(String id) => 'https://huggingface.co/papers/$id';
