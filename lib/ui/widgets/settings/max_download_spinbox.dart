// lib/ui/widgets/settings/max_download_spinbox.dart
import 'package:flutter/material.dart';
import '../../../utils/settings.dart';
import '../spin_box.dart';

class MaxDownloadBox extends StatelessWidget {
  const MaxDownloadBox({super.key});

  @override
  Widget build(BuildContext context) {
    return SpinBox(
      title: "Maximum Download",
      subtitle: "Maximum number of simultaneous download",
      valueListenable: SettingsManager.maxDownload,
      min: 1,
      max: 255,
    );
  }
}
