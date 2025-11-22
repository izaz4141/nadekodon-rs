import 'package:flutter/material.dart';
import 'package:nadekodon/ui/widgets/components/download_card.dart';
import 'package:nadekodon/ui/widgets/dialog/delete_multiple_download.dart';

import '../../theme/app_theme.dart';
import '../../utils/helper.dart';
import '../../src/bindings/bindings.dart';
import '../widgets/dialog/add_download.dart';
import '../widgets/dialog/download_context_menu.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  static const activeStatuses = {
    DownloadStatus.queued,
    DownloadStatus.running,
    DownloadStatus.paused,
  };

  static const completedStatuses = {
    DownloadStatus.completed,
    DownloadStatus.cancelled,
    DownloadStatus.failed,
  };

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final Set<String> _selectedIds = {};
  bool get _isSelectionMode => _selectedIds.isNotEmpty;

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll(List<DownloadItem> items) {
    setState(() {
      final allIds = items.map((e) => e.id).toSet();
      if (_selectedIds.containsAll(allIds)) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(allIds);
      }
    });
  }

  void _unselectAll() {
    setState(() {
      _selectedIds.clear();
    });
  }

  void _cancelSelected(List<DownloadItem> allItems) {
    final selectedItems = allItems
        .where((item) => _selectedIds.contains(item.id))
        .toList();

    if (selectedItems.isEmpty) return;

    for (final item in selectedItems) {
      if (DownloadPage.activeStatuses.contains(item.status)) {
        CancelDownload(id: item.id).sendSignalToRust();
      }
    }
    _unselectAll();
  }

  Future<void> _deleteSelected(List<DownloadItem> allItems) async {
    final selectedItems = allItems
        .where((item) => _selectedIds.contains(item.id))
        .toList();

    if (selectedItems.isEmpty) return;

    await showDeleteMultipleDownloadsDialog(
      context,
      selectedItems,
      onDeleted: _unselectAll,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDesktop = AppTheme.isDesktop(context);

    return StreamBuilder(
      stream: DownloadList.rustSignalStream,
      builder: (context, snapshot) {
        final signalPack = snapshot.data;
        final List<DownloadItem> allDownloads;

        if (signalPack == null) {
          allDownloads = [];
        } else {
          final downloadListOutput = signalPack.message;
          allDownloads = downloadListOutput.list.map<DownloadItem>((d) {
            final status = parseDownloadStatus(d.state);
            return DownloadItem(
              id: d.id,
              name: d.name,
              dest: d.dest,
              downloaded: d.downloaded.toInt(),
              total: d.totalSize?.toInt(),
              status: status,
              speed: d.speed,
            );
          }).toList();
        }

        final activeDownloads = allDownloads
            .where((d) => DownloadPage.activeStatuses.contains(d.status))
            .toList();
        final completedDownloads = allDownloads
            .where((d) => DownloadPage.completedStatuses.contains(d.status))
            .toList();

        // Determine if all are selected for the toggle button label/icon
        final allIds = allDownloads.map((e) => e.id).toSet();
        final isAllSelected =
            allDownloads.isNotEmpty && _selectedIds.containsAll(allIds);

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: isDesktop ? null : 0,
              title: isDesktop
                  ? Text("Downloads", style: textTheme.titleLarge)
                  : null,
              bottom: TabBar(
                labelStyle: textTheme.bodyMedium?.copyWith(
                  color: colors.primary,
                ),
                unselectedLabelStyle: textTheme.bodyMedium,
                splashBorderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppTheme.radiusLG),
                ),
                tabs: const [
                  Tab(text: "Active"),
                  Tab(text: "Completed"),
                ],
              ),
            ),
            body: Stack(
              children: [
                signalPack == null
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        children: [
                          _buildDownloadList(
                            context,
                            activeDownloads,
                            "No active downloads",
                          ),
                          _buildDownloadList(
                            context,
                            completedDownloads,
                            "No completed downloads",
                          ),
                        ],
                      ),
                // Floating Selection Menu
                if (_isSelectionMode)
                  Positioned(
                    bottom: AppTheme.spaceLG,
                    left: AppTheme.spaceLG,
                    right: AppTheme.spaceLG,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusLG,
                            ),
                          ),
                          color: colors.surfaceContainer,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spaceMD,
                              vertical: AppTheme.spaceXS,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton.icon(
                                  onPressed: () =>
                                      _cancelSelected(allDownloads),
                                  icon: Icon(
                                    Icons.stop,
                                    size:
                                        AppTheme.iconMD *
                                        AppTheme.iconScale(context),
                                  ),
                                  label: Text(
                                    "Stop",
                                    style: textTheme.bodyMedium,
                                  ),
                                ),
                                SizedBox(
                                  height:
                                      AppTheme.spaceLG *
                                      AppTheme.spaceScale(context),
                                  child: VerticalDivider(
                                    color: colors.outlineVariant,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () =>
                                      _toggleSelectAll(allDownloads),
                                  icon: Icon(
                                    isAllSelected
                                        ? Icons.deselect
                                        : Icons.select_all,
                                    size:
                                        AppTheme.iconMD *
                                        AppTheme.iconScale(context),
                                  ),
                                  label: Text(
                                    isAllSelected
                                        ? "Unselect All"
                                        : "Select All",
                                    style: textTheme.bodyMedium,
                                  ),
                                ),
                                SizedBox(
                                  height:
                                      AppTheme.spaceLG *
                                      AppTheme.spaceScale(context),
                                  child: VerticalDivider(
                                    color: colors.outlineVariant,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () =>
                                      _deleteSelected(allDownloads),
                                  icon: Icon(
                                    Icons.delete,
                                    size:
                                        AppTheme.iconMD *
                                        AppTheme.iconScale(context),
                                  ),
                                  label: Text(
                                    "Delete",
                                    style: textTheme.bodyMedium,
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: colors.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            floatingActionButton: _isSelectionMode
                ? null
                : Padding(
                    padding: const EdgeInsets.all(AppTheme.spaceMD),
                    child: FloatingActionButton(
                      onPressed: () => showAddDownloadDialog(context),
                      tooltip: 'Add download',
                      child: const Icon(Icons.add),
                    ),
                  ),
            floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          ),
        );
      },
    );
  }

  Widget _buildDownloadList(
    BuildContext context,
    List<DownloadItem> items,
    String emptyMessage,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.file_download_off_rounded,
              size: AppTheme.iconXXL * AppTheme.iconScale(context),
              color: colors.outline,
            ),
            Text(
              "No Downloads",
              style: textTheme.bodyMedium?.copyWith(color: colors.outline),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(
        top: AppTheme.spaceSM,
        bottom: 100, // Add padding for floating menu
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = _selectedIds.contains(item.id);

        return DownloadCard(
          item: item,
          isSelected: isSelected,
          isSelectionMode: _isSelectionMode,
          onTap: () {
            if (_isSelectionMode) {
              _toggleSelection(item.id);
            }
          },
          onLongPress: () {
            _toggleSelection(item.id);
          },
          onSecondaryTapDown: (details) {
            showDownloadContextMenu(context, details.globalPosition, item);
          },
          onMenuPressed: (details) {
            showDownloadContextMenu(context, details.globalPosition, item);
          },
          onPauseResume: () {
            if (item.status == DownloadStatus.running ||
                item.status == DownloadStatus.queued) {
              PauseDownload(id: item.id).sendSignalToRust();
            } else {
              ResumeDownload(id: item.id).sendSignalToRust();
            }
          },
          onCancel: () {
            if (DownloadPage.activeStatuses.contains(item.status)) {
              CancelDownload(id: item.id).sendSignalToRust();
            }
          },
        );
      },
    );
  }
}
