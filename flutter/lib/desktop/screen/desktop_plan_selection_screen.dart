import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/plan_selection_page.dart';

/// 플랜 선택 창
class DesktopPlanSelectionScreen extends StatelessWidget {
  final Map<String, dynamic> params;

  const DesktopPlanSelectionScreen({Key? key, required this.params})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: PlanSelectionPage(),
    );
  }
}
