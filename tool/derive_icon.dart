// One-off, build-time derivation of the launcher-icon and splash assets from
// the single source of truth `assets/alpha.png`. The source is never modified.
//
//   dart run tool/derive_icon.dart
//
// Why this exists: `alpha.png` is the full brand LOCKUP (triangle mark +
// "ALPHASERENA" wordmark + "HEALTH • FITNESS • LIFESTYLE" tagline). At a 48dp
// launcher size the wordmark is ~3px tall and the tagline ~2px, so shipping the
// lockup as the icon yields an illegible smudge; Android's adaptive mask would
// also clip it. The icon therefore uses the triangle MARK only, while the
// splash keeps the complete lockup on its own canvas.
//
// Outputs (all under assets/icon/):
//   alpha_icon.png             1024² · mark at 76% on opaque brand black
//                              → legacy Android + iOS icon (square/rounded mask)
//   alpha_icon_foreground.png  1024² · mark at 60%, transparent
//   ` `                        → Android adaptive foreground + monochrome layer
//                              + Android 12 splash icon. 60% keeps the mark
//                              inside the 66dp safe zone with inset 0.
//   alpha_splash.png           1024² · the untouched lockup, downscaled
//                              → native splash image
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Mark fraction of the icon canvas. Legacy/iOS icons show the full square (a
/// rounded mask at most), so the mark can be generous.
const double kIconMarkFraction = 0.76;

/// Android adaptive foreground: the visible window is 72/108dp and only the
/// central 66/108 (61%) is guaranteed. Pre-insetting to 60% lets us pass
/// `adaptive_icon_foreground_inset: 0` and stay safe under every mask shape.
const double kForegroundMarkFraction = 0.60;

const int kCanvas = 1024;

void main() {
  final srcFile = File('assets/alpha.png');
  if (!srcFile.existsSync()) {
    stderr.writeln(
      'FATAL: assets/alpha.png not found (cwd=${Directory.current.path})',
    );
    exit(1);
  }
  final src = img.decodePng(srcFile.readAsBytesSync());
  if (src == null) {
    stderr.writeln('FATAL: could not decode assets/alpha.png');
    exit(1);
  }
  stdout.writeln(
    'source      : assets/alpha.png ${src.width}x${src.height} '
    'channels=${src.numChannels}',
  );

  final bg = _borderColour(src);
  stdout.writeln(
    'border hex  : ${_hex(bg)}  <-- use as splash/adaptive colour',
  );

  final bands = _inkBands(src);
  if (bands.isEmpty) {
    stderr.writeln('FATAL: no artwork detected');
    exit(1);
  }
  stdout.writeln(
    'ink bands   : ${bands.map((b) => '${b.$1}-${b.$2}').join(', ')}',
  );

  // The first band from the top is the triangle mark; the later bands are the
  // wordmark and tagline, which the icon deliberately drops.
  final markBand = bands.first;
  final box = _markBox(src, markBand.$1, markBand.$2);
  stdout.writeln(
    'mark box    : x=${box.x} y=${box.y} w=${box.width} h=${box.height}',
  );
  stdout.writeln(
    'dropped     : ${bands.length - 1} lower band(s) '
    '(wordmark/tagline) — kept in the splash',
  );

  final mark = _cutout(
    img.copyCrop(src, x: box.x, y: box.y, width: box.width, height: box.height),
  );

  Directory('assets/icon').createSync(recursive: true);

  _writeIcon(
    mark: mark,
    fraction: kIconMarkFraction,
    background: bg,
    path: 'assets/icon/alpha_icon.png',
  );
  _writeIcon(
    mark: mark,
    fraction: kForegroundMarkFraction,
    background: null, // transparent
    path: 'assets/icon/alpha_icon_foreground.png',
  );

  // Splash keeps the lockup exactly as designed — only downscaled so the
  // generated density buckets stay a sane size.
  final splash = img.copyResize(
    src,
    width: kCanvas,
    height: kCanvas,
    interpolation: img.Interpolation.cubic,
  );
  File(
    'assets/icon/alpha_splash.png',
  ).writeAsBytesSync(img.encodePng(splash, level: 6));
  stdout.writeln(
    'wrote       : assets/icon/alpha_splash.png ($kCanvas²,'
    ' full lockup)',
  );
}

/// Composites [mark] centred on a [kCanvas]² canvas at [fraction] of its size,
/// preserving aspect ratio. A null [background] leaves the canvas transparent.
void _writeIcon({
  required img.Image mark,
  required double fraction,
  required img.Color? background,
  required String path,
}) {
  // A fresh 4-channel image is already zero-filled, i.e. fully transparent.
  final canvas = img.Image(width: kCanvas, height: kCanvas, numChannels: 4);
  if (background != null) img.fill(canvas, color: background);

  final target = (kCanvas * fraction).round();
  final scale = math.min(target / mark.width, target / mark.height);
  final w = math.max(1, (mark.width * scale).round());
  final h = math.max(1, (mark.height * scale).round());
  final scaled = img.copyResize(
    mark,
    width: w,
    height: h,
    interpolation: img.Interpolation.cubic,
  );

  img.compositeImage(
    canvas,
    scaled,
    dstX: ((kCanvas - w) / 2).round(),
    dstY: ((kCanvas - h) / 2).round(),
  );
  File(path).writeAsBytesSync(img.encodePng(canvas, level: 6));
  stdout.writeln(
    'wrote       : $path (mark ${(fraction * 100).round()}% of '
    '$kCanvas², ${background == null ? 'transparent' : 'opaque'})',
  );
}

/// Lifts the triangle mark off its opaque plate into a real alpha cutout.
///
/// The source has no alpha channel, so a plain crop drags the dark plate along
/// as an opaque rectangle — which would float as a visible square on the
/// adaptive-icon background and collapse the monochrome layer into a blob.
///
/// Keying on darkness is not an option: the athlete silhouettes INSIDE the
/// triangle are black, the same as the plate. Instead this exploits the mark's
/// geometry — for each row it keeps everything horizontally BETWEEN the mark's
/// edges, which spans the red triangle body and everything it encloses.
///
/// The edges are NOT taken per row in isolation. The triangle is filled with a
/// gradient, so on some rows its outermost red fades below the threshold and a
/// naive per-row span truncates, punching transparent notches through the mark
/// (measured: row 570 stopped at x=780 instead of 848). Because the shape is a
/// triangle its edges only ever widen from the apex down, so the running
/// envelope — left monotonically decreasing, right monotonically increasing —
/// is both geometrically correct and immune to those dropouts.
img.Image _cutout(img.Image mark) {
  final los = List<int>.filled(mark.height, -1);
  final his = List<int>.filled(mark.height, -1);
  for (var y = 0; y < mark.height; y++) {
    for (var x = 0; x < mark.width; x++) {
      if (_isRed(mark.getPixel(x, y))) {
        if (los[y] < 0) los[y] = x;
        his[y] = x;
      }
    }
  }

  // Rows outside the mark's true vertical extent must stay transparent, so the
  // envelope is only carried between the first and last row that has any red.
  var first = -1, last = -1;
  for (var y = 0; y < mark.height; y++) {
    if (los[y] >= 0) {
      if (first < 0) first = y;
      last = y;
    }
  }
  if (first < 0) return mark; // nothing detected — leave as-is

  final out = img.Image(width: mark.width, height: mark.height, numChannels: 4);
  var left = los[first], right = his[first];
  for (var y = first; y <= last; y++) {
    if (los[y] >= 0) {
      left = math.min(left, los[y]);
      right = math.max(right, his[y]);
    }
    // A row with no detected red inherits the carried envelope, which for a
    // triangle is the correct interpolation rather than a hole.
    for (var x = left; x <= right; x++) {
      final p = mark.getPixel(x, y);
      out.setPixelRgba(x, y, p.r.toInt(), p.g.toInt(), p.b.toInt(), 255);
    }
  }
  return out;
}

String _hex(img.Color c) =>
    '#${c.r.toInt().toRadixString(16).padLeft(2, '0')}'
            '${c.g.toInt().toRadixString(16).padLeft(2, '0')}'
            '${c.b.toInt().toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();

/// The flat padding colour, taken as the median of the outermost ring. The
/// asset's background carries a subtle radial vignette, so the BORDER colour —
/// not the centre — is what a flat window background must match to hide the
/// seam where the splash bitmap ends.
img.Color _borderColour(img.Image im) {
  final rs = <int>[], gs = <int>[], bs = <int>[];
  void add(int x, int y) {
    final p = im.getPixel(x, y);
    rs.add(p.r.toInt());
    gs.add(p.g.toInt());
    bs.add(p.b.toInt());
  }

  for (var x = 0; x < im.width; x++) {
    add(x, 0);
    add(x, im.height - 1);
  }
  for (var y = 0; y < im.height; y++) {
    add(0, y);
    add(im.width - 1, y);
  }
  int median(List<int> v) {
    v.sort();
    return v[v.length ~/ 2];
  }

  return img.ColorRgb8(median(rs), median(gs), median(bs));
}

/// True when the pixel belongs to the artwork rather than the dark plate.
///
/// Deliberately keys on the brand's own ink — saturated RED or near-WHITE —
/// instead of "differs from background". The plate has a radial vignette that a
/// distance-from-background test would read as content across the whole centre.
/// The black silhouettes inside the triangle are not ink by this test, but they
/// sit inside the triangle's bounding box, so the crop still contains them.
bool _isInk(img.Pixel p) => _isRed(p) || _isBright(p);

/// Saturated brand red — the triangle body and the wordmark's "ALPHA".
bool _isRed(img.Pixel p) {
  final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
  return r > 60 && (r - math.max(g, b)) > 25;
}

/// Near-white — the wordmark's "SERENA".
bool _isBright(img.Pixel p) =>
    math.min(p.r.toInt(), math.min(p.g.toInt(), p.b.toInt())) > 90;

/// Vertical bands of consecutive rows containing artwork, top to bottom.
/// Bands separated by fewer than 10 blank rows are merged so anti-aliasing
/// gaps inside one element don't split it.
List<(int, int)> _inkBands(img.Image im) {
  final minPerRow = math.max(2, (im.width * 0.004).round());
  final rowHasInk = List<bool>.filled(im.height, false);
  for (var y = 0; y < im.height; y++) {
    var n = 0;
    for (var x = 0; x < im.width; x++) {
      if (_isInk(im.getPixel(x, y))) {
        n++;
        if (n >= minPerRow) break;
      }
    }
    rowHasInk[y] = n >= minPerRow;
  }

  final bands = <(int, int)>[];
  int? start;
  var blank = 0;
  for (var y = 0; y < im.height; y++) {
    if (rowHasInk[y]) {
      start ??= y;
      blank = 0;
    } else if (start != null) {
      blank++;
      if (blank >= 10) {
        bands.add((start, y - blank));
        start = null;
      }
    }
  }
  if (start != null) bands.add((start, im.height - 1));
  return bands;
}

/// Tight bounding box of the artwork within rows [top]..[bottom], plus a small
/// margin so scaling never shaves the mark's edges.
_Box _markBox(img.Image im, int top, int bottom) {
  var minX = im.width, maxX = -1;
  for (var y = top; y <= bottom; y++) {
    for (var x = 0; x < im.width; x++) {
      if (_isInk(im.getPixel(x, y))) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
      }
    }
  }
  if (maxX < 0) {
    minX = 0;
    maxX = im.width - 1;
  }
  const margin = 6;
  final x = math.max(0, minX - margin);
  final y = math.max(0, top - margin);
  final right = math.min(im.width - 1, maxX + margin);
  final low = math.min(im.height - 1, bottom + margin);
  return _Box(x, y, right - x + 1, low - y + 1);
}

class _Box {
  final int x, y, width, height;
  const _Box(this.x, this.y, this.width, this.height);
}
