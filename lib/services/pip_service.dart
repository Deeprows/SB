import 'package:flutter/services.dart';

/// Picture-in-picture through a tiny native channel (see
/// tool/patch_main_activity.py). Replaces the unmaintained `floating` plugin,
/// which no longer compiles with current Flutter.
class PipService {
  static const _channel = MethodChannel('footbolive/pip');

  static Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Enters a 16:9 picture-in-picture window. Returns false if it failed.
  static Future<bool> enter() async {
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } catch (_) {
      return false;
    }
  }
}
