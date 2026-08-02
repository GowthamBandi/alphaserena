import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../controllers/member_controller.dart';
import '../../controllers/membership_controller.dart';
import '../../core/models/organization_profile_model.dart';
import '../../core/route_observer.dart';
import '../../core/services/coach_service.dart';
import '../dashboard/membership_screen.dart';
import 'discover_models.dart';
import 'plans_screen.dart';

/// Reuses the exact public storefront while keeping its source document live.
/// The supplied fallback makes navigation instant; the first Firestore event
/// replaces it and all later TrainerHQ edits rebuild the same storefront.
class LiveCoachStorefrontScreen extends StatelessWidget {
  final String adminId;
  final OrganizationProfileModel? fallback;

  const LiveCoachStorefrontScreen({
    super.key,
    required this.adminId,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<OrganizationProfileModel?>(
        stream: CoachService().watchById(adminId),
        initialData: fallback,
        builder: (context, snapshot) {
          final org = snapshot.data;
          if (org != null) return CoachStorefrontScreen(org: org);
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('Organization')),
              body: const Center(
                child: Text('Could not load this organization right now.'),
              ),
            );
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        },
      );
}

/// Organization Profile — the storefront a member sees before subscribing.
/// Driven by the live [OrganizationProfileModel]; sections the organization
/// hasn't authored are simply hidden — a customer-facing page never shows
/// authoring placeholders or fabricated content.
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
              // Only authored sections render — an unauthored section is hidden
              // entirely (never an authoring placeholder on a customer page).
              children: _spaced([
                _headerBlock(),
                _statsPanel(),
                // Price transparency before the pitch: real plan data (same
                // query the Plans screen uses), never a marketing claim.
                _PlansTeaser(org: org, onOpen: _choose),
                _about(),
                _transformations(),
                _whatWeOffer(),
                _whyChoose(),
                _footer(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  /// Drops hidden (null) sections and interleaves consistent vertical rhythm,
  /// so a sparse profile never shows stacked double-gaps.
  List<Widget> _spaced(List<Widget?> sections) {
    final present = sections.whereType<Widget>().toList();
    return [
      for (var i = 0; i < present.length; i++) ...[
        if (i > 0) const SizedBox(height: 22),
        present[i],
      ],
    ];
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: GoogleFonts.poppins(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.w700,
    ),
  );

  /// Disk+memory cached network image with a fade-in and right-sized decoding
  /// ([cacheWidth] → memCacheWidth) so large Storage images don't decode
  /// slowly/jank, and revisits never re-download.
  Widget _netImage(
    String url, {
    BoxFit fit = BoxFit.cover,
    Alignment alignment = Alignment.center,
    int? cacheWidth,
    Widget? error,
  }) => CachedNetworkImage(
    imageUrl: url,
    fit: fit,
    alignment: alignment,
    memCacheWidth: cacheWidth,
    fadeInDuration: const Duration(milliseconds: 250),
    placeholder: (_, _) => _imgLoading(),
    errorWidget: (_, _, _) => error ?? _imgError(),
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
    child: const Icon(Icons.broken_image_outlined, color: _muted, size: 24),
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
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
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
      media = _netImage(
        org.coverImageUrl!,
        cacheWidth: 1280,
        error: _heroPlaceholder(),
      );
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
    child: Icon(
      Icons.fitness_center,
      color: _red.withValues(alpha: 0.5),
      size: 48,
    ),
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
                        Flexible(
                          child: Text(
                            'VERIFIED ORGANIZATION',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: _red,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'ORGANIZATION',
                      style: GoogleFonts.poppins(
                        color: _muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    org.name,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (org.tagline != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      org.tagline!,
                      style: GoogleFonts.poppins(color: _muted, fontSize: 13),
                    ),
                  ],
                  if (_location.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      // A long "City, State" wraps to extra lines instead of
                      // overflowing; keep the pin on the first line.
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.location_on,
                            color: _muted,
                            size: 13,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _location,
                            style: GoogleFonts.poppins(
                              color: _muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
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
        if (org.specializations.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: org.specializations.map(_chip).toList(),
          ),
        ],
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
              Text(
                org.rating.toStringAsFixed(1),
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              _stars(org.rating),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${NumberFormat.compact().format(org.reviewCount)} '
            '${org.reviewCount == 1 ? 'member' : 'members'} rated',
            maxLines: 1,
            style: GoogleFonts.poppins(color: _muted, fontSize: 10.5),
          ),
        ] else ...[
          _stars(0),
          const SizedBox(height: 4),
          Text(
            'No ratings yet',
            style: GoogleFonts.poppins(color: _muted, fontSize: 10.5),
          ),
        ],
      ],
    );
  }

  // Rounds to the nearest half star: >= .75 of the way through a star shows
  // it full, >= .25 shows it half — so 3.9 reads as 4 stars, not 3.5, and
  // 3.05 reads as 3 stars, not 3.5.
  Widget _stars(double rating) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(5, (i) {
      final filled = rating >= i + 0.75;
      final half = !filled && rating >= i + 0.25;
      return Icon(
        half ? Icons.star_half : (filled ? Icons.star : Icons.star_border),
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
          ? CachedNetworkImage(
              imageUrl: logo,
              width: 86,
              height: 86,
              fit: BoxFit.cover,
              memCacheWidth: 256,
              placeholder: (_, _) => _imgLoading(),
              errorWidget: (_, _, _) => _logoInitial(initial),
            )
          : _logoInitial(initial),
    );
  }

  Widget _logoInitial(String initial) => Text(
    initial,
    style: GoogleFonts.poppins(
      color: _red,
      fontSize: 34,
      fontWeight: FontWeight.w800,
    ),
  );

  Widget _chip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: const Color(0xFF262626)),
    ),
    child: Text(
      label,
      style: GoogleFonts.poppins(
        color: const Color(0xFFC0C0C0),
        fontSize: 11.5,
      ),
    ),
  );

  // ── Stat band ────────────────────────────────────────────────────────────────

  /// Hidden until the org authors at least one stat; only authored stats show
  /// (no "—" placeholder columns on a customer page).
  Widget? _statsPanel() {
    final stats = [
      (Icons.groups_outlined, org.statClientsTrained, 'Clients Trained'),
      (
        Icons.calendar_today_outlined,
        org.statYearsExperience,
        'Years Experience',
      ),
      (
        Icons.emoji_events_outlined,
        org.statCertifiedTrainers,
        'Certified Trainers',
      ),
      (Icons.shield_outlined, org.statTransformations, 'Transformations'),
    ].where((s) => s.$2 != null && s.$2!.isNotEmpty).toList();
    if (stats.isEmpty) return null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Row(
        children: stats
            .map(
              (s) => Expanded(
                child: Column(
                  children: [
                    Icon(s.$1, color: _red, size: 22),
                    const SizedBox(height: 8),
                    Text(
                      s.$2!,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.$3,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(color: _muted, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ── About + pull quote ────────────────────────────────────────────────────────

  /// About text and/or the AUTHORED testimonial. A testimonial is social proof
  /// — it is never fabricated from a default quote; no testimonial → no card.
  /// Layout adapts: both → side by side; one → full width; neither → hidden.
  Widget? _about() {
    final hasAbout = org.about != null && org.about!.isNotEmpty;
    final hasQuote =
        org.testimonialQuote != null && org.testimonialQuote!.isNotEmpty;
    if (!hasAbout && !hasQuote) return null;

    final aboutText = hasAbout
        ? Text(
            org.about!,
            style: GoogleFonts.poppins(
              color: _muted,
              fontSize: 12.5,
              height: 1.5,
            ),
          )
        : null;

    final quoteCard = hasQuote
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1E1E1E)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '"',
                  style: GoogleFonts.poppins(
                    color: _red,
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                Text(
                  org.testimonialQuote!,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                if (org.testimonialAuthor != null &&
                    org.testimonialAuthor!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '— ${org.testimonialAuthor!}',
                    style: GoogleFonts.poppins(color: _muted, fontSize: 11),
                  ),
                ],
              ],
            ),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('About ${org.name}'),
        const SizedBox(height: 10),
        if (aboutText != null && quoteCard != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: aboutText),
              const SizedBox(width: 12),
              Expanded(flex: 4, child: quoteCard),
            ],
          )
        else
          (aboutText ?? quoteCard!),
      ],
    );
  }

  // ── Transformations ──────────────────────────────────────────────────────────

  Widget? _transformations() {
    if (org.transformations.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionTitle('Client Transformations'),
            Semantics(
              button: true,
              label: 'View all client transformations',
              child: GestureDetector(
                onTap: () => Get.to(
                  () => _TransformationsGallery(
                    orgName: org.name,
                    items: org.transformations,
                  ),
                ),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View All',
                      style: GoogleFonts.poppins(
                        color: _red,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: _red, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 214,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: org.transformations.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
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
                            Expanded(child: _transImage(t.beforeUrl, 'BEFORE')),
                            Expanded(child: _transImage(t.afterUrl, 'AFTER')),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (t.caption != null)
                      Text(
                        t.caption!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          color: _muted,
                          fontSize: 11.5,
                        ),
                      ),
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
            ? _netImage(
                url,
                fit: BoxFit.fitHeight,
                cacheWidth: 500,
                error: _transPlaceholder(),
              )
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
            child: Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
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

  Widget? _whatWeOffer() {
    if (org.whatWeOffer.isEmpty) return null;
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
            child: Text(
              t,
              style: GoogleFonts.poppins(
                color: const Color(0xFFE2E2E2),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('What We Offer'),
        const SizedBox(height: 12),
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

  Widget? _whyChoose() {
    if (org.whyChooseUs.isEmpty) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Why Choose ${org.name}?'),
        const SizedBox(height: 12),
        Container(
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
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }

  // ── Footer ───────────────────────────────────────────────────────────────────

  /// Hours / contact / socials — hidden entirely when nothing is authored.
  /// Phone and email launch the dialer / mail app (they're contact actions,
  /// not decoration).
  Widget? _footer() {
    final hasHours =
        org.operatingHours != null && org.operatingHours!.isNotEmpty;
    // (line text, launch uri or null)
    final contactLines = <(String, String?)>[
      if (org.phone != null) (org.phone!, 'tel:${org.phone!}'),
      if (org.email != null) (org.email!, 'mailto:${org.email!}'),
      if (org.address != null) (org.address!, null),
    ];
    final socials = _socials();
    if (!hasHours && contactLines.isEmpty && socials.isEmpty) return null;

    Widget line((String, String?) l) {
      final text = Text(
        l.$1,
        style: GoogleFonts.poppins(color: _muted, fontSize: 10.5, height: 1.3),
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: l.$2 == null
            ? text
            : Semantics(
                button: true,
                label: l.$1,
                child: GestureDetector(
                  onTap: () => _launch(l.$2!),
                  behavior: HitTestBehavior.opaque,
                  child: text,
                ),
              ),
      );
    }

    Widget col(IconData icon, String title, List<(String, String?)> lines) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: _red, size: 14),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      title,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...lines.map(line),
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
          if (hasHours || contactLines.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasHours)
                  col(Icons.access_time, 'Operating Hours', [
                    (org.operatingHours!, null),
                  ]),
                if (hasHours && contactLines.isNotEmpty)
                  const SizedBox(width: 10),
                if (contactLines.isNotEmpty)
                  col(Icons.call, 'Contact', contactLines),
              ],
            ),
          if (socials.isNotEmpty) ...[
            if (hasHours || contactLines.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Divider(color: Color(0xFF1E1E1E), height: 1),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                const Icon(Icons.public, color: _red, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Follow Us',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: socials.map((s) => _socialButton(s.$1, s.$2)).toList(),
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

  Widget _socialButton(IconData icon, String url) => Semantics(
    button: true,
    label: 'Open ${Uri.tryParse(url)?.host ?? 'link'}',
    child: GestureDetector(
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
        Get.snackbar(
          'Link unavailable',
          'Could not open $url',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: _card,
          colorText: Colors.white,
        );
      }
    } catch (_) {
      Get.snackbar(
        'Link unavailable',
        'Could not open $url',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: _card,
        colorText: Colors.white,
      );
    }
  }

  // ── Centered CTA (floating) — lifecycle-aware ─────────────────────────────
  //
  // A member who ALREADY belongs to this organization must never be prompted
  // to "choose" it again (re-entry defect): their storefront visits come from
  // the dashboard's partner card. For them the CTA becomes a membership
  // surface — a passive "active member" pill while active, "Renew Membership"
  // when lapsed — and never a join funnel.

  /// True when the signed-in member's linked org IS this storefront's org.
  bool get _isMyOrg =>
      Get.isRegistered<MemberController>() &&
      Get.find<MemberController>().adminId == org.adminId;

  bool get _amActiveMember =>
      _isMyOrg &&
      Get.isRegistered<MembershipController>() &&
      Get.find<MembershipController>().isActive;

  Widget _chooseFab() {
    if (_isMyOrg && _amActiveMember) {
      // Informational, not a CTA: nothing to buy, nothing to re-choose.
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _red.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_rounded, color: _red, size: 20),
            const SizedBox(width: 8),
            Text(
              "You're an active member",
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    final renew = _isMyOrg;
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
            borderRadius: BorderRadius.circular(16),
          ),
          icon: const Icon(Icons.arrow_forward_rounded, size: 20),
          label: Text(
            renew ? 'Renew Membership' : 'Choose This Organization',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  void _choose() {
    if (_isMyOrg) {
      // Existing members manage/renew through the membership surface — never
      // back through the join/subscribe funnel.
      Get.to(() => MembershipScreen());
      return;
    }
    Get.to(() => PlansScreen(org: DiscoverOrg.fromProfile(org)));
  }
}

/// "Plans start at ₹X" teaser — built from the SAME `membershipPlans` query the
/// Plans screen uses (active plans, cheapest first). Answers the price question
/// without leaving the storefront. Renders nothing while loading, on error, or
/// when the org has no plans — a teaser must never block or mislead.
class _PlansTeaser extends StatelessWidget {
  final OrganizationProfileModel org;
  final VoidCallback onOpen;
  const _PlansTeaser({required this.org, required this.onOpen});

  static const Color _card = Color(0xFF141414);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CoachService().watchPlans(org.adminId),
      builder: (context, snap) {
        final plans = (snap.data ?? const <Map<String, dynamic>>[])
            .map(PlanVM.fromMap)
            .toList();
        if (plans.isEmpty) return const SizedBox.shrink();
        final cheapest = plans.first; // service returns cheapest-first
        final label = plans.length == 1
            ? '1 membership plan'
            : '${plans.length} membership plans';
        return Semantics(
          button: true,
          label:
              '$label, starting at ${inr(cheapest.price)} rupees for ${cheapest.durationLabel}. View plans',
          child: GestureDetector(
            onTap: onOpen,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1E1E1E)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.payments_outlined,
                      color: _red,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Starting at ₹${inr(cheapest.price)} / ${cheapest.durationLabel}',
                          style: GoogleFonts.poppins(
                            color: _muted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: _muted,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
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
        title: Text(
          'Client Transformations',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 18),
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
              Text(
                t.name.isNotEmpty ? t.name : 'Client transformation',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (t.caption != null && t.caption!.isNotEmpty)
                Text(
                  t.caption!,
                  style: GoogleFonts.poppins(color: _muted, fontSize: 12),
                ),
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
                onTap: () => Get.to(
                  () => _FullImageView(url: url),
                  transition: Transition.fadeIn,
                ),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.fitHeight,
                  memCacheWidth: 700,
                  placeholder: (_, _) => Container(
                    color: const Color(0xFF161616),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _red,
                      ),
                    ),
                  ),
                  errorWidget: (_, _, _) => _placeholder(),
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
            child: Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
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
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                errorWidget: (_, _, _) => const Icon(
                  Icons.broken_image_outlined,
                  color: Color(0xFF8E8E8E),
                  size: 40,
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
                  onPressed: () => Get.back(),
                  icon: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
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
    Get.to(
      () => _FullscreenVideoPage(controller: c),
      transition: Transition.fadeIn,
    );
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
              aspectRatio: c.value.aspectRatio == 0
                  ? 16 / 9
                  : c.value.aspectRatio,
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
                    icon: const Icon(
                      Icons.fullscreen,
                      color: Colors.white,
                      size: 24,
                    ),
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
      child: const Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: 34,
      ),
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
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
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
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
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
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.15,
                            ),
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
