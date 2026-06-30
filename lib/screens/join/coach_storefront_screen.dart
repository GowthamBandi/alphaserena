import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/models/organization_profile_model.dart';
import '../../core/route_observer.dart';
import 'discover_models.dart';
import 'plans_screen.dart';

/// Organization Profile — the storefront a member sees before subscribing.
/// Driven by the live [OrganizationProfileModel]; sections with no data show a
/// "missing" placeholder (the quote section falls back to a default quote).
///
/// Renders the full authored profile: a tap-to-play cover-video hero
/// (falling back to the cover image, then a branded gradient), identity,
/// stat band, about + testimonial, transformations, what-we-offer,
/// why-choose-us, and a footer with operating hours, contact, address and a
/// tappable "Follow Us" social row.
class CoachStorefrontScreen extends StatelessWidget {
  final OrganizationProfileModel org;
  const CoachStorefrontScreen({super.key, required this.org});

  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _card = Color(0xFF141414);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);

  static const String _defaultQuote =
      'Fitness isn\'t just a goal — it\'s a way of life.';

  String get _location => [
        if (org.city != null) org.city!,
        if (org.state != null) org.state!,
      ].join(', ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _appBar(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _chooseFab(),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _hero(context),
          Padding(
            // extra bottom space so the floating CTA never covers the footer
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 96),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _headerBlock(),
                const SizedBox(height: 16),
                _statsPanel(),
                const SizedBox(height: 22),
                _about(),
                const SizedBox(height: 22),
                _transformations(),
                const SizedBox(height: 22),
                _whatWeOffer(),
                const SizedBox(height: 22),
                _whyChoose(),
                const SizedBox(height: 18),
                _footer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _sectionTitle(String text) => Text(text,
      style: GoogleFonts.poppins(
          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700));

  /// Placeholder shown when an organization hasn't filled in a section yet.
  Widget _missing(String label) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E1E1E)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: _muted, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$label — this section is missing.',
                  style: GoogleFonts.poppins(color: _muted, fontSize: 12)),
            ),
          ],
        ),
      );

  /// Network image with a professional loading spinner, a smooth fade-in, and
  /// right-sized decoding ([cacheWidth]) so large Storage images don't decode
  /// slowly/jank. Flutter memory-caches the decoded bytes, so repeat views are
  /// instant within a session.
  Widget _netImage(
    String url, {
    BoxFit fit = BoxFit.cover,
    Alignment alignment = Alignment.center,
    int? cacheWidth,
    Widget? error,
  }) =>
      Image.network(
        url,
        fit: fit,
        alignment: alignment,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        frameBuilder: (_, child, frame, wasSync) {
          if (wasSync) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: child,
          );
        },
        loadingBuilder: (_, child, prog) =>
            prog == null ? child : _imgLoading(),
        errorBuilder: (_, __, ___) => error ?? _imgError(),
      );

  Widget _imgLoading() => Container(
        color: const Color(0xFF161616),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: _red),
        ),
      );

  Widget _imgError() => Container(
        color: const Color(0xFF1E1E1E),
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined,
            color: _muted, size: 24),
      );

  // ── App bar (separate, solid — sits above the hero) ─────────────────────────

  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: _bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      iconTheme: const IconThemeData(color: Colors.white),
      title: Text(
        org.name.isNotEmpty ? org.name : 'Organization',
        style: GoogleFonts.poppins(
            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────────

  Widget _hero(BuildContext context) {
    // Media precedence: cover video → cover image → branded gradient. The frame
    // is always a fixed 16:9 banner so a tall/portrait clip can't blow up the
    // hero height, and the branded gradient is the placeholder so it's never a
    // black box.
    final Widget media;
    if (org.hasCoverVideo) {
      // Poster = the cover image (instant) so the hero never waits on the video.
      // The video only downloads/initializes when the user taps play.
      // Poster precedence: cover image → auto-generated video frame → branded.
      final posterUrl = org.coverImageUrl ?? org.coverVideoPosterUrl;
      media = _CoverVideo(
        url: org.coverVideoUrl!,
        poster: posterUrl != null
            ? _netImage(posterUrl, cacheWidth: 1280)
            : _heroPlaceholder(),
        loading: _heroLoading(),
        fallback: _heroPlaceholder(),
      );
    } else if (org.hasCoverImage) {
      media = _netImage(org.coverImageUrl!,
          cacheWidth: 1280, error: _heroPlaceholder());
    } else {
      media = _heroPlaceholder();
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: SizedBox(width: double.infinity, child: media),
    );
  }

  Widget _heroPlaceholder() => Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
          ),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.fitness_center,
            color: _red.withValues(alpha: 0.5), size: 48),
      );

  /// Branded hero backdrop while the cover image/video loads — gradient + a
  /// subtle spinner (never a flat black box).
  Widget _heroLoading() => Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
          ),
        ),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: _red),
        ),
      );

  // ── Header block ────────────────────────────────────────────────────────────

  Widget _headerBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _logoTile(),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (org.verified)
                    Row(
                      children: [
                        const Icon(Icons.verified, color: _red, size: 13),
                        const SizedBox(width: 4),
                        Text('VERIFIED ORGANIZATION',
                            style: GoogleFonts.poppins(
                                color: _red,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5)),
                      ],
                    )
                  else
                    Text('ORGANIZATION',
                        style: GoogleFonts.poppins(
                            color: _muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5)),
                  const SizedBox(height: 4),
                  Text(org.name,
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(org.tagline ?? 'No tagline added',
                      style: GoogleFonts.poppins(
                          color: _muted,
                          fontSize: 13,
                          fontStyle: org.tagline == null
                              ? FontStyle.italic
                              : FontStyle.normal)),
                  if (_location.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: _muted, size: 13),
                        const SizedBox(width: 4),
                        Text(_location,
                            style: GoogleFonts.poppins(
                                color: _muted, fontSize: 12)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _ratingBadge(),
          ],
        ),
        const SizedBox(height: 14),
        if (org.specializations.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: org.specializations.map(_chip).toList(),
          )
        else
          _missing('Specializations'),
      ],
    );
  }

  /// Trailing rating block in the header row: star icons + average, with the
  /// number of members who rated below. Falls back to a "No ratings yet" state.
  /// The aggregate (`rating`/`reviewCount`) is platform-maintained — members
  /// submit ratings from inside the app (subscribers only).
  Widget _ratingBadge() {
    final rated = org.reviewCount > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (rated) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(org.rating.toStringAsFixed(1),
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
              _stars(org.rating),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${org.reviewCount} ${org.reviewCount == 1 ? 'member' : 'members'} rated',
            style: GoogleFonts.poppins(color: _muted, fontSize: 10.5),
          ),
        ] else ...[
          _stars(0),
          const SizedBox(height: 4),
          Text('No ratings yet',
              style: GoogleFonts.poppins(color: _muted, fontSize: 10.5)),
        ],
      ],
    );
  }

  Widget _stars(double rating) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (i) {
          final filled = rating >= i + 1;
          final half = !filled && rating > i;
          return Icon(
            half
                ? Icons.star_half
                : (filled ? Icons.star : Icons.star_border),
            color: const Color(0xFFFFC107),
            size: 14,
          );
        }),
      );

  Widget _logoTile() {
    final logo = org.logoUrl;
    final initial = org.name.isNotEmpty ? org.name[0].toUpperCase() : '?';
    return Container(
      width: 86,
      height: 86,
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: logo != null && logo.isNotEmpty
          ? Image.network(
              logo,
              width: 86,
              height: 86,
              fit: BoxFit.cover,
              cacheWidth: 256,
              gaplessPlayback: true,
              loadingBuilder: (_, child, prog) =>
                  prog == null ? child : _imgLoading(),
              errorBuilder: (_, __, ___) => _logoInitial(initial),
            )
          : _logoInitial(initial),
    );
  }

  Widget _logoInitial(String initial) => Text(initial,
      style: GoogleFonts.poppins(
          color: _red, fontSize: 34, fontWeight: FontWeight.w800));

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFF262626)),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                color: const Color(0xFFC0C0C0), fontSize: 11.5)),
      );

  // ── Stat band ────────────────────────────────────────────────────────────────

  Widget _statsPanel() {
    final stats = [
      (Icons.groups_outlined, org.statClientsTrained, 'Clients Trained'),
      (Icons.calendar_today_outlined, org.statYearsExperience,
          'Years Experience'),
      (Icons.emoji_events_outlined, org.statCertifiedTrainers,
          'Certified Trainers'),
      (Icons.shield_outlined, org.statTransformations, 'Transformations'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Row(
        children: stats
            .map((s) => Expanded(
                  child: Column(
                    children: [
                      Icon(s.$1, color: _red, size: 22),
                      const SizedBox(height: 8),
                      Text(s.$2 ?? '—',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(s.$3,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                              color: _muted, fontSize: 10.5)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  // ── About + pull quote ────────────────────────────────────────────────────────

  Widget _about() {
    final quote =
        (org.testimonialQuote != null && org.testimonialQuote!.isNotEmpty)
            ? org.testimonialQuote!
            : _defaultQuote;
    final author = (org.testimonialAuthor != null &&
            org.testimonialAuthor!.isNotEmpty)
        ? org.testimonialAuthor!
        : org.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('About ${org.name}'),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: (org.about != null && org.about!.isNotEmpty)
                  ? Text(
                      org.about!,
                      style: GoogleFonts.poppins(
                          color: _muted, fontSize: 12.5, height: 1.5),
                    )
                  : _missing('About'),
            ),
            const SizedBox(width: 12),
            // Quote card — always shown (falls back to a default quote)
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1E1E1E)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('"',
                        style: GoogleFonts.poppins(
                            color: _red,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            height: 1)),
                    Text(
                      quote,
                      style: GoogleFonts.poppins(
                          color: Colors.white, fontSize: 12.5, height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    Text('— $author',
                        style:
                            GoogleFonts.poppins(color: _muted, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Transformations ──────────────────────────────────────────────────────────

  Widget _transformations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionTitle('Client Transformations'),
            if (org.transformations.isNotEmpty)
              GestureDetector(
                onTap: () => Get.to(() => _TransformationsGallery(
                      orgName: org.name,
                      items: org.transformations,
                    )),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('View All',
                        style: GoogleFonts.poppins(
                            color: _red,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                    const Icon(Icons.chevron_right, color: _red, size: 18),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (org.transformations.isEmpty)
          _missing('Client Transformations')
        else
          SizedBox(
            height: 214,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: org.transformations.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final t = org.transformations[i];
                return SizedBox(
                  width: 250,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Before + after, side by side. fitHeight fills the frame
                      // height and crops width so portrait progress shots line up.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: 150,
                          child: Row(
                            children: [
                              // Before + after flush together (no gap) in one
                              // seamless card.
                              Expanded(
                                  child: _transImage(t.beforeUrl, 'BEFORE')),
                              Expanded(
                                  child: _transImage(t.afterUrl, 'AFTER')),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      if (t.caption != null)
                        Text(t.caption!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                color: _muted, fontSize: 11.5)),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// One half of a transformation card — a cached image cropped with
  /// [BoxFit.fitHeight] and a small BEFORE/AFTER tag in the corner.
  Widget _transImage(String url, String label) {
    return Stack(
      fit: StackFit.expand,
      children: [
        url.isNotEmpty
            ? _netImage(url,
                fit: BoxFit.fitHeight,
                cacheWidth: 500,
                error: _transPlaceholder())
            : _transPlaceholder(),
        Positioned(
          left: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ),
        ),
      ],
    );
  }

  Widget _transPlaceholder() => Container(
        color: const Color(0xFF1E1E1E),
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined, color: _muted, size: 26),
      );

  // ── What We Offer ────────────────────────────────────────────────────────────

  Widget _whatWeOffer() {
    // Each offering is a point with a leading icon.
    Widget point(String t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.fitness_center, color: _red, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(t,
                    style: GoogleFonts.poppins(
                        color: const Color(0xFFE2E2E2),
                        fontSize: 12.5,
                        height: 1.35)),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('What We Offer'),
        const SizedBox(height: 12),
        if (org.whatWeOffer.isEmpty)
          _missing('What We Offer')
        else
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1E1E1E)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: org.whatWeOffer.map(point).toList(),
            ),
          ),
      ],
    );
  }

  // ── Why Choose Us (paragraph) ──────────────────────────────────────────────

  Widget _whyChoose() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Why Choose ${org.name}?'),
        const SizedBox(height: 12),
        org.whyChooseUs.isEmpty
            ? _missing('Why Choose Us')
            : Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF1E1E1E)),
                ),
                child: Text(
                  // Render the authored points as flowing paragraph text.
                  org.whyChooseUs.join('\n\n'),
                  style: GoogleFonts.poppins(
                      color: const Color(0xFFCFCFCF),
                      fontSize: 12.5,
                      height: 1.55),
                ),
              ),
      ],
    );
  }

  // ── Footer ───────────────────────────────────────────────────────────────────

  Widget _footer() {
    final hoursLines =
        (org.operatingHours != null && org.operatingHours!.isNotEmpty)
            ? [org.operatingHours!]
            : ['Not provided'];
    final contactLines = [
      if (org.phone != null) org.phone!,
      if (org.email != null) org.email!,
      if (org.address != null) org.address!,
    ];
    final socials = _socials();

    Widget col(IconData icon, String title, List<String> lines) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: _red, size: 14),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(title,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...lines.map((l) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(l,
                        style: GoogleFonts.poppins(
                            color: _muted, fontSize: 10.5, height: 1.3)),
                  )),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              col(Icons.access_time, 'Operating Hours', hoursLines),
              const SizedBox(width: 10),
              col(Icons.call, 'Contact',
                  contactLines.isEmpty ? ['Not provided'] : contactLines),
            ],
          ),
          if (socials.isNotEmpty) ...[
            const SizedBox(height: 18),
            Divider(color: const Color(0xFF1E1E1E), height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.public, color: _red, size: 14),
                const SizedBox(width: 6),
                Text('Follow Us',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: socials
                  .map((s) => _socialButton(s.$1, s.$2))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ── Social links ──────────────────────────────────────────────────────────

  /// The platforms the coach filled in, each as (icon, launch-url). URLs are
  /// normalized so a bare handle (e.g. "alphas.arena") still opens correctly.
  List<(IconData, String)> _socials() {
    return [
      if (org.instagram != null)
        (Icons.camera_alt_outlined, _instagramUrl(org.instagram!)),
      if (org.facebook != null) (Icons.facebook, _socialUrl(org.facebook!)),
      if (org.youtube != null)
        (Icons.play_circle_outline, _socialUrl(org.youtube!)),
      if (org.twitter != null)
        (Icons.alternate_email, _twitterUrl(org.twitter!)),
      if (org.website != null) (Icons.language, _socialUrl(org.website!)),
    ];
  }

  Widget _socialButton(IconData icon, String url) => GestureDetector(
        onTap: () => _launch(url),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: const Color(0xFF262626)),
          ),
          child: Icon(icon, color: Colors.white, size: 19),
        ),
      );

  /// Prefix a bare value with https:// if it has no scheme.
  String _socialUrl(String raw) {
    final v = raw.trim();
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    return 'https://$v';
  }

  /// Accept a full URL, an @handle, or a bare handle for Instagram.
  String _instagramUrl(String raw) {
    final v = raw.trim();
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    return 'https://instagram.com/${v.replaceFirst('@', '')}';
  }

  /// Accept a full URL, an @handle, or a bare handle for Twitter/X.
  String _twitterUrl(String raw) {
    final v = raw.trim();
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    return 'https://x.com/${v.replaceFirst('@', '')}';
  }

  Future<void> _launch(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        Get.snackbar('Link unavailable', 'Could not open $url',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: _card,
            colorText: Colors.white);
      }
    } catch (_) {
      Get.snackbar('Link unavailable', 'Could not open $url',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: _card,
          colorText: Colors.white);
    }
  }

  // ── Centered "Choose This Organization" CTA (floating) ────────────────────────

  Widget _chooseFab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: FloatingActionButton.extended(
          onPressed: _choose,
          backgroundColor: _red,
          foregroundColor: Colors.white,
          elevation: 8,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          icon: const Icon(Icons.arrow_forward_rounded, size: 20),
          label: Text('Choose This Organization',
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  void _choose() =>
      Get.to(() => PlansScreen(org: DiscoverOrg.fromProfile(org)));
}

/// Full "Client Transformations" gallery — every before/after, scrollable.
class _TransformationsGallery extends StatelessWidget {
  final String orgName;
  final List<Transformation> items;
  const _TransformationsGallery({required this.orgName, required this.items});

  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Client Transformations',
            style: GoogleFonts.poppins(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 18),
        itemBuilder: (_, i) {
          final t = items[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  height: 240,
                  child: Row(
                    children: [
                      Expanded(child: _img(context, t.beforeUrl, 'BEFORE')),
                      Expanded(child: _img(context, t.afterUrl, 'AFTER')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(t.name.isNotEmpty ? t.name : 'Client transformation',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              if (t.caption != null && t.caption!.isNotEmpty)
                Text(t.caption!,
                    style: GoogleFonts.poppins(color: _muted, fontSize: 12)),
            ],
          );
        },
      ),
    );
  }

  Widget _img(BuildContext context, String url, String label) {
    return Stack(
      fit: StackFit.expand,
      children: [
        url.isNotEmpty
            ? GestureDetector(
                onTap: () => Get.to(() => _FullImageView(url: url),
                    transition: Transition.fadeIn),
                child: Image.network(
                  url,
                  fit: BoxFit.fitHeight,
                  cacheWidth: 700,
                  loadingBuilder: (_, child, prog) => prog == null
                      ? child
                      : Container(
                          color: const Color(0xFF161616),
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _red),
                          ),
                        ),
                  errorBuilder: (_, __, ___) => _placeholder(),
                ),
              )
            : _placeholder(),
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ),
        ),
      ],
    );
  }

  Widget _placeholder() => Container(
        color: const Color(0xFF1E1E1E),
        alignment: Alignment.center,
        child: const Icon(Icons.image_outlined, color: _muted, size: 28),
      );
}

