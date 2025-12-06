import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nadekodon/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/components/section_header.dart';

class SystemInfo extends StatelessWidget {
  const SystemInfo({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        const SectionHeader(
          title: 'System Info',
          icon: Icons.info_outline_rounded,
        ),
        ListTile(
          leading: Icon(
            Icons.computer_outlined,
            size: AppTheme.iconMD * AppTheme.iconScale(context),
          ),
          title: Text('Platform', style: textTheme.bodyMedium),
          subtitle: Text(
            Platform.operatingSystemVersion,
            style: textTheme.bodySmall,
          ),
        ),
        ListTile(
          leading: Icon(
            Icons.memory_outlined,
            size: AppTheme.iconMD * AppTheme.iconScale(context),
          ),
          title: Text('Processors', style: textTheme.bodyMedium),
          subtitle: Text(
            Platform.numberOfProcessors.toString(),
            style: textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
