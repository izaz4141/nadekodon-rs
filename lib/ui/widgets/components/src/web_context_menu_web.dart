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

  final _identifier = UniqueKey();
  String get identifier => widget.identifier ?? _identifier.toString();

  @override
  void initState() {
    super.initState();
    SemanticsBinding.instance.ensureSemantics();
    _activeIdentifiers.add(identifier);

    if (!_globalListenerAdded) {
      _globalListenerAdded = true;
      html.document.addEventListener('contextmenu', _handleContextMenu.toJS);
    }
  }

  void _handleContextMenu(html.Event event) {
    final target = event.target as html.Element?;
    if (target == null) return;

    final elementWithIdentifier = target.closest('[flt-semantics-identifier]');
    if (elementWithIdentifier != null) {
      final id = elementWithIdentifier.getAttribute('flt-semantics-identifier');
      if (id != null && _activeIdentifiers.contains(id)) {
        event.preventDefault();
      }
    }
  }

  @override
  void dispose() {
    _activeIdentifiers.remove(identifier);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: identifier,
      child: widget.child,
    );
  }
}
