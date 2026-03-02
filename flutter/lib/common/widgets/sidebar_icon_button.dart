import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../../common.dart';

/// 사이드바 아이콘 버튼 위젯
/// 테마에서 스타일을 가져와서 아이콘 경로와 onTap만 지정하면 됨
class SidebarIconButton extends StatelessWidget {
  final String iconPath;
  final VoidCallback onTap;
  final EdgeInsets? padding;
  final Color? backgroundColor;
  final Color? iconColor;
  final Color? hoverIconColor;

  const SidebarIconButton({
    Key? key,
    required this.iconPath,
    required this.onTap,
    this.padding,
    this.backgroundColor,
    this.iconColor,
    this.hoverIconColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = MyTheme.sidebarIconButton(context);
    final RxBool isHovered = false.obs;

    return InkWell(
      onTap: onTap,
      onHover: (value) => isHovered.value = value,
      borderRadius: BorderRadius.circular(theme.borderRadius),
      child: Obx(() => Container(
            padding: padding ?? theme.padding,
            decoration: BoxDecoration(
              color: backgroundColor ?? theme.backgroundColor,
              borderRadius: BorderRadius.circular(theme.borderRadius),
              border: Border.all(
                color: isHovered.value ? theme.hoverBorderColor : theme.borderColor,
                width: theme.borderWidth,
              ),
            ),
            child: SvgPicture.asset(
              iconPath,
              width: theme.iconSize,
              height: theme.iconSize,
              colorFilter: ColorFilter.mode(
                isHovered.value
                    ? (hoverIconColor ?? theme.hoverIconColor)
                    : (iconColor ?? theme.iconColor),
                BlendMode.srcIn,
              ),
            ),
          )),
    );
  }
}
