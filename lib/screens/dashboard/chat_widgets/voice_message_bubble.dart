import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'chat_audio_player.dart';

/// Voice-message playback bubble content: play/pause, waveform-as-progress
/// with tap/drag seek, position/duration label, and a speed chip while
/// active. Palette-agnostic (colors injected) and GetX-free so the file is
/// kept byte-identical between trainersHQ and alphaserena.
class VoiceMessageBubble extends StatelessWidget {
  final String messageId;
  final String url;
  final int durationMs;
  final List<int> waveform; // normalized 0–100, ≤48 samples
  final Color fg; // main foreground (icon/labels)
  final Color fgMuted; // waveform "remaining" bars
  const VoiceMessageBubble({
    super.key,
    required this.messageId,
    required this.url,
    required this.durationMs,
    required this.waveform,
    required this.fg,
    required this.fgMuted,
  });

  @override
  Widget build(BuildContext context) {
    final audio = ChatAudioPlayer.instance;
    return ValueListenableBuilder<String?>(
      valueListenable: audio.playingId,
      builder: (context, playing, child) {
        final active = playing == messageId;
        return SizedBox(
          width: 232,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Play / pause
              StreamBuilder<PlayerState>(
                stream: active ? audio.player.playerStateStream : null,
                builder: (context, snap) {
                  final isPlaying =
                      active && (snap.data?.playing ?? audio.player.playing);
                  return InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => audio.toggle(messageId, url),
                    child: Icon(
                      isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      color: fg,
                      size: 38,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 30,
                      child: active
                          ? StreamBuilder<Duration>(
                              stream: audio.player.positionStream,
                              builder: (context, snap) => _wave(
                                context,
                                progress: _progressOf(
                                    snap.data ?? Duration.zero),
                                seekable: true,
                              ),
                            )
                          : _wave(context, progress: 0, seekable: true),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        StreamBuilder<Duration>(
                          stream:
                              active ? audio.player.positionStream : null,
                          builder: (context, snap) => Text(
                            _mmss(active
                                ? (snap.data ?? Duration.zero)
                                : Duration(milliseconds: durationMs)),
                            style: TextStyle(
                              color: fgMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (active)
                          ValueListenableBuilder<double>(
                            valueListenable: audio.speed,
                            builder: (context, sp, child) => InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: audio.cycleSpeed,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: fgMuted.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${sp == sp.roundToDouble() ? sp.toInt() : sp}x',
                                  style: TextStyle(
                                    color: fg,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double _progressOf(Duration position) {
    if (durationMs <= 0) return 0;
    return (position.inMilliseconds / durationMs).clamp(0.0, 1.0).toDouble();
  }

  Widget _wave(BuildContext context,
      {required double progress, required bool seekable}) {
    final bars = waveform.isNotEmpty
        ? waveform
        : List<int>.filled(32, 35); // legacy/failed-sample fallback
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: seekable
            ? (d) {
                final frac =
                    (d.localPosition.dx / box.maxWidth).clamp(0.0, 1.0);
                final audio = ChatAudioPlayer.instance;
                if (audio.isActive(messageId)) {
                  audio.seek(messageId,
                      Duration(milliseconds: (durationMs * frac).round()));
                } else {
                  audio.toggle(messageId, url);
                }
              }
            : null,
        child: CustomPaint(
          size: Size(box.maxWidth, 30),
          painter: _WavePainter(
            bars: bars,
            progress: progress,
            played: fg,
            remaining: fgMuted,
          ),
        ),
      ),
    );
  }

  String _mmss(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _WavePainter extends CustomPainter {
  final List<int> bars;
  final double progress;
  final Color played;
  final Color remaining;
  _WavePainter({
    required this.bars,
    required this.progress,
    required this.played,
    required this.remaining,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = bars.length;
    final slot = size.width / n;
    final barW = (slot * 0.62).clamp(1.5, 4.0);
    final playedPaint = Paint()
      ..color = played
      ..strokeWidth = barW
      ..strokeCap = StrokeCap.round;
    final remainingPaint = Paint()
      ..color = remaining
      ..strokeWidth = barW
      ..strokeCap = StrokeCap.round;
    final cutoff = progress * n;
    for (var i = 0; i < n; i++) {
      final x = slot * i + slot / 2;
      // Min 12% height so silence still draws a dot-like bar.
      final h = (bars[i].clamp(0, 100) / 100 * size.height)
          .clamp(size.height * 0.12, size.height);
      final y0 = (size.height - h) / 2;
      canvas.drawLine(
        Offset(x, y0),
        Offset(x, y0 + h),
        i < cutoff ? playedPaint : remainingPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress ||
      old.bars != bars ||
      old.played != played ||
      old.remaining != remaining;
}
