// ═══════════════════════════════════════════════════════════════════════════
// WEEKLY REPORTS — THE QUESTION RENDERER REGISTRY
//
// THIS FILE IS SHARED BYTE-FOR-BYTE BETWEEN alphaserena AND trainersHQ, and is
// pinned by `weekly_report_engine_parity_test.dart` alongside the engine.
//
// WHY IT IS SHARED. The coach's live preview must render the EXACT widget the
// member will answer. If the builder drew its own approximation, "preview" would
// be a second rendering of the same fact — and the two would drift the first
// time a bound changed. The coach's preview and the member's form are the same
// code path; that is what makes the preview trustworthy.
//
// ── THE ONE RULE: NO SWITCH ON QUESTION TYPE ───────────────────────────────
//
// Dispatch is a MAP LOOKUP (`rendererFor`). Adding a question type is one row
// in the engine's registry + one row here + one contract case — never a new
// branch inside a screen. A type this build does not know renders an honest
// "needs an app update" card and the member can still submit the rest of their
// report; it never crashes and never silently omits a question.
//
// ── NO BUSINESS LOGIC LIVES HERE ───────────────────────────────────────────
//
// Bounds, options, units, visibility, completion and validity all come from
// `question_engine.dart`. This file decides pixels and nothing else. It reads
// `q.bounds` rather than `q.validation`, so a type default the coach never
// overrode is still honoured.
//
// ── NO PLUGINS ─────────────────────────────────────────────────────────────
//
// Photo picking is injected as a callback (`onPickPhotos`), so this file depends
// on Flutter and the engine only. That keeps it byte-identical across two apps
// with different plugin sets, and testable in a plain widget test.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/app_text.dart';
import 'question_engine.dart';

/// Everything a renderer needs. Deliberately a single object so adding a
/// capability never changes 22 signatures.
class QuestionRenderContext {
  final QuestionDefinition question;

  /// The current answer, in the engine's coerced form (or null).
  final dynamic value;

  /// Reports a new answer. Never called in [readOnly].
  final ValueChanged<dynamic> onChanged;

  /// A submitted report, or the coach's review view. Controls are inert and
  /// styled as a record rather than a form.
  final bool readOnly;

  /// The engine's verdict for [value], when the surface wants errors shown.
  /// Null while a member is still typing — an error on every keystroke is
  /// noise, so the caller decides when a question has been "touched".
  final AnswerVerdict? verdict;

  /// Supplies photo URLs for a `photos` question. Null disables the control —
  /// which is correct on the coach's side, where photos are read-only.
  final Future<List<String>> Function()? onPickPhotos;

  const QuestionRenderContext({
    required this.question,
    required this.value,
    required this.onChanged,
    this.readOnly = false,
    this.verdict,
    this.onPickPhotos,
  });

  QuestionRenderContext copyWith({dynamic value}) => QuestionRenderContext(
        question: question,
        value: value,
        onChanged: onChanged,
        readOnly: readOnly,
        verdict: verdict,
        onPickPhotos: onPickPhotos,
      );

  bool get hasError => verdict != null && !verdict!.ok;
  String get errorText => verdict?.message ?? '';
}

typedef QuestionWidgetBuilder = Widget Function(
  BuildContext context,
  QuestionRenderContext ctx,
);

/// THE DISPATCH TABLE. A map, not a switch.
class QuestionRendererRegistry {
  QuestionRendererRegistry._();

  static final Map<String, QuestionWidgetBuilder> _builders =
      <String, QuestionWidgetBuilder>{
    // Scales — one widget, ten types. The DIFFERENCE between them lives in the
    // engine (bounds + analytics key), not here, which is why "mood" and
    // "energy" cannot drift apart visually.
    'rating': _scale,
    'mood': _scale,
    'energy': _scale,
    'stress': _scale,
    'recovery': _scale,
    'workoutSatisfaction': _scale,
    'dietSatisfaction': _scale,
    'supplementAdherence': _scale,
    'pain': _scale,
    'digestion': _scale,

    'emoji': _emoji,
    'slider': _slider,
    'yesNo': _yesNo,
    'singleChoice': _singleChoice,
    'multipleChoice': _multipleChoice,

    // Numbers — one widget, four types, differing only by unit and bounds.
    'number': _number,
    'water': _number,
    'sleep': _number,
    'weight': _number,

    'text': _text,
    'paragraph': _text,
    'photos': _photos,
  };

