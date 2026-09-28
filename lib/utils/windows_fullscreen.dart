import 'dart:io';

import 'package:flutter/services.dart';

/// Native Windows borderless fullscreen bridge.
///
/// The Win32 runner owns the actual window style/bounds. Flutter only requests
/// transitions so the reader and tablet shell never depend on F11/Escape.
final class WindowsFullscreen {
  WindowsFullscreen._();

  static const MethodChannel _channel = MethodChannel(
    'io.github.caolib.kira/window',
  );

  static bool get supported => Platform.isWindows;

  static Future<bool> isFullscreen() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isFullscreen') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> toggle() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('toggleFullscreen') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> enter() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('enterFullscreen') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> exit() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('exitFullscreen') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
