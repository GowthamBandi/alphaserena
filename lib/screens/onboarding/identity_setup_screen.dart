import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../controllers/home_controller.dart';
import '../../core/utils/body_units.dart';
import '../../controllers/member_controller.dart';
import '../../core/services/member_identity_service.dart';
import '../../core/widgets/gradient_button.dart';
import 'onboarding_flow_screen.dart';

/// Why this screen is open. The form and the writes are identical; only the
/// framing and what happens after saving differ.
enum IdentitySetupMode {
  /// First run, reached from Home's Getting Started card. Chains straight into
  /// the coach questionnaire when that is still pending.
  onboarding,

  /// Maintenance, reached from Profile → Personal details. Returns to Profile
  /// and never chains into onboarding.
  edit,
}

/// UMHIPP P2 — Member Identity. Writes the member-owned canonical sections
/// (`profile.identity` / `contact` / `bodyMetrics`); the P3 backend projection
/// shares only what policy allows with the coach.
///
/// Deliberately three light steps, not a form: photo (optional) → basics →
/// body metrics (optional). Only the display name is required to continue.
///
/// **This screen used to be reachable exactly once, ever.** Its only entrance
/// was Home's Getting Started card at `ClientStage.identity`, and
/// `HomeController.stage` returns `ready` as soon as a plan exists — evaluated
/// BEFORE the identity check. So a coach who assigned a plan promptly
/// permanently removed their member's only route to their own identity: no
/// photo, no date of birth, no gender, no height, no weight, in any build.
/// The more attentive the coach, the more certainly their member was locked out.
///
/// [IdentitySetupMode.edit] is the fix. Home's stage logic is deliberately
/// UNCHANGED — a delivered plan still always wins there, because hiding paid
/// content behind a profile form would be a worse product. Identity maintenance
/// simply moved to where it belongs: Profile, permanently reachable.
class IdentitySetupScreen extends StatefulWidget {
  final IdentitySetupMode mode;

  const IdentitySetupScreen({
    super.key,
    this.mode = IdentitySetupMode.onboarding,
  });

  @override
  State<IdentitySetupScreen> createState() => _IdentitySetupScreenState();
}

class _IdentitySetupScreenState extends State<IdentitySetupScreen> {
  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _card = Color(0xFF141414);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _border = Color(0xFF242424);
  static const Color _red = Color(0xFFE10600);

  final MemberIdentityService _service = MemberIdentityService();
  final MemberController _member = Get.find<MemberController>();

  final PageController _pager = PageController();
  int _step = 0;

  // Step 1 — photo
  String? _photoUrl;
  bool _uploadingPhoto = false;

  // Step 2 — basics (prefilled from repository evidence: auth + linked docs)
  // `MemberController` now resolves these through the shared identity rule and
  // returns '' when nothing is known, so no placeholder-stripping is needed
  // here any more (this field used to have to filter out the literal 'Alpha').
  late final TextEditingController _name = TextEditingController(
    text: _member.name,
  );
  late final TextEditingController _email = TextEditingController(
    text: _member.email,
  );
  final String _phone = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
  String? _gender;
  DateTime? _dob;

  // Step 3 — body metrics (optional). Entry follows the member's preferred
  // unit; storage is ALWAYS canonical metric (heightCm/weightKg).
  final TextEditingController _height = TextEditingController(); // cm
  final TextEditingController _ft = TextEditingController();
  final TextEditingController _in = TextEditingController();
  final TextEditingController _weight = TextEditingController(); // kg or lb
  String _heightUnit = 'cm'; // 'cm' | 'ftin'
  String _weightUnit = 'kg'; // 'kg' | 'lb'

  bool _saving = false;

  bool get _isEdit => widget.mode == IdentitySetupMode.edit;

