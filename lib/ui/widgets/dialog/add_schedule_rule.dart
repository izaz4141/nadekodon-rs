import 'package:flutter/material.dart';
import 'package:nadekodon/utils/speed_scheduler.dart';
import 'package:nadekodon/ui/widgets/components/double_spin_box.dart';
import 'package:nadekodon/theme/app_theme.dart';

class AddScheduleRuleDialog extends StatefulWidget {
  const AddScheduleRuleDialog({super.key});

  @override
  State<AddScheduleRuleDialog> createState() => _AddScheduleRuleDialogState();
}

class _AddScheduleRuleDialogState extends State<AddScheduleRuleDialog> {
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  final ValueNotifier<double> _speedLimit = ValueNotifier(1.0);

  @override
  Widget build(BuildContext context) {
    final scale = AppTheme.spaceScale(context);

    return AlertDialog(
      title: const Text("Add Schedule Rule"),
      content: SizedBox(
        width: 400 * scale,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildTimePicker(
                    context,
                    "Start Time",
                    _startTime,
                    (t) => setState(() => _startTime = t),
                  ),
                ),
                SizedBox(width: AppTheme.spaceMD * scale),
                Expanded(
                  child: _buildTimePicker(
                    context,
                    "End Time",
                    _endTime,
                    (t) => setState(() => _endTime = t),
                  ),
                ),
              ],
            ),
            SizedBox(height: AppTheme.spaceLG * scale),
            DoubleSpinBox(
              title: "Speed Limit (MB/s)",
              subtitle: "",
              valueListenable: _speedLimit,
              min: 0.0,
              max: 999999,
              step: 0.1,
              decimalPlaces: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: (_startTime != null && _endTime != null)
              ? () {
                  Navigator.of(context).pop(
                    ScheduleRule(
                      startTime: _startTime!,
                      endTime: _endTime!,
                      speedLimit: _speedLimit.value,
                    ),
                  );
                }
              : null,
          child: const Text("Add"),
        ),
      ],
    );
  }

  Widget _buildTimePicker(
    BuildContext context,
    String label,
    TimeOfDay? selected,
    Function(TimeOfDay) onSelect,
  ) {
    return InkWell(
      onTap: () async {
        final t = await showTimePicker(
          context: context,
          initialTime: selected ?? TimeOfDay.now(),
        );
        if (t != null) onSelect(t);
      },
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: Theme.of(context).textTheme.bodyMedium,
          border: const OutlineInputBorder(),
        ),
        child: Text(
          selected?.format(context) ?? "Select",
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
