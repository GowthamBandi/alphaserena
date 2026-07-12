import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Full-screen chat image viewer: black stage, Hero continuity from the
/// bubble, pinch-zoom (up to 5x) + double-tap toggle, tap or swipe-down-feel
/// close. No new dependencies — InteractiveViewer + CachedNetworkImage.
class ChatImageViewer extends StatefulWidget {
  final String url;
  final String heroTag;
  const ChatImageViewer({super.key, required this.url, required this.heroTag});

  static void open(BuildContext context,
      {required String url, required String heroTag}) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (context, anim, secondary) =>
          ChatImageViewer(url: url, heroTag: heroTag),
      transitionsBuilder: (context, anim, secondary, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  State<ChatImageViewer> createState() => _ChatImageViewerState();
}

class _ChatImageViewerState extends State<ChatImageViewer> {
  final TransformationController _transform = TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  bool get _zoomed => _transform.value.getMaxScaleOnAxis() > 1.01;

  void _handleDoubleTap() {
    if (_zoomed) {
      _transform.value = Matrix4.identity();
    } else {
      final pos = _doubleTapDetails?.localPosition;
      if (pos == null) return;
      _transform.value = Matrix4.identity()
        ..translateByDouble(-pos.dx * 1.5, -pos.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 2.5, 1);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                if (!_zoomed) Navigator.of(context).pop();
              },
              onDoubleTapDown: (d) => _doubleTapDetails = d,
              onDoubleTap: _handleDoubleTap,
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Hero(
                    tag: widget.heroTag,
                    child: CachedNetworkImage(
                      imageUrl: widget.url,
                      fit: BoxFit.contain,
                      progressIndicatorBuilder: (context, url, p) => SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          value: p.progress,
                          color: Colors.white70,
                        ),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white38,
                          size: 56),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  style: IconButton.styleFrom(
                      backgroundColor: Colors.black45),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
