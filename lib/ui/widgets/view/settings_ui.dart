import 'dart:io';
import 'package:flutter/material.dart';

import 'package:nadekodon/theme/app_theme.dart';
import 'package:nadekodon/utils/settings.dart';

import 'package:nadekodon/ui/widgets/components/section_header.dart';

class SettingsUI extends StatelessWidget {
  const SettingsUI({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'UI Settings', icon: Icons.palette_rounded),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: SettingsManager.themeMode,
          builder: (context, themeMode, _) {
            return ListTile(
              title: Text("Theme Mode", style: textTheme.bodyMedium),
              subtitle: Text(
                "Choose your theme mode",
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ThemeModeChip(
                    label: "System",
                    icon: Icons.settings_suggest_rounded,
                    isSelected: themeMode == ThemeMode.system,
                    onSelected: () {
                      SettingsManager.themeMode.value = ThemeMode.system;
                    },
                  ),
                  SizedBox(
                    width: AppTheme.spaceXS * AppTheme.spaceScale(context),
                  ),
                  _ThemeModeChip(
                    label: "Light",
                    icon: Icons.light_mode_rounded,
                    isSelected: themeMode == ThemeMode.light,
                    onSelected: () {
                      SettingsManager.themeMode.value = ThemeMode.light;
                    },
                  ),
                  SizedBox(
                    width: AppTheme.spaceXS * AppTheme.spaceScale(context),
                  ),
                  _ThemeModeChip(
                    label: "Dark",
                    icon: Icons.dark_mode_rounded,
                    isSelected: themeMode == ThemeMode.dark,
                    onSelected: () {
                      SettingsManager.themeMode.value = ThemeMode.dark;
                    },
                  ),
                ],
              ),
            );
          },
        ),
        ValueListenableBuilder<bool>(
          valueListenable: SettingsManager.useDynamicColor,
          builder: (context, useDynamicColor, _) {
            return Column(
              children: [
                ListTile(
                  title: Text("Use Dynamic Color", style: textTheme.bodyMedium),
                  subtitle: Text(
                    "Use system wallpaper colors",
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  trailing: Switch(
                    value: useDynamicColor,
                    onChanged: (value) {
                      SettingsManager.useDynamicColor.value = value;
                    },
                  ),
                ),
                if (!useDynamicColor)
                  ValueListenableBuilder<int>(
                    valueListenable: SettingsManager.customColor,
                    builder: (context, customColorValue, _) {
                      return ListTile(
                        title: Text(
                          "Custom Color",
                          style: textTheme.bodyMedium,
                        ),
                        subtitle: Text(
                          "Custom color for the app",
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        trailing: GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => SimpleColorPicker(
                                currentColor: Color(customColorValue),
                                onColorSelected: (color) {
                                  SettingsManager.customColor.value = color
                                      .toARGB32();
                                  Navigator.of(context).pop();
                                },
                              ),
                            );
                          },
                          child: Container(
                            width:
                                AppTheme.spaceXXL *
                                AppTheme.spaceScale(context),
                            height:
                                AppTheme.spaceXXL *
                                AppTheme.spaceScale(context),
                            decoration: BoxDecoration(
                              color: Color(customColorValue),
                              shape: BoxShape.circle,
                              border: Border.all(
                                width: 2,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
        if (!Platform.isAndroid)
          ValueListenableBuilder<bool>(
            valueListenable: SettingsManager.retreatToTray,
            builder: (context, value, _) {
              return ListTile(
                title: Text(
                  "Close to system tray",
                  style: textTheme.bodyMedium,
                ),
                subtitle: Text(
                  "Minimize to system tray instead of exiting the application",
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                trailing: Transform.scale(
                  scale: AppTheme.iconScale(context),
                  alignment: Alignment.centerRight,
                  child: Switch(
                    value: value,
                    onChanged: (newValue) {
                      SettingsManager.retreatToTray.value = newValue;
                    },
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _ThemeModeChip extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onSelected;

  const _ThemeModeChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  State<_ThemeModeChip> createState() => _ThemeModeChipState();
}

class _ThemeModeChipState extends State<_ThemeModeChip> {
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

class SimpleColorPicker extends StatelessWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorSelected;

  const SimpleColorPicker({
    super.key,
    required this.currentColor,
    required this.onColorSelected,
  });

  static const List<Color> _colors = [
    Colors.red,
    Colors.pinkAccent,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.brown,
    Colors.grey,
    Colors.blueGrey,
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text("Select Color", style: textTheme.titleMedium),
      content: SingleChildScrollView(
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _colors.map((color) {
            return GestureDetector(
              onTap: () => onColorSelected(color),
              child: Container(
                width: AppTheme.spaceXXL * AppTheme.spaceScale(context),
                height: AppTheme.spaceXXL * AppTheme.spaceScale(context),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: currentColor.toARGB32() == color.toARGB32()
                        ? colors.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: currentColor.toARGB32() == color.toARGB32()
                    ? Icon(
                        Icons.check,
                        color: Colors.white,
                        size: AppTheme.iconMD * AppTheme.iconScale(context),
                      )
                    : null,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
