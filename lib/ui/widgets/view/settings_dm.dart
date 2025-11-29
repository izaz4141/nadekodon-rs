import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'package:nadekodon/ui/widgets/components/section_header.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/settings.dart';
import '../components/spin_box.dart';
import '../components/double_spin_box.dart';

class SettingsDM extends StatelessWidget {
  const SettingsDM({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        const SectionHeader(
          title: 'DM Settings',
          icon: Icons.downloading_rounded,
        ),
        ValueListenableBuilder<String>(
          valueListenable: SettingsManager.downloadFolder,
          builder: (context, value, _) {
            return ListTile(
              title: Text("Download Folder", style: textTheme.bodyMedium),
              subtitle: Text(
                value.isEmpty ? "No Folder Selected" : value,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              trailing: IconButton(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.spaceXL * AppTheme.spaceScale(context),
                  vertical: AppTheme.spaceSM * AppTheme.spaceScale(context),
                ),
                icon: const Icon(Icons.folder_open),
                iconSize: AppTheme.iconMD * AppTheme.spaceScale(context),
                onPressed: () async {
                  String? selectedDirectory = await FilePicker.platform
                      .getDirectoryPath();
                  if (selectedDirectory != null) {
                    SettingsManager.downloadFolder.value = selectedDirectory;
                  }
                },
              ),
            );
          },
        ),
        DoubleSpinBox(
          title: "Speed Limit",
          subtitle: "Maximum download speed (MB/s)",
          valueListenable: SettingsManager.speedLimit,
          min: 0.00,
          max: 999999,
          step: 0.1,
          decimalPlaces: 2,
        ),
        SpinBox(
          title: "Download Thread",
          subtitle: "Number of thread per download",
          valueListenable: SettingsManager.downloadThreads,
          min: 1,
          max: 16,
        ),
        SpinBox(
          title: "Concurrency Limit",
          subtitle: "Maximum number of simultaneous download",
          valueListenable: SettingsManager.concurrencyLimit,
          min: 1,
          max: 255,
        ),
        SpinBox(
          title: "Download Timeout",
          subtitle: "Maximum download timeout (s)",
          valueListenable: SettingsManager.downloadTimeout,
          min: 0,
          max: 9999999,
        ),
        SpinBox(
          title: "Download Retries",
          subtitle: "Number of download retries before error",
          valueListenable: SettingsManager.downloadRetries,
          min: 0,
          max: 10,
        ),
      ],
    );
  }
}