  /// The renderer for [type], or the honest fallback.
  static QuestionWidgetBuilder rendererFor(String type) =>
      _builders[type] ?? _unsupported;

  /// Whether this build can render [type] at all.
  static bool knows(String type) => _builders.containsKey(type);

  /// Every type this build can draw. Asserted against the engine's registry by
  /// `weekly_report_renderers_test.dart` — a type the engine accepts but nobody
  /// can draw would reach a member as an "app update needed" card.
  static List<String> get renderableTypes => _builders.keys.toList();

  /// Builds one question, chrome included.
  static Widget build(BuildContext context, QuestionRenderContext ctx) =>
      QuestionCard(ctx: ctx);
}

// ───────────────────────────────────────────────────────────────────────────
// The card — title, description, required marker, control, error
// ───────────────────────────────────────────────────────────────────────────

class QuestionCard extends StatelessWidget {
  final QuestionRenderContext ctx;
  const QuestionCard({super.key, required this.ctx});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final q = ctx.question;
    final answered = isAnswered(ctx.value);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(
          color: ctx.hasError
              ? p.error.withValues(alpha: 0.55)
              // A faint accent edge marks a question the member has answered —
              // scanning a 17-question report for what is left is the single
              // most common thing they do on this screen.
              : answered
                  ? p.accent.withValues(alpha: 0.30)
                  : p.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  q.title,
                  style: AppText.cardTitle(size: 15)
                      .copyWith(color: p.textPrimary),
                ),
              ),
              if (q.required) _RequiredMarker(answered: answered),
            ],
          ),
          if (q.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              q.description,
              style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
            ),
          ],
          const SizedBox(height: 12),
          QuestionRendererRegistry.rendererFor(q.type)(context, ctx),
          if (ctx.hasError) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.error_outline, size: 14, color: p.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    ctx.errorText,
                    style: AppText.body(size: 12).copyWith(color: p.error),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RequiredMarker extends StatelessWidget {
  final bool answered;
  const _RequiredMarker({required this.answered});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // "Required" that turns into a tick is a progress signal, not a scold. The
    // member reads the same marker as "you still owe this" and "done".
    return Container(
      margin: const EdgeInsets.only(left: 8, top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (answered ? p.accent : p.textMuted).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        answered ? 'Done' : 'Required',
        style: AppText.label(size: 10)
            .copyWith(color: answered ? p.accent : p.textMuted),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Renderers
// ───────────────────────────────────────────────────────────────────────────

/// 1..N segmented scale. Bounds come from the engine, so a coach who widens a
/// rating to 1..10 gets ten segments with no code change.
Widget _scale(BuildContext context, QuestionRenderContext ctx) {
  final p = context.palette;
  final b = ctx.question.bounds;
  final min = (b.min ?? 1).round();
  final max = (b.max ?? 5).round();
  final current = ctx.value is num ? (ctx.value as num).round() : null;
  // A 1..10 scale must not produce ten unreadable slivers on a 320dp phone.
  final wide = max - min >= 6;

  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (var v = min; v <= max; v++)
        _ScaleSegment(
          value: v,
          selected: current == v,
          compact: wide,
          onTap: ctx.readOnly ? null : () => ctx.onChanged(v),
          palette: p,
        ),
    ],
  );
}

class _ScaleSegment extends StatelessWidget {
  final int value;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;
  final AppPalette palette;

  const _ScaleSegment({
    required this.value,
    required this.selected,
    required this.compact,
    required this.onTap,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final size = compact ? 38.0 : 46.0;
    return Semantics(
      container: true,
      button: onTap != null,
      selected: selected,
      label: '$value',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? palette.accent : palette.inputFill,
            borderRadius: AppRadii.smR,
            border: Border.all(
              color: selected ? palette.accent : palette.border,
            ),
          ),
          child: Text(
            '$value',
            style: AppText.label(size: compact ? 14 : 16).copyWith(
              color: selected ? Colors.white : palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Option chips carrying the coach's emoji. The stored answer is the option ID,
/// never the glyph — so renaming an emoji never orphans a historical answer.
Widget _emoji(BuildContext context, QuestionRenderContext ctx) {
  final p = context.palette;
  final selected = ctx.value?.toString();
  return Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final o in ctx.question.options)
        GestureDetector(
          onTap: ctx.readOnly ? null : () => ctx.onChanged(o.id),
          child: Semantics(
            container: true,
            selected: selected == o.id,
            label: o.label,
            child: Container(
              width: 62,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected == o.id ? p.accent.withValues(alpha: 0.12)
                    : p.inputFill,
                borderRadius: AppRadii.smR,
                border: Border.all(
                  color: selected == o.id ? p.accent : p.border,
                ),
              ),
              child: Column(
                children: [
                  Text(o.emoji.isEmpty ? '•' : o.emoji,
                      style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 4),
                  Text(
                    o.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(size: 10.5)
                        .copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

Widget _slider(BuildContext context, QuestionRenderContext ctx) {
  final p = context.palette;
  final b = ctx.question.bounds;
  final min = (b.min ?? 0).toDouble();
  final max = (b.max ?? 100).toDouble();
  final step = (b.step ?? 1).toDouble();
  final raw = ctx.value is num ? (ctx.value as num).toDouble() : min;
  final v = raw.clamp(min, max).toDouble();
  final divisions = step > 0 && max > min ? ((max - min) / step).round() : null;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _plainNum(v) + (ctx.question.unit.isEmpty ? '' : ' ${ctx.question.unit}'),
        style: AppText.title(size: 20).copyWith(color: p.accent),
      ),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: p.accent,
          inactiveTrackColor: p.inputFill,
          thumbColor: p.accent,
          overlayColor: p.accent.withValues(alpha: 0.12),
        ),
        child: Slider(
          value: v,
          min: min,
          max: max,
          divisions: (divisions != null && divisions > 0) ? divisions : null,
          onChanged: ctx.readOnly ? null : (nv) => ctx.onChanged(nv),
        ),
      ),
    ],
  );
}

Widget _yesNo(BuildContext context, QuestionRenderContext ctx) {
  final p = context.palette;
  final v = ctx.value is bool ? ctx.value as bool : null;
  Widget opt(String label, bool val) {
    final on = v == val;
    return Expanded(
      child: GestureDetector(
        onTap: ctx.readOnly ? null : () => ctx.onChanged(val),
        child: Semantics(
          container: true,
          selected: on,
          label: label,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? p.accent : p.inputFill,
              borderRadius: AppRadii.smR,
              border: Border.all(color: on ? p.accent : p.border),
            ),
            child: Text(
              label,
              style: AppText.label(size: 14).copyWith(
                color: on ? Colors.white : p.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  return Row(children: [opt('Yes', true), const SizedBox(width: 10), opt('No', false)]);
}

Widget _singleChoice(BuildContext context, QuestionRenderContext ctx) =>
    _choiceChips(context, ctx, multi: false);

Widget _multipleChoice(BuildContext context, QuestionRenderContext ctx) =>
    _choiceChips(context, ctx, multi: true);

Widget _choiceChips(
  BuildContext context,
  QuestionRenderContext ctx, {
  required bool multi,
}) {
  final p = context.palette;
  final selected = <String>{
    if (multi && ctx.value is List)
      ...(ctx.value as List).map((e) => e.toString())
    else if (!multi && ctx.value != null)
      ctx.value.toString(),
  };

  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final o in ctx.question.options)
        GestureDetector(
          onTap: ctx.readOnly
              ? null
              : () {
                  if (!multi) {
                    ctx.onChanged(o.id);
                    return;
                  }
                  final next = <String>{...selected};
                  if (!next.remove(o.id)) next.add(o.id);
                  // Stable order: the OPTION order the coach authored, not the
                  // order the member happened to tap. Otherwise the same answer
                  // serializes two ways and every diff looks like a change.
                  ctx.onChanged([
                    for (final x in ctx.question.options)
                      if (next.contains(x.id)) x.id,
                  ]);
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected.contains(o.id) ? p.accent : p.inputFill,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: selected.contains(o.id) ? p.accent : p.border,
              ),
            ),
            child: Text(
              o.label,
              style: AppText.body(size: 13).copyWith(
                color: selected.contains(o.id) ? Colors.white : p.textSecondary,
              ),
            ),
          ),
        ),
    ],
  );
}

Widget _number(BuildContext context, QuestionRenderContext ctx) =>
    _NumberField(ctx: ctx);

/// A stateful field so the member can type "7." on the way to "7.5" without the
/// parent rewriting the box under their fingers. The parent is told about the
/// PARSED value; the raw text stays local.
class _NumberField extends StatefulWidget {
  final QuestionRenderContext ctx;
  const _NumberField({required this.ctx});

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: _fmt(widget.ctx.value));
  }

  @override
  void didUpdateWidget(covariant _NumberField old) {
    super.didUpdateWidget(old);
    // Re-seed ONLY when the incoming value is genuinely different from what the
    // box already says. Without this guard a draft autosave round-trip moves
    // the caret to the end mid-word, on every keystroke.
    final incoming = _fmt(widget.ctx.value);
    if (incoming != _fmt(_parse(_c.text))) _c.text = incoming;
  }

  static String _fmt(dynamic v) {
    if (v is! num) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  static num? _parse(String s) => num.tryParse(s.trim());

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ctx = widget.ctx;
    final b = ctx.question.bounds;
    final decimals = b.decimals ?? 2;

    return TextField(
      controller: _c,
      enabled: !ctx.readOnly,
      keyboardType: TextInputType.numberWithOptions(decimal: decimals > 0),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          decimals > 0 ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
        ),
      ],
      style: AppText.label(size: 16).copyWith(color: p.textPrimary),
      onChanged: (s) => ctx.onChanged(_parse(s)),
      decoration: InputDecoration(
        filled: true,
        fillColor: p.inputFill,
        hintText: _hint(b),
        hintStyle: AppText.body(size: 14).copyWith(color: p.textMuted),
        suffixText: ctx.question.unit.isEmpty ? null : ctx.question.unit,
        suffixStyle: AppText.body(size: 13).copyWith(color: p.textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: AppRadii.smR,
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.smR,
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.smR,
          borderSide: BorderSide(color: p.accent),
        ),
      ),
    );
  }

  /// The accepted range, stated up front. A member should not have to submit to
  /// discover a bound.
  static String _hint(QuestionValidation b) {
    if (b.min != null && b.max != null) {
      return '${_plainNum(b.min!)}–${_plainNum(b.max!)}';
    }
    if (b.min != null) return 'min ${_plainNum(b.min!)}';
    if (b.max != null) return 'max ${_plainNum(b.max!)}';
    return 'Enter a number';
  }
}

Widget _text(BuildContext context, QuestionRenderContext ctx) =>
    _TextAnswerField(ctx: ctx);

class _TextAnswerField extends StatefulWidget {
  final QuestionRenderContext ctx;
  const _TextAnswerField({required this.ctx});

  @override
  State<_TextAnswerField> createState() => _TextAnswerFieldState();
}

class _TextAnswerFieldState extends State<_TextAnswerField> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.ctx.value?.toString() ?? '');
  }

  @override
  void didUpdateWidget(covariant _TextAnswerField old) {
    super.didUpdateWidget(old);
    final incoming = widget.ctx.value?.toString() ?? '';
    // Same caret guard as the number field — and `trim()` on the comparison,
    // because the engine trims on coercion and would otherwise fight a member
    // who is mid-sentence with a trailing space.
    if (incoming.trim() != _c.text.trim()) _c.text = incoming;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ctx = widget.ctx;
    final multiline = ctx.question.type == 'paragraph';
    final max = ctx.question.bounds.maxLength;
    final used = _c.text.characters.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextField(
          controller: _c,
          enabled: !ctx.readOnly,
          minLines: multiline ? 4 : 1,
          maxLines: multiline ? 8 : 1,
          textCapitalization: TextCapitalization.sentences,
          style: AppText.body(size: 14.5).copyWith(color: p.textPrimary),
          onChanged: (s) {
            ctx.onChanged(s);
            if (max != null) setState(() {});
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: p.inputFill,
            hintText: multiline ? 'Write as much as you like…' : 'Your answer',
            hintStyle: AppText.body(size: 14).copyWith(color: p.textMuted),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: AppRadii.smR,
              borderSide: BorderSide(color: p.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadii.smR,
              borderSide: BorderSide(color: p.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadii.smR,
              borderSide: BorderSide(color: p.accent),
            ),
          ),
        ),
        if (max != null && !ctx.readOnly) ...[
          const SizedBox(height: 5),
          Text(
            '$used / $max',
            style: AppText.body(size: 11).copyWith(
              color: used > max ? p.error : p.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

/// Photo answers. The picker is INJECTED — this file never imports a plugin, so
/// it stays byte-identical across two apps and mounts in a plain widget test.
Widget _photos(BuildContext context, QuestionRenderContext ctx) {
  final p = context.palette;
  final urls = <String>[
    if (ctx.value is List) ...(ctx.value as List).map((e) => e.toString()),
  ];
  final cap = ctx.question.bounds.maxPhotos ?? 8;
  final canAdd = !ctx.readOnly && ctx.onPickPhotos != null && urls.length < cap;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (urls.isNotEmpty)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < urls.length; i++)
              _PhotoTile(
                url: urls[i],
                palette: p,
                onRemove: ctx.readOnly
                    ? null
                    : () => ctx.onChanged([...urls]..removeAt(i)),
              ),
          ],
        ),
      if (urls.isEmpty && ctx.readOnly)
        Text('No photos', style: AppText.body(size: 13).copyWith(color: p.textMuted)),
      if (canAdd) ...[
        if (urls.isNotEmpty) const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await ctx.onPickPhotos!();
            if (picked.isEmpty) return;
            // Respect the cap the coach set rather than accepting and having
            // the engine reject the whole answer at submit.
            ctx.onChanged([...urls, ...picked].take(cap).toList());
          },
          icon: const Icon(Icons.add_a_photo_outlined, size: 18),
          label: Text('Add photo  ·  ${urls.length}/$cap'),
          style: OutlinedButton.styleFrom(
            foregroundColor: p.accent,
            side: BorderSide(color: p.accent.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: const RoundedRectangleBorder(borderRadius: AppRadii.smR),
          ),
        ),
      ],
    ],
  );
}

