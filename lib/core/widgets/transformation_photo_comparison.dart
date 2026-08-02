import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../screens/dashboard/chat_image_viewer.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

enum TransformationComparisonMode { swipe, sideBySide }

class TransformationPhotoComparison extends StatefulWidget {
  const TransformationPhotoComparison({
    super.key,
    required this.beforeUrl,
    required this.afterUrl,
    required this.poseLabel,
  });

  final String beforeUrl;
  final String afterUrl;
  final String poseLabel;

  @override
  State<TransformationPhotoComparison> createState() =>
      _TransformationPhotoComparisonState();
}

class _TransformationPhotoComparisonState
    extends State<TransformationPhotoComparison> {
  TransformationComparisonMode _mode = TransformationComparisonMode.swipe;
  double _fraction = .5;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              widget.poseLabel,
              style: AppText.label(size: 12).copyWith(color: p.textPrimary),
            ),
            SegmentedButton<TransformationComparisonMode>(
              segments: const [
                ButtonSegment(
                  value: TransformationComparisonMode.swipe,
                  label: Text('Swipe'),
                  icon: Icon(Icons.compare_arrows, size: 17),
                ),
                ButtonSegment(
                  value: TransformationComparisonMode.sideBySide,
                  label: Text('Side by side'),
                  icon: Icon(Icons.view_column_outlined, size: 17),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) =>
                  setState(() => _mode = value.first),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_mode == TransformationComparisonMode.swipe)
          _swipe(p)
        else
          _sideBySide(p),
        const SizedBox(height: 7),
        Text(
          'Tap either photo to open the high-resolution zoom viewer.',
          style: AppText.body(size: 10.5).copyWith(color: p.textMuted),
        ),
      ],
    );
  }

  Widget _swipe(AppPalette p) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = (width * 1.12).clamp(260.0, 560.0);
      return Semantics(
        label:
            '${widget.poseLabel} before and after comparison. Swipe horizontally to reveal each photo.',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: height,
            child: GestureDetector(
              onTap: () => _open(widget.afterUrl, 'after'),
              onHorizontalDragUpdate: (details) => setState(() {
                _fraction = (_fraction + details.delta.dx / width).clamp(0, 1);
              }),
              child: Stack(
                children: [
                  Positioned.fill(child: _image(widget.afterUrl, p)),
                  Positioned.fill(
                    child: ClipRect(
                      clipper: _FractionClipper(_fraction),
                      child: _image(widget.beforeUrl, p),
                    ),
                  ),
                  Positioned(
                    left: _fraction * width - 1,
                    top: 0,
                    bottom: 0,
                    width: 2,
                    child: const ColoredBox(color: Colors.white),
                  ),
                  Positioned(
                    left: (_fraction * width - 22).clamp(4, width - 48),
                    top: height / 2 - 22,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.compare_arrows,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 10,
                    top: 10,
                    child: _PhotoTag('BEFORE'),
                  ),
                  const Positioned(
                    right: 10,
                    top: 10,
                    child: _PhotoTag('AFTER'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _sideBySide(AppPalette p) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: _tappablePhoto(p, widget.beforeUrl, 'Before')),
      const SizedBox(width: 8),
      Expanded(child: _tappablePhoto(p, widget.afterUrl, 'After')),
    ],
  );

  Widget _tappablePhoto(AppPalette p, String url, String label) => Semantics(
    button: true,
    label: 'Open $label ${widget.poseLabel} photo full screen',
    child: InkWell(
      onTap: () => _open(url, label.toLowerCase()),
      borderRadius: BorderRadius.circular(14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            AspectRatio(aspectRatio: .78, child: _image(url, p)),
            Positioned(left: 8, top: 8, child: _PhotoTag(label.toUpperCase())),
          ],
        ),
      ),
    ),
  );

  Widget _image(String url, AppPalette p) => CachedNetworkImage(
    imageUrl: url,
    fit: BoxFit.cover,
    memCacheWidth: 1200,
    placeholder: (_, _) => ColoredBox(color: p.surfaceAlt),
    errorWidget: (_, _, _) => ColoredBox(
      color: p.surfaceAlt,
      child: Icon(Icons.broken_image_outlined, color: p.textMuted),
    ),
  );

  void _open(String url, String suffix) => ChatImageViewer.open(
    context,
    url: url,
    heroTag: 'transformation_${widget.poseLabel}_$suffix',
  );
}

class _FractionClipper extends CustomClipper<Rect> {
  const _FractionClipper(this.fraction);
  final double fraction;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_FractionClipper oldClipper) =>
      oldClipper.fraction != fraction;
}

class _PhotoTag extends StatelessWidget {
  const _PhotoTag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .72),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        letterSpacing: .5,
      ),
    ),
  );
}
