import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'clay_surface.dart';

/// A brief, accessible confirmation that follows the active app theme.
void showSuccessToast(BuildContext context, String message) {
  _showStatusToast(context, message, error: false);
}

void showErrorToast(BuildContext context, String message) {
  _showStatusToast(context, message, error: true);
}

void _showStatusToast(
  BuildContext context,
  String message, {
  required bool error,
}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: math.min(420, MediaQuery.sizeOf(context).width - 32),
        duration: const Duration(seconds: 3),
        elevation: 0,
        backgroundColor: scheme.surfaceContainerHigh,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        content: ClaySurface(
          radius: 22,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: error
                          ? scheme.errorContainer
                          : scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      error ? Icons.error_outline_rounded : Icons.check_rounded,
                      color: error
                          ? scheme.onErrorContainer
                          : scheme.onPrimaryContainer,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(message)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
}
