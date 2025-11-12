import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nadekodon/theme/app_theme.dart';
import 'package:nadekodon/utils/log_entry.dart';
import 'package:nadekodon/utils/log_service.dart';

class LogsDialog extends StatefulWidget {
  const LogsDialog({super.key});

  @override
  State<LogsDialog> createState() => _LogsDialogState();
}

class _LogsDialogState extends State<LogsDialog> {
  bool _showDebug = true;
  bool _showStdout = true;
  final Set<LogEntry> _selectedLogs = {};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final filteredLogs = LogService.logs.where((log) {
      if (!_showDebug && log.level == LogLevel.debug) return false;
      if (!_showStdout && log.level == LogLevel.stdout) return false;
      return true;
    }).toList();

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Logs'),
          IconButton(
            onPressed: _selectedLogs.isEmpty
                ? null
                : () {
                    final selectedLogText = _selectedLogs.map((log) => '[${log.level.toString().split('.').last.toUpperCase()}] [${log.timestamp}] ${log.message}').join('\n');
                    Clipboard.setData(ClipboardData(text: selectedLogText));
                  },
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
      content: SizedBox(
        width: AppTheme.dialogWidth(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Debug'),
                  selected: _showDebug,
                  onSelected: (selected) {
                    setState(() {
                      _showDebug = selected;
                    });
                  },
                  avatar: Icon(_showDebug ? Icons.check : Icons.close),
                  selectedColor: colors.primaryContainer,
                ),
                const SizedBox(width: AppTheme.spaceMD),
                ChoiceChip(
                  label: const Text('Stdout'),
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
            Flexible(
              child: Container(
                color: colors.surfaceVariant.withOpacity(0.5),
                child: filteredLogs.isEmpty
                    ? const Center(child: Text('No logs yet.'))
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: filteredLogs.length,
                        itemBuilder: (context, index) {
                          final log = filteredLogs[index];
                          final isSelected = _selectedLogs.contains(log);
                          return SelectableRegion(
                        focusNode: FocusNode(),
                        selectionControls: materialTextSelectionControls,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedLogs.remove(log);
                              } else {
                                _selectedLogs.add(log);
                              }
                            });
                          },
                          child: Container(
                            width: double.infinity,
                            color: isSelected ? colors.primaryContainer : null,
                            child: Padding(
                              padding: const EdgeInsets.all(AppTheme.spaceSM),
                              child: Text(
                                '[${log.level.toString().split('.').last.toUpperCase()}] [${log.timestamp}] ${log.message}',
                                style: textTheme.bodyMedium?.copyWith(
                                  color: log.level == LogLevel.error ? colors.error : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              LogService.clearLogs();
              _selectedLogs.clear();
            });
          },
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}