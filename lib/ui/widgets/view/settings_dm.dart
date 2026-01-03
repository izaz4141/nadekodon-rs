import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'package:nadekodon/ui/widgets/components/section_header.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/settings.dart';
import '../components/spin_box.dart';
import '../components/double_spin_box.dart';
import 'package:nadekodon/utils/speed_scheduler.dart';
import 'package:nadekodon/ui/widgets/dialog/add_schedule_rule.dart';
import 'package:nadekodon/ui/widgets/components/settings_chip.dart';

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
        ValueListenableBuilder<SpeedMode>(
          valueListenable: SettingsManager.speedMode,
          builder: (context, mode, _) {
            return Column(
              children: [
                ListTile(
                  title: Text("Speed Limit", style: textTheme.bodyMedium),
                  subtitle: Text(
                    "Maximum global download speed (MB/s)",
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SettingsChip(
                        label: "Fixed",
                        icon: Icons.speed_rounded,
                        isSelected: mode == SpeedMode.fixed,
                        onSelected: () {
                          SettingsManager.speedMode.value = SpeedMode.fixed;
                        },
                      ),
                      SizedBox(
                        width: AppTheme.spaceXS * AppTheme.spaceScale(context),
                      ),
                      SettingsChip(
                        label: "Scheduled",
                        icon: Icons.schedule_rounded,
                        isSelected: mode == SpeedMode.scheduled,
                        onSelected: () {
                          SettingsManager.speedMode.value = SpeedMode.scheduled;
                        },
                      ),
                      if (mode == SpeedMode.fixed) ...[
                        SizedBox(
                          width:
                              AppTheme.spaceMD * AppTheme.spaceScale(context),
                        ),
                        DoubleSpinControls(
                          valueListenable: SettingsManager.speedLimit,
                          min: 0.00,
                          max: 999999,
                          step: 0.1,
                          decimalPlaces: 2,
                        ),
                      ] else ...[
                        SizedBox(
                          width:
                              AppTheme.spaceLG * AppTheme.spaceScale(context),
                        ),
                        ValueListenableBuilder<double>(
                          valueListenable: SpeedScheduler.currentSpeed,
                          builder: (context, currentSpeed, _) {
                            return Text(
                              currentSpeed == 0
                                  ? "∞ MB/s"
                                  : "${currentSpeed.toStringAsFixed(2)} MB/s",
                              style: textTheme.bodyMedium?.copyWith(
                                color: colors.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                        SizedBox(
                          width:
                              AppTheme.spaceLG * AppTheme.spaceScale(context),
                        ),
                      ],
                    ],
                  ),
                ),
                if (mode == SpeedMode.scheduled) const _ScheduleList(),
              ],
            );
          },
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
        DoubleSpinBox(
          title: "Seeding Ratio",
          subtitle: "Ratio of uploaded to downloaded data",
          valueListenable: SettingsManager.seedingRatio,
          min: 0.00,
          max: 999999,
          step: 0.1,
          decimalPlaces: 2,
        ),
        SpinBox(
          title: "Seeding Time",
          subtitle: "Maximum seeding time (Minutes)",
          valueListenable: SettingsManager.seedingTime,
          min: 0,
          max: 999999,
        ),
      ],
    );
  }
}

class _ScheduleList extends StatefulWidget {
  const _ScheduleList();

  @override
  State<_ScheduleList> createState() => _ScheduleListState();
}

class _ScheduleListState extends State<_ScheduleList> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ValueListenableBuilder<List<ScheduleRule>>(
      valueListenable: SettingsManager.speedSchedule,
      builder: (context, rules, _) {
        return Column(
          children: [
            // Header to toggle visibility
            if (rules.isNotEmpty)
              ListTile(
                title: Text(
                  "Schedule Rules (${rules.length})",
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                trailing: Icon(
                  _isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: colors.onSurface,
                ),
                onTap: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
              ),

            // The list of rules (collapsible)
            if (_isExpanded && rules.isNotEmpty)
              ...rules.map((rule) {
                return ListTile(
                  contentPadding: EdgeInsets.only(
                    left: AppTheme.spaceXL * AppTheme.spaceScale(context),
                    right: AppTheme.spaceMD * AppTheme.spaceScale(context),
                  ),
                  title: Text(
                    "${rule.startTime.format(context)} - ${rule.endTime.format(context)}",
                    style: textTheme.bodyMedium,
                  ),
                  subtitle: Text(
                    "${rule.speedLimit.toStringAsFixed(2)} MB/s",
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline, color: colors.onSurface),
                    onPressed: () {
                      final newRules = List<ScheduleRule>.from(rules);
                      newRules.remove(rule);
                      SettingsManager.speedSchedule.value = newRules;
                    },
                  ),
                );
              }),

            // Always visible Add Rule button
            ListTile(
              leading: Icon(Icons.add, color: colors.onSurface),
              title: Text("Add Rule", style: textTheme.bodyMedium),
              onTap: () async {
                final result = await showDialog<ScheduleRule>(
                  context: context,
                  builder: (context) => const AddScheduleRuleDialog(),
                );
                if (result != null) {
                  final newRules = List<ScheduleRule>.from(rules);
                  newRules.add(result);
                  newRules.sort((a, b) {
                    final aMin = a.startTime.hour * 60 + a.startTime.minute;
                    final bMin = b.startTime.hour * 60 + b.startTime.minute;
                    return aMin.compareTo(bMin);
                  });
                  SettingsManager.speedSchedule.value = newRules;

                  // Auto-expand when adding a rule if not already
                  if (!_isExpanded) {
                    setState(() {
                      _isExpanded = true;
                    });
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }
}
