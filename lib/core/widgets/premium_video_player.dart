import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../domain/video_playback.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// THE EXERCISE VIDEO SURFACE.
///
/// What it replaces was a `VideoPlayer` with a tap-to-toggle gesture: no
/// timeline, no scrub, no duration, no fullscreen, no mute — and it autoplayed
/// on a loop, which in a gym means a member's phone starts making noise the
/// moment they open an exercise. A demo clip is *studied*: the member wants to
/// go back four seconds and watch the bottom of the rep again. Everything here
/// exists to make that specific act one gesture.
///
/// ── DESIGN DECISIONS ───────────────────────────────────────────────────────
///  • **Poster first.** The library thumbnail paints instantly while the
///    decoder initialises, so the member sees the exercise rather than a grey
///    box. It is `cached_network_image`, so it is fetched once ever.
///  • **No autoplay, no forced loop.** A short clip loops (learning a
///    movement), a long one does not (it becomes a distraction). Sound starts
///    muted-by-default only when the caller says so.
///  • **Controls auto-hide while playing** and stay put while paused — a
///    paused frame is being read, and hiding the scrubber on a frame someone
///    is studying is hostile.
///  • **Failure is stated.** The old screen swallowed the error and left a
///    spinner running forever, which is a promise the video is coming.
///  • **Lifecycle-aware.** Backgrounding pauses; the controller is always
///    disposed; orientation and system chrome are always restored.
class PremiumVideoPlayer extends StatefulWidget {
  final String videoUrl;

  /// The library thumbnail. '' → the brand crest, never a broken-image glyph.
  final String posterUrl;

  /// Spoken name for the media, so the player is navigable without sight.
  final String title;

  /// Fullscreen is offered only where a route can be pushed.
  final bool allowFullscreen;

  const PremiumVideoPlayer({
    super.key,
    required this.videoUrl,
    this.posterUrl = '',
    this.title = 'Exercise video',
    this.allowFullscreen = true,
  });

  @override
  State<PremiumVideoPlayer> createState() => _PremiumVideoPlayerState();
}

