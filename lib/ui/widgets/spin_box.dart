// lib/ui/widgets/spin_box.dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class SpinBox extends StatefulWidget {
  const SpinBox({
    super.key,
    required this.title,
    required this.subtitle,
    required this.valueListenable,
    required this.min,
    required this.max,
    this.step = 1,
    this.width = AppTheme.spaceXXL * 2.5,
  });

  final String title;
  final String subtitle;
  final ValueNotifier<int> valueListenable;
  final int min;
  final int max;
  final int step;
  final double width;

  @override
  State<SpinBox> createState() => _SpinBoxState();
}

class _SpinBoxState extends State<SpinBox> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.valueListenable.value.toString());
    _focusNode = FocusNode();
    
    // Listen for external changes to update the text field
    widget.valueListenable.addListener(_updateController);
    
    // Handle focus changes
    _focusNode.addListener(_handleFocusChange);
  }

  void _updateController() {
    if (!_isEditing && _controller.text != widget.valueListenable.value.toString()) {
      _controller.text = widget.valueListenable.value.toString();
    }
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      // Save the value when focus is lost
      _saveValue();
      setState(() {
        _isEditing = false;
      });
    } else {
      setState(() {
        _isEditing = true;
      });
    }
  }

  void _saveValue() {
    final intValue = int.tryParse(_controller.text);
    if (intValue != null && intValue >= widget.min && intValue <= widget.max) {
      widget.valueListenable.value = intValue;
    } else {
      // Reset to current value if invalid
      _controller.text = widget.valueListenable.value.toString();
    }
  }

  void _increment() {
    if (widget.valueListenable.value < widget.max) {
      widget.valueListenable.value = widget.valueListenable.value + widget.step;
    }
  }

  void _decrement() {
    if (widget.valueListenable.value > widget.min) {
      widget.valueListenable.value = widget.valueListenable.value - widget.step;
    }
  }

  @override
  void dispose() {
    widget.valueListenable.removeListener(_updateController);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      title: Text(
        widget.title, 
        style: textTheme.bodyMedium
      ),
      subtitle: Text(
        widget.subtitle, 
        style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppTheme.spaceSM * AppTheme.spaceScale(context),
            ),
            child: IconButton(
              icon: const Icon(Icons.remove),
              iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
              onPressed: _decrement,
            ),
          ),
          SizedBox(
            width: widget.width * AppTheme.spaceScale(context),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppTheme.spaceSM * AppTheme.spaceScale(context),
                  vertical: AppTheme.spaceSM * AppTheme.spaceScale(context),
                ),
                isDense: true,
              ),
              onChanged: (value) {
                // Update the value as the user types
                final intValue = int.tryParse(value);
                if (intValue != null && intValue >= widget.min && intValue <= widget.max) {
                  widget.valueListenable.value = intValue;
                }
              },
              onSubmitted: (value) {
                _saveValue();
                _focusNode.unfocus();
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppTheme.spaceSM * AppTheme.spaceScale(context),
            ),
            child: IconButton(
              icon: const Icon(Icons.add),
              iconSize: AppTheme.iconMD * AppTheme.spaceScale(context),
              onPressed: _increment,
            ),
          ),
        ],
      ),
    );
  }
}