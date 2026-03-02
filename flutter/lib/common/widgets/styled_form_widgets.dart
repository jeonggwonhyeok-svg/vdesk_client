/// 스타일이 적용된 폼 위젯 (체크박스, 라디오 버튼, 버튼)
/// 공통으로 사용 가능한 커스텀 폼 컨트롤 위젯
library;

import 'package:flutter/material.dart';

/// 기본 테마 색상 (다른 곳에서 오버라이드 가능)
const Color kFormAccentColor = Color(0xFF5F71FF);
const Color kFormPrimaryColor = Color(0xFF5B7BF8);
const Color kFormDisabledColor = Color(0xFFB9B8BF);

/// 스타일이 적용된 체크박스 위젯 (24px, 1px 테두리, 4px 둥글기)
/// 호버 시 테두리 색상 변경 및 핸드 커서
class StyledCheckbox extends StatefulWidget {
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final bool enabled;
  final double size;
  final double borderRadius;
  final double borderWidth;
  final double iconSize;
  final Color? accentColor;
  final Color? borderColor;
  final Color? disabledBorderColor;

  const StyledCheckbox({
    Key? key,
    required this.value,
    this.onChanged,
    this.enabled = true,
    this.size = 24,
    this.borderRadius = 4,
    this.borderWidth = 1,
    this.iconSize = 16,
    this.accentColor,
    this.borderColor,
    this.disabledBorderColor,
  }) : super(key: key);

  @override
  State<StyledCheckbox> createState() => _StyledCheckboxState();
}

class _StyledCheckboxState extends State<StyledCheckbox> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color accentColor = widget.accentColor ?? kFormAccentColor;
    final Color normalBorderColor = widget.borderColor ?? const Color(0xFFCBD5E1);
    final Color disabledBorderColor = widget.disabledBorderColor ?? const Color(0xFFE2E8F0);

    final Color borderColor = widget.enabled
        ? (_isHovered ? accentColor : normalBorderColor)
        : disabledBorderColor;

    return MouseRegion(
      cursor: widget.enabled && widget.onChanged != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.enabled && widget.onChanged != null
            ? () => widget.onChanged!(!widget.value)
            : null,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: widget.value
                  ? (widget.enabled ? accentColor : disabledBorderColor)
                  : borderColor,
              width: widget.borderWidth,
            ),
            color: widget.value
                ? (widget.enabled ? accentColor : disabledBorderColor)
                : Colors.transparent,
          ),
          child: widget.value
              ? Center(
                  child: Icon(
                    Icons.check,
                    size: widget.iconSize,
                    color: Colors.white,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// 스타일이 적용된 라디오 버튼 위젯 (24px, 1px 테두리)
/// 호버 시 테두리 색상 변경 및 핸드 커서
class StyledRadio<T> extends StatefulWidget {
  final T value;
  final T groupValue;
  final ValueChanged<T?>? onChanged;
  final bool enabled;
  final double size;
  final double innerSize;
  final double borderWidth;
  final Color? accentColor;
  final Color? borderColor;
  final Color? disabledBorderColor;

  const StyledRadio({
    Key? key,
    required this.value,
    required this.groupValue,
    this.onChanged,
    this.enabled = true,
    this.size = 24,
    this.innerSize = 12,
    this.borderWidth = 1,
    this.accentColor,
    this.borderColor,
    this.disabledBorderColor,
  }) : super(key: key);

  @override
  State<StyledRadio<T>> createState() => _StyledRadioState<T>();
}

class _StyledRadioState<T> extends State<StyledRadio<T>> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final Color accentColor = widget.accentColor ?? kFormAccentColor;
    final Color normalBorderColor = widget.borderColor ?? const Color(0xFFCBD5E1);
    final Color disabledBorderColor = widget.disabledBorderColor ?? const Color(0xFFE2E8F0);

    final bool isSelected = widget.value == widget.groupValue;
    final Color borderColor = widget.enabled
        ? (_isHovered ? accentColor : normalBorderColor)
        : disabledBorderColor;

    return MouseRegion(
      cursor: widget.enabled && widget.onChanged != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.enabled && widget.onChanged != null
            ? () => widget.onChanged!(widget.value)
            : null,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? (widget.enabled ? accentColor : disabledBorderColor)
                  : borderColor,
              width: widget.borderWidth,
            ),
            color: Colors.transparent,
          ),
          child: isSelected
              ? Center(
                  child: Container(
                    width: widget.innerSize,
                    height: widget.innerSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.enabled ? accentColor : disabledBorderColor,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

/// 스타일이 적용된 Primary 버튼 (파란 배경, 호버 시 테두리 강조)
class StyledPrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double? height;
  final double? width;
  final double fontSize;
  final Color? backgroundColor;
  final Color? hoverBorderColor;
  final String? tooltip;

  const StyledPrimaryButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.height = 56,
    this.width,
    this.fontSize = 16,
    this.backgroundColor,
    this.hoverBorderColor,
    this.tooltip,
  }) : super(key: key);

  @override
  State<StyledPrimaryButton> createState() => _StyledPrimaryButtonState();
}