class _PremiumVideoPlayerState extends State<PremiumVideoPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _c;
  bool _initialized = false;
  bool _failed = false;
  bool _muted = false;
  double _speed = 1.0;

  bool _controlsVisible = true;
  Timer? _hideTimer;

  /// While the member's finger is down the bar follows the FINGER, not the
  /// decoder — a bar that snaps back to the play head mid-drag feels broken.
  bool _dragging = false;
  double _dragFraction = 0;

  /// Transient "-10s / +10s" flash after a double tap.
  String _skipFlash = '';
  Timer? _skipTimer;

  /// The fullscreen surface is a SEPARATE route, so this state's `setState`
  /// cannot rebuild it — a paused video in fullscreen would show controls
  /// that never respond to a tap. Every UI-state change bumps this notifier,
  /// which the fullscreen route listens to. (The decoder's own ticks are not
  /// enough: a paused player emits none.)
  final ValueNotifier<int> _uiRevision = ValueNotifier<int>(0);

  /// setState that BOTH surfaces observe.
  void _setUi(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _uiRevision.value++;
  }

  /// Clips at or under this loop; longer ones play once. A 6-second demo that
  /// stops dead is useless for learning a movement; a 3-minute walkthrough
  /// that restarts on its own is an interruption.
  static const Duration _loopCeiling = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  Future<void> _open() async {
    final url = widget.videoUrl.trim();
    if (!isPlayableUrl(url)) {
      // A stored URL that is not an absolute URI is a BROKEN video, not a
      // missing one — the coach attached something that will never play.
      if (url.isNotEmpty) setState(() => _failed = true);
      return;
    }
    final c = VideoPlayerController.networkUrl(Uri.parse(url));
    _c = c;
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      await c.setLooping(c.value.duration <= _loopCeiling);
      setState(() => _initialized = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  /// Retry after a failure — a fresh controller, because a failed one cannot
  /// be revived. This is the offline-recovery path: the member reconnects and
  /// presses one button.
  Future<void> _retry() async {
    final old = _c;
    _c = null;
    await old?.dispose();
    if (!mounted) return;
    setState(() {
      _failed = false;
      _initialized = false;
    });
    await _open();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A video that keeps playing into a phone call, or into the member's
    // music app, is a bug the member experiences as rudeness.
    if (state != AppLifecycleState.resumed) _c?.pause();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _skipTimer?.cancel();
    _uiRevision.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _c?.dispose();
    super.dispose();
  }

  // ── Interaction ────────────────────────────────────────────────────────

  void _armAutoHide() {
    _hideTimer?.cancel();
    final playing = _c?.value.isPlaying ?? false;
    // Controls persist on a paused frame: it is being studied.
    if (!playing) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      _setUi(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    _setUi(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _armAutoHide();
  }

  void _togglePlay() {
    final c = _c;
    if (c == null || !_initialized) return;
    final ended =
        c.value.position >= c.value.duration &&
        c.value.duration > Duration.zero &&
        !c.value.isLooping;
    _setUi(() {
      if (c.value.isPlaying) {
        c.pause();
        _hideTimer?.cancel();
        _controlsVisible = true;
      } else {
        // Pressing play on a finished clip REPLAYS it — the alternative is a
        // button that visibly does nothing.
        if (ended) c.seekTo(Duration.zero);
        c.play();
        _armAutoHide();
      }
    });
  }

  void _skip(int seconds) {
    final c = _c;
    if (c == null || !_initialized) return;
    final target = skipBy(
      position: c.value.position,
      duration: c.value.duration,
      delta: Duration(seconds: seconds),
    );
    c.seekTo(target);
    // The tick a member feels confirms the gesture landed without them having
    // to look — the whole point of a double tap is not looking.
    HapticFeedback.selectionClick();
    _setUi(() => _skipFlash = seconds < 0 ? '−10s' : '+10s');
    _skipTimer?.cancel();
    _skipTimer = Timer(const Duration(milliseconds: 650), () {
      _setUi(() => _skipFlash = '');
    });
  }

  void _seekToFraction(double f) {
    final c = _c;
    if (c == null || !_initialized) return;
    c.seekTo(seekTargetFor(fraction: f, duration: c.value.duration));
  }

  void _toggleMute() {
    final c = _c;
    if (c == null) return;
    _setUi(() {
      _muted = !_muted;
      c.setVolume(_muted ? 0 : 1);
    });
    _armAutoHide();
  }

  void _cycleSpeed() {
    final c = _c;
    if (c == null) return;
    final i = kPlaybackSpeeds.indexOf(_speed);
    final next = kPlaybackSpeeds[(i + 1) % kPlaybackSpeeds.length];
    _setUi(() => _speed = next);
    c.setPlaybackSpeed(next);
    _armAutoHide();
  }

  Future<void> _enterFullscreen() async {
    final c = _c;
    if (c == null || !_initialized) return;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => _FullscreenStage(
          controller: c,
          title: widget.title,
          uiRevision: _uiRevision,
          onSurface: _buildStage,
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
    // ALWAYS restored, including on a system back gesture out of the route.
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) setState(() {});
  }

  // ── Render ─────────────────────────────────────────────────────────────

  /// The stage before the decoder's per-frame state is consulted. Buffering
  /// is resolved inside the value listener below, so the OUTER tree does not
  /// rebuild on it.
  VideoStage get _baseStage => videoStageFor(
    url: widget.videoUrl,
    initialized: _initialized,
    failed: _failed,
    buffering: false,
  );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = _c;
    final aspect = _initialized && c != null && c.value.aspectRatio > 0
        ? c.value.aspectRatio
        : 16 / 9;

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: aspect,
        child: ColoredBox(
          color: Colors.black,
          child: switch (_baseStage) {
            VideoStage.none => _placeholder(
              p,
              Icons.videocam_off_outlined,
              'No demo video',
              'Your coach hasn\'t attached one for this exercise.',
            ),
            VideoStage.failed => _failureState(p),
            _ => _buildStage(context, fullscreen: false),
          },
        ),
      ),
    );
  }

  /// The video + its controls. Shared verbatim by the inline and fullscreen
  /// surfaces, so the two can never drift apart.
  ///
  /// PERFORMANCE: the controller ticks on EVERY decoded frame. Listening with
  /// `setState` — the obvious implementation — rebuilds this whole subtree,
  /// including the poster's image widget, sixty times a second for the entire
  /// clip. `VideoPlayerController` is itself a `ValueNotifier`, so only the
  /// overlay that actually reads the play head is subscribed; the video
  /// texture, the gesture layer and the poster are built ONCE and left alone.
  Widget _buildStage(BuildContext context, {required bool fullscreen}) {
    final c = _c;
    final p = context.palette;
    if (c == null) return _placeholder(p, Icons.videocam_off_outlined, '', '');

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_initialized)
          Center(
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          )
        else
          _poster(p),

        // Double-tap zones. A single tap anywhere toggles the controls; a
        // double tap on a HALF seeks that direction — the gesture every
        // member already knows from YouTube, with no button to find.
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                onDoubleTap: () => _skip(-10),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                onDoubleTap: () => _skip(10),
              ),
            ),
          ],
        ),

        if (_skipFlash.isNotEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                _skipFlash,
                style: AppText.label(size: 15).copyWith(color: Colors.white),
              ),
            ),
          ),

        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: c,
          builder: (context, value, _) {
            final duration = value.duration;
            final fraction = _dragging
                ? _dragFraction
                : playbackFraction(
                    position: value.position,
                    duration: duration,
                  );
            final shownPosition = _dragging
                ? seekTargetFor(fraction: _dragFraction, duration: duration)
                : value.position;

            return Stack(
              fit: StackFit.expand,
              children: [
                // Buffering is DISTINCT from loading: the video is here, the
                // bytes are late. Saying so stops the member wondering if it
                // is broken.
                if (value.isBuffering)
                  const Center(
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: Colors.white,
                      ),
                    ),
                  ),
                AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: _controls(
                      context,
                      value: value,
                      fraction: fraction,
                      shownPosition: shownPosition,
                      duration: duration,
                      fullscreen: fullscreen,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _controls(
    BuildContext context, {
    required VideoPlayerValue value,
    required double fraction,
    required Duration shownPosition,
    required Duration duration,
    required bool fullscreen,
  }) {
    final playing = value.isPlaying;
    final ended =
        duration > Duration.zero &&
        value.position >= duration &&
        !value.isLooping;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x66000000), Color(0x00000000), Color(0xB3000000)],
          stops: [0, 0.45, 1],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Center(
              child: _roundButton(
                icon: ended
                    ? Icons.replay_rounded
                    : playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                label: ended
                    ? 'Replay'
                    : playing
                    ? 'Pause'
                    : 'Play',
                size: 58,
                iconSize: 34,
                onTap: _togglePlay,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, fullscreen ? 18 : 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SeekBar(
                  fraction: fraction,
                  buffered: _bufferedFraction(value, duration),
                  onDragStart: () {
                    _hideTimer?.cancel();
                    _setUi(() {
                      _dragging = true;
                      _dragFraction = fraction;
                    });
                  },
                  onDragUpdate: (f) => _setUi(() => _dragFraction = f),
                  onDragEnd: (f) {
                    _seekToFraction(f);
                    _setUi(() => _dragging = false);
                    _armAutoHide();
                  },
                  onTapAt: (f) {
                    _seekToFraction(f);
                    _armAutoHide();
                  },
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // FLEXIBLE + ellipsis: at 2.0x text on a 320dp phone the
                    // clock alone wants more room than the control bar has, and
                    // an unconstrained Text in a Row pushes the transport
                    // buttons off the screen rather than shrinking. The buttons
                    // are what the member needs; the timestamp is what can give.
                    Flexible(
                      child: Text(
                        // The clock reflects the FINGER during a drag, so the
                        // member can scrub to a number rather than to a guess.
                        '${formatPlaybackTime(shownPosition)}'
                        '  /  ${formatPlaybackTime(duration)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(
                          size: 11.5,
                        ).copyWith(color: Colors.white),
                      ),
                    ),
                    const Spacer(),
                    _textButton(
                      formatSpeed(_speed),
                      'Playback speed, ${formatSpeed(_speed)}',
                      _cycleSpeed,
                    ),
                    _roundButton(
                      icon: _muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      label: _muted ? 'Unmute' : 'Mute',
                      size: 34,
                      iconSize: 18,
                      onTap: _toggleMute,
                    ),
                    if (widget.allowFullscreen) ...[
                      const SizedBox(width: 4),
                      _roundButton(
                        icon: fullscreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        label: fullscreen ? 'Exit fullscreen' : 'Fullscreen',
                        size: 34,
                        iconSize: 20,
                        onTap: fullscreen
                            ? () => Navigator.of(context).maybePop()
                            : _enterFullscreen,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _bufferedFraction(VideoPlayerValue value, Duration duration) {
    if (duration <= Duration.zero) return 0;
    final ranges = value.buffered;
    if (ranges.isEmpty) return 0;
    return playbackFraction(position: ranges.last.end, duration: duration);
  }

  Widget _roundButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    double size = 40,
    double iconSize = 22,
  }) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.black.withValues(alpha: 0.34),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: iconSize, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _textButton(String text, String label, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            // 34px tall to match the round buttons and clear the 44px target
            // once the surrounding row padding is counted.
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Text(
              text,
              style: AppText.label(size: 12).copyWith(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  /// The library thumbnail under a scrim, with a spinner — the member sees the
  /// exercise immediately instead of a grey rectangle.
  Widget _poster(AppPalette p) => Stack(
    fit: StackFit.expand,
    children: [
      if (widget.posterUrl.isNotEmpty)
        CachedNetworkImage(
          imageUrl: widget.posterUrl,
          fit: BoxFit.cover,
          // The poster is decorative behind a scrim; decoding it at full
          // sensor resolution to blur it is wasted memory.
          memCacheWidth: 900,
          placeholder: (_, _) => ColoredBox(color: p.surfaceAlt),
          errorWidget: (_, _, _) => ColoredBox(color: p.surfaceAlt),
        )
      else
        ColoredBox(color: p.surfaceAlt),
      const DecoratedBox(decoration: BoxDecoration(color: Color(0x59000000))),
      const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Colors.white,
          ),
        ),
      ),
    ],
  );

  Widget _failureState(AppPalette p) => Stack(
    fit: StackFit.expand,
    children: [
      if (widget.posterUrl.isNotEmpty)
        CachedNetworkImage(
          imageUrl: widget.posterUrl,
          fit: BoxFit.cover,
          memCacheWidth: 900,
          placeholder: (_, _) => ColoredBox(color: p.surfaceAlt),
          errorWidget: (_, _, _) => ColoredBox(color: p.surfaceAlt),
        ),
      const DecoratedBox(decoration: BoxDecoration(color: Color(0x99000000))),
      // SCROLLABLE, and it has to be. This sits inside a FIXED 16:9 box, so its
      // height is decided by the video's aspect ratio and not by its own
      // content — at 2.0x text the icon, three lines and the Retry button want
      // more vertical room than 16:9 gives them on any phone. A bare Column
      // simply overflows, and the member meets a striped error box instead of
      // the one control that would fix their problem.
      Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: Colors.white70,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                "Video couldn't load",
                style: AppText.label(size: 13).copyWith(color: Colors.white),
              ),
              const SizedBox(height: 2),
              Text(
                'Check your connection and try again.',
                style: AppText.body(
                  size: 11.5,
                ).copyWith(color: Colors.white.withValues(alpha: 0.75)),
              ),
              const SizedBox(height: 12),
              Semantics(
                button: true,
                label: 'Retry loading the video',
                excludeSemantics: true,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _retry,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.refresh_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Retry',
                            style: AppText.label(
                              size: 12.5,
                            ).copyWith(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  /// "The coach attached nothing" — an honest, calm absence, never dressed as
  /// an error.
  Widget _placeholder(
    AppPalette p,
    IconData icon,
    String title,
    String body,
  ) => ColoredBox(
    color: p.surfaceAlt,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: p.textMuted, size: 34),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              title,
              style: AppText.label(size: 13).copyWith(color: p.textSecondary),
            ),
          ],
          if (body.isNotEmpty) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                body,
                textAlign: TextAlign.center,
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// The landscape surface. It renders the SAME controller and the SAME control
/// stack as the inline player, so entering fullscreen never restarts the clip
/// or loses the member's position.
class _FullscreenStage extends StatelessWidget {
  final VideoPlayerController controller;
  final String title;

  /// Bumped by the inline player on every UI-state change. Without it, a
  /// PAUSED fullscreen video emits no decoder ticks, so tapping to show or
  /// hide the controls would appear to do nothing.
  final ValueNotifier<int> uiRevision;

  final Widget Function(BuildContext, {required bool fullscreen}) onSurface;

  const _FullscreenStage({
    required this.controller,
    required this.title,
    required this.uiRevision,
    required this.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Semantics(
        label: '$title, fullscreen',
        child: Center(
          child: ValueListenableBuilder<int>(
            valueListenable: uiRevision,
            builder: (context, _, _) => AspectRatio(
              aspectRatio: controller.value.aspectRatio > 0
                  ? controller.value.aspectRatio
                  : 16 / 9,
              child: onSurface(context, fullscreen: true),
            ),
          ),
        ),
      ),
    );
  }
}

/// The scrub bar: a red played track, a lighter buffered track, and a thumb
/// large enough to actually grab. Tap anywhere to jump; drag the thumb to
/// scrub. Built by hand rather than with a `Slider` because a Slider's hit
/// target, thumb size and buffered range are all wrong for video.
class _SeekBar extends StatelessWidget {
  final double fraction;
  final double buffered;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<double> onDragEnd;
  final ValueChanged<double> onTapAt;

  const _SeekBar({
    required this.fraction,
    required this.buffered,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onTapAt,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        double at(double dx) => w <= 0 ? 0 : (dx / w).clamp(0.0, 1.0);

        return Semantics(
          slider: true,
          label: 'Video position',
          value: '${(fraction * 100).round()} percent',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => onTapAt(at(d.localPosition.dx)),
            onHorizontalDragStart: (_) => onDragStart(),
            onHorizontalDragUpdate: (d) => onDragUpdate(at(d.localPosition.dx)),
            onHorizontalDragEnd: (_) => onDragEnd(fraction),
            child: SizedBox(
              // 28px of touchable height around a 4px visual track: the bar
              // must be grabbable with a thumb, mid-workout, without looking.
              height: 28,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.26),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: buffered.clamp(0.0, 1.0),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: fraction.clamp(0.0, 1.0),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        // The signature red — the same accent the CTA uses, so
                        // the player reads as part of this product.
                        color: const Color(0xFFE10600),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment((fraction.clamp(0.0, 1.0) * 2) - 1, 0),
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE10600),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
