import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../../controllers/training_controller.dart';
import '../../core/services/workout_log_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/gradient_button.dart';

// ── In-session state ─────────────────────────────────────────────────
class _SetState {
  final String pReps; // prescribed
  final String pWeight;
  final String pRest;
  final TextEditingController reps = TextEditingController();
  final TextEditingController weight = TextEditingController();
  bool completed = false;
  _SetState(this.pReps, this.pWeight, this.pRest);

  void dispose() {
    reps.dispose();
    weight.dispose();
  }
}

class _ExState {
  final String name;
  final String exerciseId;
  final String videoUrl;
  final String instructions;
  final String muscle;
  final List<_SetState> sets;
  int activeSet = 0;
  _ExState({
    required this.name,
    required this.exerciseId,
    required this.videoUrl,
    required this.instructions,
    required this.muscle,
    required this.sets,
  });

  int get completedCount => sets.where((s) => s.completed).length;
  bool get done => sets.isNotEmpty && sets.every((s) => s.completed);
}

/// The guided "Start Full Workout" session — one exercise at a time, per-set
/// logging (Reps Done + Weight Used → Complete Set → rest timer → next set),
/// saving actuals to `client_workout_sessions` per exercise.
class WorkoutSessionScreen extends StatefulWidget {
  const WorkoutSessionScreen({super.key});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  final TrainingController _training = Get.isRegistered<TrainingController>()
      ? Get.find<TrainingController>()
      : Get.put(TrainingController());
  final WorkoutLogService _log = WorkoutLogService();

  late final List<_ExState> _exercises;
  late final String _planName;
  final DateTime _sessionDate = DateTime.now();
  late final String _sessionId;
  bool _savedOnce = false;
  bool _saveError = false;

  int _current = 0;

