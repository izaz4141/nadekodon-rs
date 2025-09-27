// lib/ui/widgets/settings/server_port_spinbox.dart
import 'package:flutter/material.dart';
import '../../../utils/settings.dart';
import '../spin_box.dart';

class PortSpinBox extends StatelessWidget {
  const PortSpinBox({super.key});

  @override
  Widget build(BuildContext context) {
    return SpinBox(
      title: "Port",
      subtitle: "Network Port used for the browser integration",
      valueListenable: SettingsManager.serverPort,
      min: 1024,
      max: 65535,
    );
  }
}