class _PhotoTile extends StatelessWidget {
  final String url;
  final AppPalette palette;
  final VoidCallback? onRemove;

  const _PhotoTile({
    required this.url,
    required this.palette,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: AppRadii.smR,
          child: Container(
            width: 84,
            height: 84,
            color: palette.inputFill,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              // A broken URL must read as a broken photo, not as an empty
              // report — the member uploaded something and deserves to see so.
              errorBuilder: (_, _, _) => Icon(
                Icons.broken_image_outlined,
                color: palette.textMuted,
                size: 22,
              ),
            ),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

/// THE FORWARD-COMPATIBILITY CARD.
///
/// An older build meeting a question type shipped after it. It renders honestly,
/// does not crash, and — because the engine excludes unknown types from the
/// submit gate — never strands the member on a report they cannot complete.
Widget _unsupported(BuildContext context, QuestionRenderContext ctx) {
  final p = context.palette;
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: p.inputFill,
      borderRadius: AppRadii.smR,
      border: Border.all(color: p.border),
    ),
    child: Row(
      children: [
        Icon(Icons.system_update_alt, size: 18, color: p.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'This question needs an app update. You can still submit the rest '
            'of your report.',
            style: AppText.body(size: 12.5).copyWith(color: p.textSecondary),
          ),
        ),
      ],
    ),
  );
}

