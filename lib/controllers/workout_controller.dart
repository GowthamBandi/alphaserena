import 'dart:async';
import 'package:alphaserena/controllers/video_service_controller.dart';
import 'package:alphaserena/models/workout_model.dart';
import 'package:get/get.dart';

class WorkoutController extends GetxController {
  final Rx<WorkoutModel?> workout = Rx<WorkoutModel?>(null);
  final RxInt currentSet = 0.obs;
  final RxBool isResting = false.obs;
  final RxInt restTime = 30.obs;

  final VideoServiceController videoService = Get.put(VideoServiceController());

  Timer? _restTimer;

  @override
  void onInit() {
    super.onInit();
    _loadWorkout();
  }

  @override
  void onClose() {
    _restTimer?.cancel();
    super.onClose();
  }

  Future<void> _loadWorkout() async {
    // Dummy workout data
    final Map<String, dynamic> dummyData = {
      "title": "Push-up Tutorial",
      "description": "Learn perfect form and posture for push-ups.",
      "videoUrl":
          "https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4",
      "sets": [
        {"set": 1, "reps": 10, "weight": 0},
        {"set": 2, "reps": 12, "weight": 0},
        {"set": 3, "reps": 15, "weight": 0},
        {"set": 2, "reps": 12, "weight": 0},
        {"set": 3, "reps": 15, "weight": 0},
      ],
    };

    workout.value = WorkoutModel.fromJson(dummyData);
    await videoService.initialize(dummyData["videoUrl"] as String);
  }

  /// Called when user finishes a set
  void completeSet() {
    final totalSets = workout.value?.sets.length ?? 0;

    if (currentSet.value < totalSets - 1) {
      startRestTimer();
    } else {
      Get.snackbar("🎉 Workout Complete", "You’ve finished all sets!");
    }
  }

  /// Starts the rest timer overlay
  void startRestTimer() {
    _restTimer?.cancel();
    isResting.value = true;
    restTime.value = 30;

    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (restTime.value <= 1) {
        timer.cancel();
        finishRest();
      } else {
        restTime.value--;
      }
    });
  }

  /// Skips the rest immediately
  void skipRest() {
    _restTimer?.cancel();
    finishRest();
  }

  /// Ends the rest and moves to next set
  void finishRest() {
    isResting.value = false;
    currentSet.value++;
  }
}
