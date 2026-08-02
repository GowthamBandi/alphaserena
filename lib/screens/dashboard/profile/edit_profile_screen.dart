import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../controllers/member_controller.dart';
import '../../../core/domain/member_profile_form.dart';
import '../../../core/services/member_identity_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/widgets/primary_button.dart';

/// The member's profile editor — the ONE place a member authors their own
/// identity, and the only profile-maintenance surface in the app.
///
/// Writes `clientProfiles/{uid}.profile` through
/// [MemberIdentityService.saveForm]; the backend's `onClientProfileWritten`
/// projects the coach-visible sections onto every `clients/{id}.sharedProfile`
/// the member holds, so a rename, a corrected date of birth or a new photo
/// reaches their coach's roster and header with no further action from either
/// side.
///
/// Four things about this screen were broken in ways that all read to the
/// member as "I cannot edit my profile":
///
///  1. It **did not build at all** for a member whose stored gender was
///     `'Other'` — the value the onboarding wizard writes. Its dropdown offered
///     `Female / Male / Non-binary / Prefer not to say`, and a
///     `DropdownButtonFormField` whose value is absent from its items asserts.
///     Vocabulary now comes from [genderOptionsFor], which ADOPTS whatever is
///     stored, so no stored value can ever crash this screen again.
///  2. Its **Save button was permanently disabled** for anyone who had skipped
///     an optional field. It required height, weight, date of birth, phone and
///     a goal weight that nothing else in the app has ever collected — while
///     the wizard that collects them says "optional, you can skip this". With
///     the button disabled, `_validate` never ran, so no error text ever
///     appeared either: a dead end with no explanation. Validation is now the
///     shared [MemberProfileForm.errors] rule set, only the name is required,
///     and **Save is always tappable** so an invalid field always says so.
///  3. Its **photo button did nothing** — a snackbar reading "Photo upload will
///     use the existing profile media flow". The flow existed; it was simply
///     never wired here. Pick, replace and remove all work now, and a replaced
///     object is deleted from Storage rather than orphaned.
///  4. Its **save could never fail or finish offline**: `set()` resolves only
///     on server acknowledgement, so the button spun forever with the member
///     never told their change was safely queued.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, this.initialForm});

  /// Test seam: the profile to open with, instead of reading
  /// [MemberController]. Supplying it is the only way to exercise this screen
  /// without a live Firebase app — and this screen has already shipped one
  /// defect (an un-renderable gender) that only a build-it-and-look test
  /// catches, so it must be reachable from a widget test.
  @visibleForTesting
  final MemberProfileForm? initialForm;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  // `late` on both: neither is touched until the member actually saves or picks
  // a photo, so a test that only renders and validates needs no Firebase.
  late final _service = MemberIdentityService();
  final _scrollController = ScrollController();

  /// The profile as it stood when the editor opened. Never re-read from the
  /// live stream: a snapshot arriving mid-edit (another device, or the
  /// projection's own round trip) must not overwrite what the member is typing.
  late final MemberProfileForm _original;
  late MemberProfileForm _form;

  /// Errors are hidden until the member has asked to save at least once —
  /// greeting someone with red text on fields they have not touched is hostile.
  /// After that they stay live on every keystroke.
  bool _submitted = false;
  bool _saving = false;
  bool _uploadingPhoto = false;

  /// The avatar object that was attached when the editor opened. Deleted from
  /// Storage only once a REPLACEMENT has been durably stored, so a failed save
  /// can never leave the member with a `photoUrl` pointing at a deleted file.
  late final String _originalPhotoUrl;

  /// Every avatar uploaded during this editing session. Uploading happens the
  /// moment a photo is picked — the member has to SEE it — so a member who
  /// picks three photos and then backs out has left three objects in Storage
  /// that no document will ever reference. Discarding cleans them up.
  final _uploadedThisSession = <String>[];

  final _controllers = <String, TextEditingController>{};
  final _fieldKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _original = widget.initialForm ?? _fromMemberController();
    _form = _original;
    _originalPhotoUrl = _original.photoUrl;
    for (final entry in <String, String>{
      'firstName': _original.firstName,
      'lastName': _original.lastName,
      'email': _original.email,
      'phone': _original.phone,
      'heightCm': _original.heightCmText,
      'heightFt': _original.heightFtText,
      'heightIn': _original.heightInText,
      'weight': _original.weightText,
      'goalWeight': _original.goalWeightText,
      'emergencyPhone': _original.emergencyPhone,
      'address': _original.address,
      'city': _original.city,
      'state': _original.state,
      'country': _original.country,
    }.entries) {
      _controllers[entry.key] = TextEditingController(text: entry.value);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  /// The one place this screen reads the live member. Snapshotted ONCE: a
  /// document update arriving mid-edit (another device, or the projection's own
  /// round trip) must never overwrite what the member is typing.
  MemberProfileForm _fromMemberController() {
    final member = Get.find<MemberController>();
    return MemberProfileForm.fromProfileDoc(
      member.profile.value,
      fallbackName: member.name,
      fallbackEmail: member.email,
      fallbackPhone: member.phone,
    );
  }

  TextEditingController _c(String key) => _controllers[key]!;

  GlobalKey _key(String field) => _fieldKeys[field] ??= GlobalKey();

  void _update(MemberProfileForm next) {
    if (identical(next, _form)) return;
    setState(() => _form = next);
  }

  Map<String, String> get _errors => _form.errors;

  String? _errorFor(String field) => _submitted ? _errors[field] : null;

  bool get _dirty => _form.differsFrom(_original);

  // ── Avatar ───────────────────────────────────────────────────────────

  Future<void> _pickPhoto(ImageSource source) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty || _uploadingPhoto) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return; // cancelled — not an error
      setState(() => _uploadingPhoto = true);
      final url = await _service.uploadPhoto(uid, File(picked.path));
      if (!mounted) return;
      setState(() {
        _uploadedThisSession.add(url);
        _form = _form.copyWith(photoUrl: url);
        _uploadingPhoto = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadingPhoto = false);
      Get.snackbar(
        'Upload failed',
        'We could not upload that photo. Please try again.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  void _photoSheet() {
    final p = context.palette;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: p.accent),
              title: Text(
                'Take a photo',
                style: GoogleFonts.poppins(color: p.textPrimary),
              ),
              onTap: () {
                Get.back<void>();
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: p.accent),
              title: Text(
                'Choose from gallery',
                style: GoogleFonts.poppins(color: p.textPrimary),
              ),
              onTap: () {
                Get.back<void>();
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (_form.photoUrl.isNotEmpty)
              ListTile(
                leading: Icon(Icons.delete_outline, color: p.error),
                title: Text(
                  'Remove photo',
                  style: GoogleFonts.poppins(color: p.error),
                ),
                subtitle: Text(
                  'Your coach will see your initials instead.',
                  style: GoogleFonts.poppins(
                    color: p.textMuted,
                    fontSize: 11.5,
                  ),
                ),
                onTap: () {
                  Get.back<void>();
                  // Marks the removal on the DRAFT only. The stored photo — and
                  // the Storage object behind it — go when the member saves, so
                  // backing out of the editor changes nothing.
                  _update(_form.copyWith(photoUrl: ''));
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── Date of birth ────────────────────────────────────────────────────

  Future<void> _pickDob() async {
    final now = DateTime.now();
    // The picker's own bounds are the validation bounds, so it is not possible
    // to choose a date the form will then reject.
    final chosen = await showDatePicker(
      context: context,
      initialDate: _form.dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - kMaxAgeYears, now.month, now.day),
      lastDate: DateTime(now.year - kMinAgeYears, now.month, now.day),
      helpText: 'Select your date of birth',
    );
    if (chosen == null || !mounted) return;
    _update(_form.copyWith(dob: chosen));
  }

  // ── Save ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving || _uploadingPhoto) return; // one write per intent
    FocusScope.of(context).unfocus();

    if (!_form.isValid) {
      setState(() => _submitted = true);
      // The button stays live precisely so this path can run — a disabled
      // button is why the previous screen could refuse to save while never
      // saying which field was wrong.
      await _scrollToFirstError();
      Get.snackbar(
        'Check your details',
        _errors.length == 1
            ? _errors.values.first
            : 'Please fix the ${_errors.length} highlighted fields.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    if (!_dirty) {
      // Nothing changed. Writing anyway would burn a write, re-run the coach
      // projection and bump `updatedAt` for no reason.
      Get.back<void>();
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      Get.snackbar(
        'Not signed in',
        'Please sign in again to update your profile.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    setState(() {
      _submitted = true;
      _saving = true;
    });
    try {
      final outcome = await _service.saveForm(uid, _form);
      // Only now is the superseded photo safe to remove: the record no longer
      // points at it. Best-effort and non-blocking — an orphaned object must
      // never turn a successful save into a failure.
      // Everything this session uploaded that the saved record does NOT point
      // at, plus the photo it replaced.
      for (final orphan in [..._uploadedThisSession, _originalPhotoUrl]) {
        if (orphan.isNotEmpty && orphan != _form.photoUrl) {
          unawaited(_service.deletePhotoAt(uid, orphan));
        }
      }
      if (!mounted) return;
      setState(() => _saving = false);
      Get.back<void>();
      Get.snackbar(
        outcome == ProfileSaveOutcome.acknowledged
            ? 'Profile updated'
            : 'Saved on this device',
        outcome == ProfileSaveOutcome.acknowledged
            ? 'Your coach sees your new details right away.'
            : 'You are offline — your changes will reach your coach as soon '
                  'as you reconnect.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (_) {
      if (!mounted) return;
      // Stay on the form with the member's typing intact. Reporting success for
      // a write that failed is the failure mode this screen exists to end.
      setState(() => _saving = false);
      Get.snackbar(
        'Could not save',
        'Your changes are still here. Please try again.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _scrollToFirstError() async {
    const order = [
      ProfileFormField.displayName,
      ProfileFormField.dob,
      ProfileFormField.height,
      ProfileFormField.weight,
      ProfileFormField.goalWeight,
      ProfileFormField.phone,
      ProfileFormField.email,
      ProfileFormField.emergencyPhone,
    ];
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    for (final field in order) {
      if (!_errors.containsKey(field)) continue;
      final ctx = _fieldKeys[field]?.currentContext;
      if (ctx == null || !ctx.mounted) continue;
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.15,
      );
      return;
    }
  }

  Future<void> _confirmDiscard() async {
    final p = context.palette;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: p.surface,
        title: Text(
          'Discard changes?',
          style: GoogleFonts.poppins(
            color: p.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Your edits have not been saved yet.',
          style: GoogleFonts.poppins(color: p.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Discard', style: TextStyle(color: p.error)),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    // Nothing this session uploaded is referenced by anything now.
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      for (final orphan in _uploadedThisSession) {
        if (orphan != _originalPhotoUrl) {
          unawaited(_service.deletePhotoAt(uid, orphan));
        }
      }
    }
    Get.back<void>();
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = width >= 700 ? 28.0 : 18.0;

    return PopScope(
      // A back gesture must not silently throw away typing. Saving is still
      // never implicit — the member chooses.
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _saving) return;
        _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(
          backgroundColor: p.background,
          title: Text(
            'Edit Profile',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(
          child: ListView(
            controller: _scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 24),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _section(p, 'Photo', child: _photo(p)),
                      const SizedBox(height: 14),
                      _section(
                        p,
                        'Personal information',
                        child: Column(children: _personalFields(p, width)),
                      ),
                      const SizedBox(height: 14),
                      _section(
                        p,
                        'Body metrics',
                        child: Column(children: _bodyFields(p, width)),
                      ),
                      const SizedBox(height: 14),
                      _section(
                        p,
                        'Contact',
                        child: Column(children: _contactFields(p)),
                      ),
                      const SizedBox(height: 14),
                      _section(
                        p,
                        'Location',
                        child: Column(children: _locationFields(width)),
                      ),
                      const SizedBox(height: 18),
                      // ALWAYS enabled while idle. Whether the form is valid is
                      // answered by tapping it, never by a dead control the
                      // member cannot interrogate.
                      PrimaryButton(
                        label: 'Save Changes',
                        isLoading: _saving,
                        onPressed: (_saving || _uploadingPhoto) ? null : _save,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Your name, photo, contact details and body metrics are '
                        'shared with your coach so they can train you. Your '
                        'address and emergency contact are not.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: p.textMuted,
                          fontSize: 11.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _personalFields(AppPalette p, double width) => [
    _responsivePair(
      width,
      _field(
        name: 'firstName',
        scrollKey: _key(ProfileFormField.displayName),
        controller: _c('firstName'),
        label: 'First name',
        icon: Icons.person_outline,
        capitalization: TextCapitalization.words,
        errorText: _errorFor(ProfileFormField.displayName),
        onChanged: (v) => _update(_form.copyWith(firstName: v)),
      ),
      _field(
        name: 'lastName',
        controller: _c('lastName'),
        label: 'Last name (optional)',
        capitalization: TextCapitalization.words,
        onChanged: (v) => _update(_form.copyWith(lastName: v)),
      ),
    ),
    const SizedBox(height: 12),
    _genderField(p),
    const SizedBox(height: 12),
    _dobField(p),
  ];

  List<Widget> _bodyFields(AppPalette p, double width) => [
    Row(
      children: [
        Expanded(
          child: Text(
            'Height (optional)',
            style: GoogleFonts.poppins(color: p.textMuted, fontSize: 12),
          ),
        ),
        _unitToggle(
          p,
          value: _form.heightUnit,
          options: const [('cm', 'cm'), ('ftin', 'ft/in')],
          semantics: 'Height unit',
          onChanged: (unit) {
            final next = _form.withHeightUnit(unit);
            _c('heightCm').text = next.heightCmText;
            _c('heightFt').text = next.heightFtText;
            _c('heightIn').text = next.heightInText;
            _update(next);
          },
        ),
      ],
    ),
    const SizedBox(height: 8),
    KeyedSubtree(
      key: _key(ProfileFormField.height),
      child: _form.heightUnit == 'ftin'
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    name: 'heightFt',
                    controller: _c('heightFt'),
                    label: 'Feet',
                    number: true,
                    onChanged: (v) => _update(_form.copyWith(heightFtText: v)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    name: 'heightIn',
                    controller: _c('heightIn'),
                    label: 'Inches',
                    number: true,
                    errorText: _errorFor(ProfileFormField.height),
                    onChanged: (v) => _update(_form.copyWith(heightInText: v)),
                  ),
                ),
              ],
            )
          : _field(
              name: 'heightCm',
              controller: _c('heightCm'),
              label: 'Height (cm)',
              icon: Icons.straighten,
              number: true,
              errorText: _errorFor(ProfileFormField.height),
              onChanged: (v) => _update(_form.copyWith(heightCmText: v)),
            ),
    ),
    const SizedBox(height: 14),
    Row(
      children: [
        Expanded(
          child: Text(
            'Weight (optional)',
            style: GoogleFonts.poppins(color: p.textMuted, fontSize: 12),
          ),
        ),
        _unitToggle(
          p,
          value: _form.weightUnit,
          options: const [('kg', 'kg'), ('lb', 'lb')],
          semantics: 'Weight unit',
          onChanged: (unit) {
            final next = _form.withWeightUnit(unit);
            _c('weight').text = next.weightText;
            _c('goalWeight').text = next.goalWeightText;
            _update(next);
          },
        ),
      ],
    ),
    const SizedBox(height: 8),
    _responsivePair(
      width,
      _field(
        name: 'weight',
        scrollKey: _key(ProfileFormField.weight),
        controller: _c('weight'),
        label: 'Current weight (${_form.weightUnit})',
        icon: Icons.monitor_weight_outlined,
        number: true,
        errorText: _errorFor(ProfileFormField.weight),
        onChanged: (v) => _update(_form.copyWith(weightText: v)),
      ),
      _field(
        name: 'goalWeight',
        scrollKey: _key(ProfileFormField.goalWeight),
        controller: _c('goalWeight'),
        label: 'Goal weight (${_form.weightUnit})',
        icon: Icons.flag_outlined,
        number: true,
        errorText: _errorFor(ProfileFormField.goalWeight),
        onChanged: (v) => _update(_form.copyWith(goalWeightText: v)),
      ),
    ),
  ];

  List<Widget> _contactFields(AppPalette p) => [
    _field(
      name: 'phone',
      scrollKey: _key(ProfileFormField.phone),
      controller: _c('phone'),
      label: 'Phone number',
      icon: Icons.phone_outlined,
      phone: true,
      errorText: _errorFor(ProfileFormField.phone),
      onChanged: (v) => _update(_form.copyWith(phone: v)),
    ),
    const SizedBox(height: 12),
    // EDITABLE. It used to be locked with the helper "Email is managed by your
    // sign-in account", which is not true of a phone-auth member: nothing but
    // this profile ever supplies their email, so locking it meant a member who
    // skipped it during onboarding could never add one at all.
    _field(
      name: 'email',
      scrollKey: _key(ProfileFormField.email),
      controller: _c('email'),
      label: 'Email (optional)',
      icon: Icons.mail_outline,
      email: true,
      errorText: _errorFor(ProfileFormField.email),
      onChanged: (v) => _update(_form.copyWith(email: v)),
    ),
    const SizedBox(height: 12),
    _field(
      name: 'emergencyPhone',
      scrollKey: _key(ProfileFormField.emergencyPhone),
      controller: _c('emergencyPhone'),
      label: 'Emergency contact (optional)',
      icon: Icons.emergency_outlined,
      phone: true,
      helper: 'Never shared with your coach.',
      errorText: _errorFor(ProfileFormField.emergencyPhone),
      onChanged: (v) => _update(_form.copyWith(emergencyPhone: v)),
    ),
  ];

  List<Widget> _locationFields(double width) => [
    _field(
      name: 'address',
      controller: _c('address'),
      label: 'Address (optional)',
      icon: Icons.home_outlined,
      capitalization: TextCapitalization.words,
      onChanged: (v) => _update(_form.copyWith(address: v)),
    ),
    const SizedBox(height: 12),
    _responsivePair(
      width,
      _field(
        name: 'city',
        controller: _c('city'),
        label: 'City',
        capitalization: TextCapitalization.words,
        onChanged: (v) => _update(_form.copyWith(city: v)),
      ),
      _field(
        name: 'state',
        controller: _c('state'),
        label: 'State',
        capitalization: TextCapitalization.words,
        onChanged: (v) => _update(_form.copyWith(state: v)),
      ),
    ),
    const SizedBox(height: 12),
    _field(
      name: 'country',
      controller: _c('country'),
      label: 'Country',
      icon: Icons.public_outlined,
      capitalization: TextCapitalization.words,
      onChanged: (v) => _update(_form.copyWith(country: v)),
    ),
  ];

  Widget _genderField(AppPalette p) => DropdownButtonFormField<String>(
    // The option list ADOPTS whatever is stored, so a value written by the
    // onboarding wizard, a legacy build or TrainerHQ can never be missing from
    // the items — the assertion that made this whole screen un-openable.
    initialValue: _form.gender,
    isExpanded: true,
    decoration: const InputDecoration(
      labelText: 'Gender (optional)',
      prefixIcon: Icon(Icons.wc_outlined),
    ),
    items: [
      DropdownMenuItem<String>(
        value: null,
        child: Text('Not specified', style: TextStyle(color: p.textMuted)),
      ),
      ...genderOptionsFor(
        _form.gender,
      ).map((v) => DropdownMenuItem(value: v, child: Text(v))),
    ],
    onChanged: (value) => _update(_form.copyWith(gender: value)),
  );

  Widget _dobField(AppPalette p) {
    final error = _errorFor(ProfileFormField.dob);
    // `button: true` WITHOUT a custom label: the decorator already announces
    // "Date of birth (optional)", the chosen date, and — critically — any error
    // text. Overriding the label with our own would have replaced the error
    // announcement with a static sentence, so a screen-reader user would never
    // hear why their save was refused.
    return Semantics(
      button: true,
      child: InkWell(
        key: _key(ProfileFormField.dob),
        onTap: _pickDob,
        borderRadius: AppRadii.smR,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Date of birth (optional)',
            errorText: error,
            prefixIcon: const Icon(Icons.cake_outlined),
            suffixIcon: _form.dob == null
                ? const Icon(Icons.calendar_today_outlined)
                : IconButton(
                    tooltip: 'Clear date of birth',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _update(_form.copyWith(dob: null)),
                  ),
          ),
          child: Text(
            _form.dob == null
                ? 'Select date'
                : DateFormat('dd MMM yyyy').format(_form.dob!),
            style: TextStyle(
              color: _form.dob == null ? p.textMuted : p.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(AppPalette p, String title, {required Widget child}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              color: p.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: AppRadii.cardR,
              border: Border.all(color: p.border),
            ),
            child: child,
          ),
        ],
      );

  Widget _photo(AppPalette p) {
    final url = _form.photoUrl;
    return Row(
      children: [
        Semantics(
          button: true,
          label: url.isEmpty ? 'Add profile photo' : 'Change profile photo',
          child: GestureDetector(
            onTap: _uploadingPhoto ? null : _photoSheet,
            child: Container(
              width: 68,
              height: 68,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.surfaceAlt,
                border: Border.all(color: p.accent, width: 2),
              ),
              child: _uploadingPhoto
                  ? Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: p.accent,
                        ),
                      ),
                    )
                  : url.isEmpty
                  ? Icon(Icons.person_outline, color: p.textMuted, size: 30)
                  : CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          Icon(Icons.person_outline, color: p.textMuted),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile photo',
                style: GoogleFonts.poppins(
                  color: p.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _uploadingPhoto
                    ? 'Uploading…'
                    : url.isEmpty
                    ? 'Your coach will see your initials.'
                    : 'Visible to your coach.',
                style: GoogleFonts.poppins(color: p.textMuted, fontSize: 11),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _uploadingPhoto ? null : _photoSheet,
                icon: const Icon(Icons.camera_alt_outlined, size: 17),
                label: Text(url.isEmpty ? 'Add photo' : 'Change photo'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _unitToggle(
    AppPalette p, {
    required String value,
    required List<(String, String)> options,
    required ValueChanged<String> onChanged,
    required String semantics,
  }) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: p.surfaceAlt,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: p.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: options.map((o) {
        final selected = value == o.$1;
        return Semantics(
          button: true,
          selected: selected,
          label: '$semantics ${o.$2}',
          // The pill's own 'cm' / 'lb' glyph would otherwise be announced
          // alongside the label, so a screen reader read "cm, Height unit cm".
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () => onChanged(o.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? p.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                o.$2,
                style: GoogleFonts.poppins(
                  color: selected ? Colors.white : p.textMuted,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    ),
  );

  Widget _responsivePair(double width, Widget first, Widget second) {
    if (width < 560) {
      return Column(children: [first, const SizedBox(height: 12), second]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }

  /// One text field.
  ///
  /// [scrollKey] anchors the error-scroll target and goes on a wrapper, so the
  /// field itself always carries a STABLE `ValueKey` derived from its
  /// controller name. Device tests cannot address these fields any other way:
  /// an `InputDecoration` label is not hit-testable, and positional lookup is
  /// meaningless in a lazily built list.
  Widget _field({
    Key? scrollKey,
    required String name,
    required TextEditingController controller,
    required String label,
    required ValueChanged<String> onChanged,
    IconData? icon,
    bool number = false,
    bool phone = false,
    bool email = false,
    String? helper,
    String? errorText,
    TextCapitalization capitalization = TextCapitalization.none,
  }) => KeyedSubtree(
    key: scrollKey,
    child: TextField(
      key: ValueKey(fieldKey(name)),
      controller: controller,
      onChanged: onChanged,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : phone
          ? TextInputType.phone
          : email
          ? TextInputType.emailAddress
          : TextInputType.text,
      inputFormatters: number
          ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))]
          : phone
          ? [FilteringTextInputFormatter.allow(RegExp(r'[\d+()\- ]'))]
          : null,
      textCapitalization: capitalization,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        errorText: errorText,
        prefixIcon: icon == null ? null : Icon(icon),
      ),
    ),
  );
}

/// The stable widget key for one editor field. Public so a device test can
/// address a field without depending on its label text or its position.
String fieldKey(String name) => 'editProfile.$name';