  @override
  void initState() {
    super.initState();
    // Prefill the existing photo so an editing member sees the one they already
    // have instead of an empty "add a photo" target. (Leaving it null would not
    // erase the stored photo — the service merge-writes — but it would wrongly
    // imply they had never set one.)
    final existingPhoto = _member.photoUrl;
    if (existingPhoto.isNotEmpty) _photoUrl = existingPhoto;
    // Gender and date of birth were never prefilled, so re-opening the form
    // presented them as unset even when the member had already answered.
    final existingGender = _member.gender;
    if (existingGender.isNotEmpty) _gender = existingGender;
    final existingDob = _member.dob;
    if (existingDob.isNotEmpty) _dob = DateTime.tryParse(existingDob);
    // Prefill existing canonical values in the member's saved display units so
    // nothing has to be re-entered.
    final profile = _member.profile.value?['profile'];
    if (profile is Map) {
      final units = (profile['preferences'] is Map)
          ? (profile['preferences'] as Map)['units']
          : null;
      if (units is Map) {
        if (units['height'] == 'ftin') _heightUnit = 'ftin';
        if (units['weight'] == 'lb') _weightUnit = 'lb';
      }
      final bm = profile['bodyMetrics'];
      if (bm is Map) {
        final h = bm['heightCm'];
        if (h is num) {
          if (_heightUnit == 'ftin') {
            final (f, i) = BodyUnits.cmToFtIn(h.toDouble());
            _ft.text = '$f';
            _in.text = '$i';
          } else {
            _height.text = BodyUnits.trim(h.toDouble());
          }
        }
        final w = bm['weightKg'];
        if (w is num) {
          _weight.text = BodyUnits.trim(
            _weightUnit == 'lb' ? BodyUnits.kgToLb(w.toDouble()) : w.toDouble(),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    _name.dispose();
    _email.dispose();
    _height.dispose();
    _ft.dispose();
    _in.dispose();
    _weight.dispose();
    super.dispose();
  }

  // ── Photo ────────────────────────────────────────────────────────────

  Future<void> _pickPhoto(ImageSource source) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _uploadingPhoto) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return; // member cancelled — not an error
      setState(() => _uploadingPhoto = true);
      final url = await _service.uploadPhoto(uid, File(picked.path));
      if (!mounted) return;
      setState(() {
        _photoUrl = url;
        _uploadingPhoto = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadingPhoto = false);
      Get.snackbar('Upload failed', 'Please try again.');
    }
  }

  void _photoSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: _red),
              title: Text(
                'Take a photo',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              onTap: () {
                Get.back();
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: _red),
              title: Text(
                'Choose from gallery',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              onTap: () {
                Get.back();
                _pickPhoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Navigation / validation ──────────────────────────────────────────

  void _next() {
    if (_step == 1) {
      final err = _validateBasics();
      if (err != null) {
        Get.snackbar('Almost there', err);
        return;
      }
    }
    if (_step < 2) {
      FocusScope.of(context).unfocus();
      _pager.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step == 0) return;
    _pager.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  String? _validateBasics() {
    if (_name.text.trim().length < 2) return 'Please enter your name.';
    final email = _email.text.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'That email doesn\'t look right.';
    }
    return null;
  }

  // ── Unit switching (lossless: converts whatever is already entered) ──

  void _setHeightUnit(String unit) {
    if (unit == _heightUnit) return;
    setState(() {
      if (unit == 'ftin') {
        final cm = double.tryParse(_height.text.trim());
        if (cm != null) {
          final (f, i) = BodyUnits.cmToFtIn(cm);
          _ft.text = '$f';
          _in.text = '$i';
        }
      } else {
        final f = int.tryParse(_ft.text.trim());
        final i = int.tryParse(_in.text.trim());
        if (f != null || i != null) {
          _height.text = BodyUnits.trim(BodyUnits.ftInToCm(f ?? 0, i ?? 0));
        }
      }
      _heightUnit = unit;
    });
  }

  void _setWeightUnit(String unit) {
    if (unit == _weightUnit) return;
    setState(() {
      final v = double.tryParse(_weight.text.trim());
      if (v != null) {
        _weight.text = BodyUnits.trim(
          unit == 'lb' ? BodyUnits.kgToLb(v) : BodyUnits.lbToKg(v),
        );
      }
      _weightUnit = unit;
    });
  }

  /// Canonical height in cm from whatever unit is active. Returns null when
  /// empty; throws [FormatException] with a human message when out of range —
  /// impossible values are REJECTED, never silently dropped.
  double? _canonicalHeightCm() {
    if (_heightUnit == 'ftin') {
      final ftText = _ft.text.trim();
      final inText = _in.text.trim();
      if (ftText.isEmpty && inText.isEmpty) return null;
      final f = int.tryParse(ftText) ?? 0;
      final i = int.tryParse(inText) ?? 0;
      final cm = BodyUnits.ftInToCm(f, i);
      if (!BodyUnits.isValidHeightCm(cm)) {
        throw const FormatException(
          'Height must be between 3 ft 4 in and 8 ft 2 in.',
        );
      }
      return cm;
    }
    final t = _height.text.trim();
    if (t.isEmpty) return null;
    final cm = double.tryParse(t);
    if (cm == null || !BodyUnits.isValidHeightCm(cm)) {
      throw const FormatException('Height must be between 100 and 250 cm.');
    }
    return cm;
  }

  double? _canonicalWeightKg() {
    final t = _weight.text.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    final kg = v == null
        ? null
        : (_weightUnit == 'lb' ? BodyUnits.lbToKg(v) : v);
    if (kg == null || !BodyUnits.isValidWeightKg(kg)) {
      throw FormatException(
        _weightUnit == 'lb'
            ? 'Weight must be between 44 and 880 lb.'
            : 'Weight must be between 20 and 400 kg.',
      );
    }
    return kg;
  }

  Future<void> _finish() async {
    if (_saving) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final double? heightCm;
    final double? weightKg;
    try {
      heightCm = _canonicalHeightCm();
      weightKg = _canonicalWeightKg();
    } on FormatException catch (e) {
      Get.snackbar('Check your details', e.message);
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.save(
        uid,
        displayName: _name.text.trim(),
        photoUrl: _photoUrl,
        gender: _gender,
        dob: _dob == null ? null : DateFormat('yyyy-MM-dd').format(_dob!),
        phone: _phone,
        email: _email.text.trim(),
        heightCm: heightCm,
        weightKg: weightKg,
        heightUnit: _heightUnit,
        weightUnit: _weightUnit,
      );
      Get.back();
      if (_isEdit) {
        // Maintenance from Profile: return to Profile and confirm. Never chain
        // into the coach questionnaire — the member came here to change a
        // detail, not to be pulled back into onboarding.
        Get.snackbar(
          'Saved',
          'Your details have been updated.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
      // Home's stage tracker (streamed clientProfiles) advances on its own.
      // Chain straight into the coach questionnaire when it's still pending —
      // one continuous journey, no extra tap on Home in between.
      if (Get.isRegistered<HomeController>() &&
          !Get.find<HomeController>().onboardingDone) {
        Get.to(() => const OnboardingFlowScreen());
      }
    } catch (_) {
      Get.snackbar('Could not save', 'Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: PageView(
                controller: _pager,
                // Steps are gated by the buttons (validation runs on Next).
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _step = i),
                children: [_stepPhoto(), _stepBasics(), _stepBody()],
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // In edit mode the first step must also be dismissible — the
              // member arrived from Profile and has to be able to leave.
              if (_step > 0 || _isEdit)
                IconButton(
                  tooltip: _step > 0 ? 'Back' : 'Close',
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  onPressed: _saving
                      ? null
                      : (_step > 0 ? _back : () => Get.back()),
                  icon: Icon(
                    _step > 0 ? Icons.arrow_back_ios_new : Icons.close,
                    color: Colors.white,
                    size: _step > 0 ? 18 : 22,
                  ),
                ),
              const Spacer(),
              Text(
                _isEdit ? '${_step + 1} of 3' : 'Step ${_step + 1} of 3',
                style: GoogleFonts.poppins(color: _muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (_step + 1) / 3,
              minHeight: 5,
              backgroundColor: _card,
              color: _red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: GradientButton(
        label: _step < 2
            ? 'Continue'
            : (_isEdit ? 'Save changes' : 'Complete Setup'),
        showChevron: _step < 2,
        isLoading: _saving || _uploadingPhoto,
        onPressed: _next,
      ),
    );
  }

  Widget _page({required List<Widget> children}) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );

  Widget _title(String big, String sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        big,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        sub,
        style: GoogleFonts.poppins(color: _muted, fontSize: 13.5, height: 1.45),
      ),
      const SizedBox(height: 26),
    ],
  );

  // Step 1 — welcome + photo
  Widget _stepPhoto() {
    return _page(
      children: [
        _title(
          _isEdit ? 'Your photo' : "Let's personalize your coaching",
          _isEdit
              ? 'Tap to change your photo, or leave it as it is.'
              : 'Add a photo so your coach knows who they\'re training. You can skip this and add one later.',
        ),
        Center(
          child: Semantics(
            button: true,
            label: _photoUrl == null
                ? 'Add profile photo'
                : 'Change profile photo',
            child: GestureDetector(
              onTap: _uploadingPhoto ? null : _photoSheet,
              child: Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _card,
                  border: Border.all(
                    color: _photoUrl != null ? _red : _border,
                    width: 2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _uploadingPhoto
                    ? const Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: _red,
                          ),
                        ),
                      )
                    : _photoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: _photoUrl!,
                        fit: BoxFit.cover,
                      )
                    : const Icon(
                        Icons.add_a_photo_outlined,
                        color: _muted,
                        size: 40,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            _photoUrl != null ? 'Tap to change' : 'Tap to add a photo',
            style: GoogleFonts.poppins(color: _muted, fontSize: 12.5),
          ),
        ),
        const SizedBox(height: 26),
        // TRUTHFUL PRIVACY COPY. This used to read "Your profile is private.
        // Only what you choose to share is visible to your coach." — which
        // described the UMHIPP design rather than the running system. The
        // `identity`, `contact` and `bodyMetrics` sections all carry a DEFAULT
        // visibility of `coach`, and the live P3 projection CF stamps them onto
        // the coach's record the moment this form is saved. The member was never
        // offered the choice the sentence claimed they had made.
        //
        // Profile → "What your coach can see" now shows exactly what is shared,
        // derived from the same policy engine that performs the projection.
        _privacyNote(
          'Your name, photo and contact details are shared with your coach '
          'so they can train you — and with nobody else. You can see exactly '
          'what is shared under Profile.',
        ),
      ],
    );
  }

  // Step 2 — basics
  Widget _stepBasics() {
    return _page(
      children: [
        _title(
          _isEdit ? 'Your details' : 'Tell us about you',
          'This is how your coach will know you across your journey.',
        ),
        _label('Full name'),
        _textField(_name, hint: 'Your name', capitalize: true),
        const SizedBox(height: 16),
        _label('Email (optional)'),
        _textField(
          _email,
          hint: 'you@example.com',
          keyboard: TextInputType.emailAddress,
          autofill: AutofillHints.email,
        ),
        if (_phone.isNotEmpty) ...[
          const SizedBox(height: 16),
          _label('Phone'),
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.centerLeft,
            decoration: _boxDeco(),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, color: _muted, size: 15),
                const SizedBox(width: 8),
                Text(
                  _phone,
                  style: GoogleFonts.poppins(color: _muted, fontSize: 14.5),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _label('Gender (optional)'),
        Row(
          children: ['Male', 'Female', 'Other'].map((g) {
            final selected = _gender == g;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ChoiceChip(
                label: Text(g),
                selected: selected,
                onSelected: (_) =>
                    setState(() => _gender = selected ? null : g),
                labelStyle: GoogleFonts.poppins(
                  color: selected ? Colors.white : _muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                selectedColor: _red,
                backgroundColor: _card,
                side: BorderSide(color: selected ? _red : _border),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _label('Date of birth (optional)'),
        Semantics(
          button: true,
          label: _dob == null
              ? 'Select date of birth'
              : 'Date of birth ${DateFormat('d MMMM yyyy').format(_dob!)}',
          child: GestureDetector(
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _dob ?? DateTime(now.year - 25),
                firstDate: DateTime(now.year - 100),
                lastDate: DateTime(now.year - 10),
              );
              if (picked != null) setState(() => _dob = picked);
            },
            child: Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              decoration: _boxDeco(),
              child: Row(
                children: [
                  const Icon(Icons.cake_outlined, color: _muted, size: 16),
                  const SizedBox(width: 10),
                  Text(
                    _dob == null
                        ? 'Select your birthday'
                        : DateFormat('d MMM yyyy').format(_dob!),
                    style: GoogleFonts.poppins(
                      color: _dob == null ? _muted : Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Step 3 — body metrics
  Widget _stepBody() {
    const decimal = TextInputType.numberWithOptions(decimal: true);
    return _page(
      children: [
        _title(
          _isEdit ? 'Height & weight' : 'Your starting point',
          _isEdit
              ? 'Update these whenever they change. Your weight history lives in Progress.'
              : 'Optional — helps your coach tailor your plan from day one. You can update these anytime.',
        ),
        Row(
          children: [
            _label('Height'),
            const Spacer(),
            _unitToggle(
              value: _heightUnit,
              options: const [('cm', 'cm'), ('ftin', 'ft/in')],
              onChanged: _setHeightUnit,
              semantics: 'Height unit',
            ),
          ],
        ),
        if (_heightUnit == 'cm')
          _textField(_height, hint: 'e.g. 172', keyboard: decimal)
        else
          Row(
            children: [
              Expanded(
                child: _textField(
                  _ft,
                  hint: 'ft',
                  keyboard: TextInputType.number,
                  suffix: 'ft',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _textField(
                  _in,
                  hint: 'in',
                  keyboard: TextInputType.number,
                  suffix: 'in',
                ),
              ),
            ],
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            _label('Weight'),
            const Spacer(),
            _unitToggle(
              value: _weightUnit,
              options: const [('kg', 'kg'), ('lb', 'lb')],
              onChanged: _setWeightUnit,
              semantics: 'Weight unit',
            ),
          ],
        ),
        _textField(
          _weight,
          hint: _weightUnit == 'lb' ? 'e.g. 150' : 'e.g. 68',
          keyboard: decimal,
          suffix: _weightUnit,
        ),
        const SizedBox(height: 26),
        _privacyNote(
          'Body metrics are shared with your coach so your plan '
          'fits you — never with anyone else.',
        ),
      ],
    );
  }

  /// Native-feeling segmented unit switch — two pills, one tap, instant
  /// conversion of whatever is already typed (never a dropdown or dialog).
  Widget _unitToggle({
    required String value,
    required List<(String, String)> options,
    required ValueChanged<String> onChanged,
    required String semantics,
  }) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((o) {
          final selected = value == o.$1;
          return Semantics(
            button: true,
            selected: selected,
            label: '$semantics ${o.$2}',
            child: GestureDetector(
              onTap: () => onChanged(o.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: selected ? _red : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  o.$2,
                  style: GoogleFonts.poppins(
                    color: selected ? Colors.white : _muted,
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
  }

  // ── Small shared widgets ─────────────────────────────────────────────

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: GoogleFonts.poppins(
        color: Colors.white,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  BoxDecoration _boxDeco() => BoxDecoration(
    color: _card,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: _border),
  );

  Widget _textField(
    TextEditingController c, {
    required String hint,
    TextInputType keyboard = TextInputType.text,
    String? autofill,
    bool capitalize = false,
    String? suffix,
  }) {
    return Container(
      height: 54,
      decoration: _boxDeco(),
      alignment: Alignment.center,
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        autofillHints: autofill == null ? null : [autofill],
        textCapitalization: capitalize
            ? TextCapitalization.words
            : TextCapitalization.none,
        cursorColor: _red,
        style: GoogleFonts.poppins(color: Colors.white, fontSize: 14.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.poppins(color: _muted, fontSize: 13.5),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          suffixText: suffix,
          suffixStyle: GoogleFonts.poppins(color: _muted, fontSize: 13),
        ),
      ),
    );
  }

  Widget _privacyNote(String text) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _border),
    ),
    child: Row(
      children: [
        const Icon(Icons.shield_outlined, color: _red, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              color: _muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}
