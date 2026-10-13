import 'package:flutter/material.dart';

/// The app's single navigator, so something that is not tied to a screen
/// (the 15-minute support timer) can still show a page on top of whatever is
/// open.
class AppNav {
  /// Lets snackbars be shown from anywhere (timers, services).
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  /// A context that lives INSIDE the navigator (dialogs need one).
  static BuildContext? get overlayContext => key.currentState?.overlay?.context;
}
