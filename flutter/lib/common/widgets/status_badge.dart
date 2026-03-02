import 'package:flutter/material.dart';
import '../../common.dart';

/// 공통 상태 배지 위젯
/// Common status badge widget for online/offline status
class StatusBadge extends StatelessWidget {
  final bool isOnline;
  final double? fontSize;
  final double? dotSize;
  final EdgeInsets? padding;

  const StatusBadge({
    Key? key,
    required this.isOnline,
    this.fontSize = 10,
    this.dotSize = 6,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bgColor = isOnline ? const Color(0xFFDCFCE7) : const Color(0xFFFCE4EC);
    final borderColor = isOnline ? const Color(0xFF62A93E) : const Color(0xFFE57373);
    final dotColor = isOnline ? const Color(0xFF599A38) : const Color(0xFFE57373);
    final textColor = isOnline ? const Color(0xFF62A93E) : const Color(0xFFC62828);
    final text = isOnline ? translate('Available') : translate('Offline');

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
