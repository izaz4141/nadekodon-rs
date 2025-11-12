import 'package:flutter/material.dart';

import 'package:nadekodon/theme/app_theme.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/ui/widgets/components/dir_choose.dart';

import 'package:rinf/rinf.dart';
import 'package:nadekodon/src/bindings/bindings.dart';

class QueryResultView extends StatelessWidget {
  final TextEditingController urlController;
  final TextEditingController nameController;
  final ValueNotifier<String> selectedDir;
  final ValueNotifier<bool> queryFinished;
  final ValueNotifier<bool> isQueryingYtdl;
  final void Function() onDownload;

  const QueryResultView({
    super.key,
    required this.urlController,
    required this.nameController,
    required this.selectedDir,
    required this.queryFinished,
    required this.isQueryingYtdl,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            final urlQuery = signalPack.message as UrlQueryOutput;
            if (!queryFinished.value && !urlQuery.error) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                queryFinished.value = true;
                nameController.text = urlQuery.isWebpage ? "index.html" : urlQuery.name;
              });
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
                    onSubmitted: (_) => onDownload(),
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
                      suffixIcon: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: nameController,
                        builder: (context, value, child) {
                          if (value.text.isEmpty) {
                            return const SizedBox.shrink(); // Hide button if empty
                          }
                          return IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: "Clear",
                            onPressed: () => nameController.clear(),
                          );
                        },
                      ),
                    ),
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppTheme.spaceSM),
                  DirChoose(selectedDir: selectedDir),
                  const SizedBox(height: AppTheme.spaceSM),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (urlQuery.isWebpage)
                        Row(
                          children: [
                            Text(
                              "RETURNED WEBPAGE",
                              style: textTheme.bodySmall?.copyWith(color: colors.error),
                            ),
                            const SizedBox(width: AppTheme.spaceMD),
                            ElevatedButton(
                              onPressed: () {
                                isQueryingYtdl.value = true;
                                QueryYtdl(url: urlController.text.trim()).sendSignalToRust();
                              },
                              child: Text("YTDL", style: textTheme.bodySmall),
                            ),
                          ],
                        ),
                      Text(
                        "Filesize: ${urlQuery.totalSize != null ? formatBytes(urlQuery.totalSize!.toInt()) : '?'}",
                        style: textTheme.bodySmall,
                      ),
                    ],
                  )
                ],
            );
          },
        ),
      ]
    );
  }
}
