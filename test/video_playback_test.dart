import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/video_playback.dart';

/// THE PLAYER'S PURE RULES — the parts that are easy to get subtly wrong and
/// impossible to notice until a member is mid-set staring at "1:1".
void main() {
  group('formatPlaybackTime', () {
    test('pads seconds so the clock is readable at a glance', () {
      expect(formatPlaybackTime(const Duration(seconds: 61)), '1:01');
      expect(formatPlaybackTime(const Duration(seconds: 9)), '0:09');
      expect(formatPlaybackTime(Duration.zero), '0:00');
      expect(formatPlaybackTime(const Duration(minutes: 12, seconds: 5)),
          '12:05');
    });

    test('grows an hours field only when there are hours', () {
      expect(formatPlaybackTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
      expect(formatPlaybackTime(const Duration(minutes: 59, seconds: 59)),
          '59:59');
    });

    test('a negative position (a seek artefact) reads as zero, not "-0:01"',
        () {
      expect(formatPlaybackTime(const Duration(seconds: -3)), '0:00');
    });
  });

  group('seekTargetFor — a scrub can never leave the media', () {
    const d = Duration(seconds: 100);

    test('lands proportionally', () {
      expect(seekTargetFor(fraction: 0.25, duration: d),
          const Duration(seconds: 25));
    });

    test('a drag off either end clamps instead of throwing', () {
      expect(seekTargetFor(fraction: -3, duration: d), Duration.zero);
      expect(seekTargetFor(fraction: 9.4, duration: d), d);
    });

    test('unknown duration seeks nowhere rather than crashing', () {
      expect(seekTargetFor(fraction: 0.5, duration: Duration.zero),
          Duration.zero);
    });

    test('NaN is absorbed', () {
      expect(seekTargetFor(fraction: double.nan, duration: d), Duration.zero);
    });
  });

  group('playbackFraction — never NaN, because NaN reaches the render tree', () {
    test('is the honest ratio', () {
      expect(
        playbackFraction(
          position: const Duration(seconds: 30),
          duration: const Duration(seconds: 120),
        ),
        0.25,
      );
    });

    test('a zero-length video reports 0, not NaN', () {
      expect(
        playbackFraction(position: Duration.zero, duration: Duration.zero),
        0,
      );
    });

    test('a position past the end clamps to a full bar', () {
      expect(
        playbackFraction(
          position: const Duration(seconds: 200),
          duration: const Duration(seconds: 120),
        ),
        1.0,
      );
    });
  });

  group('skipBy — double-tap seek', () {
    const d = Duration(seconds: 60);

    test('skips forward and back', () {
      expect(
        skipBy(
          position: const Duration(seconds: 20),
          duration: d,
          delta: const Duration(seconds: 10),
        ),
        const Duration(seconds: 30),
      );
    });

    test('skipping back near the start lands at zero, never negative', () {
      expect(
        skipBy(
          position: const Duration(seconds: 3),
          duration: d,
          delta: const Duration(seconds: -10),
        ),
        Duration.zero,
      );
    });

    test('skipping forward near the end lands ON the end', () {
      expect(
        skipBy(
          position: const Duration(seconds: 57),
          duration: d,
          delta: const Duration(seconds: 10),
        ),
        d,
      );
    });
  });

  group('videoStageFor — "no video" and "broken video" are different truths', () {
    test('no url at all is NOT an error', () {
      expect(
        videoStageFor(
            url: '', initialized: false, failed: false, buffering: false),
        VideoStage.none,
      );
      expect(
        videoStageFor(
            url: '   ', initialized: false, failed: false, buffering: false),
        VideoStage.none,
      );
    });

    test('a url that failed says so — it never spins forever', () {
      expect(
        videoStageFor(
            url: 'https://x/v.mp4',
            initialized: false,
            failed: true,
            buffering: false),
        VideoStage.failed,
      );
    });

    test('failure outranks initialisation', () {
      expect(
        videoStageFor(
            url: 'https://x/v.mp4',
            initialized: true,
            failed: true,
            buffering: false),
        VideoStage.failed,
      );
    });

    test('uninitialised is loading, and buffering is distinct from loading', () {
      expect(
        videoStageFor(
            url: 'https://x/v.mp4',
            initialized: false,
            failed: false,
            buffering: false),
        VideoStage.loading,
      );
      expect(
        videoStageFor(
            url: 'https://x/v.mp4',
            initialized: true,
            failed: false,
            buffering: true),
        VideoStage.buffering,
      );
      expect(
        videoStageFor(
            url: 'https://x/v.mp4',
            initialized: true,
            failed: false,
            buffering: false),
        VideoStage.ready,
      );
    });
  });

  group('isPlayableUrl', () {
    test('accepts real absolute media urls', () {
      expect(isPlayableUrl('https://cdn.example.com/a.mp4'), isTrue);
    });

    test('rejects junk the coach app may have stored', () {
      expect(isPlayableUrl(''), isFalse);
      expect(isPlayableUrl('   '), isFalse);
      expect(isPlayableUrl('not a url'), isFalse);
      expect(isPlayableUrl('/local/path.mp4'), isFalse);
    });
  });

  group('speed options', () {
    test('offers a short, purposeful set centred on normal', () {
      expect(kPlaybackSpeeds, contains(1.0));
      expect(kPlaybackSpeeds.first, lessThan(1.0));
      expect(kPlaybackSpeeds.length, lessThanOrEqualTo(5));
    });

    test('normal speed reads 1×, not 1.0×', () {
      expect(formatSpeed(1.0), '1×');
      expect(formatSpeed(2.0), '2×');
      expect(formatSpeed(0.5), '0.5×');
      expect(formatSpeed(0.75), '0.75×');
    });
  });
}
