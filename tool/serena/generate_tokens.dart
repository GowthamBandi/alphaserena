// Serena Design System — deterministic token generator (M1 foundation).
// Pure Dart (no Flutter): reads serena.tokens.json (the single source of truth)
// and emits generated/serena_tokens.g.dart — an analyzable, const, Flutter-free
// token layer. Deterministic: same input -> byte-identical output (drift-guard checks this).
//
// Usage:  dart run tools/generate_tokens.dart [tokensJsonPath] [outDartPath]
// Defaults: serena.tokens.json  ->  generated/serena_tokens.g.dart

import 'dart:convert';
import 'dart:io';

const _header = '''
// GENERATED FILE — DO NOT EDIT BY HAND.
// Source of truth: serena.tokens.json (Serena Design System, Option B / RFC-DISTRIBUTION).
// Regenerate: dart run tools/generate_tokens.dart. Drift-guard CI asserts byte-parity.
// Flutter-free raw token layer; the theme-integration binding (SerenaPalette ThemeExtension)
// consumes these. Brand: black-&-red (RFC-BRAND); orange = secondary semantic only.

// ignore_for_file: constant_identifier_names
''';

String _gen(Map<String, dynamic> t) {
  final b = StringBuffer()..write(_header);
  final meta = t[r'$meta'] as Map<String, dynamic>;
  b.writeln('\n// SDS version: ${meta['version']} · fontsDeferred: ${meta['fontsDeferred']}');

  // ---- Colors (raw ARGB ints, light + dark) ----
  b.writeln('\n/// Raw ARGB color tokens (0xAARRGGBB). Light/Dark suffix.');
  b.writeln('class SerenaColor {');
  b.writeln('  const SerenaColor._();');
  final color = t['color'] as Map<String, dynamic>;
  for (final group in color.keys) {
    if (group.startsWith('_')) continue; // skip meta/notes
    final entries = color[group] as Map<String, dynamic>;
    for (final name in entries.keys) {
      if (name.startsWith('_')) continue; // skip meta/notes
      final v = entries[name] as Map<String, dynamic>;
      if (v.containsKey('light') && v.containsKey('dark')) {
        b.writeln('  static const int ${name}Light = ${v['light']};');
        b.writeln('  static const int ${name}Dark = ${v['dark']};');
      } else {
        // {fill:{light,dark}, on, subtleBg:{light,dark}}
        if (v['fill'] is Map) {
          final fill = v['fill'] as Map<String, dynamic>;
          b.writeln('  static const int ${name}FillLight = ${fill['light']};');
          b.writeln('  static const int ${name}FillDark = ${fill['dark']};');
        }
        if (v.containsKey('on')) b.writeln('  static const int ${name}On = ${v['on']};');
        if (v['subtleBg'] is Map) {
          final s = v['subtleBg'] as Map<String, dynamic>;
          b.writeln('  static const int ${name}SubtleBgLight = ${s['light']};');
          b.writeln('  static const int ${name}SubtleBgDark = ${s['dark']};');
        }
      }
    }
  }
  b.writeln('}');

  // ---- Typography (Flutter-free descriptor) ----
  b.writeln('\n/// Type token: font family name + metrics (no Flutter dep).');
  b.writeln('class SerenaTextToken {');
  b.writeln('  final String font; final double size; final int weight;');
  b.writeln('  final double tracking; final double height; final bool tabular;');
  b.writeln('  const SerenaTextToken(this.font, this.size, this.weight, this.tracking, this.height, {this.tabular = false});');
  b.writeln('}');
  b.writeln('class SerenaText {');
  b.writeln('  const SerenaText._();');
  final text = t['text'] as Map<String, dynamic>;
  for (final name in text.keys) {
    final v = text[name] as Map<String, dynamic>;
    final tab = v['tabular'] == true ? ', tabular: true' : '';
    b.writeln("  static const SerenaTextToken $name = SerenaTextToken('${v['font']}', ${_d(v['size'])}, ${v['weight']}, ${_d(v['tracking'])}, ${_d(v['height'])}$tab);");
  }
  b.writeln('}');

  // ---- Scales: space / radius / icon ----
  _scale(b, 'SerenaSpace', t['space'] as Map<String, dynamic>);
  _scale(b, 'SerenaRadius', t['radius'] as Map<String, dynamic>);
  _scale(b, 'SerenaIcon', t['icon'] as Map<String, dynamic>);

  // ---- Density ----
  b.writeln('\n/// Density token: vertical rhythm (references SerenaSpace).');
  b.writeln('class SerenaDensityToken { final double rowInset; final double gap; const SerenaDensityToken(this.rowInset, this.gap); }');
  b.writeln('class SerenaDensity {');
  b.writeln('  const SerenaDensity._();');
  final density = t['density'] as Map<String, dynamic>;
  for (final name in density.keys) {
    if (name.startsWith('_')) continue;
    final v = density[name] as Map<String, dynamic>;
    b.writeln('  static const SerenaDensityToken $name = SerenaDensityToken(SerenaSpace.${v['rowInset']}, SerenaSpace.${v['gap']});');
  }
  b.writeln('}');

  // ---- Elevation (shadow layers) ----
  b.writeln('\n/// Shadow layer descriptor (Flutter-free).');
  b.writeln('class SerenaShadowLayer {');
  b.writeln('  final int colorLight; final int colorDark; final double blur; final double spread; final double dx; final double dy;');
  b.writeln('  const SerenaShadowLayer(this.colorLight, this.colorDark, this.blur, this.spread, this.dx, this.dy);');
  b.writeln('}');
  b.writeln('class SerenaElevation {');
  b.writeln('  const SerenaElevation._();');
  final elev = t['elevation'] as Map<String, dynamic>;
  for (final name in elev.keys) {
    final layers = (elev[name] as Map<String, dynamic>)['layers'] as List;
    final parts = layers.map((l) {
      final m = l as Map<String, dynamic>;
      return 'SerenaShadowLayer(${m['colorLight']}, ${m['colorDark']}, ${_d(m['blur'])}, ${_d(m['spread'])}, ${_d(m['dx'])}, ${_d(m['dy'])})';
    }).join(', ');
    b.writeln('  static const List<SerenaShadowLayer> $name = [$parts];');
  }
  b.writeln('}');

  // ---- Motion ----
  b.writeln('\n/// Motion token: duration (ms) + easing name.');
  b.writeln('class SerenaMotionToken { final int ms; final String easing; const SerenaMotionToken(this.ms, this.easing); }');
  b.writeln('class SerenaMotion {');
  b.writeln('  const SerenaMotion._();');
  final motion = t['motion'] as Map<String, dynamic>;
  for (final name in motion.keys) {
    final v = motion[name] as Map<String, dynamic>;
    b.writeln("  static const SerenaMotionToken $name = SerenaMotionToken(${v['ms']}, '${v['easing']}');");
  }
  b.writeln('}');

  // ---- Border (focus ring / neon edge) ----
  b.writeln('\nclass SerenaBorder {');
  b.writeln('  const SerenaBorder._();');
  final border = t['border'] as Map<String, dynamic>;
  final fr = border['focusRing'] as Map<String, dynamic>;
  b.writeln('  static const int focusRingColor = ${fr['color']};');
  b.writeln('  static const double focusRingWidth = ${_d(fr['width'])};');
  b.writeln('  static const double focusRingOffset = ${_d(fr['offset'])};');
  final ne = border['neonEdge'] as Map<String, dynamic>;
  b.writeln('  static const int neonEdgeColor = ${ne['color']};');
  b.writeln('  static const double neonEdgeWidth = ${_d(ne['width'])};');
  b.writeln('}');

  return b.toString();
}

void _scale(StringBuffer b, String cls, Map<String, dynamic> m) {
  b.writeln('\nclass $cls {');
  b.writeln('  const $cls._();');
  for (final k in m.keys) {
    b.writeln('  static const double $k = ${_d(m[k])};');
  }
  b.writeln('}');
}

String _d(dynamic n) {
  final d = (n as num).toDouble();
  return d == d.roundToDouble() ? '${d.toInt()}.0' : '$d';
}

void main(List<String> args) {
  final inPath = args.isNotEmpty ? args[0] : 'serena.tokens.json';
  final outPath = args.length > 1 ? args[1] : 'generated/serena_tokens.g.dart';
  final tokens = jsonDecode(File(inPath).readAsStringSync()) as Map<String, dynamic>;
  final out = _gen(tokens);
  final f = File(outPath)..createSync(recursive: true);
  f.writeAsStringSync(out);
  stdout.writeln('Generated $outPath (${out.length} bytes) from $inPath');
}
