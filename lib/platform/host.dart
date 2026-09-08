import 'dart:io';

import 'package:flutter/services.dart';

/// The single channel to the host platform. Android implements it in Kotlin,
/// macOS in Swift, Windows in C++; every method is optional and the Dart side
/// degrades gracefully when a platform does not answer.
const MethodChannel hostChannel = MethodChannel('anime_now/platform');

/// Desktop = a window on a screen, mobile = a full-screen app. The two differ
/// in how files are saved, how notifications are posted and how the window is
/// sized, so the checks live here instead of being spelled out at each site.
bool get isDesktop => Platform.isMacOS || Platform.isWindows || Platform.isLinux;

bool get isMobile => Platform.isAndroid || Platform.isIOS;
