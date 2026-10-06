import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Page gestures stay disabled until every popup (including its exit) is gone.
class MenuActivity {
  static final isOpen = ValueNotifier<bool>(false);
  static final _leases = <Object>{};

  static Object begin() {
    final lease = Object();
    _leases.add(lease);
    _publish();
    return lease;
  }

  static void end(Object lease) {
    _leases.remove(lease);
    _publish();
  }

  static void _publish() {
    void update() => isOpen.value = _leases.isNotEmpty;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => update());
    } else {
      update();
    }
  }
}

class MenuActivityScope extends StatefulWidget {
  const MenuActivityScope({required this.child, super.key});
  final Widget child;
  @override
  State<MenuActivityScope> createState() => _MenuActivityScopeState();
}

class _MenuActivityScopeState extends State<MenuActivityScope> {
  late final Object _lease;
  @override
  void initState() {
    super.initState();
    _lease = MenuActivity.begin();
  }

  @override
  void dispose() {
    MenuActivity.end(_lease);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
