import 'package:flutter/material.dart';
import 'package:nadekodon/ui/widgets/components/section_header.dart';
import 'package:nadekodon/utils/settings.dart';

class SettingsMisc extends StatelessWidget {
  const SettingsMisc({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Misc',
          icon: Icons.miscellaneous_services_rounded,
        ),
        ValueListenableBuilder<bool>(
          valueListenable: SettingsManager.checkNightly,
          builder: (context, checkNightly, _) {
            return ListTile(
              title: Text(
                "Check for Nightly Updates",
                style: textTheme.bodyMedium,
              ),
              subtitle: Text(
                "Include pre-release versions in update checks",
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              trailing: Switch(
                value: checkNightly,
                onChanged: (value) {
                  SettingsManager.checkNightly.value = value;
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
