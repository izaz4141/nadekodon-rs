import 'package:flutter/material.dart';
import 'package:nadekodon/theme/app_theme.dart';

class SettingsChip extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onSelected;
  final bool iconOnly;

  const SettingsChip({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onSelected,
    this.iconOnly = false,
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

    final iconColor = widget.isSelected
        ? colors.onSecondaryContainer
        : colors.onSurfaceVariant;

    final backgroundColor = widget.isSelected
        ? colors.secondaryContainer
        : (_isHovered
              ? colors.surfaceContainerHighest
              : colors.surfaceContainer);

    final border = widget.isSelected
        ? BorderSide(color: colors.secondary.withAlpha(128), width: 1.5)
        : BorderSide(color: colors.outline.withAlpha(64));

    if (widget.iconOnly) {
      return MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: Tooltip(
          message: widget.label,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(AppTheme.radiusSM),
              border: Border.fromBorderSide(border),
              boxShadow: _isHovered && !widget.isSelected
                  ? [
                      BoxShadow(
                        color: colors.shadow.withAlpha(128),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: InkWell(
              onTap: widget.onSelected,
              borderRadius: BorderRadius.circular(AppTheme.radiusSM),
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spaceSM),
                child: Icon(
                  widget.icon,
                  size: AppTheme.iconSM * AppTheme.iconScale(context),
                  color: iconColor,
                ),
              ),
            ),
          ),
        ),
      );
    }

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
              color: iconColor,
              fontWeight: widget.isSelected
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
          avatar: Icon(
            widget.icon,
            size: AppTheme.iconSM * AppTheme.iconScale(context),
            color: iconColor,
          ),
          backgroundColor: backgroundColor,
          side: border,
          onPressed: widget.onSelected,
          elevation: _isHovered && !widget.isSelected ? 2 : 0,
          shadowColor: colors.shadow.withAlpha(128),
        ),
      ),
    );
  }
}
