// lib/ui/widgets/double_spin_box.dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class DoubleSpinBox extends StatefulWidget {
  const DoubleSpinBox({
    super.key,
    required this.title,
    required this.subtitle,
    required this.valueListenable,
    required this.min,
    required this.max,
    this.step = 1.0,
    this.decimalPlaces = 2,
    this.width = AppTheme.spaceXXL * 2.5,
  });

  final String title;
  final String subtitle;
  final ValueNotifier<double> valueListenable;
  final double min;
  final double max;
  final double step;
  final int decimalPlaces;
  final double width;

  @override
  State<DoubleSpinBox> createState() => _DoubleSpinBoxState();
}

class _DoubleSpinBoxState extends State<DoubleSpinBox> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.valueListenable.value.toStringAsFixed(widget.decimalPlaces)
    );
    _focusNode = FocusNode();
    
    // Listen for external changes to update the text field
    widget.valueListenable.addListener(_updateController);
    
    // Handle focus changes
    _focusNode.addListener(_handleFocusChange);
  }

  void _updateController() {
    final String newValue = widget.valueListenable.value.toStringAsFixed(widget.decimalPlaces);
    if (!_isEditing && _controller.text != newValue) {
      _controller.text = newValue;
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
    final doubleValue = double.tryParse(_controller.text);
    if (doubleValue != null && doubleValue >= widget.min && doubleValue <= widget.max) {
      widget.valueListenable.value = double.parse(doubleValue.toStringAsFixed(widget.decimalPlaces));
    } else {
      // Reset to current value if invalid
      _controller.text = widget.valueListenable.value.toStringAsFixed(widget.decimalPlaces);
    }
  }

  void _increment() {
    if (widget.valueListenable.value < widget.max) {
      final newValue = widget.valueListenable.value + widget.step;
      widget.valueListenable.value = double.parse(newValue.toStringAsFixed(widget.decimalPlaces));
    }
  }

  void _decrement() {
    if (widget.valueListenable.value > widget.min) {
      final newValue = widget.valueListenable.value - widget.step;
      widget.valueListenable.value = double.parse(newValue.toStringAsFixed(widget.decimalPlaces));
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
    final textTheme = Theme.of(context).textTheme;
    
    return ListTile(
      title: Text(
        widget.title, 
        style: textTheme.bodyMedium
      ),
      subtitle: Text(
        widget.subtitle, 
        style: textTheme.bodySmall?.copyWith(color: Colors.grey),
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
                final doubleValue = double.tryParse(value);
                if (doubleValue != null && doubleValue >= widget.min && doubleValue <= widget.max) {
                  widget.valueListenable.value = double.parse(doubleValue.toStringAsFixed(widget.decimalPlaces));
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