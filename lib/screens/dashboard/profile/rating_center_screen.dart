import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../controllers/member_controller.dart';
import '../../../core/models/coach_profile_model.dart';
import '../../../core/services/coach_profile_service.dart';
import '../../../core/services/review_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/widgets/brand.dart';

class RatingCenterScreen extends StatelessWidget {
  const RatingCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final member = Get.find<MemberController>();
    final orgReviews = ReviewService();
    final coachReviews = CoachReviewService();
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(title: const Text('Rating Center')),
      body: Obx(() {
        final coachId = member.coachId;
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Text(
              'Share your experience',
              style: GoogleFonts.poppins(
                color: context.palette.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'You can rate only your current organization and assigned coach.',
              style: TextStyle(color: context.palette.textMuted),
            ),
            const SizedBox(height: 16),
            StreamBuilder<OrgReview?>(
              stream: orgReviews.watchMyReview(member.adminId, member.clientId),
              builder: (context, snapshot) => _RatingCard(
                title: 'Organization Rating',
                name: member.orgName.isEmpty
                    ? 'Your Organization'
                    : member.orgName,
                imageUrl: member.orgLogoUrl.value,
                fallback: const AlphaAMark(size: 28),
                review: snapshot.data,
                onEdit: member.adminId.isEmpty
                    ? null
                    : () => _editOrganization(
                        context,
                        member,
                        orgReviews,
                        snapshot.data,
                      ),
              ),
            ),
            const SizedBox(height: 14),
            if (coachId.isNotEmpty)
              StreamBuilder<CoachProfileModel?>(
                key: ValueKey(coachId),
                stream: CoachProfileService().watch(coachId),
                builder: (context, coachSnapshot) =>
                    StreamBuilder<CoachReview?>(
                      stream: coachReviews.watchCurrent(
                        coachId,
                        member.clientId,
                      ),
                      builder: (context, reviewSnapshot) {
                        final coach = coachSnapshot.data;
                        return _RatingCard(
                          title: 'Assigned Coach Rating',
                          name: coach?.name ?? member.trainerName,
                          imageUrl: coach?.avatarUrl,
                          fallback: Icon(
                            Icons.person_outline,
                            color: context.palette.textMuted,
                          ),
                          review: reviewSnapshot.data == null
                              ? null
                              : OrgReview(
                                  rating: reviewSnapshot.data!.rating,
                                  comment: reviewSnapshot.data!.comment,
                                  updatedAt: reviewSnapshot.data!.updatedAt,
                                ),
                          onEdit: coach == null || !coach.isActive
                              ? null
                              : () => _editCoach(
                                  context,
                                  member,
                                  coachReviews,
                                  coachId,
                                  reviewSnapshot.data,
                                ),
                        );
                      },
                    ),
              ),
            const SizedBox(height: 22),
            Text(
              'Rating History',
              style: GoogleFonts.poppins(
                color: context.palette.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            StreamBuilder<List<CoachReview>>(
              stream: coachReviews.watchMine(member.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    snapshot.data == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _message(context, 'Could not load rating history.');
                }
                final history = (snapshot.data ?? const [])
                    .where((review) => review.coachId != coachId)
                    .toList();
                if (history.isEmpty) {
                  return _message(context, 'No previous coach ratings yet.');
                }
                return Column(
                  children: history
                      .map((review) => _HistoryTile(review: review))
                      .toList(),
                );
              },
            ),
          ],
        );
      }),
    );
  }

  Widget _message(BuildContext context, String text) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.palette.surface,
      borderRadius: AppRadii.cardR,
      border: Border.all(color: context.palette.border),
    ),
    child: Text(text, style: TextStyle(color: context.palette.textMuted)),
  );

  Future<void> _editOrganization(
    BuildContext context,
    MemberController member,
    ReviewService service,
    OrgReview? existing,
  ) async {
    final result = await _showEditor(context, existing);
    if (result == null) return;
    try {
      await service.submit(
        adminId: member.adminId,
        clientId: member.clientId,
        authUid: member.uid,
        memberName: member.name,
        rating: result.$1,
        comment: result.$2,
      );
      Get.snackbar('Rating saved', 'Your organization rating is up to date.');
    } catch (_) {
      Get.snackbar('Not saved', 'Please check your connection and try again.');
    }
  }

  Future<void> _editCoach(
    BuildContext context,
    MemberController member,
    CoachReviewService service,
    String coachId,
    CoachReview? existing,
  ) async {
    final result = await _showEditor(
      context,
      existing == null
          ? null
          : OrgReview(rating: existing.rating, comment: existing.comment),
    );
    if (result == null) return;
    // The id is captured before the editor opens. If reassignment happens
    // while the sheet is visible, rules reject the now-historical coach instead
    // of silently applying the rating to a different person.
    try {
      await service.submit(
        coachId: coachId,
        adminId: member.adminId,
        clientId: member.clientId,
        authUid: member.uid,
        rating: result.$1,
        comment: result.$2,
      );
      Get.snackbar('Rating saved', 'Your coach rating is up to date.');
    } catch (_) {
      Get.snackbar(
        'Not saved',
        'Your coach may have changed. Reopen Rating Center and try again.',
      );
    }
  }

  Future<(int, String)?> _showEditor(
    BuildContext context,
    OrgReview? existing,
  ) => showModalBottomSheet<(int, String)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _RatingEditor(existing: existing),
  );
}

