import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

/// 🎥 A clean and future-proof video controller.
/// Supports Firebase, local, or any URL-based MP4 video.
class VideoServiceController extends GetxController {
  Rx<VideoPlayerController?> videoController = Rx<VideoPlayerController?>(null);
  RxBool isInitialized = false.obs;

  Future<void> initialize(String url) async {
    try {
      videoController.value = VideoPlayerController.network(url);
      await videoController.value!.initialize();
      isInitialized.value = true;
      videoController.value!.play();
    } catch (e) {
      print('❌ Video initialization failed: $e');
      isInitialized.value = false;
    }
  }

  void togglePlayPause() {
    if (videoController.value == null) return;
    if (videoController.value!.value.isPlaying) {
      videoController.value!.pause();
    } else {
      videoController.value!.play();
    }
  }

  @override
  void onClose() {
    videoController.value?.dispose();
    super.onClose();
  }
}
