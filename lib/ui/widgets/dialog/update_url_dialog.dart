import 'package:flutter/material.dart';
import 'package:nadekodon/ui/widgets/app_snackbar.dart';
import 'package:nadekodon/theme/app_theme.dart';

class UpdateUrlDialog extends StatefulWidget {
  final String currentUrl;

  const UpdateUrlDialog({super.key, required this.currentUrl});

  @override
  State<UpdateUrlDialog> createState() => _UpdateUrlDialogState();
}

class _UpdateUrlDialogState extends State<UpdateUrlDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text('Update Download URL', style: textTheme.titleMedium),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: "New URL",
              labelStyle: textTheme.bodyMedium,
              floatingLabelStyle: textTheme.bodySmall?.copyWith(
                color: colors.primary,
              ),
              hintText: "https://example.com",
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
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, child) {
                  if (value.text.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: "Clear",
                    onPressed: () => _controller.clear(),
                  );
                },
              ),
            ),
            style: textTheme.bodyMedium,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: textTheme.bodyMedium),
        ),
        FilledButton(
          onPressed: () {
            final url = _controller.text.trim();
            if (url.isNotEmpty) {
              Navigator.of(context).pop(url);
            } else {
              AppSnackBar.show(
                context,
                'URL cannot be empty',
                type: SnackType.error,
              );
            }
          },
          child: Text('Update', style: textTheme.bodyMedium),
        ),
      ],
    );
  }
}
