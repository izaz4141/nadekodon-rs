// lib/ui/widgets/settings/speed_limit_spinbox.dart
import 'package:flutter/material.dart';
import '../../../utils/settings.dart';
import '../double_spin_box.dart';

class SpeedLimitSpinBox extends StatelessWidget {
  const SpeedLimitSpinBox({super.key});

  @override
  Widget build(BuildContext context) {
    return DoubleSpinBox(
      title: "Speed Limit (MB/s)",
      subtitle: "Maximum download speed",
      valueListenable: SettingsManager.speedLimit,
      min: 0.01,
      max: 999999,
      step: 0.01,
      decimalPlaces: 2,
    );
  }
}
