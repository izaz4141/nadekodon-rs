import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nadekodon/models/account.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/utils/platform_service.dart';
import 'package:nadekodon/ui/widgets/dialog/add_account_dialog.dart';
// ignore: unused_import
import 'package:nadekodon/ui/theme/app_theme.dart';

class AccountManagerDialog extends StatelessWidget {
  const AccountManagerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text("Manage Accounts", style: textTheme.titleMedium),
      content: SizedBox(
        width: AppTheme.dialogWidth(context),
        child: ValueListenableBuilder<List<Account>>(
          valueListenable: SettingsManager.accounts,
          builder: (context, accounts, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    kIsWeb ? Icons.public : Icons.home,
                    size: AppTheme.iconMD * AppTheme.iconScale(context),
                  ),
                  title: Text(kIsWeb ? "Web Session" : "Local Session"),
                  subtitle: Text(
                    kIsWeb ? Uri.base.origin : "Internal Rust Backend",
                  ),
                  trailing: SettingsManager.serverHost.value == '127.0.0.1'
                      ? Icon(
                          Icons.check,
                          size: AppTheme.iconMD * AppTheme.iconScale(context),
                          color: Colors.green,
                        )
                      : null,
                  onTap: () {
                    SettingsManager.switchToLocal();
                    Navigator.pop(context);
                  },
                ),
                if (!PlatformService().isRemote) ...[
                  const Divider(),
                  if (accounts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(AppTheme.spaceMD),
                      child: Text("No saved accounts"),
                    ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: accounts.length,
                      itemBuilder: (context, index) {
                        final account = accounts[index];
                        final isCurrent =
                            account.host == SettingsManager.serverHost.value &&
                            account.port == SettingsManager.serverPort.value;

                        return ListTile(
                          leading: Icon(
                            Icons.dns,
                            size: AppTheme.iconMD * AppTheme.iconScale(context),
                          ),
                          title: Text(account.label),
                          subtitle: Text("${account.host}:${account.port}"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isCurrent)
                                Icon(
                                  Icons.check,
                                  size:
                                      AppTheme.iconMD *
                                      AppTheme.iconScale(context),
                                  color: Colors.green,
                                ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete,
                                  size:
                                      AppTheme.iconMD *
                                      AppTheme.iconScale(context),
                                ),
                                onPressed: () {
                                  SettingsManager.removeAccount(account);
                                },
                              ),
                            ],
                          ),
                          onTap: () {
                            SettingsManager.switchAccount(account);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
                  ),
                  if (!kIsWeb) ...[
                    const SizedBox(height: AppTheme.spaceMD),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context); // Close manager
                        _showAddAccountDialog(context);
                      },
                      icon: Icon(
                        Icons.add,
                        size: AppTheme.iconMD * AppTheme.iconScale(context),
                      ),
                      label: Text("Add Account", style: textTheme.bodyMedium),
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Close", style: textTheme.bodyMedium),
        ),
      ],
    );
  }

  void _showAddAccountDialog(BuildContext context) {
    showDialog(context: context, builder: (ctx) => const AddAccountDialog());
  }
}
