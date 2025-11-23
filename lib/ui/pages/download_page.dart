import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nadekodon/ui/widgets/components/download_card.dart';
import 'package:nadekodon/ui/widgets/dialog/delete_multiple_download.dart';
import 'package:rinf/rinf.dart';

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

class _DownloadListState {
  List<DownloadItem?> items = [];
  int totalCount = 0;
  bool isLoading = true;
  final ScrollController scrollController = ScrollController();
  final Set<String> selectedIds = {};

  bool get isSelectionMode => selectedIds.isNotEmpty;
}

class _DownloadPageState extends State<DownloadPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late StreamSubscription<RustSignalPack<DownloadList>> _dListSubs;
  Timer? _pollTimer;

  final _activeState = _DownloadListState();
  final _completedState = _DownloadListState();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Listen for updates from Rust
    _dListSubs = DownloadList.rustSignalStream.listen(_onDownloadListReceived);

    // Start polling
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _pollDownloads();
    });

    // Initial poll
    Future.delayed(Duration.zero, _pollDownloads);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    _dListSubs.cancel();
    _activeState.scrollController.dispose();
    _completedState.scrollController.dispose();
    super.dispose();
  }

  void _onDownloadListReceived(RustSignalPack<DownloadList> signal) {
    final message = signal.message;
    final tag = message.tag; // 0 for active, 1 for completed

    if (tag == null) return;
    if (!mounted) return;

    final state = tag == 0 ? _activeState : _completedState;

    final startIndex = message.startIndex.toInt();
    final totalCount = message.totalCount.toInt();
    final newItems = message.list.map((d) {
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

    setState(() {
      state.isLoading = false;
      if (state.items.length != totalCount) {
        // Resize if total count changed
        if (totalCount > state.items.length) {
          state.items.addAll(
            List.filled(totalCount - state.items.length, null),
          );
        } else {
          state.items = state.items.sublist(0, totalCount);
        }
      }
      state.totalCount = totalCount;

      for (int i = 0; i < newItems.length; i++) {
        if (startIndex + i < state.items.length) {
          state.items[startIndex + i] = newItems[i];
        }
      }
    });
  }

  void _pollDownloads() {
    if (!mounted) return;

    _pollForState(_activeState, DownloadPage.activeStatuses, 0);
    _pollForState(_completedState, DownloadPage.completedStatuses, 1);
  }

  void _pollForState(
    _DownloadListState state,
    Set<DownloadStatus> statuses,
    int tag,
  ) {
    // Determine visible range
    const itemHeight = 80.0;
    final double offset = state.scrollController.hasClients
        ? state.scrollController.offset
        : 0;
    final double viewportHeight = state.scrollController.hasClients
        ? state.scrollController.position.viewportDimension
        : MediaQuery.of(context).size.height;

    final int firstVisibleIndex = (offset / itemHeight).floor().clamp(
      0,
      state.totalCount,
    );

    String? anchorId;
    if (firstVisibleIndex < state.items.length) {
      anchorId = state.items[firstVisibleIndex]?.id;
    }

    final int afterCount = (viewportHeight / itemHeight).ceil() + 5;
    const int beforeCount = 5;

    final statusStrings = statuses.map((s) {
      switch (s) {
        case DownloadStatus.queued:
          return "Queued";
        case DownloadStatus.running:
          return "Running";
        case DownloadStatus.paused:
          return "Paused";
        case DownloadStatus.completed:
          return "Completed";
        case DownloadStatus.cancelled:
          return "Cancelled";
        case DownloadStatus.failed:
          return "Error";
      }
    }).toList();

    GetDownloadList(
      anchorId: anchorId,
      before: beforeCount,
      after: afterCount,
      statuses: statusStrings,
      tag: tag,
    ).sendSignalToRust();
  }

  void _toggleSelection(_DownloadListState state, String id) {
    setState(() {
      if (state.selectedIds.contains(id)) {
        state.selectedIds.remove(id);
      } else {
        state.selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll(_DownloadListState state) {
    setState(() {
      final loadedItems = state.items.whereType<DownloadItem>().toList();
      final allIds = loadedItems.map((e) => e.id).toSet();

      if (state.selectedIds.containsAll(allIds) && allIds.isNotEmpty) {
        state.selectedIds.clear();
      } else {
        state.selectedIds.addAll(allIds);
      }
    });
  }

  void _unselectAll(_DownloadListState state) {
    setState(() {
      state.selectedIds.clear();
    });
  }

  void _cancelSelected(_DownloadListState state) {
    final loadedItems = state.items.whereType<DownloadItem>().toList();
    final selectedItems = loadedItems
        .where((item) => state.selectedIds.contains(item.id))
        .toList();

    if (selectedItems.isEmpty) return;

    for (final item in selectedItems) {
      if (DownloadPage.activeStatuses.contains(item.status)) {
        CancelDownload(id: item.id).sendSignalToRust();
      }
    }
    _unselectAll(state);
  }

  Future<void> _deleteSelected(_DownloadListState state) async {
    final loadedItems = state.items.whereType<DownloadItem>().toList();
    final selectedItems = loadedItems
        .where((item) => state.selectedIds.contains(item.id))
        .toList();

    if (selectedItems.isEmpty) return;

    await showDeleteMultipleDownloadsDialog(
      context,
      selectedItems,
      onDeleted: () => _unselectAll(state),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDesktop = AppTheme.isDesktop(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: isDesktop ? null : 0,
        title: isDesktop
            ? Text("Downloads", style: textTheme.titleLarge)
            : null,
        bottom: TabBar(
          controller: _tabController,
          labelStyle: textTheme.bodyMedium?.copyWith(color: colors.primary),
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _DownloadListTab(
            state: _activeState,
            emptyMessage: "No active downloads",
            onToggleSelection: (id) => _toggleSelection(_activeState, id),
            onToggleSelectAll: () => _toggleSelectAll(_activeState),
            onCancelSelected: () => _cancelSelected(_activeState),
            onDeleteSelected: () => _deleteSelected(_activeState),
          ),
          _DownloadListTab(
            state: _completedState,
            emptyMessage: "No completed downloads",
            onToggleSelection: (id) => _toggleSelection(_completedState, id),
            onToggleSelectAll: () => _toggleSelectAll(_completedState),
            onCancelSelected: () => _cancelSelected(_completedState),
            onDeleteSelected: () => _deleteSelected(_completedState),
          ),
        ],
      ),
      floatingActionButton:
          (_activeState.isSelectionMode || _completedState.isSelectionMode)
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
    );
  }
}

class _DownloadListTab extends StatefulWidget {
  final _DownloadListState state;
  final String emptyMessage;
  final Function(String) onToggleSelection;
  final VoidCallback onToggleSelectAll;
  final VoidCallback onCancelSelected;
  final VoidCallback onDeleteSelected;

  const _DownloadListTab({
    required this.state,
    required this.emptyMessage,
    required this.onToggleSelection,
    required this.onToggleSelectAll,
    required this.onCancelSelected,
    required this.onDeleteSelected,
  });

  @override
  State<_DownloadListTab> createState() => _DownloadListTabState();
}

class _DownloadListTabState extends State<_DownloadListTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final state = widget.state;

    // Determine if all loaded items are selected
    final loadedItems = state.items.whereType<DownloadItem>().toList();
    final allIds = loadedItems.map((e) => e.id).toSet();
    final isAllSelected =
        loadedItems.isNotEmpty && state.selectedIds.containsAll(allIds);

    return Stack(
      children: [
        if (state.isLoading && state.items.isEmpty)
          const Center(child: CircularProgressIndicator())
        else if (state.items.isEmpty)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.file_download_off_rounded,
                  size: AppTheme.iconXXL * AppTheme.iconScale(context),
                  color: colors.outline,
                ),
                Text(
                  widget.emptyMessage,
                  style: textTheme.bodyMedium?.copyWith(color: colors.outline),
                ),
              ],
            ),
          )
        else
          ListView.builder(
            controller: state.scrollController,
            padding: const EdgeInsets.only(
              top: AppTheme.spaceSM,
              bottom: 100, // Add padding for floating menu
            ),
            itemCount: state.items.length,
            itemBuilder: (context, index) {
              final item = state.items[index];

              if (item == null) {
                // Placeholder for unloaded items
                return SizedBox(
                  height: 80,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }

              final isSelected = state.selectedIds.contains(item.id);

              return DownloadCard(
                item: item,
                isSelected: isSelected,
                isSelectionMode: state.isSelectionMode,
                onTap: () {
                  if (state.isSelectionMode) {
                    widget.onToggleSelection(item.id);
                  }
                },
                onLongPress: () {
                  widget.onToggleSelection(item.id);
                },
                onSecondaryTapDown: (details) {
                  showDownloadContextMenu(
                    context,
                    details.globalPosition,
                    item,
                  );
                },
                onMenuPressed: (details) {
                  showDownloadContextMenu(
                    context,
                    details.globalPosition,
                    item,
                  );
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
          ),
        // Floating Selection Menu
        if (state.isSelectionMode)
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
                    borderRadius: BorderRadius.circular(AppTheme.radiusLG),
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
                          onPressed: widget.onCancelSelected,
                          icon: Icon(
                            Icons.stop,
                            size: AppTheme.iconMD * AppTheme.iconScale(context),
                          ),
                          label: Text("Stop", style: textTheme.bodyMedium),
                        ),
                        SizedBox(
                          height:
                              AppTheme.spaceLG * AppTheme.spaceScale(context),
                          child: VerticalDivider(color: colors.outlineVariant),
                        ),
                        TextButton.icon(
                          onPressed: widget.onToggleSelectAll,
                          icon: Icon(
                            isAllSelected ? Icons.deselect : Icons.select_all,
                            size: AppTheme.iconMD * AppTheme.iconScale(context),
                          ),
                          label: Text(
                            isAllSelected ? "Unselect All" : "Select All",
                            style: textTheme.bodyMedium,
                          ),
                        ),
                        SizedBox(
                          height:
                              AppTheme.spaceLG * AppTheme.spaceScale(context),
                          child: VerticalDivider(color: colors.outlineVariant),
                        ),
                        TextButton.icon(
                          onPressed: widget.onDeleteSelected,
                          icon: Icon(
                            Icons.delete,
                            size: AppTheme.iconMD * AppTheme.iconScale(context),
                          ),
                          label: Text("Delete", style: textTheme.bodyMedium),
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
    );
  }
}
