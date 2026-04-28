import 'package:flutter/material.dart';
import 'package:nadekodon/utils/io_service.dart';

import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/utils/speed_scheduler.dart';
import 'package:nadekodon/ui/widgets/components/section_header.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/components/spin_box.dart';
import 'package:nadekodon/ui/widgets/components/double_spin_box.dart';
import 'package:nadekodon/ui/widgets/dialog/add_schedule_rule.dart';
import 'package:nadekodon/ui/widgets/dialog/category_manager.dart';
import 'package:nadekodon/ui/widgets/components/settings_chip.dart';

class SettingsDM extends StatelessWidget {
  const SettingsDM({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDesktop = AppTheme.isDesktop(context);

    return Column(
      children: [
        SectionHeader(
          title: 'DM Settings',
          leading: Icon(
            Icons.downloading_rounded,
            color: colors.onPrimaryContainer,
            size: AppTheme.iconMD * AppTheme.iconScale(context),
          ),
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
                  final ioService = IOServiceFactory.create();
                  String? selectedDirectory = await ioService
                      .getDirectoryPath();
                  if (selectedDirectory != null) {
                    SettingsManager.downloadFolder.value = selectedDirectory;
                  }
                },
              ),
            );
          },
        ),
        ListTile(
          title: Text("Categories", style: textTheme.bodyMedium),
          subtitle: Text(
            "Manage download categories",
            style: textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => const CategoryManagerDialog(),
            );
          },
        ),
        ValueListenableBuilder<SpeedMode>(
          valueListenable: SettingsManager.speedMode,
          builder: (context, mode, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                ListTile(
                  title: Text("Speed Limit", style: textTheme.bodyMedium),
                  subtitle: Text(
                    "Global download speed limit (MB/s)",
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                // Controls row
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppTheme.spaceSM * AppTheme.spaceScale(context),
                    vertical: AppTheme.spaceSM * AppTheme.spaceScale(context),
                  ),
                  child: Row(
                    children: [
                      // Mode chips on the left
                      SettingsChip(
                        label: "Fixed",
                        icon: Icons.speed_rounded,
                        iconOnly: !isDesktop,
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
                        iconOnly: !isDesktop,
                        isSelected: mode == SpeedMode.scheduled,
                        onSelected: () {
                          SettingsManager.speedMode.value = SpeedMode.scheduled;
                        },
                      ),
                      const Spacer(),
                      // Speed control on the right
                      if (mode == SpeedMode.fixed)
                        DoubleSpinControls(
                          valueListenable: SettingsManager.speedLimit,
                          min: 0.00,
                          max: 999999,
                          step: 0.1,
                          decimalPlaces: 2,
                        )
                      else
                        ValueListenableBuilder<double>(
                          valueListenable: SpeedScheduler.currentSpeed,
                          builder: (context, currentSpeed, _) {
                            return Container(
                              padding: EdgeInsets.symmetric(
                                horizontal:
                                    AppTheme.spaceMD *
                                    AppTheme.spaceScale(context),
                                vertical:
                                    AppTheme.spaceSM *
                                    AppTheme.spaceScale(context),
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusSM,
                                ),
                                border: Border.all(
                                  color: colors.outline.withAlpha(64),
                                ),
                              ),
                              child: Text(
                                currentSpeed == 0
                                    ? "∞ MB/s"
                                    : "${currentSpeed.toStringAsFixed(2)} MB/s",
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colors.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                        ),
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
              ...rules.asMap().entries.map((entry) {
                final index = entry.key;
                final rule = entry.value;
                final isLast = index == rules.length - 1;

                return Padding(
                  padding: EdgeInsets.only(
                    left: AppTheme.spaceLG * AppTheme.spaceScale(context),
                    right: AppTheme.spaceMD * AppTheme.spaceScale(context),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Vertical connector line
                        SizedBox(
                          width:
                              AppTheme.spaceMD * AppTheme.spaceScale(context),
                          child: Column(
                            children: [
                              // Top half line
                              Expanded(
                                child: Container(
                                  width: 2,
                                  color: colors.outlineVariant,
                                ),
                              ),
                              // Dot indicator
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              // Bottom half line (hidden for last item)
                              Expanded(
                                child: Container(
                                  width: 2,
                                  color: isLast
                                      ? Colors.transparent
                                      : colors.outlineVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width:
                              AppTheme.spaceSM * AppTheme.spaceScale(context),
                        ),
                        // Rule content
                        Expanded(
                          child: Container(
                            margin: EdgeInsets.symmetric(
                              vertical:
                                  AppTheme.spaceXS *
                                  AppTheme.spaceScale(context),
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal:
                                  AppTheme.spaceMD *
                                  AppTheme.spaceScale(context),
                              vertical:
                                  AppTheme.spaceSM *
                                  AppTheme.spaceScale(context),
                            ),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerHighest.withAlpha(
                                128,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusSM,
                              ),
                              border: Border.all(
                                color: colors.outlineVariant.withAlpha(64),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        "${rule.startTime.format(context)} - ${rule.endTime.format(context)}",
                                        style: textTheme.bodyMedium,
                                      ),
                                      SizedBox(
                                        height:
                                            AppTheme.spaceXS *
                                            AppTheme.spaceScale(context),
                                      ),
                                      Text(
                                        "${rule.speedLimit.toStringAsFixed(2)} MB/s",
                                        style: textTheme.bodySmall?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: colors.onSurfaceVariant,
                                  ),
                                  onPressed: () {
                                    final newRules = List<ScheduleRule>.from(
                                      rules,
                                    );
                                    newRules.remove(rule);
                                    SettingsManager.speedSchedule.value =
                                        newRules;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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
