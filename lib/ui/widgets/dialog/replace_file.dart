import 'package:flutter/material.dart';

import 'package:nadekodon/theme/app_theme.dart';

class ReplaceFile extends StatelessWidget {
  const ReplaceFile({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
      ),
      title: Text("Replace file", style: textTheme.titleMedium),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overwrite existing file?', style: textTheme.bodyMedium),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text("Abort", style: textTheme.bodyMedium),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            "Proceed",
            style: textTheme.bodyMedium?.copyWith(color: colors.primary),
          ),
        ),
      ],
    );
  }
}
