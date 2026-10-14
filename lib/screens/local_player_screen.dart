import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../theme/app_theme.dart';
import '../widgets/glass.dart';

/// Plays a downloaded video file inside the app: tap to show or hide the
/// controls, drag the bar to seek, double-tap the sides to jump 10 seconds.
class LocalPlayerScreen extends StatefulWidget {
  final String path;
  final String title;
  const LocalPlayerScreen({super.key, required this.path, required this.title});

  @override
  State<LocalPlayerScreen> createState() => _LocalPlayerScreenState();
}

class _LocalPlayerScreenState extends State<LocalPlayerScreen> {
  late final VideoPlayerController _c;
  bool _ready = false;
  bool _failed = false;
  bool _controls = true;
  bool _landscape = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _c = VideoPlayerController.file(File(widget.path));
    _c.addListener(() {
      if (mounted) setState(() {});
    });
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c.play();
      _scheduleHide();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _c.value.isPlaying) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _playPause() {
    _c.value.isPlaying ? _c.pause() : _c.play();
    _scheduleHide();
  }

  void _jump(int seconds) {
    final pos = _c.value.position + Duration(seconds: seconds);
    final max = _c.value.duration;
    _c.seekTo(pos < Duration.zero ? Duration.zero : (pos > max ? max : pos));
    setState(() => _controls = true);
    _scheduleHide();
  }

  Future<void> _rotate() async {
    _landscape = !_landscape;
    await SystemChrome.setPreferredOrientations(_landscape
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : [DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(
        _landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    if (mounted) setState(() {});
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_failed)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  'This file can\'t be played here. It may still be downloading or in a format this phone can\'t play.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Ui.muted, height: 1.4),
                ),
              ),
            )
          else if (!_ready)
            Center(child: CircularProgressIndicator(color: Ui.red))
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              child: Center(
                child: AspectRatio(
                  aspectRatio: v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio,
                  child: VideoPlayer(_c),
                ),
              ),
            ),
          // Double-tap zones: back / forward 10 seconds.
          if (_ready)
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _toggleControls,
                    onDoubleTap: () => _jump(-10),
                  ),
                ),
                const Spacer(),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _toggleControls,
                    onDoubleTap: () => _jump(10),
                  ),
                ),
              ],
            ),
          if (_controls || _failed || !_ready) ...[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(14, top + 8, 14, 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: .75), Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                    if (_ready)
                      GlassIconButton(
                        icon: _landscape
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        onTap: _rotate,
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (_ready && _controls)
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlassIconButton(
                      icon: Icons.replay_10_rounded,
                      size: 52,
                      onTap: () => _jump(-10)),
                  const SizedBox(width: 24),
                  GestureDetector(
                    onTap: _playPause,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        gradient: Ui.gradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Ui.red.withValues(alpha: .5),
                              blurRadius: 20)
                        ],
                      ),
                      child: Icon(
                          v.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 42,
                          color: Ui.palette.onAccent),
                    ),
                  ),
                  const SizedBox(width: 24),
                  GlassIconButton(
                      icon: Icons.forward_10_rounded,
                      size: 52,
                      onTap: () => _jump(10)),
                ],
              ),
            ),
          if (_ready && _controls)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                    18, 24, 18, 12 + MediaQuery.of(context).padding.bottom),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withValues(alpha: .8), Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    Text(_fmt(v.position),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3.5,
                          activeTrackColor: Ui.red,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Ui.redSoft,
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          min: 0,
                          max: v.duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                          value: v.position.inMilliseconds
                              .toDouble()
                              .clamp(0, v.duration.inMilliseconds.toDouble().clamp(1, double.infinity)),
                          onChangeStart: (_) => _hide?.cancel(),
                          onChanged: (x) =>
                              _c.seekTo(Duration(milliseconds: x.round())),
                          onChangeEnd: (_) => _scheduleHide(),
                        ),
                      ),
                    ),
                    Text(_fmt(v.duration),
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
