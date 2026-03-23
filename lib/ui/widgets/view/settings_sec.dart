import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nadekodon/utils/platform_service.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/ui/widgets/app_snackbar.dart';
import 'package:nadekodon/ui/widgets/components/section_header.dart';
import 'package:nadekodon/ui/widgets/components/spin_box.dart';
import 'package:nadekodon/ui/widgets/components/list_text_field.dart';
import 'package:nadekodon/ui/widgets/dialog/verify_password_dialog.dart';
import 'package:nadekodon/utils/api_service.dart';

class SettingsSec extends StatefulWidget {
  const SettingsSec({super.key});

  @override
  State<SettingsSec> createState() => _SettingsSecState();
}

class _SettingsSecState extends State<SettingsSec> {
  bool _isLocked = true;
  bool _isSaving = false;

  final _localRequireLogin = ValueNotifier<bool>(
    SettingsManager.requireLogin.value,
  );
  final _localServerPort = ValueNotifier<int>(SettingsManager.serverPort.value);
  final _localUsername = ValueNotifier<String>(SettingsManager.username.value);
  final _localPassword = ValueNotifier<String>('');

  Future<void> _handleLockToggle() async {
    if (_isLocked) {
      final unlocked = await showDialog<bool>(
        context: context,
        builder: (context) => const VerifyPasswordDialog(),
      );
      if (unlocked == true) {
        _localRequireLogin.value = SettingsManager.requireLogin.value;
        _localServerPort.value = SettingsManager.serverPort.value;
        _localUsername.value = SettingsManager.username.value;
        _localPassword.value = '';
        setState(() {
          _isLocked = false;
        });
      }
    } else {
      setState(() {
        _isLocked = true;
      });
    }
  }

  Future<void> _saveChanges() async {
    setState(() {
      _isSaving = true;
    });
    bool success = false;
    if (PlatformService().isRemote) {
      success = await APIService.changeCredentials(
        currentPassword: SettingsManager.password.value,
        newUsername: _localUsername.value,
        newPassword: _localPassword.value.isEmpty ? null : _localPassword.value,
        serverPort: _localServerPort.value,
      );
    } else {
      await SettingsManager.saveChanged('server_port', _localServerPort.value);
      await SettingsManager.saveChanged('username', _localUsername.value);
      if (_localPassword.value.isNotEmpty) {
        await SettingsManager.saveChanged('password', _localPassword.value);
      }
      success = true;
    }

    await SettingsManager.saveChanged(
      'require_login',
      _localRequireLogin.value,
    );

    setState(() {
      _isSaving = false;
    });

    if (success) {
      setState(() {
        _isLocked = true;
      });

      SettingsManager.requireLogin.value = _localRequireLogin.value;
      SettingsManager.serverPort.value = _localServerPort.value;
      SettingsManager.username.value = _localUsername.value;
      await SettingsManager.reloadConfig();

      if (!mounted) return;
      AppSnackBar.show(
        context,
        "Settings saved successfully",
        type: SnackType.success,
      );
    } else {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        "Failed to save settings",
        type: SnackType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final isEnabled = !_isLocked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Security Settings',
          leading: IconButton(
            icon: Icon(
              _isLocked ? Icons.lock : Icons.lock_open,
              color: colors.onPrimaryContainer,
            ),
            iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
            tooltip: _isLocked ? "Unlock settings" : "Lock settings",
            onPressed: _handleLockToggle,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: APIService.isOnline,
                builder: (context, isOnline, _) {
                  return IconButton(
                    icon: Icon(
                      Icons.refresh,
                      color: isOnline
                          ? colors.onPrimaryContainer
                          : colors.error,
                    ),
                    iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
                    tooltip: isOnline ? "Server Online" : "Server Offline",
                    onPressed: () {
                      SettingsManager.restartServer();
                      APIService.restartPolling();
                      AppSnackBar.show(context, "Server restarted");
                    },
                  );
                },
              ),
            ],
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _localRequireLogin,
          builder: (context, value, _) {
            return ListTile(
              title: Text("Require Login", style: textTheme.bodyMedium),
              subtitle: Text(
                "Show login screen on startup",
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              trailing: Transform.scale(
                scale: AppTheme.iconScale(context),
                alignment: Alignment.centerRight,
                child: Switch(
                  value: value,
                  onChanged: isEnabled
                      ? (newValue) {
                          _localRequireLogin.value = newValue;
                        }
                      : null,
                ),
              ),
            );
          },
        ),
        SpinBox(
          title: "Server Port",
          subtitle: "Port to listen on",
          valueListenable: _localServerPort,
          min: 1024,
          max: 65535,
          enabled: isEnabled,
        ),
        AutofillGroup(
          child: Column(
            children: [
              ListTextField(
                title: "Username",
                subtitle: "API username",
                valueListenable: _localUsername,
                autofillHints: AutofillHints.newUsername,
                enabled: isEnabled,
              ),
              ListTextField(
                title: "Password",
                subtitle: "API password",
                valueListenable: _localPassword,
                isObscured: true,
                autofillHints: AutofillHints.newPassword,
                keyboardType: TextInputType.visiblePassword,
                enabled: isEnabled,
              ),
            ],
          ),
        ),
        _buildApiKeyDisplay(context, textTheme, colors, isEnabled),
        if (!_isLocked) _buildSaveButton(context, colors),
      ],
    );
  }

  Widget _buildApiKeyDisplay(
    BuildContext context,
    TextTheme textTheme,
    ColorScheme colors,
    bool isEnabled,
  ) {
    return ListTile(
      title: Text("API Key", style: textTheme.bodyMedium),
      subtitle: ValueListenableBuilder<String>(
        valueListenable: SettingsManager.serverApiKey,
        builder: (context, key, _) {
          return SelectableText(
            key,
            style: textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          );
        },
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.copy),
            iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
            tooltip: "Copy API Key",
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: SettingsManager.serverApiKey.value),
              );
              AppSnackBar.show(context, "API Key copied to clipboard");
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
            tooltip: "Regenerate API Key",
            onPressed: isEnabled
                ? () {
                    SettingsManager.regenerateApiKey();
                    AppSnackBar.show(context, "API Key regenerated");
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(BuildContext context, ColorScheme colors) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.all(AppTheme.spaceMD * AppTheme.spaceScale(context)),
      child: SizedBox(
        width: double.infinity,
        height: 2 * AppTheme.textMD * AppTheme.textScale(context),
        child: FilledButton.icon(
          onPressed: _isSaving ? null : _saveChanges,
          icon: _isSaving
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.onPrimary,
                  ),
                )
              : Icon(
                  Icons.save,
                  size: AppTheme.iconMD * AppTheme.iconScale(context),
                ),
          label: Text(
            _isSaving ? "Saving..." : "Save Changes",
            style: textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}
