import 'package:flutter/material.dart';
import 'package:nadekodon/theme/app_theme.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: AppTheme.spaceSM * AppTheme.spaceScale(context),
        horizontal: AppTheme.spaceSM * AppTheme.spaceScale(context),
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.spaceLG * AppTheme.spaceScale(context),
          vertical: AppTheme.spaceMD * AppTheme.spaceScale(context),
        ),
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(
            AppTheme.radiusLG * AppTheme.radiusScale(context),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: colors.onPrimaryContainer,
              size: AppTheme.iconMD * AppTheme.iconScale(context),
            ),
            SizedBox(width: AppTheme.spaceMD * AppTheme.spaceScale(context)),
            Text(
              title,
              style: textTheme.titleMedium?.copyWith(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (trailing != null) ...[const Spacer(), trailing!],
          ],
        ),
      ),
    );
  }
}
