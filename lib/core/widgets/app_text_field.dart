import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Standard filled text field with accent focus + optional password toggle.
class AppTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final bool isPassword;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onSubmitted;

  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
    this.onSubmitted,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TextField(
      controller: widget.controller,
      obscureText: widget.isPassword && _obscured,
      keyboardType: widget.keyboardType,
      textCapitalization: widget.textCapitalization,
      cursorColor: p.accent,
      onSubmitted: widget.onSubmitted,
      style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon:
            widget.icon != null ? Icon(widget.icon, color: p.accent) : null,
        suffixIcon: widget.isPassword
            ? IconButton(
                icon: Icon(
                  _obscured
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: p.accent,
                ),
                onPressed: () => setState(() => _obscured = !_obscured),
              )
            : null,
      ),
    );
  }
}
