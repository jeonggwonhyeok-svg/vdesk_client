import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/custom_scale_base.dart';

class MobileCustomScaleControls extends StatefulWidget {
  final FFI ffi;
  final ValueChanged<int>? onChanged;
  const MobileCustomScaleControls({super.key, required this.ffi, this.onChanged});

  @override
  State<MobileCustomScaleControls> createState() => _MobileCustomScaleControlsState();
}

class _MobileCustomScaleControlsState extends CustomScaleControls<MobileCustomScaleControls> {
  @override
  FFI get ffi => widget.ffi;

  @override
  ValueChanged<int>? get onScaleChanged => widget.onChanged;

  static const Color _accentColor = Color(0xFF5F71FF);
  static const Color _titleColor = Color(0xFF454447);

  @override
  Widget build(BuildContext context) {
    const smallBtnConstraints = BoxConstraints(minWidth: 32, minHeight: 32);

    final sliderControl = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: _accentColor,
        inactiveTrackColor: const Color(0xFFDEDEE2),
        thumbColor: _accentColor,
        overlayColor: _accentColor.withValues(alpha: 0.1),
        showValueIndicator: ShowValueIndicator.never,
        thumbShape: _RectValueThumbShape(
          min: CustomScaleControls.minPercent.toDouble(),
          max: CustomScaleControls.maxPercent.toDouble(),
          width: 48,
          height: 22,
          radius: 4,
          displayValueForNormalized: (t) => mapPosToPercent(t),
        ),
      ),
      child: Slider(
        value: scalePos,
        min: 0.0,
        max: 1.0,
        divisions: (CustomScaleControls.maxPercent - CustomScaleControls.minPercent).round(),
        onChanged: onSliderChanged,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${translate("Scale custom")}: $scaleValue%',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _titleColor,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                iconSize: 20,
                padding: const EdgeInsets.all(4),
                constraints: smallBtnConstraints,
                icon: const Icon(Icons.remove, color: _titleColor),
                tooltip: translate('Decrease'),
                onPressed: () => nudgeScale(-1),
              ),
              Expanded(child: sliderControl),
              IconButton(
                iconSize: 20,
                padding: const EdgeInsets.all(4),
                constraints: smallBtnConstraints,
                icon: const Icon(Icons.add, color: _titleColor),
                tooltip: translate('Increase'),
                onPressed: () => nudgeScale(1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rectangular thumb shape that displays the current percentage value.
class _RectValueThumbShape extends SliderComponentShape {
  final double min;
  final double max;
  final double width;
  final double height;
  final double radius;
  final String unit;
  final int Function(double normalized)? displayValueForNormalized;

  const _RectValueThumbShape({
    required this.min,
    required this.max,
    required this.width,
    required this.height,
    required this.radius,
    this.displayValueForNormalized,
    this.unit = '%',
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size(width, height);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    final ColorTween colorTween = ColorTween(
      begin: sliderTheme.disabledThumbColor,
      end: sliderTheme.thumbColor,
    );
    final Color? evaluatedColor = colorTween.evaluate(enableAnimation);
    final Color fillColor =
        evaluatedColor ?? sliderTheme.thumbColor ?? Colors.blueAccent;

    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: height),
      Radius.circular(radius),
    );
    final Paint paint = Paint()..color = fillColor;
    canvas.drawRRect(rrect, paint);

    final int displayValue = displayValueForNormalized != null
        ? displayValueForNormalized!(value)
        : (min + value * (max - min)).round();
    final TextSpan span = TextSpan(
      text: '$displayValue$unit',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
    final TextPainter tp = TextPainter(
      text: span,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
        canvas, center + Offset(-tp.width / 2, -tp.height / 2));
  }
}
