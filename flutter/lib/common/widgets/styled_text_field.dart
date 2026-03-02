/// 범용 스타일 텍스트 필드 위젯
/// 호버/포커스 효과가 포함된 커스텀 TextField
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 범용 스타일 텍스트 필드 - 호버/포커스 효과 포함
/// 앱 전체에서 사용 가능한 통일된 스타일의 TextField
class StyledTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? labelText;
  final String? errorText;
  final String? helperText;
  final bool obscureText;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final Widget? prefix;
  final Widget? suffix;
  final String? suffixText;
  final TextStyle? suffixStyle;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final bool autofocus;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final bool isCollapsed;
  final bool isDense;
  final EdgeInsetsGeometry? contentPadding;

  const StyledTextField({
    Key? key,
    required this.controller,
    this.focusNode,
    this.hintText,
    this.labelText,
    this.errorText,
    this.helperText,
    this.obscureText = false,
    this.suffixIcon,
    this.prefixIcon,
    this.prefix,
    this.suffix,
    this.suffixText,
    this.suffixStyle,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.autofocus = false,
    this.inputFormatters,
    this.textInputAction,
    this.isCollapsed = false,
    this.isDense = false,
    this.contentPadding,
  }) : super(key: key);

  @override
  State<StyledTextField> createState() => _StyledTextFieldState();
}

/// AuthTextField는 StyledTextField의 별칭 (하위 호환성)
typedef AuthTextField = StyledTextField;

class _StyledTextFieldState extends State<StyledTextField> {
  bool _isHovered = false;
  bool _isFocused = false;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _isFocused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF5B7BF8);
    final isHighlighted = widget.enabled && (_isHovered || _isFocused);
    final isDisabled = !widget.enabled;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        enabled: widget.enabled,
        maxLines: widget.obscureText ? 1 : widget.maxLines,
        minLines: widget.minLines,
        maxLength: widget.maxLength,
        autofocus: widget.autofocus,
        inputFormatters: widget.inputFormatters,
        textInputAction: widget.textInputAction,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(fontSize: 15, color: Colors.grey[400]),
          labelText: widget.labelText,
          errorText: widget.errorText,
          helperText: widget.helperText,
          helperMaxLines: 8,
          suffixIcon: widget.suffixIcon,
          prefixIcon: widget.prefixIcon,
          prefix: widget.prefix,
          suffix: widget.suffix,
          suffixText: widget.suffixText,
          suffixStyle: widget.suffixStyle,
          isCollapsed: widget.isCollapsed,
          isDense: widget.isDense,
          filled: true,
          fillColor: isDisabled ? Colors.grey[100] : Colors.white,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
                color: isHighlighted ? primaryColor : Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
                color: isHighlighted ? primaryColor : Colors.grey[300]!),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[200]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: primaryColor),
          ),
          contentPadding: widget.contentPadding ??
              const EdgeInsets.symmetric(horizontal: 23, vertical: 23),
        ),
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}
