import 'package:flutter/material.dart';
import 'package:nadekodon/models/account.dart';
import 'package:nadekodon/utils/api_service.dart';
import 'package:nadekodon/utils/settings.dart';
// ignore: unused_import
import 'package:nadekodon/ui/theme/app_theme.dart';

class AddAccountDialog extends StatefulWidget {
  const AddAccountDialog({super.key});

  @override
  State<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<AddAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  String _protocol = 'http://';
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '8080');
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _labelCtrl = TextEditingController();

  bool _isTesting = false;
  String? _testResult;
  String? _retrievedApiKey;
  bool _connectionSuccess = false;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text("Add Account", style: textTheme.titleMedium),
      constraints: BoxConstraints(minWidth: AppTheme.dialogWidth(context)),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _labelCtrl,
                style: textTheme.bodyMedium,
                decoration: InputDecoration(
                  labelText: "Label (Optional)",
                  labelStyle: textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spaceSM),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: DropdownButtonFormField<String>(
                      initialValue: _protocol,
                      style: textTheme.bodyMedium,
                      decoration: InputDecoration(
                        labelText: "Protocol",
                        labelStyle: textTheme.bodyMedium?.copyWith(
                          color: colors.onSurface,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'http://',
                          child: Text('http://'),
                        ),
                        DropdownMenuItem(
                          value: 'https://',
                          child: Text('https://'),
                        ),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _protocol = v!;
                          if (_protocol == 'https://') {
                            _portCtrl.text = '443';
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceSM),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _hostCtrl,
                      style: textTheme.bodyMedium,
                      decoration: InputDecoration(
                        labelText: "Host (IP/Domain)",
                        hintText: "127.0.0.1",
                        labelStyle: textTheme.bodyMedium?.copyWith(
                          color: colors.onSurface,
                        ),
                      ),
                      validator: (v) =>
                          v?.isNotEmpty == true ? null : "Required",
                    ),
                  ),
                  const SizedBox(width: AppTheme.spaceSM),
                  Expanded(
                    child: TextFormField(
                      controller: _portCtrl,
                      style: textTheme.bodyMedium,
                      decoration: InputDecoration(
                        labelText: "Port",
                        labelStyle: textTheme.bodyMedium?.copyWith(
                          color: colors.onSurface,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          v?.isNotEmpty == true ? null : "Required",
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spaceSM),
              TextFormField(
                controller: _usernameCtrl,
                style: textTheme.bodyMedium,
                decoration: InputDecoration(
                  labelText: "Username",
                  labelStyle: textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface,
                  ),
                ),
                validator: (v) => v?.isNotEmpty == true ? null : "Required",
              ),
              const SizedBox(height: AppTheme.spaceSM),
              TextFormField(
                controller: _passwordCtrl,
                style: textTheme.bodyMedium,
                decoration: InputDecoration(
                  labelText: "Password",
                  labelStyle: textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface,
                  ),
                ),
                obscureText: true,
                validator: (v) => v?.isNotEmpty == true ? null : "Required",
              ),
              const SizedBox(height: AppTheme.spaceSM),
              if (_testResult != null)
                Text(
                  _testResult!,
                  style: TextStyle(
                    color: _connectionSuccess ? Colors.green : Colors.red,
                  ),
                ),
              const SizedBox(height: AppTheme.spaceSM),
              ElevatedButton(
                onPressed: _isTesting ? null : _runTestConnection,
                child: _isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        "Test Connection",
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.primary,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Cancel", style: textTheme.bodyMedium),
        ),
        FilledButton(
          onPressed: _connectionSuccess ? _saveAccount : null,
          child: Text("Save", style: textTheme.bodyMedium),
        ),
      ],
    );
  }

  Future<void> _runTestConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
      _connectionSuccess = false;
    });

    final host = '$_protocol${_hostCtrl.text}';
    final port = _portCtrl.text;
    final username = _usernameCtrl.text;
    final password = _passwordCtrl.text;

    try {
      final success = await APIService.testLogin(
        host: host,
        port: int.parse(port),
        username: username,
        password: password,
      );

      if (success != null) {
        setState(() {
          _connectionSuccess = true;
          _retrievedApiKey = success; // success returns api key
          _testResult = "Connection Successful!";
        });
      } else {
        setState(() {
          _connectionSuccess = false;
          _testResult =
              "Login Failed: Invalid credentials or host unreachable.";
        });
      }
    } catch (e) {
      setState(() {
        _connectionSuccess = false;
        _testResult = "Error: $e";
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  void _saveAccount() {
    if (!_connectionSuccess || _retrievedApiKey == null) return;

    final account = Account(
      host: '$_protocol${_hostCtrl.text}',
      port: int.parse(_portCtrl.text),
      apiKey: _retrievedApiKey!,
      username: _usernameCtrl.text,
      label: _labelCtrl.text.isEmpty ? _hostCtrl.text : _labelCtrl.text,
    );

    SettingsManager.addAccount(account);
    Navigator.pop(context);
  }
}
