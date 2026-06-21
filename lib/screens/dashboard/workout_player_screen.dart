import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/primary_button.dart';

class WorkoutPlayerScreen extends StatefulWidget {
  final Map<String, dynamic> exercise;
  const WorkoutPlayerScreen({super.key, required this.exercise});

  @override
  State<WorkoutPlayerScreen> createState() => _WorkoutPlayerScreenState();
}

class _WorkoutPlayerScreenState extends State<WorkoutPlayerScreen> {
  VideoPlayerController? _video;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final url = (widget.exercise['videoUrl'] ?? '').toString();
    if (url.isNotEmpty) {
      _video = VideoPlayerController.networkUrl(Uri.parse(url));
      _video!.initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _video!
          ..setLooping(true)
          ..play();
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  void _toggle() {
    final v = _video;
    if (v == null) return;
    setState(() => v.value.isPlaying ? v.pause() : v.play());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ex = widget.exercise;
    final sets = (ex['sets'] ?? 0).toString();
    final reps = (ex['reps'] ?? 0).toString();
    final instructions = (ex['instructions'] ?? '').toString();
    final muscle = (ex['muscleGroup'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(ex['name']?.toString() ?? 'Exercise',
            style: AppText.title(size: 22).copyWith(color: p.textPrimary)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            // Video / placeholder
            ClipRRect(
              borderRadius: AppRadii.lgR,
              child: AspectRatio(
                aspectRatio: _ready ? _video!.value.aspectRatio : 16 / 9,
                child: _video == null
                    ? Container(
                        color: p.surfaceAlt,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.videocam_off_outlined,
                                  color: p.textMuted, size: 36),
                              const SizedBox(height: 8),
                              Text('No demo video',
                                  style: AppText.body(size: 13)
                                      .copyWith(color: p.textMuted)),
                            ],
                          ),
                        ),
                      )
                    : _ready
                        ? GestureDetector(
                            onTap: _toggle,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                VideoPlayer(_video!),
                                if (!_video!.value.isPlaying)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.3),
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    child: const Icon(Icons.play_arrow,
                                        color: Colors.white, size: 44),
                                  ),
                              ],
                            ),
                          )
                        : Container(
                            color: p.surfaceAlt,
                            child: Center(
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: p.accent)),
                          ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _stat(p, 'SETS', sets),
                const SizedBox(width: 12),
                _stat(p, 'REPS', reps),
                if (muscle.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  _stat(p, 'TARGET', muscle),
                ],
              ],
            ),
            if (instructions.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('HOW TO',
                  style: AppText.label(size: 12)
                      .copyWith(color: p.textMuted, letterSpacing: 3)),
              const SizedBox(height: 8),
              Text(instructions,
                  style: AppText.feature(size: 15)
                      .copyWith(color: p.textSecondary, height: 1.5)),
            ],
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Done',
              icon: Icons.check,
              onPressed: () => Get.back(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(AppPalette p, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: AppRadii.cardR,
          border: Border.all(color: p.border),
        ),
        child: Column(
          children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.title(size: 22).copyWith(color: p.accent)),
            const SizedBox(height: 2),
            Text(label,
                style: AppText.body(size: 11)
                    .copyWith(color: p.textMuted, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}
