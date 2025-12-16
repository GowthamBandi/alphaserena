// lib/screens/workout/workout_player_page.dart

import 'dart:ui';
import 'package:alphaserena/controllers/theme_controller.dart';
import 'package:alphaserena/controllers/workout_controller.dart';
import 'package:alphaserena/models/workout_model.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

class WorkoutPlayerPage extends StatelessWidget {
  WorkoutPlayerPage({super.key});

  final WorkoutController controller = Get.put(WorkoutController());
  final ThemeController theme = Get.find<ThemeController>();

  @override
  Widget build(BuildContext context) {
    final accent = Colors.redAccent.shade700;
    final height = MediaQuery.of(context).size.height;

    return Obx(() {
      final isDark = theme.isDarkMode.value;

      return Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.grey.shade100,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
          title: Text(
            "Workout Session",
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.w600,
              fontSize: 18,
            ),
          ),
        ),
        body: Obx(() {
          final workout = controller.workout.value;
          if (workout == null) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.redAccent),
            );
          }

          return Stack(
            children: [
              Column(
                children: [
                  _videoSection(height, accent, isDark),
                  Expanded(child: _detailsSection(workout, accent, isDark)),
                ],
              ),
              if (controller.isResting.value) _restOverlay(accent, isDark),
            ],
          );
        }),
      );
    });
  }

  // ---------------------------------------------------------------------------
  /// 🎥 VIDEO SECTION
  Widget _videoSection(double height, Color accent, bool isDark) {
    return SizedBox(
      height: height * 0.48,
      width: double.infinity,
      child: Obx(() {
        final service = controller.videoService;

        if (!service.isInitialized.value) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.redAccent),
          );
        }

        final videoCtrl = service.videoController.value!;

        return Stack(
          children: [
            Positioned.fill(child: VideoPlayer(videoCtrl)),

            // Gradient overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(.75),
                      Colors.transparent,
                      Colors.black.withOpacity(.9),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

            // Play / Pause
            Center(
              child: GestureDetector(
                onTap: service.togglePlayPause,
                child: AnimatedOpacity(
                  opacity: videoCtrl.value.isPlaying ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.55),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 64,
                      color: accent,
                    ),
                  ),
                ),
              ),
            ),

            // Progress
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                children: [
                  VideoProgressIndicator(
                    videoCtrl,
                    allowScrubbing: true,
                    padding: EdgeInsets.zero,
                    colors: const VideoProgressColors(
                      playedColor: Colors.redAccent,
                      bufferedColor: Colors.white30,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _time(videoCtrl.value.position, isDark),
                      _time(videoCtrl.value.duration, isDark),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _time(Duration d, bool isDark) {
    String two(int n) => n.toString().padLeft(2, '0');
    return Text(
      "${two(d.inMinutes)}:${two(d.inSeconds.remainder(60))}",
      style: GoogleFonts.poppins(
        color: isDark ? Colors.white70 : Colors.black54,
        fontSize: 12,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  /// 📋 DETAILS SECTION
  Widget _detailsSection(WorkoutModel workout, Color accent, bool isDark) {
    final currentIndex = controller.currentSet.value;
    final current = workout.sets[currentIndex];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            workout.title,
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 20),

          // Set progress
          Row(
            children: List.generate(
              workout.sets.length,
              (i) => Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  height: 5,
                  decoration: BoxDecoration(
                    color: i < currentIndex
                        ? accent
                        : i == currentIndex
                        ? (isDark ? Colors.white : Colors.black)
                        : (isDark ? Colors.white24 : Colors.black12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 26),

          // Glass card
          _glassCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Set ${current.set}",
                  style: GoogleFonts.poppins(
                    color: accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                _stat("Reps", current.reps.toString(), isDark),
                _stat(
                  "Weight",
                  "${current.weight % 1 == 0 ? current.weight.toInt() : current.weight} kg",
                  isDark,
                ),
                const SizedBox(height: 24),
                Center(
                  child: ElevatedButton(
                    onPressed: controller.completeSet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 64,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      currentIndex == workout.sets.length - 1
                          ? "Finish Workout"
                          : "Finish Set",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          Center(
            child: Text(
              "Set ${currentIndex + 1} of ${workout.sets.length}",
              style: GoogleFonts.poppins(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            height: 6,
            width: 6,
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            "$label: $value",
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  /// 🔴 REST OVERLAY
  Widget _restOverlay(Color accent, bool isDark) {
    return Positioned.fill(
      child: Container(
        color: (isDark ? Colors.black : Colors.white).withOpacity(.95),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.timer_rounded,
                color: Colors.redAccent,
                size: 90,
              ),
              const SizedBox(height: 20),
              Obx(
                () => Text(
                  "${controller.restTime.value}s",
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 46,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Rest before next set",
                style: GoogleFonts.poppins(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: controller.skipRest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 42,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  "Skip Rest",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _glassCard({required Widget child, required bool isDark}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(.06)
                : Colors.white.withOpacity(.7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(.08)
                  : Colors.black.withOpacity(.06),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
