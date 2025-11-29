import 'package:flutter/material.dart';
import 'package:nadekodon/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/view/system_app.dart';
import 'package:nadekodon/ui/widgets/view/system_deps.dart';
import 'package:nadekodon/ui/widgets/view/system_info.dart';

class SystemPage extends StatelessWidget {
  const SystemPage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isDesktop = AppTheme.isDesktop(context);

    return Scaffold(
      appBar: isDesktop
          ? AppBar(title: Text("System", style: textTheme.titleLarge))
          : null,
      body: ListView(
        children: [
          SizedBox(height: AppTheme.spaceXL),
          const SystemApp(),
          SizedBox(height: AppTheme.spaceXL),
          const Divider(),
          const SystemInfo(),
          const Divider(),
          const SystemDeps(),
        ],
      ),
    );
  }
}