class _StyledPrimaryButtonState extends State<StyledPrimaryButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.backgroundColor ?? kFormPrimaryColor;
    final hoverBorderColor = widget.hoverBorderColor ?? kFormAccentColor;
    final isDisabled = widget.onPressed == null || widget.isLoading;

    final borderColor = isDisabled
        ? Colors.grey[300]!
        : (_isHovered ? hoverBorderColor : primaryColor);

    Widget button = MouseRegion(
      cursor: isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: SizedBox(
        height: widget.height,
        width: widget.width ?? double.infinity,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: borderColor,
              width: 1,
            ),
          ),
          child: ElevatedButton(
            onPressed: widget.isLoading ? null : widget.onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              disabledBackgroundColor: Colors.grey[300],
              elevation: 0,
              overlayColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            child: widget.isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: widget.fontSize,
                      color: isDisabled ? Colors.grey[500] : Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// 스타일이 적용된 Outlined 버튼 (흰 배경 + 테두리, 호버 시 테두리 색상 변경)
class StyledOutlinedButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double? height;
  final double? width;
  final double fontSize;
  final Color? borderColor;
  final Color? hoverBorderColor;
  final Color? textColor;
  final String? tooltip;
  final bool fillWidth;
  final EdgeInsetsGeometry? padding;
  final Widget? icon;
  final double iconSpacing;

  const StyledOutlinedButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.height,
    this.width,
    this.fontSize = 16,
    this.borderColor,
    this.hoverBorderColor,
    this.textColor,
    this.tooltip,
    this.fillWidth = true,
    this.padding,
    this.icon,
    this.iconSpacing = 8,
  }) : super(key: key);

  @override
  State<StyledOutlinedButton> createState() => _StyledOutlinedButtonState();
}

class _StyledOutlinedButtonState extends State<StyledOutlinedButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverBorderColor = widget.hoverBorderColor ?? kFormPrimaryColor;
    final isDisabled = widget.onPressed == null || widget.isLoading;

    final borderColor = isDisabled
        ? Colors.grey[300]!
        : (_isHovered ? hoverBorderColor : (widget.borderColor ?? Colors.grey[300]!));

    final textColor = isDisabled
        ? Colors.grey[400]
        : (_isHovered ? hoverBorderColor : (widget.textColor ?? Colors.grey[600]));

    // StyledCompactButton과 동일한 Container 기반 구조 사용
    final container = Container(
      height: widget.height,
      width: widget.fillWidth ? double.infinity : null,
      padding: widget.padding ?? const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: isDisabled ? Colors.grey[100] : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
      ),
      child: widget.isLoading
          ? Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[600]!),
                ),
              ),
            )
          : Center(
              child: widget.icon == null
                  ? Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: widget.fontSize,
                        color: textColor,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        widget.icon!,
                        SizedBox(width: widget.iconSpacing),
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: widget.fontSize,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
            ),
    );

    final result = MouseRegion(
      cursor: isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: isDisabled ? null : widget.onPressed,
        child: container,
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: result);
    }
    return result;
  }
}

/// 스타일이 적용된 텍스트 버튼 (호버 시 밑줄 표시)
class StyledTextButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final double fontSize;
  final Color? textColor;
  final FontWeight? fontWeight;

  const StyledTextButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.fontSize = 14,
    this.textColor,
    this.fontWeight,
  }) : super(key: key);

  @override
  State<StyledTextButton> createState() => _StyledTextButtonState();
}

class _StyledTextButtonState extends State<StyledTextButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final textColor = widget.textColor ?? const Color(0xFF666666);
    final isDisabled = widget.onPressed == null;

    return MouseRegion(
      cursor: isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: Text(
          widget.label,
          style: TextStyle(
            fontSize: widget.fontSize,
            fontWeight: widget.fontWeight,
            color: isDisabled ? Colors.grey[400] : textColor,
            decoration: _isHovered && !isDisabled
                ? TextDecoration.underline
                : TextDecoration.none,
            decorationColor: textColor,
          ),
        ),
      ),
    );
  }
}

/// 컴팩트 Primary 버튼 - 작은 영역에 사용
class StyledCompactButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final double? height;
  final double? fontSize;
  final bool fillWidth;
  final String? tooltip;
  final EdgeInsetsGeometry? padding;

  const StyledCompactButton({
    Key? key,
    required this.label,
    this.onPressed,
    this.height,
    this.fontSize,
    this.fillWidth = false,
    this.tooltip,
    this.padding,
  }) : super(key: key);

  @override
  State<StyledCompactButton> createState() => _StyledCompactButtonState();
}

class _StyledCompactButtonState extends State<StyledCompactButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;
    final borderColor = isDisabled
        ? kFormDisabledColor
        : (_isHovered ? kFormAccentColor : kFormPrimaryColor);

    final container = Container(
      height: widget.height,
      width: widget.fillWidth ? double.infinity : null,
      padding: widget.padding ?? const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: isDisabled ? Colors.grey[300] : kFormPrimaryColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          widget.label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: isDisabled ? kFormDisabledColor : Colors.white,
          ),
        ),
      ),
    );

    final result = MouseRegion(
      cursor: isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: container,
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: result);
    }
    return result;
  }
}

