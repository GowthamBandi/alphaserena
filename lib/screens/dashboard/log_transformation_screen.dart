import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../controllers/progress_controller.dart';
import '../../core/domain/transformation_comparison.dart';
import '../../core/models/transformation_entry.dart';
import '../../core/services/progress_log_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/primary_button.dart';

class LogTransformationScreen extends StatefulWidget {
  const LogTransformationScreen({
    super.key,
    this.recoveryDraft,
    this.editing,
    this.previous,
    this.service,
    this.offlineCheck,
    this.onSaved,
  });

  /// An already-published checkpoint being CORRECTED rather than logged.
  ///
  /// The screen is the same because the member's task is the same — describing
  /// one check-in. What changes is that the record keeps its place in history:
  /// it is written back in place, and the coach is shown that it was revised.
  final TransformationEntry? editing;

  final TransformationEntry? recoveryDraft;
  final TransformationEntry? previous;
  final TransformationWriter? service;
  final Future<bool> Function()? offlineCheck;
  final VoidCallback? onSaved;

  @override
  State<LogTransformationScreen> createState() =>
      _LogTransformationScreenState();
}

class _LogTransformationScreenState extends State<LogTransformationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _weight = TextEditingController();
  final _note = TextEditingController();
  final _picker = ImagePicker();
  final _selected = <TransformationPose, XFile>{};
  final _uploaded = <TransformationPose, TransformationPhoto>{};
  final _posesNeedingUpload = <TransformationPose>{};

  /// The canonical set every check-in offers.
  static const _canonicalMeasurements = [
    'chest',
    'waist',
    'hips',
    'neck',
    'leftArm',
    'rightArm',
    'leftThigh',
    'rightThigh',
    'leftCalf',
    'rightCalf',
  ];

  /// Built in [initState] rather than inline, because a record being corrected
  /// may carry measurement keys this editor does not otherwise offer — the
  /// legacy symmetric `arms`/`thighs` an older AlphaSerena build wrote. They are
  /// given real fields instead of being ignored: a correction REPLACES the whole
  /// measurement map, so a key with no field would have been silently deleted by
  /// the act of editing anything else on the record.
  final _measurementControllers = <String, TextEditingController>{};

  /// Carried through a correction untouched. This editor never collected body
  /// fat, so passing null would have deleted a value the record already held.
  double? _bodyFatPercent;

  late final TransformationWriter _service;
  TransformationVisibility? _visibility;
  String? _recordId;
  bool _saving = false;
  bool _checkingConnection = false;
  double _uploadProgress = 0;
  String? _error;

  TransformationEntry? get _previous {
    if (widget.previous != null) return widget.previous;
    if (!Get.isRegistered<ProgressController>()) return null;
    final completed = Get.find<ProgressController>().completed;
    // While CORRECTING a checkpoint, the latest completed entry is usually the
    // very record being corrected — comparing it with itself reported a change
    // of 0.0 kg against a "Last" weight that was the one in the field above.
    return completed
        .where((entry) => entry.id != widget.editing?.id)
        .firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ProgressLogService();
    final editing = widget.editing;
    for (final key in [
      ..._canonicalMeasurements,
      // Order matters only in that a legacy key keeps its own field rather
      // than colliding with a canonical one.
      ...?editing?.measurements.keys.where(
        (key) => !_canonicalMeasurements.contains(key),
      ),
    ]) {
      _measurementControllers[key] = TextEditingController();
    }
    for (final controller in [
      _weight,
      _note,
      ..._measurementControllers.values,
    ]) {
      controller.addListener(_refresh);
    }
    if (editing != null) {
      _recordId = editing.id;
      _uploaded.addAll(editing.photos);
      _visibility = editing.visibility;
      _bodyFatPercent = editing.bodyFatPercent;
      if (editing.weightKg != null) {
        _weight.text = _trimTrailingZero(editing.weightKg!);
      }
      for (final entry in editing.measurements.entries) {
        _measurementControllers[entry.key]?.text = _trimTrailingZero(
          entry.value,
        );
      }
      _note.text = editing.note ?? '';
      return;
    }

    final draft = widget.recoveryDraft;
    if (draft != null) {
      _recordId = draft.id;
      _uploaded.addAll(draft.photos);
      _error = draft.photos.isEmpty
          ? 'Your unfinished check-in is ready to continue.'
          : 'Recovered ${draft.photos.length} uploaded photo${draft.photos.length == 1 ? '' : 's'}. Nothing was shared with your coach.';
    }
  }

  bool get _isEditing => widget.editing != null;

  /// 82.0 → "82", 82.4 → "82.4". A prefilled field must read the way the member
  /// typed it, or every edit looks like it changed a value that it did not.
  static String _trimTrailingZero(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in [
      _weight,
      _note,
      ..._measurementControllers.values,
    ]) {
      controller.removeListener(_refresh);
      controller.dispose();
    }
    super.dispose();
  }

  double? _value(TextEditingController controller) =>
      double.tryParse(controller.text.trim());

  Map<String, double> get _measurements => {
    for (final entry in _measurementControllers.entries)
      if (_value(entry.value) != null) entry.key: _value(entry.value)!,
  };

  bool get _hasContent =>
      _value(_weight) != null ||
      _bodyFatPercent != null ||
      _measurements.isNotEmpty ||
      _selected.isNotEmpty ||
      _uploaded.isNotEmpty ||
      _note.text.trim().isNotEmpty;

  bool get _canSave =>
      !_saving && !_checkingConnection && _hasContent && _visibility != null;

  int get _totalPhotoCount => {..._selected.keys, ..._uploaded.keys}.length;
  int get _completedPhotoUploads =>
      (_totalPhotoCount - _posesNeedingUpload.length).clamp(
        0,
        _totalPhotoCount,
      );

  String? _validateNumber(String? raw, {required double max}) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite || parsed <= 0 || parsed > max) {
      return 'Use 0.1–${max.toStringAsFixed(0)}';
    }
    return null;
  }

  Future<bool> _isOffline() async {
    if (widget.offlineCheck != null) return widget.offlineCheck!();
    final states = await Connectivity().checkConnectivity();
    return states.every((state) => state == ConnectivityResult.none);
  }

  Future<void> _pick(TransformationPose pose, ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1800,
      imageQuality: 84,
    );
    if (file == null || !mounted) return;
    setState(() {
      _selected[pose] = file;
      _posesNeedingUpload.add(pose);
      _error = null;
    });
  }

  Future<void> _chooseSource(TransformationPose pose) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              subtitle: const Text('Use your camera now'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              subtitle: const Text('Select an existing photo'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pick(pose, source);
  }

  Future<void> _removePhoto(TransformationPose pose) async {
    final persisted = _uploaded[pose];
    setState(() {
      _selected.remove(pose);
      _uploaded.remove(pose);
      _posesNeedingUpload.remove(pose);
      _error = null;
    });
    // While correcting a published record, removal is staged only. The live
    // record keeps the photo until the member saves, so abandoning the edit
    // leaves what the coach already saw intact; the correction write is what
    // detaches it and clears the stored media.
    if (_recordId != null && persisted != null && !_isEditing) {
      try {
        await _service.removeDraftPose(
          recordId: _recordId!,
          pose: pose,
          photo: persisted,
        );
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _error =
              'The photo could not be removed from the saved draft. Retry removal before publishing.';
          _uploaded[pose] = persisted;
        });
      }
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    // `_checkingConnection` is part of the guard, not just `_saving`: two taps
    // landing in the same frame both reach here before the button rebuilds
    // disabled, and the connection probe is awaited BEFORE `_saving` is set.
    // Without it a double tap minted two record ids and published twice.
    if (_saving || _checkingConnection) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_hasContent || _visibility == null) {
      setState(() {
        _error = !_hasContent
            ? 'Add at least one real observation.'
            : 'Choose who can see this check-in.';
      });
      return;
    }

    setState(() {
      _checkingConnection = true;
      _error = null;
    });
    final offline = await _isOffline();
    if (!mounted) return;
    if (offline && _selected.isNotEmpty) {
      setState(() {
        _checkingConnection = false;
        _error =
            'Photos need a connection. Everything you entered is still here—retry when online.';
      });
      return;
    }
    setState(() {
      _checkingConnection = false;
      _saving = true;
      _uploadProgress = _totalPhotoCount == 0
          ? 0
          : _completedPhotoUploads / _totalPhotoCount;
    });

    final capturedAt = DateTime.now();
    final editing = widget.editing;
    try {
      final isNewRecord = _recordId == null;
      final recordId = _recordId ?? _service.newRecordId();
      _recordId = recordId;
      if (_selected.isNotEmpty && isNewRecord) {
        await _service.createUploadDraft(
          recordId: recordId,
          clientRecordedAt: capturedAt,
        );
      }

      for (final entry in _selected.entries) {
        if (!_posesNeedingUpload.contains(entry.key) &&
            _uploaded.containsKey(entry.key)) {
          continue;
        }
        final photo = await _service.uploadPose(
          recordId: recordId,
          pose: entry.key,
          file: File(entry.value.path),
          filename: entry.value.name,
          // A published record stays exactly as the coach last saw it until the
          // member commits the correction below.
          persistToRecord: editing == null,
        );
        _uploaded[entry.key] = photo;
        _posesNeedingUpload.remove(entry.key);
        if (mounted) {
          setState(() {
            _uploadProgress = _completedPhotoUploads / _totalPhotoCount;
          });
        }
      }

      final outcome = editing != null
          ? await _service.updatePublished(
              original: editing,
              visibility: _visibility!,
              weightKg: _value(_weight),
              bodyFatPercent: _bodyFatPercent,
              measurements: _measurements,
              photos: _uploaded,
              note: _note.text,
            )
          : await _service.finalize(
              recordId: recordId,
              clientRecordedAt: capturedAt,
              visibility: _visibility!,
              weightKg: _value(_weight),
              bodyFatPercent: _bodyFatPercent,
              measurements: _measurements,
              photos: _uploaded,
              note: _note.text,
            );
      if (!mounted) return;
      widget.onSaved?.call();
      // Reported from what the WRITE actually did, not from the connectivity
      // probe taken before it. A connection can be up and still not reach
      // Firestore, and that check-in is queued exactly the same way.
      await _showSuccess(
        queued: outcome == TransformationWriteOutcome.queued,
      );
      if (!mounted) return;
      Get.back();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = _uploaded.isEmpty
            ? _isEditing
                  ? 'Your changes were not saved. The original check-in is unchanged — check your connection and retry.'
                  : 'Nothing was published. Check your connection and retry.'
            : 'Upload paused at $_completedPhotoUploads/$_totalPhotoCount. Retry continues from here without duplicate photos.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showSuccess({required bool queued}) async {
    HapticFeedback.mediumImpact();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 280),
                tween: Tween(begin: .72, end: 1),
                builder: (_, value, child) =>
                    Transform.scale(scale: value, child: child),
                child: Icon(
                  queued ? Icons.cloud_done_outlined : Icons.check_circle,
                  size: 64,
                  color: context.palette.accent,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                queued
                    ? 'Queued safely'
                    : _isEditing
                    ? 'Check-in updated'
                    : 'Transformation saved',
                textAlign: TextAlign.center,
                style: AppText.title(size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                queued
                    ? 'It will sync automatically when you are online.'
                    : _visibility == TransformationVisibility.shared
                    ? _isEditing
                          ? 'Your coach sees the updated values, marked as edited.'
                          : 'Your coach can now review this checkpoint.'
                    : 'This checkpoint is visible only to you.',
                textAlign: TextAlign.center,
                style: AppText.body(size: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
    await Future<void>.delayed(
      reduceMotion
          ? const Duration(milliseconds: 250)
          : const Duration(milliseconds: 750),
    );
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  bool get _hasUnsavedContent =>
      _recordId != null ||
      _selected.isNotEmpty ||
      _uploaded.isNotEmpty ||
      _weight.text.trim().isNotEmpty ||
      _note.text.trim().isNotEmpty ||
      _measurementControllers.values.any(
        (value) => value.text.trim().isNotEmpty,
      );

  Future<void> _requestClose() async {
    if (_saving || _checkingConnection) return;
    if (!_hasUnsavedContent) {
      Get.back();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _isEditing ? 'Discard these changes?' : 'Leave this check-in?',
        ),
        content: Text(
          _isEditing
              ? 'Your check-in stays exactly as it is now. Any photo you already replaced cannot be brought back.'
              : _recordId == null
              ? 'Your unsaved changes will be lost.'
              : 'Uploaded parts will be removed. You can stay and retry instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true) return;
    // `abandon` is for an UNPUBLISHED envelope only. In edit mode `_recordId`
    // is a live checkpoint the coach may already have reviewed — abandoning it
    // would mark real history as discarded and delete its photos.
    if (_recordId != null && !_isEditing) {
      await _service.abandon(_recordId!, _uploaded.values);
    }
    if (mounted) Get.back();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit check-in' : "Today's check-in"),
          leading: IconButton(
            tooltip: 'Close check-in',
            onPressed: _requestClose,
            icon: const Icon(Icons.close),
          ),
        ),
        body: Form(
          key: _formKey,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  _gutter(context),
                  8,
                  _gutter(context),
                  keyboardOpen ? 24 : 112,
                ),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _header(p),
                          const SizedBox(height: 18),
                          _weightCard(p),
                          const SizedBox(height: 14),
                          _measurementsCard(p),
                          const SizedBox(height: 14),
                          _photosCard(p),
                          const SizedBox(height: 14),
                          _notesCard(p),
                          const SizedBox(height: 14),
                          _privacyCard(p),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            _errorBanner(p, _error!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: keyboardOpen ? null : _saveBar(p),
      ),
    );
  }

  double _gutter(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1024) return 40;
    if (width >= 600) return 28;
    return 16;
  }

  Widget _header(AppPalette p) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('EEEE, d MMMM').format(DateTime.now()),
          style: AppText.label(size: 11).copyWith(color: p.accent),
        ),
        const SizedBox(height: 5),
        Text(
          'Capture the evidence that matters today.',
          style: AppText.title(size: 22).copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: 5),
        Text(
          'Weight, measurements, photos, or any combination. Nothing is required unnecessarily.',
          style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
        ),
      ],
    ),
  );

  Widget _weightCard(AppPalette p) {
    final current = _value(_weight);
    final previous = _previous?.weightKg;
    final delta = current != null && previous != null
        ? current - previous
        : null;
    return _section(
      p,
      icon: Icons.monitor_weight_outlined,
      title: 'Weight',
      subtitle: 'Optional · kilograms',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 480;
          final editor = TextFormField(
            key: const ValueKey('transformation_weight'),
            controller: _weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'^\d{0,3}(\.\d{0,1})?'),
              ),
            ],
            style: AppText.title(size: 30).copyWith(color: p.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Current weight',
              hintText: '72.5',
              suffixText: 'kg',
            ),
            validator: (value) => _validateNumber(value, max: 300),
          );
          final history = Row(
            children: [
              Expanded(
                child: _stat(
                  p,
                  'Last',
                  previous == null ? '—' : '${previous.toStringAsFixed(1)} kg',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _stat(
                  p,
                  'Change',
                  delta == null
                      ? '—'
                      : '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} kg',
                  accent: delta != null,
                ),
              ),
            ],
          );
          return compact
              ? Column(children: [editor, const SizedBox(height: 12), history])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: editor),
                    const SizedBox(width: 14),
                    Expanded(flex: 2, child: history),
                  ],
                );
        },
      ),
    );
  }

  Widget _measurementsCard(AppPalette p) => _section(
    p,
    icon: Icons.straighten_outlined,
    title: 'Measurements',
    subtitle: 'Optional · centimetres',
    child: LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context).scale(1);
        final columns = constraints.maxWidth >= 760 && scaler < 1.4
            ? 3
            : constraints.maxWidth >= 360 && scaler < 1.3
            ? 2
            : 1;
        final keys = _measurementControllers.keys;
        final width = (constraints.maxWidth - ((columns - 1) * 10)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final key in keys)
              SizedBox(
                width: width,
                child: TextFormField(
                  key: ValueKey('measurement_$key'),
                  controller: _measurementControllers[key],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,3}(\.\d{0,1})?'),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: transformationMetricLabel(key),
                    suffixText: 'cm',
                  ),
                  validator: (value) => _validateNumber(value, max: 300),
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _photosCard(AppPalette p) => _section(
    p,
    icon: Icons.photo_camera_back_outlined,
    title: 'Progress photos',
    subtitle: 'Optional · matching poses make comparisons trustworthy',
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        if (wide) {
          final width = (constraints.maxWidth - 24) / 3;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < TransformationPose.values.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                SizedBox(
                  width: width,
                  child: _photoSlot(p, TransformationPose.values[i]),
                ),
              ],
            ],
          );
        }
        final width = (constraints.maxWidth * .76).clamp(220.0, 300.0);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < TransformationPose.values.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                SizedBox(
                  width: width,
                  child: _photoSlot(p, TransformationPose.values[i]),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );

  Widget _photoSlot(AppPalette p, TransformationPose pose) {
    final file = _selected[pose];
    final uploaded = _uploaded[pose];
    final hasPhoto = file != null || uploaded != null;
    final label = transformationMetricLabel(pose.name);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final cameraButton = OutlinedButton(
      onPressed: _saving ? null : () => _pick(pose, ImageSource.camera),
      child: _photoAction(Icons.photo_camera_outlined, 'Camera'),
    );
    final galleryButton = OutlinedButton(
      onPressed: _saving ? null : () => _pick(pose, ImageSource.gallery),
      child: _photoAction(Icons.photo_library_outlined, 'Gallery'),
    );
    return Semantics(
      container: true,
      label: '$label progress photo, ${hasPhoto ? 'selected' : 'not selected'}',
      child: Container(
        decoration: BoxDecoration(
          color: p.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: hasPhoto ? p.accent : p.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: .82,
              child: hasPhoto
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        if (file != null)
                          Image.file(
                            File(file.path),
                            fit: BoxFit.cover,
                            cacheWidth: 900,
                            semanticLabel: '$label progress photo preview',
                          )
                        else
                          CachedNetworkImage(
                            imageUrl: uploaded!.url,
                            fit: BoxFit.cover,
                            memCacheWidth: 900,
                            placeholder: (_, _) => Container(
                              color: p.surfaceAlt,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            errorWidget: (_, _, _) => _photoEmpty(p, label),
                          ),
                        Positioned(left: 10, top: 10, child: _darkChip(label)),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: IconButton.filledTonal(
                            tooltip: 'Remove $label photo',
                            onPressed: _saving
                                ? null
                                : () => _removePhoto(pose),
                            icon: const Icon(Icons.delete_outline, size: 19),
                          ),
                        ),
                      ],
                    )
                  : _photoEmpty(p, label),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: hasPhoto
                  ? OutlinedButton.icon(
                      onPressed: _saving ? null : () => _chooseSource(pose),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Replace'),
                    )
                  : largeText
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        cameraButton,
                        const SizedBox(height: 8),
                        galleryButton,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: cameraButton),
                        const SizedBox(width: 8),
                        Expanded(child: galleryButton),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoAction(IconData icon, String label) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, size: 18),
      const SizedBox(width: 6),
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1),
        ),
      ),
    ],
  );

  Widget _photoEmpty(AppPalette p, String label) => Container(
    color: p.surfaceAlt,
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.accent.withValues(alpha: .10),
          ),
          child: Icon(Icons.person_outline, color: p.accent, size: 31),
        ),
        const SizedBox(height: 13),
        Text(
          label,
          style: AppText.title(size: 17).copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Add when you are ready',
          textAlign: TextAlign.center,
          style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
        ),
      ],
    ),
  );

  Widget _notesCard(AppPalette p) => _section(
    p,
    icon: Icons.notes_outlined,
    title: 'Notes',
    subtitle: 'Optional · add context your numbers cannot show',
    child: TextFormField(
      key: const ValueKey('transformation_notes'),
      controller: _note,
      minLines: 3,
      maxLines: 7,
      maxLength: 500,
      decoration: const InputDecoration(
        labelText: 'How did this checkpoint feel?',
        hintText:
            'Example: Energy felt better this week; posture is improving.',
        alignLabelWithHint: true,
      ),
    ),
  );

  Widget _privacyCard(AppPalette p) => _section(
    p,
    icon: Icons.shield_outlined,
    title: 'Privacy',
    subtitle: 'Choose who can see this entire checkpoint',
    child: LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 600;
        final shared = _privacyOption(
          p,
          value: TransformationVisibility.shared,
          icon: Icons.visibility_outlined,
          title: 'Shared with coach',
          body:
              'Your assigned coach can review these values and photos in TrainerHQ.',
        );
        final private = _privacyOption(
          p,
          value: TransformationVisibility.private,
          icon: Icons.lock_outline,
          title: 'Only me',
          body:
              'This checkpoint stays in AlphaSerena and is never returned to your coach.',
        );
        return horizontal
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: shared),
                  const SizedBox(width: 10),
                  Expanded(child: private),
                ],
              )
            : Column(children: [shared, const SizedBox(height: 10), private]);
      },
    ),
  );

  Widget _privacyOption(
    AppPalette p, {
    required TransformationVisibility value,
    required IconData icon,
    required String title,
    required String body,
  }) {
    final selected = _visibility == value;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $body',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _saving ? null : () => setState(() => _visibility = value),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? p.accent.withValues(alpha: .10) : p.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? p.accent : p.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? p.accent : p.textMuted),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.label(
                        size: 13,
                      ).copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: AppText.body(
                        size: 11,
                      ).copyWith(color: p.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? p.accent : p.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _saveBar(AppPalette p) => Material(
    color: p.surface,
    elevation: 12,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _gutter(context),
          10,
          _gutter(context),
          10,
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_saving && _totalPhotoCount > 0) ...[
                  Semantics(
                    liveRegion: true,
                    label:
                        'Uploading $_completedPhotoUploads of $_totalPhotoCount photos',
                    child: LinearProgressIndicator(value: _uploadProgress),
                  ),
                  const SizedBox(height: 7),
                ],
                PrimaryButton(
                  label: _checkingConnection
                      ? 'Checking connection…'
                      : _saving && _totalPhotoCount > 0
                      ? 'Uploading $_completedPhotoUploads of $_totalPhotoCount…'
                      : _recordId != null && _error != null
                      ? 'Retry & Save'
                      : _isEditing
                      ? 'Save Changes'
                      : 'Save Check-in',
                  icon: _recordId != null && _error != null
                      ? Icons.refresh
                      : Icons.check_circle_outline,
                  isLoading: _saving || _checkingConnection,
                  onPressed: _canSave ? _save : null,
                ),
                if (!_canSave && !_saving && !_checkingConnection) ...[
                  const SizedBox(height: 5),
                  Text(
                    !_hasContent
                        ? 'Add one item to continue'
                        : 'Choose a privacy option to continue',
                    textAlign: TextAlign.center,
                    style: AppText.body(
                      size: 10.5,
                    ).copyWith(color: p.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _section(
    AppPalette p, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: p.surface,
      borderRadius: AppRadii.cardR,
      border: Border.all(color: p.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: p.accent.withValues(alpha: .10),
              ),
              child: Icon(icon, color: p.accent, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppText.title(
                      size: 17,
                    ).copyWith(color: p.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppText.body(
                      size: 11.5,
                    ).copyWith(color: p.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );

  Widget _stat(
    AppPalette p,
    String label,
    String value, {
    bool accent = false,
  }) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: p.surfaceAlt,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: p.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppText.body(size: 10.5).copyWith(color: p.textMuted),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: AppText.label(
              size: 13,
            ).copyWith(color: accent ? p.accent : p.textPrimary),
          ),
        ),
      ],
    ),
  );

  Widget _darkChip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .75),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: AppText.label(size: 10.5).copyWith(color: Colors.white),
    ),
  );

  Widget _errorBanner(AppPalette p, String message) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: p.accent.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: p.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppText.body(size: 12).copyWith(color: p.textPrimary),
            ),
          ),
        ],
      ),
    ),
  );
}
