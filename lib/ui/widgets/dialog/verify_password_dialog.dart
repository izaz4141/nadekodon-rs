import 'package:flutter/material.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/app_snackbar.dart';
import 'package:nadekodon/utils/api_service.dart';
import 'package:nadekodon/utils/platform_service.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/src/bindings/bindings.dart';

class VerifyPasswordDialog extends StatefulWidget {
  const VerifyPasswordDialog({super.key});

  @override
  State<VerifyPasswordDialog> createState() => _VerifyPasswordDialogState();
}

class _VerifyPasswordDialogState extends State<VerifyPasswordDialog> {
  final _passwordController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_passwordController.text.isEmpty) {
      AppSnackBar.show(
        context,
        "Please enter the password",
        type: SnackType.error,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    bool isValid;
    if (PlatformService().isRemote) {
      isValid = await APIService.verifyPassword(_passwordController.text);
    } else {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      VerifyPassword(
        id: id,
        input: _passwordController.text,
        reference: SettingsManager.password.value,
      ).sendSignalToRust();
      final stream = VerifyPasswordResult.rustSignalStream.where(
        (signal) => signal.message.id == id,
      );
      final result = await stream.first;
      isValid = result.message.success;
    }

    setState(() {
      _isLoading = false;
    });

    if (isValid) {
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } else {
      if (!mounted) return;
      AppSnackBar.show(context, "Incorrect password", type: SnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.lock_open,
            color: colors.primary,
            size: AppTheme.iconLG * AppTheme.iconScale(context),
          ),
          SizedBox(width: AppTheme.spaceSM * AppTheme.spaceScale(context)),
          Text('Verify Credentials', style: textTheme.titleMedium),
        ],
      ),
      content: SizedBox(
        width: AppTheme.dialogWidth(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Enter your password to unlock security settings",
              style: textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            SizedBox(height: AppTheme.spaceMD * AppTheme.spaceScale(context)),
            TextField(
              controller: _passwordController,
              focusNode: _focusNode,
              obscureText: _obscurePassword,
              autofocus: true,
              autofillHints: const [AutofillHints.password],
              style: textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
              decoration: InputDecoration(
                labelText: "Password",
                labelStyle: textTheme.bodyMedium?.copyWith(
                  color: colors.primary,
                ),
                hintText: "Enter password",
                hintStyle: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              onSubmitted: (_) => _verify(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _verify,
          child: _isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.onPrimary,
                  ),
                )
              : const Text('Unlock'),
        ),
      ],
    );
  }
}
