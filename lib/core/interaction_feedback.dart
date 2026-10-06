import 'package:flutter/services.dart';

/// Immediate optional feedback; unavailable device services never block actions.
class InteractionFeedback {
  InteractionFeedback._();

  static const _channel = MethodChannel('dev.nirang.client/feedback');

  /// Tabs have their own brief pop paired with a selection haptic.
  static Future<void> playNavigation(String mode) async {
    if (mode == 'off') return;
    await Future.wait([play('haptic'), _playNavigationSound()]);
  }

  static Future<void> _playNavigationSound() async {
    try {
      await _channel.invokeMethod<void>('playNavigation');
    } on PlatformException {
      // An optional sound cannot interrupt navigation.
    } on MissingPluginException {
      // Unsupported platforms still navigate.
    }
  }

  static Future<void> play(String mode) async {
    try {
      switch (mode) {
        case 'haptic':
          await HapticFeedback.selectionClick();
        case 'sound':
          await _channel.invokeMethod<void>('play');
        default:
          return;
      }
    } on PlatformException {
      // Some devices or activity states cannot provide optional feedback.
    } on MissingPluginException {
      // Unsupported platforms still perform the requested action.
    }
  }
}
