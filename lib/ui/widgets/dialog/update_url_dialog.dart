import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nadekodon/ui/widgets/app_snackbar.dart';
import 'package:nadekodon/theme/app_theme.dart';
import 'package:nadekodon/src/bindings/bindings.dart';

class UpdateUrlDialog extends StatefulWidget {
  final String id;
  final String currentUrl;
  final String? referer;

  static bool isOpen = false;

  const UpdateUrlDialog({
    super.key,
    required this.id,
    required this.currentUrl,
    this.referer,
  });

  @override
  State<UpdateUrlDialog> createState() => _UpdateUrlDialogState();
}

class _UpdateUrlDialogState extends State<UpdateUrlDialog> {
  late TextEditingController _controller;
  String? _referer;
  bool _signalReceived = false;
  StreamSubscription? _addDownloadSub;

  @override
  void initState() {
    super.initState();
    UpdateUrlDialog.isOpen = true;
    _controller = TextEditingController(text: widget.currentUrl);
    _referer = widget.referer;
    _listenToSignals();
  }

  void _listenToSignals() {
    _addDownloadSub = RequestAddDownload.rustSignalStream.listen((signal) {
      final message = signal.message;
      if (mounted) {
        setState(() {
          _controller.text = message.url.trim();
          _signalReceived = true;
        });
      }
    });
  }

  @override
  void dispose() {
    UpdateUrlDialog.isOpen = false;
    _controller.dispose();
    _addDownloadSub?.cancel();
    super.dispose();
  }

  Future<void> _handleUpdate() async {
    final url = _controller.text.trim();
    if (url.isNotEmpty) {
      UpdateDownloadUrl(id: widget.id, newUrl: url).sendSignalToRust();
      if (mounted) {
        Navigator.of(context).pop(url);
      }
    } else {
      if (mounted) {
        AppSnackBar.show(context, 'URL cannot be empty', type: SnackType.error);
      }
    }
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
          const SizedBox(height: AppTheme.spaceMD),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: AppTheme.spaceSM),
                child: SizedBox(
                  width: AppTheme.spaceMD * AppTheme.spaceScale(context),
                  height: AppTheme.spaceMD * AppTheme.spaceScale(context),
                  child: !_signalReceived
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Icon(
                          Icons.check,
                          color: Colors.green,
                          size: AppTheme.iconSM * AppTheme.iconScale(context),
                        ),
                ),
              ),
              if (_referer != null && _referer!.isNotEmpty)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                      onTap: () async {
                        final uri = Uri.parse(_referer!);
                        bool launched = false;
                        try {
                          if (await canLaunchUrl(uri)) {
                            launched = await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        } catch (_) {}

                        if (!context.mounted) return;

                        if (!launched) {
                          AppSnackBar.show(
                            context,
                            'Could not launch referer',
                            type: SnackType.error,
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spaceXS,
                          vertical: AppTheme.spaceXS,
                        ),
                        child: Text(
                          'Open Referer',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colors.primary,
                            decoration: TextDecoration.underline,
                            decorationColor: colors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: textTheme.bodyMedium),
        ),
        ElevatedButton(
          onPressed: _handleUpdate,
          child: Text(
            'Update',
            style: textTheme.bodyMedium?.copyWith(color: colors.primary),
          ),
        ),
      ],
    );
  }
}
