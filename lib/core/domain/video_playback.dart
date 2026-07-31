/// THE VIDEO PLAYER'S PURE RULES.
///
/// Formatting a clock, deciding whether a seek is legal, choosing what a
/// failure means — none of that needs a video decoder, and all of it is easy
/// to get subtly wrong (a 61-second video reading "1:1"; a scrub past the end
/// throwing; a 2-second exercise clip showing 1× speed options nobody can
/// use). It lives here so it is unit-tested without a platform channel.
library;

/// mm:ss, or h:mm:ss once an hour is involved. Never "1:1" — a clock that
/// drops its leading zero is unreadable at a glance mid-set.
String formatPlaybackTime(Duration d) {
  // Negative positions are a platform artefact on some devices during seek;
  // clamping is honest (the video has not started) and avoids "-0:01".
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
  return h > 0
      ? '$h:$mm:${s.toString().padLeft(2, '0')}'
      : '$mm:${s.toString().padLeft(2, '0')}';
}

/// Where a scrub actually lands. Always inside `[0, duration]`, so a fast
/// drag off either end of the bar cannot ask the decoder for a position that
/// does not exist.
Duration seekTargetFor({
  required double fraction,
  required Duration duration,
}) {
  if (duration <= Duration.zero) return Duration.zero;
  final f = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
  final ms = (duration.inMilliseconds * f).round();
  return Duration(milliseconds: ms);
}

/// Progress along the bar, 0..1. Zero-length or not-yet-known media reports
/// 0 rather than NaN — a NaN reaches the render tree as a crash.
double playbackFraction({
  required Duration position,
  required Duration duration,
}) {
  if (duration <= Duration.zero) return 0;
  final f = position.inMilliseconds / duration.inMilliseconds;
  if (f.isNaN) return 0;
  return f.clamp(0.0, 1.0);
}

/// A double-tap skip, clamped at both ends. Skipping back from 3 seconds in
/// lands at zero, not at a negative position; skipping forward near the end
/// lands ON the end rather than past it.
Duration skipBy({
  required Duration position,
  required Duration duration,
  required Duration delta,
}) {
  final target = position + delta;
  if (target < Duration.zero) return Duration.zero;
  if (duration > Duration.zero && target > duration) return duration;
  return target;
}

/// The speeds offered. Deliberately short: a demo clip is watched to learn a
/// movement, so half speed (see the form) and a mild speed-up (skip the
/// set-up) are the only two that earn their place beside normal.
const List<double> kPlaybackSpeeds = [0.5, 0.75, 1.0, 1.5, 2.0];

/// '1×' not '1.0×'; '0.5×' keeps its decimal because it needs it.
String formatSpeed(double s) {
  final whole = s == s.roundToDouble();
  return whole ? '${s.toInt()}×' : '$s×';
}

/// What the player is doing, as one value the UI switches on.
enum VideoStage {
  /// No video attached at all — the coach never uploaded one. NOT an error.
  none,

  /// Initialising.
  loading,

  /// Playing or paused, with a known duration.
  ready,

  /// Ready, but the decoder is waiting on bytes mid-playback.
  buffering,

  /// A video exists and could not be loaded (bad URL, offline, dead file).
  failed,
}

/// The one place "no video" and "video is broken" are told apart, because a
/// member deserves to know which. Silence about a failure reads as the coach
/// not bothering; a spinner that never resolves reads as a promise.
VideoStage videoStageFor({
  required String url,
  required bool initialized,
  required bool failed,
  required bool buffering,
}) {
  if (url.trim().isEmpty) return VideoStage.none;
  if (failed) return VideoStage.failed;
  if (!initialized) return VideoStage.loading;
  return buffering ? VideoStage.buffering : VideoStage.ready;
}

/// A stored URL that cannot be parsed into an absolute URI is a BROKEN video,
/// not a missing one — the coach attached something and it will never play.
bool isPlayableUrl(String url) {
  final t = url.trim();
  if (t.isEmpty) return false;
  final uri = Uri.tryParse(t);
  return uri != null && uri.hasScheme && uri.hasAuthority;
}
