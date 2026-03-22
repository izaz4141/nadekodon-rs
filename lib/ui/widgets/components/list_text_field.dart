import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:nadekodon/ui/theme/app_theme.dart';

class ListTextField extends StatefulWidget {
  final String title;
  final String subtitle;
  final ValueListenable<String> valueListenable;
  final bool isObscured;
  final Function(String)? onConfirm;
  final String? autofillHints;
  final TextInputType? keyboardType;
  final bool enabled;

  const ListTextField({
    super.key,
    required this.title,
    required this.subtitle,
    required this.valueListenable,
    this.isObscured = false,
    this.onConfirm,
    this.autofillHints,
    this.keyboardType,
    this.enabled = true,
  });

  @override
  State<ListTextField> createState() => _ListTextFieldState();
}

class _ListTextFieldState extends State<ListTextField> {
  late TextEditingController _controller;
  late ValueNotifier<bool> _obscureNotifier;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.isObscured ? '' : widget.valueListenable.value,
    );
    _obscureNotifier = ValueNotifier<bool>(widget.isObscured);
  }

  @override
  void dispose() {
    _controller.dispose();
    _obscureNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      title: Text(widget.title, style: textTheme.bodyMedium),
      subtitle: Text(widget.subtitle, style: textTheme.bodySmall),
      trailing: SizedBox(
        width: 250 * AppTheme.spaceScale(context),
        child: ValueListenableBuilder<bool>(
          valueListenable: _obscureNotifier,
          builder: (context, obscureText, _) {
            return TextField(
              controller: _controller,
              obscureText: obscureText,
              keyboardType: widget.keyboardType,
              style: textTheme.bodyMedium,
              autofillHints: widget.autofillHints != null
                  ? [widget.autofillHints!]
                  : null,
              decoration: InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppTheme.spaceSM * AppTheme.spaceScale(context),
                  vertical: AppTheme.spaceSM * AppTheme.spaceScale(context),
                ),
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(AppTheme.radiusSM),
                  ),
                ),
                suffixIcon: widget.enabled
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.isObscured)
                            IconButton(
                              icon: Icon(
                                obscureText
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              iconSize:
                                  AppTheme.iconSM * AppTheme.iconScale(context),
                              onPressed: () => _obscureNotifier.value =
                                  !_obscureNotifier.value,
                            ),
                          if (widget.onConfirm != null)
                            IconButton(
                              icon: const Icon(
                                Icons.check,
                                color: Colors.green,
                              ),
                              iconSize:
                                  AppTheme.iconSM * AppTheme.iconScale(context),
                              onPressed: () {
                                widget.onConfirm!(_controller.text);
                                FocusScope.of(context).unfocus();
                              },
                            ),
                        ],
                      )
                    : null,
              ),
              enabled: widget.enabled,
              textInputAction: (widget.onConfirm == null)
                  ? TextInputAction.next
                  : TextInputAction.done,
              onSubmitted: widget.enabled
                  ? (val) {
                      if (widget.onConfirm != null) {
                        widget.onConfirm!(val);
                      }
                    }
                  : null,
              onChanged: widget.enabled
                  ? (newValue) {
                      if (widget.onConfirm == null &&
                          widget.valueListenable is ValueNotifier<String>) {
                        (widget.valueListenable as ValueNotifier<String>)
                                .value =
                            newValue;
                      }
                    }
                  : null,
            );
          },
        ),
      ),
    );
  }
}
