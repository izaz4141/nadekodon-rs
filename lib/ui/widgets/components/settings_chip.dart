import 'package:flutter/material.dart';
import 'package:nadekodon/theme/app_theme.dart';

class SettingsChip extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onSelected;

  const SettingsChip({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  State<SettingsChip> createState() => _SettingsChipState();
}

class _SettingsChipState extends State<SettingsChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: ActionChip(
          label: Text(
            widget.label,
            style: textTheme.bodySmall?.copyWith(
              color: widget.isSelected
                  ? colors.onSecondaryContainer
                  : colors.onSurfaceVariant,
              fontWeight: widget.isSelected
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
          avatar: Icon(
            widget.icon,
            size: AppTheme.iconSM * AppTheme.iconScale(context),
            color: widget.isSelected
                ? colors.onSecondaryContainer
                : colors.onSurfaceVariant,
          ),
          backgroundColor: widget.isSelected
              ? colors.secondaryContainer
              : (_isHovered
                    ? colors.surfaceContainerHighest
                    : colors.surfaceContainer),
          side: widget.isSelected
              ? BorderSide(color: colors.secondary.withAlpha(128), width: 1.5)
              : BorderSide(color: colors.outline.withAlpha(64)),
          onPressed: widget.onSelected,
          elevation: _isHovered && !widget.isSelected ? 2 : 0,
          shadowColor: colors.shadow.withAlpha(128),
        ),
      ),
    );
  }
}
