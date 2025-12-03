import 'package:flutter/material.dart';
import 'package:nadekodon/theme/app_theme.dart';

import 'package:nadekodon/utils/helper.dart';

class DownloadCard extends StatefulWidget {
  final DownloadItem item;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(TapDownDetails)? onMenuPressed;
  final VoidCallback onPauseResume;
  final VoidCallback onCancel;
  final void Function(TapDownDetails)? onSecondaryTapDown;

  const DownloadCard({
    super.key,
    required this.item,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onTap,
    this.onLongPress,
    this.onMenuPressed,
    required this.onPauseResume,
    required this.onCancel,
    this.onSecondaryTapDown,
  });

  @override
  State<DownloadCard> createState() => _DownloadCardState();
}

class _DownloadCardState extends State<DownloadCard> {
  bool _isHovering = false;

  Color _progressColor(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    switch (widget.item.status) {
      case DownloadStatus.queued:
        return colors.tertiary;
      case DownloadStatus.running:
        return colors.primary;
      case DownloadStatus.seeding:
        return colors.primary;
      case DownloadStatus.paused:
        return colors.secondary;
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.cancelled:
        return colors.secondary;
      case DownloadStatus.failed:
        return colors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDesktop = AppTheme.isDesktop(context);

    // Determine background color based on state
    Color? cardColor;
    if (widget.isSelected) {
      cardColor = colors.primaryContainer.withValues(alpha: 0.3);
    } else if (_isHovering) {
      cardColor = colors.surfaceContainerHigh;
    }

    final spaceScale = AppTheme.spaceScale(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: Card(
          color: cardColor,
          margin: EdgeInsets.symmetric(
            vertical: AppTheme.spaceXS * spaceScale,
            horizontal: AppTheme.spaceMD * spaceScale,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              AppTheme.radiusMD * AppTheme.radiusScale(context),
            ),
            side: widget.isSelected
                ? BorderSide(color: colors.primary, width: 2)
                : BorderSide.none,
          ),
          child: Padding(
            padding: EdgeInsets.all(AppTheme.spaceSM * spaceScale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + Status row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.item.name,
                        style: textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: AppTheme.spaceSM * spaceScale),
                    Text(
                      widget.item.status.name.toUpperCase(),
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _progressColor(context),
                      ),
                    ),
                    if (!isDesktop) ...[
                      SizedBox(width: AppTheme.spaceXS * spaceScale),
                      Material(
                        color: Colors.transparent,
                        child: InkResponse(
                          onTapDown: widget.onMenuPressed,
                          onTap: () {}, // Required for ripple
                          radius: AppTheme.iconSM,
                          customBorder: const CircleBorder(),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(Icons.more_vert, size: AppTheme.iconSM),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: AppTheme.spaceSM * spaceScale),
                LinearProgressIndicator(
                  value: widget.item.progress,
                  backgroundColor: colors.surfaceContainerHighest,
                  color: _progressColor(context),
                  minHeight: AppTheme.spaceSM * spaceScale,
                  borderRadius: BorderRadius.circular(
                    AppTheme.radiusSM * AppTheme.radiusScale(context),
                  ),
                ),
                SizedBox(height: AppTheme.spaceSM * spaceScale),
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.item.total != null
                              ? "${formatBytes(widget.item.downloaded)} / ${formatBytes(widget.item.total!)}"
                              : formatBytes(widget.item.downloaded),
                          style: textTheme.bodySmall,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.center,
                        child: Text(
                          "${formatBytes(widget.item.speed.toInt())}/s",
                          style: textTheme.bodySmall,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.stop),
                              iconSize:
                                  AppTheme.iconMD * AppTheme.iconScale(context),
                              constraints: BoxConstraints(
                                minWidth:
                                    AppTheme.iconLG *
                                    AppTheme.iconScale(context),
                                minHeight:
                                    AppTheme.iconLG *
                                    AppTheme.iconScale(context),
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: widget.onCancel,
                            ),
                            IconButton(
                              icon: Icon(
                                (widget.item.status == DownloadStatus.running ||
                                        widget.item.status ==
                                            DownloadStatus.seeding ||
                                        widget.item.status ==
                                            DownloadStatus.queued)
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                              iconSize:
                                  AppTheme.iconMD * AppTheme.iconScale(context),
                              constraints: BoxConstraints(
                                minWidth:
                                    AppTheme.iconLG *
                                    AppTheme.iconScale(context),
                                minHeight:
                                    AppTheme.iconLG *
                                    AppTheme.iconScale(context),
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: widget.onPauseResume,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
