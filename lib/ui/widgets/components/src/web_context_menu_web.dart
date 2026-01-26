import 'dart:js_interop';
import 'package:web/web.dart' as html;
import 'package:flutter/widgets.dart';
import 'package:flutter/semantics.dart';

class DisableWebContextMenu extends StatefulWidget {
  const DisableWebContextMenu({
    super.key,
    required this.child,
    this.identifier,
  });

  final String? identifier;
  final Widget child;

  @override
  State<DisableWebContextMenu> createState() => _DisableWebContextMenuState();
}

class _DisableWebContextMenuState extends State<DisableWebContextMenu> {
  static final _activeIdentifiers = <String>{};
  static bool _globalListenerAdded = false;

  late String _currentId;

  @override
  void initState() {
    super.initState();
    SemanticsBinding.instance.ensureSemantics();
    _currentId = widget.identifier ?? 'dwcm_${identityHashCode(this)}';
    _activeIdentifiers.add(_currentId);

    if (!_globalListenerAdded) {
      _globalListenerAdded = true;
      _setupGlobalListener();
    }
  }

  static void _setupGlobalListener() {
    html.document.addEventListener(
      'contextmenu',
      (html.Event event) {
        final target = event.target as html.Element?;
        if (target == null) return;

        final elementWithIdentifier = target.closest(
          '[flt-semantics-identifier]',
        );
        if (elementWithIdentifier != null) {
          final id = elementWithIdentifier.getAttribute(
            'flt-semantics-identifier',
          );
          if (id != null && _activeIdentifiers.contains(id)) {
            event.preventDefault();
          }
        }
      }.toJS,
    );
  }

  @override
  void didUpdateWidget(DisableWebContextMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identifier != widget.identifier) {
      _activeIdentifiers.remove(_currentId);
      _currentId = widget.identifier ?? 'dwcm_${identityHashCode(this)}';
      _activeIdentifiers.add(_currentId);
    }
  }

  @override
  void dispose() {
    _activeIdentifiers.remove(_currentId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(identifier: _currentId, child: widget.child);
  }
}
