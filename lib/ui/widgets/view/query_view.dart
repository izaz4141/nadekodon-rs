import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/components/dir_choose.dart';

class QueryView extends StatelessWidget {
  final TextEditingController urlController;
  final ValueNotifier<String> selectedDir;
  final ValueNotifier<String?> selectedCategory;
  final void Function() onQuery;
  final void Function()? onBrowseTorrent;

  const QueryView({
    super.key,
    required this.urlController,
    required this.selectedDir,
    required this.selectedCategory,
    required this.onQuery,
    this.onBrowseTorrent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: urlController,
          onSubmitted: (_) => onQuery(),
          decoration: InputDecoration(
            labelText: "Download URL",
            labelStyle: textTheme.bodyMedium,
            floatingLabelStyle: textTheme.bodyMedium?.copyWith(
              color: colors.primary,
            ),
            hintText: "https://example.com/file.zip",
            hintStyle: textTheme.bodyMedium,
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(AppTheme.radiusMD),
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spaceSM,
              vertical: AppTheme.spaceSM,
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onBrowseTorrent != null)
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.magnet),
                    tooltip: "Open .torrent file",
                    onPressed: onBrowseTorrent,
                  ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: urlController,
                  builder: (context, value, child) {
                    if (value.text.isEmpty) {
                      return const SizedBox.shrink(); // Hide button if empty
                    }
                    return IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: "Clear",
                      onPressed: () => urlController.clear(),
                    );
                  },
                ),
              ],
            ),
          ),
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: AppTheme.spaceLG),
        DirChoose(selectedDir: selectedDir, selectedCategory: selectedCategory),
      ],
    );
  }
}
