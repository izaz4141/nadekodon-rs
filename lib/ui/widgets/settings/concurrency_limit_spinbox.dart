// lib/ui/widgets/settings/max_download_spinbox.dart
import 'package:flutter/material.dart';
import '../../../utils/settings.dart';
import '../spin_box.dart';

class ConcurrencyLimitBox extends StatelessWidget {
  const ConcurrencyLimitBox({super.key});

  @override
  Widget build(BuildContext context) {
    return SpinBox(
      title: "Concurrency Limit",
      subtitle: "Maximum number of simultaneous download",
      valueListenable: SettingsManager.concurrencyLimit,
      min: 1,
      max: 255,
    );
  }
}
