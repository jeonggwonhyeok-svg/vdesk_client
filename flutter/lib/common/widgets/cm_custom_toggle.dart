/// CM 창용 커스텀 토글 스위치
/// 디자인 스펙:
/// - 비활성: bg #DEDEE2, border #DEDEE2, radius 40px, size 59x32
/// - 활성: bg #FEFEFE
/// - 토글 내부 비활성: #FEFEFE, radius 24px, size 24x24
/// - 토글 내부 활성: #5F71FF
library;

import 'package:flutter/material.dart';

class CmCustomToggle extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  const CmCustomToggle({
    Key? key,
    required this.value,
    this.onChanged,
    this.enabled = true,
  }) : super(key: key);

  @override
  State<CmCustomToggle> createState() => _CmCustomToggleState();
}

class _CmCustomToggleState extends State<CmCustomToggle>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  // 디자인 스펙 색상
  static const Color _inactiveTrackColor = Color(0xFFDEDEE2);
  static const Color _activeTrackColor = Color(0xFFFEFEFE);
  static const Color _inactiveThumbColor = Color(0xFFFEFEFE);
  static const Color _activeThumbColor = Color(0xFF5F71FF);

  // 크기 스펙
  static const double _trackWidth = 59;
  static const double _trackHeight = 32;
  static const double _thumbSize = 24;
  static const double _trackRadius = 40;
  static const double _thumbRadius = 24;
  static const double _padding = 4;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      value: widget.value ? 1.0 : 0.0,
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void didUpdateWidget(CmCustomToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (widget.value) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.enabled && widget.onChanged != null) {
      widget.onChanged!(!widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.enabled && widget.onChanged != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final trackColor = Color.lerp(
              _inactiveTrackColor,
              _activeTrackColor,
              _animation.value,
            )!;
            final thumbColor = Color.lerp(
              _inactiveThumbColor,
              _activeThumbColor,
              _animation.value,
            )!;
            final borderColor = widget.value
                ? _activeThumbColor
                : _inactiveTrackColor;

            // 썸 위치 계산 (패딩 고려)
            final thumbPosition =
                _padding + (_trackWidth - _thumbSize - _padding * 2) * _animation.value;

            return Container(
              width: _trackWidth,
              height: _trackHeight,
              decoration: BoxDecoration(
                color: trackColor,
                borderRadius: BorderRadius.circular(_trackRadius),
                border: Border.all(
                  color: borderColor,
                  width: 1,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: thumbPosition,
                    top: (_trackHeight - _thumbSize - 2) / 2,
                    child: Container(
                      width: _thumbSize,
                      height: _thumbSize,
                      decoration: BoxDecoration(
                        color: thumbColor,
                        borderRadius: BorderRadius.circular(_thumbRadius),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
