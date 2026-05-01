import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nadekodon/ui/widgets/components/download_card.dart';
import 'package:nadekodon/ui/widgets/components/web_context_menu.dart';
import 'package:nadekodon/ui/widgets/dialog/delete_download.dart';

import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/ui/widgets/dialog/add_download.dart';
import 'package:nadekodon/ui/widgets/dialog/download_context_menu.dart';
import 'package:nadekodon/utils/download_service.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  static const activeStatuses = {
    DownloadStatus.queued,
    DownloadStatus.running,
    DownloadStatus.seeding,
    DownloadStatus.stalledDL,
    DownloadStatus.stalledUP,
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
  late StreamSubscription<DownloadList> _dListSubs;
  Timer? _pollTimer;

  final _activeState = _DownloadListState();
  final _completedState = _DownloadListState();

  // Search and Sort State
  String _searchQuery = "";
  int _sortBy = 0; // 0: Date, 1: Name, 2: Size, 3: Speed
  bool _ascending = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // DownloadService is initialized in its singleton constructor.
    // Listen for updates from DownloadService
    _dListSubs = DownloadService().listStream.listen(_onDownloadListReceived);

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
    _searchController.dispose();
    super.dispose();
  }

  void _onDownloadListReceived(DownloadList message) {
    final tag = message.tag; // 0 for active, 1 for completed

    if (tag == null) return;
    if (tag != 0 && tag != 1) return;
    if (!mounted) return;

    final state = tag == 0 ? _activeState : _completedState;

    final startIndex = message.startIndex.toInt();
    final totalCount = message.totalCount.toInt();
    final newItems = message.list.map((d) {
      final status = parseDownloadStatus(d.state);
      return DownloadItem(
        id: d.id,
        downloadType: d.downloadType,
        name: d.name,
        dest: d.dest,
        downloaded: d.downloaded.toInt(),
        total: d.totalSize?.toInt(),
        status: status,
        dspeed: d.dspeed,
        uspeed: d.uspeed,
        referer: d.referer,
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
        case DownloadStatus.seeding:
          return "Seeding";
        case DownloadStatus.stalledDL:
          return "StalledDL";
        case DownloadStatus.stalledUP:
          return "StalledUP";
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

    DownloadService().fetchList(
      GetDownloadList(
        anchorId: anchorId,
        before: beforeCount,
        after: afterCount,
        statuses: statusStrings,
        tag: tag,
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
        sortBy: _sortBy,
        ascending: _ascending,
      ),
    );
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
        DownloadService().cancelDownload(item.id);
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

    await showDeleteDownloadsDialog(
      context,
      selectedItems,
      onDeleted: () => _unselectAll(state),
    );
  }

  String _getSortLabel(int sort) {
    switch (sort) {
      case 0:
        return "Date";
      case 1:
        return "Name";
      case 2:
        return "Size";
      case 3:
        return "Speed";
      default:
        return "Date";
    }
  }

  void _resetList() {
    setState(() {
      _activeState.items = [];
      _activeState.totalCount = 0;
      _activeState.isLoading = true;
      _completedState.items = [];
      _completedState.totalCount = 0;
      _completedState.isLoading = true;
    });
    _pollDownloads();
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
      body: Column(
        children: [
          // Filter Bar
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppTheme.spaceMD * AppTheme.spaceScale(context),
              AppTheme.spaceMD * AppTheme.spaceScale(context),
              AppTheme.spaceMD * AppTheme.spaceScale(context),
              0,
            ),
            child: Row(
              children: [
                // Search
                if (_isSearching)
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: "Search downloads...",
                        prefixIcon: Icon(
                          Icons.search,
                          size: AppTheme.iconSM * AppTheme.iconScale(context),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            Icons.close,
                            size: AppTheme.iconSM * AppTheme.iconScale(context),
                          ),
                          onPressed: () {
                            setState(() {
                              _isSearching = false;
                              _searchQuery = "";
                              _searchController.clear();
                              _resetList();
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusLG * AppTheme.radiusScale(context),
                          ),
                        ),
                        filled: true,
                        fillColor: colors.surfaceContainer,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal:
                              AppTheme.spaceMD * AppTheme.spaceScale(context),
                          vertical:
                              AppTheme.spaceXS * AppTheme.spaceScale(context),
                        ),
                      ),
                      style: textTheme.bodyMedium,
                      onChanged: (value) {
                        _searchQuery = value;
                        _resetList();
                      },
                    ),
                  )
                else ...[
                  ActionChip(
                    avatar: Icon(
                      Icons.search,
                      size: AppTheme.iconSM * AppTheme.iconScale(context),
                      color: colors.onSurfaceVariant,
                    ),
                    label: Text("Search", style: textTheme.bodyMedium),
                    onPressed: () {
                      setState(() {
                        _isSearching = true;
                      });
                    },
                    backgroundColor: colors.surfaceContainer,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusLG * AppTheme.radiusScale(context),
                      ),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          AppTheme.spaceXS * AppTheme.spaceScale(context),
                      vertical: AppTheme.spaceXS * AppTheme.spaceScale(context),
                    ),
                  ),
                  SizedBox(
                    width: AppTheme.spaceSM * AppTheme.spaceScale(context),
                  ),
                  // Sort
                  Builder(
                    builder: (context) {
                      return ActionChip(
                        avatar: Icon(
                          _ascending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: AppTheme.iconSM * AppTheme.iconScale(context),
                          color: colors.onSurfaceVariant,
                        ),
                        label: Text(
                          _getSortLabel(_sortBy),
                          style: textTheme.bodyMedium,
                        ),
                        onPressed: () {
                          final RenderBox button =
                              context.findRenderObject() as RenderBox;
                          final RenderBox overlay =
                              Overlay.of(context).context.findRenderObject()
                                  as RenderBox;
                          final RelativeRect position = RelativeRect.fromRect(
                            Rect.fromPoints(
                              button.localToGlobal(
                                Offset.zero,
                                ancestor: overlay,
                              ),
                              button.localToGlobal(
                                button.size.bottomRight(Offset.zero),
                                ancestor: overlay,
                              ),
                            ),
                            Offset.zero & overlay.size,
                          );

                          showMenu<int>(
                            context: context,
                            position: position,
                            color: colors.surfaceContainer,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusMD *
                                    AppTheme.radiusScale(context),
                              ),
                            ),
                            items: [
                              PopupMenuItem(
                                value: 0,
                                child: Text(
                                  "Date",
                                  style: textTheme.bodyMedium,
                                ),
                              ),
                              PopupMenuItem(
                                value: 1,
                                child: Text(
                                  "Name",
                                  style: textTheme.bodyMedium,
                                ),
                              ),
                              PopupMenuItem(
                                value: 2,
                                child: Text(
                                  "Size",
                                  style: textTheme.bodyMedium,
                                ),
                              ),
                              PopupMenuItem(
                                value: 3,
                                child: Text(
                                  "Speed",
                                  style: textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ).then((value) {
                            if (value != null) {
                              if (_sortBy == value) {
                                setState(() {
                                  _ascending = !_ascending;
                                });
                              } else {
                                setState(() {
                                  _sortBy = value;
                                  // Preserve current direction when switching sort type
                                });
                              }
                              _resetList();
                            }
                          });
                        },
                        backgroundColor: colors.surfaceContainer,
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusLG * AppTheme.radiusScale(context),
                          ),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal:
                              AppTheme.spaceXS * AppTheme.spaceScale(context),
                          vertical:
                              AppTheme.spaceXS * AppTheme.spaceScale(context),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _DownloadListTab(
                  state: _activeState,
                  emptyMessage: _searchQuery.isNotEmpty
                      ? "No results found"
                      : "No active downloads",
                  onToggleSelection: (id) => _toggleSelection(_activeState, id),
                  onToggleSelectAll: () => _toggleSelectAll(_activeState),
                  onCancelSelected: () => _cancelSelected(_activeState),
                  onDeleteSelected: () => _deleteSelected(_activeState),
                ),
                _DownloadListTab(
                  state: _completedState,
                  emptyMessage: _searchQuery.isNotEmpty
                      ? "No results found"
                      : "No completed downloads",
                  onToggleSelection: (id) =>
                      _toggleSelection(_completedState, id),
                  onToggleSelectAll: () => _toggleSelectAll(_completedState),
                  onCancelSelected: () => _cancelSelected(_completedState),
                  onDeleteSelected: () => _deleteSelected(_completedState),
                ),
              ],
            ),
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

              return DisableWebContextMenu(
                child: DownloadCard(
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
                      onDelete:
                          (state.isSelectionMode &&
                              state.selectedIds.contains(item.id))
                          ? widget.onDeleteSelected
                          : null,
                    );
                  },
                  onMenuPressed: (details) {
                    showDownloadContextMenu(
                      context,
                      details.globalPosition,
                      item,
                      onDelete:
                          (state.isSelectionMode &&
                              state.selectedIds.contains(item.id))
                          ? widget.onDeleteSelected
                          : null,
                    );
                  },
                  onPauseResume: () {
                    if (item.status == DownloadStatus.running ||
                        item.status == DownloadStatus.seeding ||
                        item.status == DownloadStatus.queued) {
                      DownloadService().pauseDownload(item.id);
                    } else {
                      DownloadService().resumeDownload(item.id);
                    }
                  },
                  onCancel: () {
                    if (DownloadPage.activeStatuses.contains(item.status)) {
                      DownloadService().cancelDownload(item.id);
                    }
                  },
                ),
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
