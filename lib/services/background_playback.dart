import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Keeps video/audio playing when the app is minimised or the screen is
/// locked. Starts an Android foreground service (media notification) while a
/// player page is open, so the system doesn't freeze or kill the app. The
/// native side is added by tool/patch_background_playback.py.
class BackgroundPlayback {
  static const _channel = MethodChannel('footbolive/playback');
  static final List<VoidCallback> _stopHandlers = [];
  static bool _hooked = false;

  // Handlers of the player page that is on screen (the latest one wins).
  static VoidCallback? _onPlay;
  static VoidCallback? _onPause;
  static void Function(int seconds)? _onSeekBy;

  static void _hook() {
    if (_hooked) return;
    _hooked = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'action':
          switch (call.arguments) {
            case 'play':
              _onPlay?.call();
            case 'pause':
              _onPause?.call();
            case 'rewind':
              _onSeekBy?.call(-10);
            case 'forward':
              _onSeekBy?.call(10);
            case 'stop':
              _fireStop();
          }
        case 'stopRequested': // older native code
          _fireStop();
      }
      return null;
    });
  }

  static void _fireStop() {
    for (final h in List.of(_stopHandlers)) {
      h();
    }
  }

  /// Android 13+ never shows a notification (media controls included) until
  /// the person allows it. Without this the audio keeps playing in the
  /// background but the tray / lock screen player is missing. Safe to call
  /// often: it only asks while the permission is still undecided.
  static Future<bool> ensureNotificationPermission() async {
    try {
      var s = await Permission.notification.status;
      if (s.isDenied) s = await Permission.notification.request();
      return s.isGranted || s.isProvisional;
    } catch (_) {
      return true;
    }
  }

  /// True when the system will actually show our notifications. Android 13+
  /// hides the media card (tray and lock screen) while this is false.
  static Future<bool> notificationsAllowed() async {
    try {
      final s = await Permission.notification.status;
      return s.isGranted || s.isProvisional || s.isLimited;
    } catch (_) {
      return true;
    }
  }

  /// Call when a player page opens. [onStopRequested] runs when the user taps
  /// Stop on the notification. [onPlay] / [onPause] / [onSeekBy] handle the
  /// other notification and lock-screen buttons (seek is +-10 seconds).
  static Future<void> start(
    String title,
    VoidCallback onStopRequested, {
    VoidCallback? onPlay,
    VoidCallback? onPause,
    void Function(int seconds)? onSeekBy,
  }) async {
    _hook();
    if (!_stopHandlers.contains(onStopRequested)) {
      _stopHandlers.add(onStopRequested);
    }
    _onPlay = onPlay;
    _onPause = onPause;
    _onSeekBy = onSeekBy;
    await ensureNotificationPermission();
    try {
      await _channel
          .invokeMethod<bool>('start', {'title': title, 'playing': true});
    } catch (_) {}
  }

  /// Tells the notification whether the video is really playing, so the
  /// button shows Pause or Play correctly.
  static Future<void> setPlaying(bool playing) async {
    try {
      await _channel.invokeMethod<bool>('update', {'playing': playing});
    } catch (_) {}
  }

  /// Call when that player page closes. The service ends with the last one.
  static Future<void> stop(VoidCallback onStopRequested) async {
    _stopHandlers.remove(onStopRequested);
    if (_stopHandlers.isNotEmpty) return;
    _onPlay = null;
    _onPause = null;
    _onSeekBy = null;
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {}
  }

  /// Web pages pause their video when they think the tab is hidden. This
  /// makes the page believe it is always visible.
  static const keepVisibleJs = '''
(function(){try{
if(window.__dwBg)return;window.__dwBg=1;
function def(o,k,v){try{Object.defineProperty(o,k,{configurable:true,get:function(){return v}})}catch(e){}}
def(document,'hidden',false);def(document,'webkitHidden',false);
def(document,'visibilityState','visible');def(document,'webkitVisibilityState','visible');
var stop=function(e){e.stopImmediatePropagation()};
document.addEventListener('visibilitychange',stop,true);
document.addEventListener('webkitvisibilitychange',stop,true);
}catch(e){}})();
''';

  /// Run when the app goes to the background: remembers which videos play.
  static const rememberPlayingJs = '''
(function(){try{window.__dwWas=[].slice.call(document.querySelectorAll('video')).filter(function(v){return !v.paused&&!v.ended})}catch(e){}})();
''';

  /// Run shortly after: restarts any of those videos the page paused.
  static const resumePlayingJs = '''
(function(){try{(window.__dwWas||[]).forEach(function(v){if(v.paused){var p=v.play();if(p&&p.catch)p.catch(function(){})}})}catch(e){}})();
''';
}
