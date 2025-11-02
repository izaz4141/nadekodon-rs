// lib/ui/widgets/settings/download_thread_spinbox.dart
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/settings.dart';
import '../spin_box.dart';

class DownloadThreadBox extends StatelessWidget {
  const DownloadThreadBox({super.key});

  @override
  Widget build(BuildContext context) {
    return SpinBox(
      title: "Download Thread",
      subtitle: "Number of thread per download",
      valueListenable: SettingsManager.downloadThreads,
      min: 1,
      max: 16,
    );
  }
}