  VideoPlayerController? _video;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    _sessionId = _log.newSessionId();
    _planName = _training.workout.value?['name']?.toString() ?? 'Workout';
    _exercises = _training.workoutItems.map(_buildExercise).toList();
    if (_exercises.isNotEmpty) _initVideo(_exercises[0].videoUrl);
  }

  _ExState _buildExercise(Map<String, dynamic> ex) {
    final rows = (ex['setRows'] as List?) ?? const [];
    final sets = <_SetState>[];
    if (rows.isNotEmpty) {
      for (final r in rows) {
        final m = Map<String, dynamic>.from(r as Map);
        sets.add(_SetState((m['reps'] ?? '').toString(),
            (m['weight'] ?? '').toString(), (m['rest'] ?? '').toString()));
      }
    } else {
      // Legacy/flat plan: synthesize N identical sets from the summary.
      final count = (ex['sets'] is num)
          ? (ex['sets'] as num).toInt()
          : int.tryParse('${ex['sets']}') ?? 0;
      final reps = (ex['reps'] ?? '').toString();
      final weight = (ex['weight'] ?? '').toString();
      final n = count > 0 ? count : (reps.isNotEmpty ? 1 : 0);
      for (var i = 0; i < n; i++) {
        sets.add(_SetState(reps, weight, ''));
      }
    }
    return _ExState(
      name: ex['name']?.toString() ?? 'Exercise',
      exerciseId: (ex['exerciseId'] ?? '').toString(),
      videoUrl: (ex['videoUrl'] ?? '').toString(),
      instructions: (ex['instructions'] ?? '').toString(),
      muscle: (ex['muscleGroup'] ?? '').toString(),
      sets: sets,
    );
  }

  // ── Video ───────────────────────────────────────────────────────────
  void _initVideo(String url) {
    _video?.dispose();
    _video = null;
    _videoReady = false;
    if (url.isEmpty) {
      setState(() {});
      return;
    }
    final v = VideoPlayerController.networkUrl(Uri.parse(url));
    _video = v;
    v.initialize().then((_) {
      if (!mounted || _video != v) return;
      setState(() => _videoReady = true);
      v
        ..setLooping(true)
        ..play();
    }).catchError((_) {});
  }

  void _toggleVideo() {
    final v = _video;
    if (v == null || !_videoReady) return;
    setState(() => v.value.isPlaying ? v.pause() : v.play());
  }

  @override
  void dispose() {
    _video?.dispose();
    for (final ex in _exercises) {
      for (final s in ex.sets) {
        s.dispose();
      }
    }
    super.dispose();
  }

  // ── Navigation between exercises ─────────────────────────────────────
  void _goTo(int index) {
    if (index < 0 || index >= _exercises.length) return;
    setState(() => _current = index);
    _initVideo(_exercises[index].videoUrl);
  }

  int _parseRest(String s) {
    final m = RegExp(r'\d+').firstMatch(s);
    return m != null ? int.parse(m.group(0)!) : 0;
  }

  // ── Complete a set → save → rest timer → next set ────────────────────
  Future<void> _completeSet(_ExState ex, int setIndex) async {
    setState(() => ex.sets[setIndex].completed = true);
    await _saveProgress();

    final hasNext = setIndex + 1 < ex.sets.length;
    if (hasNext) {
      final rest = _parseRest(ex.sets[setIndex].pRest);
      if (rest > 0) {
        await _showRestTimer(rest, setIndex + 2); // human set number
      }
      if (!mounted) return;
      setState(() => ex.activeSet = setIndex + 1);
    } else {
      setState(() => ex.activeSet = ex.sets.length); // exercise finished
    }
  }

  Future<void> _showRestTimer(int seconds, int nextSetNumber) {
    final p = context.palette;
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'rest',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => _RestTimerDialog(
        seconds: seconds,
        nextSetNumber: nextSetNumber,
        accent: p.accent,
      ),
    );
  }

  Future<void> _saveProgress() async {
    final entries = _exercises
        .map((ex) => <String, dynamic>{
              'exerciseName': ex.name,
              if (ex.exerciseId.isNotEmpty) 'exerciseId': ex.exerciseId,
              'sets': List.generate(ex.sets.length, (i) {
                final s = ex.sets[i];
                return {
                  'setNumber': i + 1,
                  'prescribedReps': s.pReps,
                  'prescribedWeight': s.pWeight,
                  'prescribedRest': s.pRest,
                  'actualReps': s.reps.text.trim(),
                  'actualWeight': s.weight.text.trim(),
                  'completed': s.completed,
                };
              }),
            })
        .toList();
    final ok = await _log.saveSession(
      sessionId: _sessionId,
      planName: _planName,
      date: _sessionDate,
      entries: entries,
      markCreated: !_savedOnce,
    );
    if (!mounted) return;
    if (ok) {
      _savedOnce = true;
      if (_saveError) setState(() => _saveError = false);
    } else {
      setState(() => _saveError = true);
    }
  }

  bool get _allDone => _exercises.every((e) => e.done);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (_exercises.isEmpty) return _noWorkout(p);

    final ex = _exercises[_current];
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        iconTheme: IconThemeData(color: p.textPrimary),
        title: Text('Exercise ${_current + 1} of ${_exercises.length}',
            style: AppText.cardTitle(size: 16).copyWith(color: p.textPrimary)),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                children: [
                  _videoHero(p, ex),
                  const SizedBox(height: 14),
                  Text(ex.name,
                      style:
                          AppText.title(size: 22).copyWith(color: p.textPrimary)),
                  if (ex.muscle.isNotEmpty)
                    Text(ex.muscle,
                        style: AppText.body(size: 12.5)
                            .copyWith(color: p.textMuted)),
                  const SizedBox(height: 14),
                  _progressStrip(p, ex),
                  const SizedBox(height: 16),
                  if (ex.sets.isEmpty)
                    _noSetsNote(p)
                  else ...[
                    _prescriptionCard(p, ex),
                    const SizedBox(height: 16),
                    _performanceSection(p, ex),
                  ],
                  if (_saveError) ...[
                    const SizedBox(height: 14),
                    _saveErrorBanner(p),
                  ],
                ],
              ),
            ),
            _bottomBar(p),
          ],
        ),
      ),
    );
  }

  // ── Video hero ───────────────────────────────────────────────────────
  Widget _videoHero(AppPalette p, _ExState ex) {
    return ClipRRect(
      borderRadius: AppRadii.lgR,
      child: AspectRatio(
        aspectRatio: _videoReady ? _video!.value.aspectRatio : 16 / 9,
        child: _video == null
            ? Container(
                color: p.surfaceAlt,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam_off_outlined,
                          color: p.textMuted, size: 34),
                      const SizedBox(height: 8),
                      Text('No demo video',
                          style: AppText.body(size: 12.5)
                              .copyWith(color: p.textMuted)),
                    ],
                  ),
                ),
              )
            : _videoReady
                ? GestureDetector(
                    onTap: _toggleVideo,
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
                                color: Colors.white, size: 42),
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
    );
  }

  // ── Progress strip ───────────────────────────────────────────────────
  Widget _progressStrip(AppPalette p, _ExState ex) {
    return Row(
      children: [
        for (var i = 0; i < ex.sets.length; i++) ...[
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ex.sets[i].completed ? p.accent : Colors.transparent,
              border: Border.all(
                color: ex.sets[i].completed
                    ? p.accent
                    : (i == ex.activeSet ? p.accent : p.border),
                width: 1.6,
              ),
            ),
          ),
          if (i < ex.sets.length - 1) const SizedBox(width: 6),
        ],
        const Spacer(),
        Text('${ex.completedCount} / ${ex.sets.length} Sets Completed',
            style: AppText.label(size: 12).copyWith(color: p.textMuted)),
      ],
    );
  }

  // ── Coach Prescription (read-only) ───────────────────────────────────
  Widget _prescriptionCard(AppPalette p, _ExState ex) {
    TextStyle head() => GoogleFonts.poppins(
        color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600);
    TextStyle cell() => GoogleFonts.poppins(
        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600);
    Widget c(String t, TextStyle s, {int flex = 1}) =>
        Expanded(flex: flex, child: Text(t, style: s));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: AppRadii.cardR,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE10600), Color(0xFF8A0000)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_outlined,
                  color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text('Coach Prescription',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            c('SET', head()),
            c('REPS', head()),
            c('KG', head()),
            c('REST', head()),
          ]),
          const SizedBox(height: 4),
          Divider(color: Colors.white.withValues(alpha: 0.25), height: 14),
          for (var i = 0; i < ex.sets.length; i++) ...[
            Row(children: [
              c('${i + 1}', cell()),
              c(ex.sets[i].pReps.isEmpty ? '—' : ex.sets[i].pReps, cell()),
              c(ex.sets[i].pWeight.isEmpty ? '—' : ex.sets[i].pWeight, cell()),
              c(_restLabel(ex.sets[i].pRest), cell()),
            ]),
            if (i < ex.sets.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  String _restLabel(String rest) {
    final s = _parseRest(rest);
    if (s <= 0) return '—';
    return '${s}s';
  }

  // ── Your Performance (accordion) ─────────────────────────────────────
  Widget _performanceSection(AppPalette p, _ExState ex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('YOUR PERFORMANCE',
            style: AppText.label(size: 12)
                .copyWith(color: p.textMuted, letterSpacing: 2)),
        const SizedBox(height: 10),
        for (var i = 0; i < ex.sets.length; i++) ...[
          _setTile(p, ex, i),
          if (i < ex.sets.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _setTile(AppPalette p, _ExState ex, int i) {
    final s = ex.sets[i];
    if (s.completed) return _completedTile(p, i, s);
    if (i == ex.activeSet) return _activeTile(p, ex, i, s);
    return _pendingTile(p, i);
  }

  Widget _completedTile(AppPalette p, int i, _SetState s) {
    final reps = s.reps.text.trim().isEmpty ? '—' : s.reps.text.trim();
    final wt = s.weight.text.trim().isEmpty ? '—' : '${s.weight.text.trim()} kg';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.success.withValues(alpha: 0.10),
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.success.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: p.success, size: 18),
          const SizedBox(width: 10),
          Text('Set ${i + 1} Completed',
              style: AppText.label(size: 13).copyWith(color: p.textPrimary)),
          const Spacer(),
          Text('$reps reps · $wt',
              style: AppText.body(size: 12.5).copyWith(color: p.textMuted)),
        ],
      ),
    );
  }

  Widget _pendingTile(AppPalette p, int i) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, color: p.textMuted, size: 16),
          const SizedBox(width: 10),
          Text('Set ${i + 1}',
              style: AppText.label(size: 13).copyWith(color: p.textMuted)),
        ],
      ),
    );
  }

  Widget _activeTile(AppPalette p, _ExState ex, int i, _SetState s) {
    final target = [
      if (s.pReps.isNotEmpty) '${s.pReps} reps',
      if (s.pWeight.isNotEmpty) '${s.pWeight} kg',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.accent, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: p.accent.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Set ${i + 1}',
                  style:
                      AppText.cardTitle(size: 15).copyWith(color: p.textPrimary)),
              const Spacer(),
              if (target.isNotEmpty)
                Text('Trainer: $target',
                    style: AppText.body(size: 11.5).copyWith(color: p.accent)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _input(p, s.reps, 'Reps Done', '')),
              const SizedBox(width: 12),
              Expanded(child: _input(p, s.weight, 'Weight Used', 'kg')),
            ],
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: 'Complete Set',
            showChevron: true,
            onPressed: () => _completeSet(ex, i),
          ),
        ],
      ),
    );
  }

  Widget _input(
      AppPalette p, TextEditingController ctrl, String label, String suffix) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      cursorColor: p.accent,
      style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: p.textMuted, fontSize: 13),
        suffixText: suffix.isEmpty ? null : suffix,
        filled: true,
        fillColor: p.inputFill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
            borderRadius: AppRadii.smR, borderSide: BorderSide(color: p.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: AppRadii.smR,
            borderSide: BorderSide(color: p.accent, width: 1.4)),
      ),
    );
  }

  // ── Bottom bar (prev / next / finish) ────────────────────────────────
  Widget _bottomBar(AppPalette p) {
    final isLast = _current == _exercises.length - 1;
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          if (_current > 0)
            _navBtn(p, Icons.arrow_back_rounded, 'Prev',
                () => _goTo(_current - 1)),
          if (_current > 0) const SizedBox(width: 12),
          Expanded(
            child: isLast
                ? GradientButton(
                    label: _allDone ? 'Finish Workout' : 'Finish',
                    onPressed: _finish,
                  )
                : _navBtnWide(p, 'Next Exercise', Icons.arrow_forward_rounded,
                    () => _goTo(_current + 1)),
          ),
        ],
      ),
    );
  }

  Widget _navBtn(AppPalette p, IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: p.textPrimary,
        side: BorderSide(color: p.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.smR),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: AppText.label(size: 13)),
    );
  }

  Widget _navBtnWide(
      AppPalette p, String label, IconData icon, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: p.accent,
        side: BorderSide(color: p.accent),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.smR),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: AppText.label(size: 14)),
          const SizedBox(width: 6),
          Icon(icon, size: 18),
        ],
      ),
    );
  }

  Future<void> _finish() async {
    await _saveProgress();
    if (!mounted) return;
    Get.back();
    Get.snackbar(
      _allDone ? 'Workout complete! 💪' : 'Progress saved',
      _allDone
          ? 'Great work — your coach can see your performance.'
          : 'Your logged sets were saved.',
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(14),
      borderRadius: 12,
    );
  }

  // ── Misc states ──────────────────────────────────────────────────────
  Widget _saveErrorBanner(AppPalette p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.error.withValues(alpha: 0.1),
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: p.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Couldn\'t save your last set. It\'ll retry on the next one.',
              style: AppText.body(size: 12).copyWith(color: p.error),
            ),
          ),
          TextButton(
            onPressed: _saveProgress,
            child: Text('Retry',
                style: AppText.label(size: 12).copyWith(color: p.accent)),
          ),
        ],
      ),
    );
  }

  Widget _noSetsNote(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Text('No sets prescribed for this exercise.',
          style: AppText.body(size: 13).copyWith(color: p.textMuted)),
    );
  }

  Widget _noWorkout(AppPalette p) {
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        iconTheme: IconThemeData(color: p.textPrimary),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fitness_center_rounded, color: p.textMuted, size: 44),
              const SizedBox(height: 14),
              Text('No workout to start',
                  style: AppText.title(size: 19).copyWith(color: p.textPrimary)),
              const SizedBox(height: 6),
              Text('Your coach hasn\'t assigned a workout yet.',
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 13).copyWith(color: p.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Full-screen rest timer ─────────────────────────────────────────────
class _RestTimerDialog extends StatefulWidget {
  final int seconds;
  final int nextSetNumber;
  final Color accent;
  const _RestTimerDialog({
    required this.seconds,
    required this.nextSetNumber,
    required this.accent,
  });

  @override
  State<_RestTimerDialog> createState() => _RestTimerDialogState();
}

class _RestTimerDialogState extends State<_RestTimerDialog> {
  late int _remaining = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        t.cancel();
        if (mounted) Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.seconds <= 0 ? 1 : widget.seconds;
    final frac = (_remaining / total).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Great work',
                style: GoogleFonts.poppins(
                    color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Rest before Set ${widget.nextSetNumber}',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 28),
            SizedBox(
              width: 200,
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: CircularProgressIndicator(
                      value: frac,
                      strokeWidth: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation(widget.accent),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${_remaining < 0 ? 0 : _remaining}',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 56,
                              fontWeight: FontWeight.w800,
                              height: 1)),
                      Text('seconds',
                          style: GoogleFonts.poppins(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Skip Rest',
                  style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