/// A single transformation image, zoomable, on a black backdrop.
class _FullImageView extends StatelessWidget {
  final String url;
  const _FullImageView({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.network(url, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Color(0xFF8E8E8E),
                      size: 40)),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  onPressed: () => Get.back(),
                  icon: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const Color _videoRed = Color(0xFFE10600);

/// Formats a video position/duration as `m:ss` (or `h:mm:ss` for long clips).
String _fmtDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${d.inMinutes}:${two(s)}';
}

/// A small monospaced-ish white time label for the video control bars.
Widget _timeLabel(String text) => Text(
      text,
      style: GoogleFonts.poppins(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

/// A storefront cover video in a fixed 16:9 frame.
///
/// FAST BY DESIGN: it shows [poster] (the cover image) INSTANTLY and does NOT
/// touch the network video until the user taps play — so the hero never waits
/// on the video to buffer. On tap it initializes + plays (a [loading] spinner
/// shows over the poster meanwhile). On failure it shows [fallback] — never a
/// black box. Once playing, a scrub timeline + time labels + fullscreen appear.
class _CoverVideo extends StatefulWidget {
  final String url;
  final Widget poster;
  final Widget loading;
  final Widget fallback;
  const _CoverVideo({
    required this.url,
    required this.poster,
    required this.loading,
    required this.fallback,
  });

  @override
  State<_CoverVideo> createState() => _CoverVideoState();
}

class _CoverVideoState extends State<_CoverVideo>
    with WidgetsBindingObserver, RouteAware {
  VideoPlayerController? _ctrl;
  bool _initializing = false;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  // Pause when another screen is pushed over this one (e.g. tapping "Choose
  // This Organization") so the video never keeps playing/audible in the
  // background.
  @override
  void didPushNext() => _pauseIfPlaying();

  // Pause when the app is backgrounded/inactive.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pauseIfPlaying();
  }

  void _pauseIfPlaying() {
    final c = _ctrl;
    if (c != null && c.value.isInitialized && c.value.isPlaying) c.pause();
  }

  /// Lazily download + initialize the video — only when the user asks for it.
  Future<void> _start() async {
    if (_initializing || _ready) return;
    setState(() => _initializing = true);
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      c.addListener(_onTick);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _ctrl = c;
        _ready = true;
        _initializing = false;
      });
      c.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _toggle() {
    final c = _ctrl;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      if (c.value.position >= c.value.duration) c.seekTo(Duration.zero);
      c.play();
    }
  }

