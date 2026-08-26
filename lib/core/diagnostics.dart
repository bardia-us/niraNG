import 'package:flutter/widgets.dart';

abstract final class NirangDiagnostics {
  static String currentFeature = 'startup';
  static String currentRoute = '/';
}

final nirangNavigatorKey = GlobalKey<NavigatorState>();
final nirangRouteObserver = _NirangRouteObserver();

class _NirangRouteObserver extends NavigatorObserver {
  void _record(Route<dynamic>? route) {
    NirangDiagnostics.currentRoute =
        route?.settings.name ?? route?.runtimeType.toString() ?? '/';
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _record(newRoute);
  }
}
