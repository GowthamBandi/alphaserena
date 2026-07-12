import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// One shared audio player for the whole chat (WhatsApp behavior: starting a
/// new voice message stops the previous one). GetX-free on purpose — this
/// file is kept byte-identical between trainersHQ and alphaserena.
class ChatAudioPlayer {
  ChatAudioPlayer._() {
    // When a message finishes, release the "playing" slot so its bubble
    // resets to the play state.
    _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) {
        _player.stop();
        playingId.value = null;
      }
    });
  }

  static final ChatAudioPlayer instance = ChatAudioPlayer._();

  final AudioPlayer _player = AudioPlayer();

  /// Message id currently loaded into the player (null = idle).
  final ValueNotifier<String?> playingId = ValueNotifier<String?>(null);

  /// Sticky across messages — a coach who listens at 2x stays at 2x.
  final ValueNotifier<double> speed = ValueNotifier<double>(1.0);

  AudioPlayer get player => _player;

  bool isActive(String id) => playingId.value == id;

  /// Play/pause [id]. A different id stops the current one and starts fresh.
  Future<void> toggle(String id, String url) async {
    if (playingId.value == id) {
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
      return;
    }
    playingId.value = id;
    try {
      await _player.stop();
      await _player.setUrl(url);
      await _player.setSpeed(speed.value);
      await _player.play();
    } catch (_) {
      if (playingId.value == id) playingId.value = null;
    }
  }

  Future<void> seek(String id, Duration position) async {
    if (playingId.value != id) return;
    try {
      await _player.seek(position);
    } catch (_) {
      // A seek racing setUrl (tap-seek while the source is still loading)
      // must never surface — playback simply continues from load.
    }
  }

  /// 1x → 1.5x → 2x → 1x.
  Future<void> cycleSpeed() async {
    final next = speed.value >= 2.0 ? 1.0 : (speed.value >= 1.5 ? 2.0 : 1.5);
    speed.value = next;
    await _player.setSpeed(next);
  }

  Future<void> stop() async {
    await _player.stop();
    playingId.value = null;
  }
}