  void _openFullscreen() {
    final c = _ctrl;
    if (c == null) return;
    Get.to(() => _FullscreenVideoPage(controller: c),
        transition: Transition.fadeIn);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.removeListener(_onTick);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;

    // Not playing yet: instant poster + a play button (or spinner while loading).
    if (!_ready || c == null) {
      return GestureDetector(
        onTap: _failed || _initializing ? null : _start,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _failed ? widget.fallback : widget.poster,
            if (_initializing)
              Container(
                color: Colors.black.withValues(alpha: 0.30),
                alignment: Alignment.center,
                child: widget.loading,
              )
            else if (!_failed)
              _playButton(),
          ],
        ),
      );
    }

    // Playing: the video + controls.
    final playing = c.value.isPlaying;
    return GestureDetector(
      onTap: _toggle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.fallback,
          Center(
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          ),
          if (!playing) _playButton(),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 20, 4, 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  _timeLabel(_fmtDuration(c.value.position)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: VideoProgressIndicator(
                      c,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      colors: VideoProgressColors(
                        playedColor: _videoRed,
                        bufferedColor: Colors.white.withValues(alpha: 0.30),
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _timeLabel(_fmtDuration(c.value.duration)),
                  const SizedBox(width: 2),
                  IconButton(
                    onPressed: _openFullscreen,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.fullscreen,
                        color: Colors.white, size: 24),
                    tooltip: 'Fullscreen',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playButton() => Container(
        color: Colors.black.withValues(alpha: 0.22),
        alignment: Alignment.center,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
          ),
          child: const Icon(Icons.play_arrow_rounded,
              color: Colors.white, size: 34),
        ),
      );
}

/// Immersive landscape fullscreen player. Reuses the caller's
/// [VideoPlayerController] (does NOT dispose it) and restores portrait + system
/// UI on exit. Tap toggles play/pause; a scrub timeline + close button overlay.
class _FullscreenVideoPage extends StatefulWidget {
  final VideoPlayerController controller;
  const _FullscreenVideoPage({required this.controller});

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  VideoPlayerController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _c.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _toggle() {
    if (_c.value.isPlaying) {
      _c.pause();
    } else {
      if (_c.value.position >= _c.value.duration) _c.seekTo(Duration.zero);
      _c.play();
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onTick);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = _c.value.isPlaying;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggle,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _c.value.aspectRatio == 0
                    ? 16 / 9
                    : _c.value.aspectRatio,
                child: VideoPlayer(_c),
              ),
            ),
            if (!playing)
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.9)),
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 40),
                ),
              ),
            // Close button (respects the notch via SafeArea).
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton(
                    onPressed: () => Get.back(),
                    icon: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),
            ),
            // Scrub timeline.
            Positioned(
              left: 12,
              right: 12,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      _timeLabel(_fmtDuration(_c.value.position)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: VideoProgressIndicator(
                          _c,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          colors: VideoProgressColors(
                            playedColor: _videoRed,
                            bufferedColor: Colors.white.withValues(alpha: 0.30),
                            backgroundColor: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _timeLabel(_fmtDuration(_c.value.duration)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
