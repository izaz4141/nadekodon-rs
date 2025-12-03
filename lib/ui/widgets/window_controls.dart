import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _init();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  void _init() async {
    _isMaximized = await windowManager.isMaximized();
    if (mounted) setState(() {});
  }

  @override
  void onWindowMaximize() {
    setState(() {
      _isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      _isMaximized = false;
    });
  }

  Widget _buildButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? hoverColor,
    required ColorScheme colors,
  }) {
    return InkWell(
      onTap: onPressed,
      hoverColor: hoverColor ?? colors.onSurface.withAlpha(26),
      child: SizedBox(
        width: kToolbarHeight,
        height: kToolbarHeight,
        child: Icon(icon, color: colors.onSurface),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        _buildButton(
          icon: Icons.minimize_rounded,
          onPressed: () => windowManager.minimize(),
          colors: colors,
        ),
        _buildButton(
          icon: _isMaximized
              ? Icons.filter_none_rounded
              : Icons.crop_square_rounded,
          onPressed: () {
            if (_isMaximized) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          },
          colors: colors,
        ),
        _buildButton(
          icon: Icons.close_rounded,
          onPressed: () => windowManager.close(),
          hoverColor: colors.error.withAlpha(26),
          colors: colors,
        ),
      ],
    );
  }
}
