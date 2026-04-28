import 'package:flutter/material.dart';
import 'package:nadekodon/utils/platform_service.dart';

import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/api_service.dart';
import 'package:nadekodon/ui/widgets/app_snackbar.dart';

class CategoryManagerDialog extends StatefulWidget {
  const CategoryManagerDialog({super.key});

  @override
  State<CategoryManagerDialog> createState() => _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends State<CategoryManagerDialog> {
  List<CategoryDisplay> _categories = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _loading = true);

    if (PlatformService().isRemote) {
      final result = await APIService.getCategories();
      if (mounted) {
        setState(() {
          _categories = result ?? [];
          _loading = false;
        });
      }
    } else {
      GetCategories().sendSignalToRust();
      final signal = await CategoriesOutput.rustSignalStream.first;
      if (mounted) {
        setState(() {
          _categories = signal.message.categories;
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveCategories() async {
    setState(() => _saving = true);

    bool success;
    if (PlatformService().isRemote) {
      success = await APIService.updateCategories(_categories);
    } else {
      UpdateCategories(categories: _categories).sendSignalToRust();
      success = true;
    }

    if (mounted) {
      setState(() => _saving = false);
      if (success) {
        AppSnackBar.show(context, "Categories saved", type: SnackType.success);
        Navigator.pop(context);
      } else {
        AppSnackBar.show(
          context,
          "Failed to save categories",
          type: SnackType.error,
        );
      }
    }
  }

  void _addCategory() {
    showDialog(
      context: context,
      builder: (context) => _CategoryEditDialog(
        onSave: (name, savePath) {
          setState(() {
            _categories.add(CategoryDisplay(name: name, savePath: savePath));
          });
        },
      ),
    );
  }

  void _editCategory(int index) {
    final cat = _categories[index];
    showDialog(
      context: context,
      builder: (context) => _CategoryEditDialog(
        initialName: cat.name,
        initialSavePath: cat.savePath,
        onSave: (name, savePath) {
          setState(() {
            _categories[index] = CategoryDisplay(
              name: name,
              savePath: savePath,
            );
          });
        },
      ),
    );
  }

  void _deleteCategory(int index) {
    setState(() {
      _categories.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: Text("Categories", style: textTheme.titleMedium),
      content: SizedBox(
        width: 400 * AppTheme.widthScale(context),
        height: 300 * AppTheme.heightScale(context),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  return ListTile(
                    leading: Icon(
                      Icons.folder,
                      color: colors.primary,
                      size: AppTheme.iconMD * AppTheme.iconScale(context),
                    ),
                    title: Text(cat.name, style: textTheme.bodyMedium),
                    subtitle: cat.savePath != null
                        ? Text(
                            cat.savePath!,
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.edit,
                            size: AppTheme.iconMD * AppTheme.iconScale(context),
                          ),
                          onPressed: () => _editCategory(index),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete,
                            size: AppTheme.iconMD * AppTheme.iconScale(context),
                          ),
                          onPressed: () => _deleteCategory(index),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Cancel", style: textTheme.bodyMedium),
        ),
        TextButton(
          onPressed: _addCategory,
          child: Text("Add", style: textTheme.bodyMedium),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _saveCategories,
          child: _saving
              ? const SizedBox(
                  width: AppTheme.iconMD,
                  height: AppTheme.iconMD,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text("Save", style: textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _CategoryEditDialog extends StatefulWidget {
  final String? initialName;
  final String? initialSavePath;
  final void Function(String name, String? savePath) onSave;

  const _CategoryEditDialog({
    this.initialName,
    this.initialSavePath,
    required this.onSave,
  });

  @override
  State<_CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends State<_CategoryEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _savePathController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _savePathController = TextEditingController(text: widget.initialSavePath);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _savePathController.dispose();
    super.dispose();
  }

  void _submitCategory() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final savePath = _savePathController.text.trim();
    widget.onSave(name, savePath.isEmpty ? null : savePath);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: Text(
        widget.initialName == null ? "Add Category" : "Edit Category",
        style: textTheme.titleSmall,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            style: textTheme.bodySmall,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: "Category Name",
              labelStyle: textTheme.bodySmall,
              floatingLabelStyle: textTheme.bodySmall?.copyWith(
                color: colors.primary,
              ),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(AppTheme.radiusMD),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spaceSM),
          TextField(
            controller: _savePathController,
            style: textTheme.bodySmall,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: "Save Path",
              labelStyle: textTheme.bodySmall,
              floatingLabelStyle: textTheme.bodySmall?.copyWith(
                color: colors.primary,
              ),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(AppTheme.radiusMD),
                ),
              ),
            ),
            onSubmitted: (_) => _submitCategory(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Cancel", style: textTheme.bodyMedium),
        ),
        ElevatedButton(
          onPressed: _submitCategory,
          child: Text("Save", style: textTheme.bodyMedium),
        ),
      ],
    );
  }
}
