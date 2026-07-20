import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// The ONE transformation-visibility chooser (V1.2 consistency): the same
/// segmented control, wording and validation for every entry type —
/// measurements, weight and photos. Value is NULL until the member consciously
/// chooses; callers gate their save on [ensureChosen].
///
/// 'shared'  → the coach can review this progress.
/// 'private' → only the member sees it (the coach app shows a locked
///             "Hidden by member" row and hides the entry everywhere else).
class VisibilityChoice extends StatelessWidget {
  final String? value; // null | 'shared' | 'private'
  final ValueChanged<String> onChanged;

  const VisibilityChoice({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static const String shared = 'shared';
  static const String private = 'private';

  /// Shared validation: true when a choice was made; otherwise shows the one
  /// canonical prompt and returns false. Never silently defaults.
  static bool ensureChosen(String? value) {
    if (value == shared || value == private) return true;
    Get.snackbar('Choose visibility',
        'Please choose whether to share this progress with your coach.');
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: p.border),
          ),
          child: Row(
            children: [
              _seg(p, 'Share with coach', Icons.visibility_outlined,
                  value == shared, () => onChanged(shared)),
              _seg(p, 'Keep private', Icons.lock_outline, value == private,
                  () => onChanged(private)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            switch (value) {
              shared => 'Shared — your coach can review this progress.',
              private => 'Private — only you can see this progress.',
              _ => 'Choose who can see this progress before saving.',
            },
            style: GoogleFonts.poppins(color: p.textMuted, fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _seg(AppPalette p, String label, IconData icon, bool selected,
      VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: selected
                ? p.accent.withValues(alpha: 0.16)
                : Colors.transparent,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: selected ? p.accent : p.textMuted),
              const SizedBox(width: 5),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        color: selected ? p.accent : p.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
