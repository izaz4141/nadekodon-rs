import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowControls extends StatelessWidget {
  const WindowControls({super.key});

  Widget _buildButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? hoverColor,
  }) {
    return InkWell(
      onTap: onPressed,
      hoverColor: hoverColor?.withAlpha(70) ?? Colors.grey.withAlpha(70),
      child: SizedBox(
        width: kToolbarHeight,
        height: kToolbarHeight,
        child: Icon(icon, color: hoverColor),
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
        ),
        _buildButton(
          icon: Icons.close,
          onPressed: () => windowManager.close(),
          hoverColor: Colors.red.withAlpha(70),
        ),
      ],
    );
  }
}
