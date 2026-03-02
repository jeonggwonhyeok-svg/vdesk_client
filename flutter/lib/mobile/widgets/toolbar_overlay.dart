import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_hbb/common.dart';

/// Toolbar popup menu item data.
class SimpleMenuItem {
  final String label;
  final VoidCallback onTap;
  final String? assetPath;
  final Color? iconColor;
  SimpleMenuItem(this.label, this.onTap, {this.assetPath, this.iconColor});
}

/// Card wrapper for toolbar sections.
Widget toolbarCard({required Widget child}) {
  return Material(
    elevation: 3,
    borderRadius: BorderRadius.circular(8),
    color: Colors.white,
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300, width: 0.5),
      ),
      child: child,
    ),
  );
}

/// 40x40 icon button with optional pressed/background state.
Widget toolbarIconButton({
  required String asset,
  VoidCallback? onPressed,
  Color? iconColor,
  Color? bgColor,
  bool isPressed = false,
}) {
  const accentColor = Color(0xFF5F71FF);
  return GestureDetector(
    onTap: onPressed,
    child: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isPressed
            ? accentColor.withValues(alpha: 0.2)
            : (bgColor ?? Colors.transparent),
        borderRadius: BorderRadius.circular(6),
        border: isPressed
            ? Border.all(color: accentColor, width: 1.5)
            : null,
      ),
      child: Center(
        child: SvgPicture.asset(
          asset,
          width: 20,
          height: 20,
          colorFilter: svgColor(
            isPressed ? accentColor : (iconColor ?? Colors.grey[700]!),
          ),
        ),
      ),
    ),
  );
}

/// Popup button that opens a styled dropdown menu.
Widget toolbarPopupButton({
  required String asset,
  required List<SimpleMenuItem> items,
  String? label,
  bool isPortrait = true,
}) {
  if (items.isEmpty) return const SizedBox.shrink();
  const accentColor = Color(0xFF5F71FF);
  return PopupButtonWrapper(
    accentColor: accentColor,
    asset: asset,
    label: label,
    items: items,
    isPortrait: isPortrait,
  );
}

/// Vertical separator line for toolbar.
Widget toolbarSeparator() {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Container(
      width: 1,
      height: 24,
      color: Colors.grey[300],
    ),
  );
}

/// Mini SVG button shown when toolbar is folded.
Widget miniShowButton({required VoidCallback onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: SvgPicture.asset(
      'assets/icons/remote-left-mini.svg',
      width: 16,
      height: 40,
      colorFilter: svgColor(const Color(0xFFFEFEFE)),
    ),
  );
}

/// Styled popup menu button wrapper.
class PopupButtonWrapper extends StatefulWidget {
  final Color accentColor;
  final String asset;
  final String? label;
  final List<SimpleMenuItem> items;
  final bool isPortrait;

  const PopupButtonWrapper({
    Key? key,
    required this.accentColor,
    required this.asset,
    this.label,
    required this.items,
    this.isPortrait = true,
  }) : super(key: key);

  @override
  State<PopupButtonWrapper> createState() => _PopupButtonWrapperState();
}

class _PopupButtonWrapperState extends State<PopupButtonWrapper> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    final itemCount = widget.items.length + (widget.label != null ? 1 : 0);
    final popupHeight = itemCount * 40.0 + 16;
    final popupOffset = widget.isPortrait
        ? const Offset(0, 44)
        : Offset(0, -popupHeight - 8);

    final headerItems = <PopupMenuEntry<int>>[];
    if (widget.label != null) {
      headerItems.add(PopupMenuItem<int>(
        value: -1,
        enabled: false,
        height: 0,
        padding: EdgeInsets.zero,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFFEFF1FF),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
          child: Text(
            translate(widget.label!),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5F71FF),
            ),
          ),
        ),
      ));
    }

    return PopupMenuButton<int>(
      tooltip: '',
      onOpened: () => setState(() => _isOpen = true),
      onCanceled: () => setState(() => _isOpen = false),
      onSelected: (index) {
        setState(() => _isOpen = false);
        if (index >= 0 && index < widget.items.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.items[index].onTap();
          });
        }
      },
      offset: popupOffset,
      clipBehavior: Clip.antiAlias,
      menuPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      itemBuilder: (context) => [
        ...headerItems,
        ...widget.items.asMap().entries.map((entry) {
          final item = entry.value;
          return PopupMenuItem<int>(
            value: entry.key,
            height: 40,
            padding: EdgeInsets.zero,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.assetPath != null) ...[
                    SvgPicture.asset(
                      item.assetPath!,
                      width: 18,
                      height: 18,
                      colorFilter:
                          svgColor(item.iconColor ?? Colors.grey[700]!),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(translate(item.label),
                      style:
                          TextStyle(fontSize: 14, color: item.iconColor)),
                ],
              ),
            ),
          );
        }),
      ],
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _isOpen ? Colors.grey[200] : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: SvgPicture.asset(
            widget.asset,
            width: 20,
            height: 20,
            colorFilter: svgColor(Colors.grey[700]!),
          ),
        ),
      ),
    );
  }
}