class _RatingCard extends StatelessWidget {
  final String title;
  final String name;
  final String? imageUrl;
  final Widget fallback;
  final OrgReview? review;
  final VoidCallback? onEdit;

  const _RatingCard({
    required this.title,
    required this.name,
    this.imageUrl,
    required this.fallback,
    required this.review,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: p.surfaceAlt,
                backgroundImage: imageUrl == null || imageUrl!.isEmpty
                    ? null
                    : CachedNetworkImageProvider(imageUrl!),
                child: imageUrl == null || imageUrl!.isEmpty ? fallback : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Profile unavailable' : name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _Stars(value: review?.rating ?? 0),
                  ],
                ),
              ),
              TextButton(
                onPressed: onEdit,
                child: Text(review == null ? 'Rate Now' : 'Edit'),
              ),
            ],
          ),
          if (review?.comment.trim().isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(
              review!.comment,
              style: TextStyle(color: p.textMuted, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final CoachReview review;
  const _HistoryTile({required this.review});

  @override
  Widget build(BuildContext context) => StreamBuilder<CoachProfileModel?>(
    stream: CoachProfileService().watch(review.coachId),
    builder: (context, snapshot) {
      final p = context.palette;
      final coach = snapshot.data;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: AppRadii.cardR,
          border: Border.all(color: p.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: p.surfaceAlt,
                  backgroundImage: coach?.avatarUrl == null
                      ? null
                      : CachedNetworkImageProvider(coach!.avatarUrl!),
                  child: coach?.avatarUrl == null
                      ? Icon(Icons.person_outline, color: p.textMuted)
                      : null,
                ),
                Container(width: 1, height: 34, color: p.border),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    coach?.name ?? 'Previous coach',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _Stars(value: review.rating),
                  if (review.comment.trim().isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(review.comment, style: TextStyle(color: p.textMuted)),
                  ],
                  if (review.updatedAt != null) ...[
                    const SizedBox(height: 7),
                    Text(
                      DateFormat('d MMM yyyy').format(review.updatedAt!),
                      style: TextStyle(color: p.textMuted, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Stars extends StatelessWidget {
  final int value;
  const _Stars({required this.value});

  @override
  Widget build(BuildContext context) => Semantics(
    label: value == 0 ? 'Not rated' : '$value out of 5 stars',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < value ? Icons.star_rounded : Icons.star_border_rounded,
          color: context.palette.accent,
          size: 18,
        ),
      ),
    ),
  );
}

class _RatingEditor extends StatefulWidget {
  final OrgReview? existing;
  const _RatingEditor({this.existing});

  @override
  State<_RatingEditor> createState() => _RatingEditorState();
}

class _RatingEditorState extends State<_RatingEditor> {
  late int _rating = widget.existing?.rating ?? 0;
  late final TextEditingController _comment = TextEditingController(
    text: widget.existing?.comment ?? '',
  );

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.existing == null ? 'Add Rating' : 'Edit Rating',
                style: GoogleFonts.poppins(
                  color: p.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => IconButton(
                    tooltip: '${i + 1} stars',
                    onPressed: () => setState(() => _rating = i + 1),
                    icon: Icon(
                      i < _rating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: p.accent,
                      size: 34,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _comment,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Review (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _rating == 0
                      ? null
                      : () => Get.back(result: (_rating, _comment.text.trim())),
                  child: const Text('Save Rating'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
