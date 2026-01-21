import 'package:flutter/material.dart';

import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/utils/api_service.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginPage({super.key, required this.onLoginSuccess});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final success = await APIService.login(
      username: _usernameController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (success) {
      SettingsManager.isLoggedIn.value = true;
      widget.onLoginSuccess();
    } else {
      setState(() {
        _errorMessage = 'Invalid username or password';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(
            AppTheme.spaceLG * AppTheme.spaceScale(context),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: EdgeInsets.all(
                  AppTheme.spaceLG * AppTheme.spaceScale(context),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height:
                          AppTheme.iconXXL * 2 * AppTheme.iconScale(context),
                      child: Image.asset('assets/icons/nadeko-don-1024.png'),
                    ),
                    SizedBox(
                      height: AppTheme.spaceMD * AppTheme.spaceScale(context),
                    ),
                    Text(
                      'Nadeko~don',
                      style: textTheme.headlineMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(
                      height: AppTheme.spaceSM * AppTheme.spaceScale(context),
                    ),
                    Text(
                      'Sign in to continue',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(
                      height: AppTheme.spaceLG * AppTheme.spaceScale(context),
                    ),
                    TextField(
                      controller: _usernameController,
                      autofocus: true,
                      autofillHints: const [AutofillHints.username],
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Username',
                        labelStyle: textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        prefixIcon: Icon(
                          Icons.person_outline,
                          color: colors.onSurfaceVariant,
                          size: AppTheme.iconMD * AppTheme.iconScale(context),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMD,
                          ),
                        ),
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    SizedBox(
                      height: AppTheme.spaceMD * AppTheme.spaceScale(context),
                    ),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.password],
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        prefixIcon: Icon(
                          Icons.lock_outline,
                          color: colors.onSurfaceVariant,
                          size: AppTheme.iconMD * AppTheme.iconScale(context),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: colors.onSurfaceVariant,
                            size: AppTheme.iconMD * AppTheme.iconScale(context),
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMD,
                          ),
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _login(),
                    ),
                    if (_errorMessage != null) ...[
                      SizedBox(
                        height: AppTheme.spaceMD * AppTheme.spaceScale(context),
                      ),
                      Text(
                        _errorMessage!,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.error,
                        ),
                      ),
                    ],
                    SizedBox(
                      height: AppTheme.spaceLG * AppTheme.spaceScale(context),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _login,
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            vertical:
                                AppTheme.spaceLG * AppTheme.spaceScale(context),
                            horizontal:
                                AppTheme.spaceMD * AppTheme.spaceScale(context),
                          ),
                        ),
                        child: _isLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text('Sign In', style: textTheme.bodyMedium),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
