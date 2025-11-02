import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/settings.dart';
import '../app_snackbar.dart';
import 'package:nadekodon/utils/helper.dart';

import 'package:rinf/rinf.dart';
import 'package:nadekodon/src/bindings/bindings.dart';

Future<void> showAddDownloadDialog(BuildContext context) async {
  final urlController = TextEditingController();
  final nameController = TextEditingController();
  String? selectedDir = SettingsManager.downloadFolder.value;

  await showDialog(
    context: context,
    builder: (context) {
      final colors = Theme.of(context).colorScheme;
      final textTheme = Theme.of(context).textTheme;

      bool showQueryInfo = false;
      bool queryFinished = false;

      return StatefulBuilder( 
        builder: (context, setState) {
          void handleSubmit() {
            final url = urlController.text.trim();

            if (showQueryInfo && queryFinished) {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                AppSnackBar.show(
                  context,
                  "Please enter the filename.",
                  type: SnackType.error,
                );
                return;
              }
              Navigator.pop(context);
              DoDownload(url: url, dest: "${selectedDir!}/$name").sendSignalToRust();
              AppSnackBar.show(context, "Added download");
            } else {
              if (url.isEmpty || (selectedDir == null || selectedDir!.isEmpty)) {
                AppSnackBar.show(
                  context,
                  "Please enter URL and select a destination folder.",
                  type: SnackType.error,
                );
                return;
              }

              QueryUrl(url: url).sendSignalToRust();
              setState(() {
                showQueryInfo = true;
              });
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLG),
            ),
            title: Text("New Download", style: textTheme.titleMedium),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: 400 * AppTheme.widthScale(context),
                maxWidth: AppTheme.dialogWidth(context),
                maxHeight: AppTheme.dialogMaxHeight(context),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!queryFinished) ...[
                    TextField(
                      controller: urlController,
                      onSubmitted: (_) => handleSubmit(),
                      decoration: InputDecoration(
                        labelText: "Download URL",
                        labelStyle: textTheme.bodyMedium,
                        floatingLabelStyle: textTheme.bodySmall?.copyWith(
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
                      ),
                    ),
                    const SizedBox(height: AppTheme.spaceLG),
                  ],

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (selectedDir?.isNotEmpty ?? false)
                              ? selectedDir!
                              : "No directory selected",
                          style: textTheme.bodySmall?.copyWith(
                            color: (selectedDir == null || selectedDir!.isEmpty)
                                ? colors.onSurfaceVariant
                                : colors.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spaceSM),
                      ElevatedButton.icon(
                        icon: Icon(
                          Icons.folder_open,
                          size: AppTheme.iconSM * AppTheme.iconScale(context),
                        ),
                        label: Text(
                          "Choose",
                          style: TextStyle(
                            fontSize: AppTheme.textMD * AppTheme.textScale(context),
                          ),
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
                        onPressed: () async {
                          final dir = await FilePicker.platform.getDirectoryPath();
                          if (dir != null) {
                            setState(() => selectedDir = dir);
                          }
                        },
                      ),
                    ],
                  ),

                  if (showQueryInfo)
                    StreamBuilder(
                      stream: UrlQueryOutput.rustSignalStream,
                      builder: (context, snapshot) {
                        final signalPack = snapshot.data;
                        if (signalPack == null) {
                          return Row(
                            children: [
                              CircularProgressIndicator(
                                color: Colors.green.shade600,
                                strokeWidth: 2,
                                constraints: BoxConstraints(
                                  minWidth: AppTheme.iconSM * AppTheme.iconScale(context),
                                  maxWidth: AppTheme.iconSM * AppTheme.iconScale(context),
                                  minHeight: AppTheme.iconSM * AppTheme.iconScale(context),
                                  maxHeight: AppTheme.iconSM * AppTheme.iconScale(context),
                                )
                              ),
                              const SizedBox(width: AppTheme.spaceSM),
                              Text(
                                "Querying info...",
                                style: textTheme.bodySmall?.copyWith(
                                  color: Colors.green.shade600,
                                ),
                              ),
                            ],
                          );
                        }

                        final urlQuery = signalPack.message;
                        if (!queryFinished && !urlQuery.error) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            setState(() {
                              queryFinished = true;
                            });
                          });
                        }
                        if (urlQuery.isWebpage) {
                          nameController.text = "index.html";
                        } else {
                          nameController.text = urlQuery.name;
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: urlQuery.error
                          ? [ 
                              const SizedBox(height: AppTheme.spaceSM),
                              Text(
                                "✖ URL can't be reached",
                                style: textTheme.bodySmall?.copyWith(
                                  color: Colors.red.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ]
                          : [
                              const SizedBox(height: AppTheme.spaceSM),
                              TextField(
                                controller: nameController,
                                onSubmitted: (_) => handleSubmit(),
                                decoration: InputDecoration(
                                  labelText: "Filename",
                                  labelStyle: textTheme.bodyMedium,
                                  floatingLabelStyle: textTheme.bodySmall?.copyWith(
                                    color: colors.primary,
                                  ),
                                  hintText: "download.bin",
                                  hintStyle: textTheme.bodyMedium,
                                  border: const OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(AppTheme.radiusMD)),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppTheme.spaceSM,
                                    vertical: AppTheme.spaceSM,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppTheme.spaceSM),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  if (urlQuery.isWebpage)
                                    Text(
                                      "RETURNED WEBPAGE",
                                      style: textTheme.bodySmall?.copyWith(
                                        color: Colors.red.shade600,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      "Filesize: ${urlQuery.totalSize != null ? formatBytes(urlQuery.totalSize!.toInt()) : '?'}",
                                      style: textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              )
                            ],
                        );
                      },
                    ),
                ],
              ),
            ),
            actionsPadding: EdgeInsets.symmetric(
              horizontal: AppTheme.spaceSM * AppTheme.spaceScale(context),
              vertical: AppTheme.spaceSM * AppTheme.spaceScale(context),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Cancel", style: textTheme.bodyMedium),
              ),
              ElevatedButton(
                onPressed: handleSubmit,
                child: Text(
                  showQueryInfo && queryFinished ? "Download" : "Query",
                  style: textTheme.bodyMedium?.copyWith(color: colors.primary),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
