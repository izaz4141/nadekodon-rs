// lib/ui/widgets/settings/download_folder_tile.dart
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../utils/settings.dart';

class DownloadFolderTile extends StatelessWidget {
  const DownloadFolderTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: SettingsManager.downloadFolder,
      builder: (context, value, _) {
        return ListTile(
          title: const Text("Download Folder"),
          subtitle: Text(
            value.isEmpty ? "Not selected" : value,
            style: TextStyle(color: Colors.grey),
          ),
          trailing: SizedBox(
            width: 72,
            child: IconButton(
              icon: const Icon(Icons.folder_open),
              onPressed: () async {
                String? selectedDirectory = await FilePicker.platform
                    .getDirectoryPath();
                if (selectedDirectory != null) {
                  SettingsManager.downloadFolder.value = selectedDirectory;
                }
              },
            ),
          ),
        );
      },
    );
  }
}
