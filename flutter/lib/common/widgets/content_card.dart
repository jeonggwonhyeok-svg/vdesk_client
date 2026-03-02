import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';

/// 공용 컨텐츠 카드 위젯
/// 연결 페이지, 세팅 페이지 등에서 사용
class ContentCard extends StatelessWidget {
  final Widget child;
  final String? title;
  final List<Widget>? titleSuffix;
  final bool showDivider;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;

  const ContentCard({
    Key? key,
    required this.child,
    this.title,
    this.titleSuffix,
    this.showDivider = true,
    this.padding,
    this.contentPadding,
    this.margin,
    this.backgroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).extension<ContentCardTheme>() ??
        ContentCardTheme.light;

    // 타이틀이 없으면 기존 단순 카드
    if (title == null) {
      return Container(
        margin: margin,
        padding: padding ?? const EdgeInsets.all(20),
        decoration: _cardDecoration(theme),
        child: child,
      );
    }

    // 타이틀이 있으면 타이틀 + 구분선 + 컨텐츠 구조
    final hp = theme.horizontalPadding;
    return Container(
      margin: margin,
      decoration: _cardDecoration(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 타이틀 영역
          Padding(
            padding: EdgeInsets.fromLTRB(hp, 16, hp, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: TextStyle(
                      fontSize: theme.titleFontSize,
                      fontWeight: FontWeight.w600,
                      color: theme.titleColor,
                    ),
                  ),
                ),
                if (titleSuffix != null) ...titleSuffix!,
              ],
            ),
          ),
          // 구분선 (옵션)
          if (showDivider)
            Container(
              height: 1,
              margin: EdgeInsets.symmetric(horizontal: hp),
              color: theme.dividerColor,
            ),
          // 구분선 아래 패딩 (타이틀 하단과 동일하게 12px)
          if (showDivider) const SizedBox(height: 12),
          // 컨텐츠 영역
          Padding(
            padding: contentPadding ?? EdgeInsets.fromLTRB(hp, 0, hp, hp),
            child: child,
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration(ContentCardTheme theme) {
    return BoxDecoration(
      color: backgroundColor ?? theme.backgroundColor,
      borderRadius: BorderRadius.circular(theme.borderRadius),
      boxShadow: [
        BoxShadow(
          color: theme.shadowColor,
          blurRadius: theme.shadowBlurRadius,
          offset: theme.shadowOffset,
        ),
      ],
    );
  }
}
