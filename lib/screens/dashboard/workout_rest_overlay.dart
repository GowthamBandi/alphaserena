import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// THE REST EXPERIENCE — the minute between sets, coached.
///
/// Replaces the tick-counting modal that a backgrounded phone silently
/// paused. Three rules:
///
///  1. **NO FAKE TIMERS.** The countdown is derived from a wall-clock
///     deadline ([_endsAt]), not from how many ticks the widget received.
///     Lock the phone, take a call, switch apps — the remaining time on
///     return is the time that actually remains.
///  2. **The member is in control.** Pause, +30s, skip — a coach adds rest
///     when the set was brutal; the app must not be stricter than the coach.
///  3. **It must work in a pocket.** Haptics fire at the last three seconds
///     and on completion, so the phone can be away from the eyes. (Sound is
///     deliberately not added here: it needs an audio dependency and a
///     mute/volume contract — the hook is [_pulse], one call site.)
class RestOverlay extends StatefulWidget {
  final int seconds;
  final int nextSetNumber;
  final Color accent;

  /// One short line of coaching for the pause — the coach's note when they
  /// wrote one, else a rotating, honest reminder.
  final String reminder;

  const RestOverlay({
    super.key,
    required this.seconds,
    required this.nextSetNumber,
    required this.accent,
    this.reminder = '',
  });

  @override
  State<RestOverlay> createState() => _RestOverlayState();
}

class _RestOverlayState extends State<RestOverlay>
    with WidgetsBindingObserver {
  /// The wall-clock deadline. Null while paused.
  DateTime? _endsAt;

  /// Remaining seconds while paused (the frozen value).
  late int _frozen = widget.seconds;

  /// Total, which grows with +30s so the ring stays proportional.
  late int _total = widget.seconds;

  Timer? _ticker;
  int _lastPulseAt = -1;

  bool get _paused => _endsAt == null;

  int get _remaining {
    if (_paused) return _frozen;
    final left = _endsAt!.difference(DateTime.now()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _endsAt = DateTime.now().add(Duration(seconds: widget.seconds));
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    // 200ms so a return-from-background repaints promptly; the VALUE always
    // comes from the deadline, never from the tick count.
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final r = _remaining;
      if (!_paused && r <= 3 && r > 0 && r != _lastPulseAt) {
        _lastPulseAt = r;
        _pulse(light: true);
      }
      if (!_paused && r <= 0) {
        _finish(auto: true);
        return;
      }
      setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from background: repaint immediately against the real clock.
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  void _pulse({bool light = false}) {
    if (light) {
      HapticFeedback.selectionClick();
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  void _togglePause() {
    setState(() {
      if (_paused) {
        _endsAt = DateTime.now().add(Duration(seconds: _frozen));
      } else {
        _frozen = _remaining;
        _endsAt = null;
      }
    });
  }

  void _addThirty() {
    setState(() {
      _total += 30;
      if (_paused) {
        _frozen += 30;
      } else {
        _endsAt = _endsAt!.add(const Duration(seconds: 30));
      }
      _lastPulseAt = -1;
    });
  }

  void _finish({bool auto = false}) {
    _ticker?.cancel();
    if (auto) _pulse();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;
    final total = _total <= 0 ? 1 : _total;
    final frac = (remaining / total).clamp(0.0, 1.0);
    final mins = remaining ~/ 60;
    final secs = remaining % 60;
    final label = mins > 0
        ? '$mins:${secs.toString().padLeft(2, '0')}'
        : '$secs';

    // The ring yields on small screens and at large text scales — this is
    // used one-handed, on every phone size, sometimes at 200% font.
    final shortest = MediaQuery.of(context).size.shortestSide;
    final ring = shortest < 360 ? 150.0 : 210.0;
    final numberSize = shortest < 360 ? 44.0 : 60.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Rest',
                    style: GoogleFonts.poppins(
                        color: Colors.white70, fontSize: 15)),
                const SizedBox(height: 2),
                Text('Next: Set ${widget.nextSetNumber}',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 24),
                SizedBox(
                  width: ring,
                  height: ring,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: ring,
                        height: ring,
                        child: CircularProgressIndicator(
                          value: frac,
                          strokeWidth: 9,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.15),
                          valueColor:
                              AlwaysStoppedAnimation(widget.accent),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(label,
                                style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: numberSize,
                                    fontWeight: FontWeight.w800,
                                    height: 1,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ])),
                          ),
                          Text(_paused ? 'paused' : 'seconds',
                              style: GoogleFonts.poppins(
                                  color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (widget.reminder.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Text(
                      widget.reminder,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          color: Colors.white70, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                // Wrap, not Row: at 1.6x text scale on a 320pt phone three
                // labelled buttons do not fit one line, and a clipped
                // "Skip" is a trap when someone is mid-workout.
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _action(
                      icon: _paused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      label: _paused ? 'Resume' : 'Pause',
                      onTap: _togglePause,
                    ),
                    _action(
                      icon: Icons.add_rounded,
                      label: '30s',
                      onTap: _addThirty,
                    ),
                    _action(
                      icon: Icons.skip_next_rounded,
                      label: 'Skip',
                      onTap: () => _finish(),
                      primary: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor:
              primary ? widget.accent.withValues(alpha: 0.9) : null,
          side: primary
              ? null
              : const BorderSide(color: Colors.white24),
          // Comfortable 44pt-plus targets — this is used with sweaty hands.
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label,
            style: GoogleFonts.poppins(
                fontSize: 13.5, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Rotating rest reminders — generic coaching truths, never presented as the
/// coach's words. The coach's own note takes precedence at the call site.
const List<String> kRestReminders = [
  'Breathe. Let your heart rate settle before the next set.',
  'Sip some water — hydration holds your performance up.',
  'Reset your setup: feet, grip, brace.',
  'Shake it out. Quality beats rushing.',
];

String restReminderFor(int setNumber) =>
    kRestReminders[setNumber.abs() % kRestReminders.length];