String _plainNum(num v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

// ───────────────────────────────────────────────────────────────────────────
// Section + progress chrome, shared by the member form and the coach preview
// ───────────────────────────────────────────────────────────────────────────

/// A titled group of questions. Sections come from the snapshot, so a report
/// always groups the way the coach authored it.
class ReportSectionHeader extends StatelessWidget {
  final ReportSection section;
  final int answered;
  final int total;

  const ReportSectionHeader({
    super.key,
    required this.section,
    required this.answered,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final done = total > 0 && answered >= total;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: done ? p.accent : p.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              section.title.toUpperCase(),
              style: AppText.label(size: 12).copyWith(
                color: p.textSecondary,
                letterSpacing: 1.1,
              ),
            ),
          ),
          if (total > 0)
            Text(
              '$answered/$total',
              style: AppText.body(size: 12).copyWith(
                color: done ? p.accent : p.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}

/// The submit-progress bar. Reads [ReportCompletion] from the engine — the same
/// object that decides `canSubmit`, so the bar and the button can never
/// disagree about how much is left.
class ReportProgressBar extends StatelessWidget {
  final ReportCompletion completion;
  final bool compact;

  const ReportProgressBar({
    super.key,
    required this.completion,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = completion;
    final ready = c.canSubmit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                ready
                    ? 'Ready to send'
                    : '${c.requiredAnswered} of ${c.requiredTotal} required '
                        'answered',
                style: AppText.label(size: compact ? 12 : 13).copyWith(
                  color: ready ? p.accent : p.textSecondary,
                ),
              ),
            ),
            Text(
              '${c.answered}/${c.total}',
              style: AppText.body(size: compact ? 11.5 : 12.5)
                  .copyWith(color: p.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            tween: Tween(begin: 0, end: c.progress.clamp(0.0, 1.0)),
            builder: (_, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: compact ? 4 : 6,
              backgroundColor: p.inputFill,
              valueColor: AlwaysStoppedAnimation<Color>(
                ready ? p.accent : p.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
