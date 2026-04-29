import 'package:flutter/material.dart';
import 'package:nadekodon/utils/io_service.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/utils/platform_service.dart';

import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/api_service.dart';

class DirChoose extends StatefulWidget {
  final ValueNotifier<String> selectedDir;
  final ValueNotifier<String?> selectedCategory;

  const DirChoose({
    super.key,
    required this.selectedDir,
    required this.selectedCategory,
  });

  @override
  State<DirChoose> createState() => _DirChooseState();
}

class _DirChooseState extends State<DirChoose> {
  List<CategoryDisplay> _categories = [];
  bool _loadingCategories = false;
  final GlobalKey _buttonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _loadingCategories = true);

    if (PlatformService().isRemote) {
      final result = await APIService.getCategories();
      if (mounted) {
        setState(() {
          _categories = result ?? [];
          _loadingCategories = false;
        });
      }
    } else {
      GetCategories().sendSignalToRust();
      CategoriesOutput.rustSignalStream.first.then((signal) {
        if (mounted) {
          setState(() {
            _categories = signal.message.categories;
            _loadingCategories = false;
          });
        }
      });
    }
  }

  String _resolvePath(String? categoryName) {
    if (categoryName == null) {
      return widget.selectedDir.value;
    }
    final category = _categories
        .where((c) => c.name == categoryName)
        .firstOrNull;
    if (category == null || category.savePath == null) {
      return widget.selectedDir.value;
    }
    final savePath = category.savePath!;
    if (savePath.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(savePath)) {
      return savePath;
    }
    final baseDir = SettingsManager.downloadFolder.value;
    return '$baseDir/$savePath';
  }

  void _showDropdown(BuildContext context) async {
    final RenderBox? buttonRenderBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? overlayRenderBox =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;

    if (buttonRenderBox == null || overlayRenderBox == null) return;

    final buttonOffset = buttonRenderBox.localToGlobal(
      Offset.zero,
      ancestor: overlayRenderBox,
    );
    final buttonSize = buttonRenderBox.size;

    final result = await showMenu<String?>(
      context: context,
      position: RelativeRect.fromLTRB(
        buttonOffset.dx,
        buttonOffset.dy + buttonSize.height,
        buttonOffset.dx + buttonSize.width,
        buttonOffset.dy + buttonSize.height + AppTheme.spaceXS,
      ),
      items: [
        PopupMenuItem<String?>(
          value: "custom-dir",
          child: Row(
            children: [
              Icon(
                Icons.folder_open,
                size: AppTheme.iconSM * AppTheme.iconScale(context),
              ),
              const SizedBox(width: AppTheme.spaceSM),
              Text(
                "Custom Path...",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (_categories.isNotEmpty) const PopupMenuDivider(),
        ..._categories.map(
          (cat) => PopupMenuItem<String?>(
            value: cat.name,
            child: Row(
              children: [
                Icon(
                  Icons.folder,
                  size: AppTheme.iconSM * AppTheme.iconScale(context),
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AppTheme.spaceSM),
                Expanded(
                  child: Text(
                    cat.name,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    if (result == null) {
      return;
    } else if (result == "custom-dir") {
      final ioService = IOServiceFactory.create();
      final dir = await ioService.getDirectoryPath();
      if (dir != null) {
        widget.selectedDir.value = dir;
        widget.selectedCategory.value = null;
      }
    } else if (result != widget.selectedCategory.value) {
      widget.selectedCategory.value = result;
      widget.selectedDir.value = _resolvePath(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            widget.selectedDir.value != ""
                ? widget.selectedDir.value
                : "No directory selected",
            style: textTheme.bodySmall?.copyWith(
              color: (widget.selectedDir.value.isEmpty)
                  ? colors.onSurfaceVariant
                  : colors.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppTheme.spaceSM),
        _loadingCategories
            ? const SizedBox(
                width: AppTheme.iconMD,
                height: AppTheme.iconMD,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : ElevatedButton.icon(
                key: _buttonKey,
                icon: Icon(
                  widget.selectedCategory.value != null
                      ? Icons.folder
                      : Icons.folder_open,
                  size: AppTheme.iconSM * AppTheme.iconScale(context),
                ),
                label: Text(
                  widget.selectedCategory.value ?? "Choose",
                  style: textTheme.bodyMedium,
                ),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppTheme.spaceSM * AppTheme.spaceScale(context),
                    vertical: AppTheme.spaceSM * AppTheme.spaceScale(context),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  ),
                ),
                onPressed: () => _showDropdown(context),
              ),
      ],
    );
  }
}
