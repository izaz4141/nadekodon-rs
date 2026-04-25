import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/app_snackbar.dart';
import 'package:nadekodon/utils/log_service.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  int? _sortColumnIndex = 1;
  bool _sortAscending = false;
  bool _showDebug = true;
  bool _showWarning = true;
  bool _showStdout = true;
  final Set<LogEntry> _selectedLogs = {};

  List<LogEntry> _getFilteredLogs() {
    final filtered = LogService.logs.value.where((log) {
      if (!_showDebug && log.level == LogLevel.debug) return false;
      if (!_showWarning && log.level == LogLevel.warning) return false;
      if (!_showStdout && log.level == LogLevel.stdout) return false;
      return true;
    }).toList();

    if (_sortColumnIndex == 1) {
      filtered.sort((a, b) {
        final comparison = a.timestamp.compareTo(b.timestamp);
        return _sortAscending ? comparison : -comparison;
      });
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Logs', style: textTheme.titleMedium),
        actions: [
          IconButton(
            tooltip: 'Copy selected logs',
            onPressed: _selectedLogs.isEmpty
                ? null
                : () {
                    final selectedLogText = _selectedLogs
                        .map(
                          (log) =>
                              '[${log.level.toString().split('.').last.toUpperCase()}] [${log.timestamp}] ${log.message}',
                        )
                        .join('\n');
                    Clipboard.setData(ClipboardData(text: selectedLogText));
                    AppSnackBar.show(
                      context,
                      'Logs copied to clipboard',
                      type: SnackType.success,
                    );
                  },
            icon: const Icon(Icons.copy),
            iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
          ),
          IconButton(
            tooltip: 'Clear all logs',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Clear Logs', style: textTheme.titleMedium),
                  content: Text(
                    'Are you sure you want to clear all logs?',
                    style: textTheme.bodyMedium,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                await LogService.clearLogs();
                setState(() {
                  _selectedLogs.clear();
                });
              }
            },
            icon: const Icon(Icons.delete_outline),
            iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMD),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: Text('Debug', style: textTheme.bodySmall),
                  selected: _showDebug,
                  onSelected: (selected) {
                    setState(() {
                      _showDebug = selected;
                    });
                  },
                  avatar: Icon(_showDebug ? Icons.check : Icons.close),
                  selectedColor: colors.primaryContainer,
                ),
                const SizedBox(width: AppTheme.spaceSM),
                ChoiceChip(
                  label: Text('Warning', style: textTheme.bodySmall),
                  selected: _showWarning,
                  onSelected: (selected) {
                    setState(() {
                      _showWarning = selected;
                    });
                  },
                  avatar: Icon(_showWarning ? Icons.check : Icons.close),
                  selectedColor: colors.primaryContainer,
                ),
                const SizedBox(width: AppTheme.spaceSM),
                ChoiceChip(
                  label: Text('Stdout', style: textTheme.bodySmall),
                  selected: _showStdout,
                  onSelected: (selected) {
                    setState(() {
                      _showStdout = selected;
                    });
                  },
                  avatar: Icon(_showStdout ? Icons.check : Icons.close),
                  selectedColor: colors.primaryContainer,
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceMD),
            Expanded(
              child: ValueListenableBuilder<List<LogEntry>>(
                valueListenable: LogService.logs,
                builder: (context, logs, child) {
                  final filteredLogs = _getFilteredLogs();
                  return Container(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest.withAlpha(128),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                    ),
                    child: filteredLogs.isEmpty
                        ? Center(
                            child: Text(
                              'No logs yet.',
                              style: textTheme.bodyMedium,
                            ),
                          )
                        : SingleChildScrollView(
                            child: IntrinsicWidth(
                              child: DataTable(
                                sortColumnIndex: _sortColumnIndex,
                                sortAscending: _sortAscending,
                                columnSpacing: AppTheme.spaceMD,
                                horizontalMargin: AppTheme.spaceMD,
                                columns: [
                                  const DataColumn(label: Text('LEVEL')),
                                  DataColumn(
                                    label: const Text('TIMESTAMP'),
                                    onSort: (columnIndex, ascending) {
                                      setState(() {
                                        _sortColumnIndex = columnIndex;
                                        _sortAscending = ascending;
                                      });
                                    },
                                  ),
                                  const DataColumn(label: Text('MESSAGE')),
                                ],
                                rows: filteredLogs.map((log) {
                                  final isSelected = _selectedLogs.contains(
                                    log,
                                  );
                                  return DataRow(
                                    selected: isSelected,
                                    onSelectChanged: (selected) {
                                      setState(() {
                                        if (selected == true) {
                                          _selectedLogs.add(log);
                                        } else {
                                          _selectedLogs.remove(log);
                                        }
                                      });
                                    },
                                    cells: [
                                      DataCell(
                                        _buildLevelBadge(
                                          log.level,
                                          colors,
                                          textTheme,
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          '${DateFormat('yyyy/MM/dd').format(log.timestamp)} ${DateFormat('HH:mm:ss').format(log.timestamp)}',
                                          style: textTheme.bodySmall,
                                        ),
                                      ),
                                      DataCell(
                                        SelectableText(
                                          log.message,
                                          style: textTheme.bodySmall?.copyWith(
                                            color: log.level == LogLevel.error
                                                ? colors.error
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelBadge(
    LogLevel level,
    ColorScheme colors,
    TextTheme textTheme,
  ) {
    Color backgroundColor;
    Color textColor;
    String label;

    switch (level) {
      case LogLevel.error:
        backgroundColor = colors.errorContainer;
        textColor = colors.onErrorContainer;
        label = 'ERROR';
      case LogLevel.warning:
        backgroundColor = Colors.orange.shade100;
        textColor = Colors.orange.shade900;
        label = 'WARN';
      case LogLevel.info:
        backgroundColor = colors.primaryContainer;
        textColor = colors.onPrimaryContainer;
        label = 'INFO';
      case LogLevel.debug:
        backgroundColor = colors.secondaryContainer;
        textColor = colors.onSecondaryContainer;
        label = 'DEBUG';
      case LogLevel.stdout:
        backgroundColor = colors.surfaceContainerHighest;
        textColor = colors.onSurfaceVariant;
        label = 'STDOUT';
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spaceSM,
        vertical: AppTheme.spaceXS,
      ),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1,
          colors: [backgroundColor, backgroundColor.withAlpha(100)],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        border: Border.all(color: textColor.withAlpha(40), width: 0.5),
      ),
      child: Text(
        label,
        style: textTheme.bodySmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: AppTheme.textXS,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
