import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowControls extends StatelessWidget {
  const WindowControls({super.key});

  Widget _buildButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? hoverColor,
    required ColorScheme colors,
  }) {
    return InkWell(
      onTap: onPressed,
      hoverColor: hoverColor ?? colors.onSurface.withOpacity(0.1),
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
          icon: Icons.remove, // better minimize icon
          onPressed: () => windowManager.minimize(),
          colors: colors,
        ),
        _buildButton(
          icon: Icons.crop_square, // maximize/restore
          onPressed: () async {
            final isMax = await windowManager.isMaximized();
            if (isMax) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
          colors: colors,
        ),
        _buildButton(
          icon: Icons.close,
          onPressed: () => windowManager.close(),
          hoverColor: colors.error.withOpacity(0.1),
          colors: colors,
        ),
      ],
    );
  }
}
