import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/member_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../core/domain/transformation_comparison.dart';
import '../../core/models/transformation_entry.dart';
import '../../core/services/progress_log_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/transformation_photo_comparison.dart';
import '../join/join_coach_screen.dart';
import 'chat_image_viewer.dart';
import 'log_transformation_screen.dart';

class ClientProgressScreen extends StatelessWidget {
  const ClientProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final progress = Get.find<ProgressController>();
    final member = Get.find<MemberController>();
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          if (member.isLoading.value || progress.isLoading.value) {
            return _loading(p);
          }
          return RefreshIndicator(
            color: p.accent,
            onRefresh: () async {
              await member.claim();
              progress.retry();
            },
            // Slivers, not a ListView of boxes: a member's whole transformation
            // history used to sit inside ONE Column, so every check-in in it was
            // laid out and every photo decoded on open, however far off screen.
            // The history is a SliverList now and is built as it is reached.
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Progress',
                          style: AppText.title(
                            size: 24,
                          ).copyWith(color: p.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Track the evidence. Build your transformation.',
                          style: AppText.body(
                            size: 12,
                          ).copyWith(color: p.textMuted),
                        ),
                        const SizedBox(height: 16),
                        _tabs(progress, p),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                if (!member.isLinked.value)
                  _boxSliver(_unlinked(p))
                else if (progress.error.value.isNotEmpty)
                  _boxSliver(_error(p, progress))
                else
                  ..._contentSlivers(context, p, progress),
                const SliverPadding(
                  padding: EdgeInsets.only(bottom: 28),
                  sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _tabs(ProgressController controller, AppPalette p) {
    const labels = ['Overview', 'Transformation', 'Strength'];
    return Row(
      children: [
        for (var index = 0; index < labels.length; index++)
          Expanded(
            child: Semantics(
              selected: controller.selectedTab.value == index,
              button: true,
              child: InkWell(
                onTap: () => controller.selectedTab.value = index,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    children: [
                      Text(
                        labels[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label(size: 12).copyWith(
                          color: controller.selectedTab.value == index
                              ? p.accent
                              : p.textMuted,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Container(
                        height: controller.selectedTab.value == index ? 3 : 1,
                        color: controller.selectedTab.value == index
                            ? p.accent
                            : p.border,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Wraps a plain box in the horizontal gutter every sliver here shares.
  Widget _boxSliver(Widget child) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 18),
    sliver: SliverToBoxAdapter(child: child),
  );

  List<Widget> _contentSlivers(
    BuildContext context,
    AppPalette p,
    ProgressController c,
  ) => switch (c.selectedTab.value) {
    0 => [_boxSliver(_overview(p, c))],
    1 => _transformationSlivers(context, p, c),
    _ => [_boxSliver(_strength(p))],
  };

  Widget _overview(AppPalette p, ProgressController c) {
    final weights = c.weights.reversed.toList();
    return Column(
      children: [
        _card(
          p,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Weight trend',
                      style: AppText.title(
                        size: 16,
                      ).copyWith(color: p.textPrimary),
                    ),
                  ),
                  if (c.latestWeight != null)
                    Text(
                      '${c.latestWeight!.toStringAsFixed(1)} kg',
                      style: AppText.title(size: 17).copyWith(color: p.accent),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                c.weightChange == null
                    ? 'Add at least two check-ins to see a trend.'
                    : _weightChangeCopy(c.weightChange!),
                style: AppText.body(size: 12).copyWith(color: p.textMuted),
              ),
              const SizedBox(height: 16),
              if (weights.length < 2)
                _honestEmpty(
                  p,
                  Icons.monitor_weight_outlined,
                  'No weight trend yet',
                  'Log weight when it is useful. We never estimate missing values.',
                )
              else
                Semantics(
                  label:
                      'Weight trend from ${weights.first.weightKg!.toStringAsFixed(1)} to ${weights.last.weightKg!.toStringAsFixed(1)} kilograms over ${weights.length} check-ins',
                  child: SizedBox(height: 180, child: _weightChart(p, weights)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _latestSnapshot(p, c.latest, compact: true),
      ],
    );
  }

  String _weightChangeCopy(double change) {
    if (change == 0) return 'No change since your previous weight check-in.';
    return '${change > 0 ? 'Up' : 'Down'} ${change.abs().toStringAsFixed(1)} kg since your previous weight check-in.';
  }

  Widget _weightChart(AppPalette p, List<TransformationEntry> entries) {
    final spots = [
      for (final entry in entries)
        FlSpot(
          entry.recordedAt.millisecondsSinceEpoch.toDouble(),
          entry.weightKg!,
        ),
    ];
    var minY = spots.first.y;
    var maxY = spots.first.y;
    for (final spot in spots) {
      if (spot.y < minY) minY = spot.y;
      if (spot.y > maxY) maxY = spot.y;
    }
    final rawMinX = spots.first.x;
    final rawMaxX = spots.last.x;
    final hasTimeRange = rawMaxX > rawMinX;
    final minX = hasTimeRange ? rawMinX : rawMinX - 43200000;
    final maxX = hasTimeRange ? rawMaxX : rawMaxX + 43200000;
    final xInterval = (maxX - minX) / 2;
    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: (minY - 2).clamp(0, double.infinity),
        maxY: maxY + 2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: p.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: p.accent,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: p.accent.withValues(alpha: .10),
            ),
          ),
        ],
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              getTitlesWidget: (value, _) => Text(
                value.toStringAsFixed(0),
                style: AppText.body(size: 10).copyWith(color: p.textMuted),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: xInterval,
              getTitlesWidget: (value, _) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  DateFormat(
                    'd MMM',
                  ).format(DateTime.fromMillisecondsSinceEpoch(value.toInt())),
                  style: AppText.body(size: 10).copyWith(color: p.textMuted),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _transformationSlivers(
    BuildContext context,
    AppPalette p,
    ProgressController c,
  ) {
    final entries = c.completed;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.recoveryDrafts.isNotEmpty) ...[
          _recovery(p, c.recoveryDrafts, c),
          const SizedBox(height: 14),
        ],
        if (entries.isEmpty)
          _transformationEmpty(p, c)
        else ...[
          // No `previous` here on purpose: the comparison card directly below
          // renders the identical change chips, so passing it printed every
          // change twice, one card apart.
          _latestSnapshot(p, entries.first),
          if (entries.length > 1) ...[
            const SizedBox(height: 14),
            _automaticComparison(p, entries.first, entries[1]),
          ],
          const SizedBox(height: 14),
          PrimaryButton(
            label: 'Log Transformation',
            icon: Icons.add_a_photo_outlined,
            onPressed: () => Get.to(
              () => LogTransformationScreen(onSaved: c.refreshAfterSave),
            ),
          ),
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Transformation history',
              style: AppText.title(size: 17).copyWith(color: p.textPrimary),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
    return [
      _boxSliver(header),
      if (entries.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          sliver: SliverList.builder(
            itemCount: entries.length,
            // Keyed by record id so scrolling a long history reuses element
            // state against the right check-in rather than by position.
            itemBuilder: (context, index) => Padding(
              key: ValueKey(entries[index].id),
              padding: const EdgeInsets.only(bottom: 10),
              child: _timelineEntry(p, entries[index], c),
            ),
          ),
        ),
    ];
  }

  Widget _transformationEmpty(AppPalette p, ProgressController c) => _card(
    p,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.accent.withValues(alpha: .12),
            ),
            child: Icon(Icons.auto_graph_rounded, color: p.accent, size: 34),
          ),
          const SizedBox(height: 16),
          Text(
            'Your transformation starts with evidence',
            textAlign: TextAlign.center,
            style: AppText.title(size: 19).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Log only what matters today—measurements, photos, weight, or any combination. Nothing is estimated or required unnecessarily.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 13).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Log First Transformation',
            icon: Icons.add,
            onPressed: () => Get.to(
              () => LogTransformationScreen(onSaved: c.refreshAfterSave),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _latestSnapshot(
    AppPalette p,
    TransformationEntry? entry, {
    bool compact = false,
    TransformationEntry? previous,
  }) {
    if (entry == null) {
      return _card(
        p,
        child: _honestEmpty(
          p,
          Icons.auto_graph,
          'No transformation yet',
          'Your latest real check-in will appear here.',
        ),
      );
    }
    return _card(
      p,
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Latest Transformation',
                  style: AppText.title(size: 17).copyWith(color: p.textPrimary),
                ),
              ),
              _privacyBadge(p, entry),
            ],
          ),
          const SizedBox(height: 4),
          // This is when the check-in HAPPENED, which is not the same as when it
          // was last touched — calling it "Updated" made a corrected entry and an
          // untouched one read identically. The edit stamp is shown separately,
          // and only when there genuinely was one.
          Text(
            'Recorded ${DateFormat('d MMM yyyy · h:mm a').format(entry.recordedAt.toLocal())}',
            style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
          ),
          if (entry.wasEdited)
            Text(
              'Edited ${DateFormat('d MMM yyyy · h:mm a').format(entry.editedAt!.toLocal())}',
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (entry.weightKg != null)
                _metric(
                  p,
                  'Weight',
                  '${entry.weightKg!.toStringAsFixed(1)} kg',
                ),
              for (final item in entry.measurements.entries)
                _metric(
                  p,
                  transformationMetricLabel(item.key),
                  '${item.value.toStringAsFixed(1)} ${entry.measurementUnit}',
                ),
            ],
          ),
          if (previous != null &&
              compareTransformations(entry, previous).isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Since previous checkpoint',
              style: AppText.label(size: 11.5).copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final change in compareTransformations(entry, previous))
                  _changeChip(p, change),
              ],
            ),
          ],
          if (entry.photos.isNotEmpty && !compact) ...[
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 16) / 3;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in entry.photos.entries)
                      _photo(p, item.key, item.value, width),
                  ],
                );
              },
            ),
          ],
          if (entry.note != null && !compact) ...[
            const SizedBox(height: 14),
            Text(
              entry.note!,
              style: AppText.body(size: 12.5).copyWith(color: p.textPrimary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _timelineEntry(
    AppPalette p,
    TransformationEntry entry,
    ProgressController c,
  ) {
    final representative = entry.photos.values.firstOrNull;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.accent,
                  border: Border.all(color: p.background, width: 2),
                ),
              ),
              Container(width: 2, height: 112, color: p.border),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          // Material, not a decorated Container: ExpansionTile's ListTile paints
          // its ink on the nearest Material ancestor, so a background painted in
          // FRONT of that hid every splash — the primary interaction of the whole
          // history gave no feedback at all, and Flutter asserted about it on
          // every build.
          child: Material(
            color: p.surface,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadii.cardR,
              side: BorderSide(color: p.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              tilePadding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              leading: representative == null
                  ? Container(
                      width: 54,
                      height: 66,
                      decoration: BoxDecoration(
                        color: p.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.auto_graph, color: p.textMuted),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: representative.url,
                        width: 54,
                        height: 66,
                        memCacheWidth: 240,
                        fit: BoxFit.cover,
                      ),
                    ),
              title: Text(
                DateFormat('d MMM yyyy').format(entry.recordedAt.toLocal()),
                style: AppText.label(size: 13).copyWith(color: p.textPrimary),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (entry.weightKg != null)
                      _summaryChip(
                        p,
                        '${entry.weightKg!.toStringAsFixed(1)} kg',
                      ),
                    _summaryChip(
                      p,
                      '${entry.measurements.length} measurements',
                    ),
                    _summaryChip(p, '${entry.photos.length} photos'),
                  ],
                ),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _privacyBadge(p, entry),
                  const SizedBox(height: 5),
                  Icon(Icons.expand_more, color: p.textMuted, size: 18),
                ],
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    DateFormat(
                      'h:mm a · EEEE',
                    ).format(entry.recordedAt.toLocal()),
                    style: AppText.body(size: 11).copyWith(color: p.textMuted),
                  ),
                ),
                if (entry.measurements.isNotEmpty ||
                    entry.weightKg != null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (entry.weightKg != null)
                        _metric(
                          p,
                          'Weight',
                          '${entry.weightKg!.toStringAsFixed(1)} kg',
                        ),
                      for (final item in entry.measurements.entries)
                        _metric(
                          p,
                          transformationMetricLabel(item.key),
                          '${item.value.toStringAsFixed(1)} ${entry.measurementUnit}',
                        ),
                    ],
                  ),
                ],
                if (entry.photos.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = (constraints.maxWidth - 16) / 3;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in entry.photos.entries)
                            _photo(p, item.key, item.value, width),
                        ],
                      );
                    },
                  ),
                ],
                if (entry.note != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      entry.note!,
                      style: AppText.body(
                        size: 12,
                      ).copyWith(color: p.textPrimary),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _entryActions(p, entry, c),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Correcting a checkpoint and changing who can see it are the two things a
  /// member actually needs after logging. Both live with the entry itself, so
  /// neither requires hunting through a menu.
  Widget _entryActions(
    AppPalette p,
    TransformationEntry entry,
    ProgressController c,
  ) {
    final shared = entry.visibility == TransformationVisibility.shared;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entry.wasEdited)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Edited ${DateFormat('d MMM yyyy, h:mm a').format(entry.editedAt!.toLocal())}',
              style: AppText.body(size: 11).copyWith(color: p.textMuted),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => Get.to(
                () => LogTransformationScreen(
                  editing: entry,
                  onSaved: c.refreshAfterSave,
                ),
              ),
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('Edit'),
            ),
            OutlinedButton.icon(
              onPressed: () => _toggleVisibility(entry, c),
              icon: Icon(
                shared ? Icons.visibility_off_outlined : Icons.visibility,
                size: 17,
              ),
              label: Text(shared ? 'Hide from coach' : 'Share with coach'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _toggleVisibility(
    TransformationEntry entry,
    ProgressController c,
  ) async {
    final next = entry.visibility == TransformationVisibility.shared
        ? TransformationVisibility.private
        : TransformationVisibility.shared;
    try {
      final outcome = await c.setVisibility(entry, next);
      // A privacy change that is only QUEUED has NOT taken effect yet — the
      // coach can still open this check-in until it syncs. Reporting "Hidden
      // from your coach" then would be the one lie this feature cannot afford.
      if (outcome == TransformationWriteOutcome.queued) {
        Get.snackbar(
          'Saved on this device',
          next == TransformationVisibility.private
              ? 'Your coach can still see this check-in until you are back online.'
              : 'It will be shared with your coach as soon as you are back online.',
        );
        return;
      }
      Get.snackbar(
        next == TransformationVisibility.shared
            ? 'Shared with your coach'
            : 'Hidden from your coach',
        next == TransformationVisibility.shared
            ? 'This check-in is now part of your coach review.'
            : 'Only you can see this check-in. You can share it again anytime.',
      );
    } catch (_) {
      Get.snackbar(
        'Not changed',
        'Check your connection and try again — nothing was altered.',
      );
    }
  }

  Widget _photo(
    AppPalette p,
    TransformationPose pose,
    TransformationPhoto photo,
    double width,
  ) => Semantics(
    button: true,
    label: 'Open ${pose.name} transformation photo full screen',
    child: InkWell(
      onTap: () => ChatImageViewer.open(
        Get.context!,
        url: photo.url,
        heroTag: 'member_transformation_${pose.name}_${photo.url.hashCode}',
      ),
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            CachedNetworkImage(
              imageUrl: photo.url,
              width: width,
              height: width * 1.25,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: width,
                height: width * 1.25,
                color: p.surfaceAlt,
              ),
              errorWidget: (_, _, _) => Container(
                width: width,
                height: width * 1.25,
                color: p.surfaceAlt,
                child: Icon(Icons.broken_image_outlined, color: p.textMuted),
              ),
            ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  pose.name.capitalizeFirst ?? pose.name,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _automaticComparison(
    AppPalette p,
    TransformationEntry latest,
    TransformationEntry previous,
  ) {
    final changes = compareTransformations(latest, previous);
    final poses = TransformationPose.values.where(
      (pose) => latest.photos[pose] != null && previous.photos[pose] != null,
    );
    return _card(
      p,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Latest vs previous',
            style: AppText.title(size: 17).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 3),
          Text(
            '${DateFormat('d MMM').format(previous.recordedAt.toLocal())} → ${DateFormat('d MMM').format(latest.recordedAt.toLocal())}',
            style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
          ),
          if (changes.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'These checkpoints have no matching measurements to compare.',
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final change in changes) _changeChip(p, change)],
            ),
          ],
          if (poses.isNotEmpty) ...[
            const SizedBox(height: 18),
            for (final pose in poses) ...[
              TransformationPhotoComparison(
                beforeUrl: previous.photos[pose]!.url,
                afterUrl: latest.photos[pose]!.url,
                poseLabel: transformationMetricLabel(pose.name),
              ),
              if (pose != poses.last) const SizedBox(height: 18),
            ],
          ] else ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.compare_outlined, color: p.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Add the same labelled pose in two checkpoints to unlock photo comparison.',
                      style: AppText.body(
                        size: 11.5,
                      ).copyWith(color: p.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _changeChip(AppPalette p, TransformationChange change) {
    final down = change.direction == TransformationChangeDirection.reduced;
    final same = change.direction == TransformationChangeDirection.unchanged;
    final icon = same
        ? Icons.remove
        : down
        ? Icons.south
        : Icons.north;
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: same ? p.textMuted : p.accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${change.label} · ${change.directionLabel} ${change.delta.abs().toStringAsFixed(1)} ${change.unit}',
              style: AppText.label(size: 10.5).copyWith(color: p.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(AppPalette p, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: p.surfaceAlt,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: AppText.body(size: 9.5).copyWith(color: p.textMuted),
    ),
  );

  Widget _metric(AppPalette p, String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: p.surfaceAlt,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: p.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppText.body(size: 10.5).copyWith(color: p.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppText.label(size: 13).copyWith(color: p.textPrimary),
        ),
      ],
    ),
  );

  Widget _privacyBadge(AppPalette p, TransformationEntry entry) {
    final private = entry.isPrivate;
    return Semantics(
      label: private
          ? 'Private, only you can see this check-in'
          : 'Shared with coach',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: (private ? p.textMuted : p.accent).withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              private ? Icons.lock_outline : Icons.visibility_outlined,
              size: 13,
              color: private ? p.textMuted : p.accent,
            ),
            const SizedBox(width: 5),
            Text(
              private ? 'Private' : 'Shared',
              style: AppText.label(
                size: 10.5,
              ).copyWith(color: private ? p.textMuted : p.accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recovery(
    AppPalette p,
    List<TransformationEntry> drafts,
    ProgressController c,
  ) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFE0A020).withValues(alpha: .10),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE0A020).withValues(alpha: .45)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.cloud_upload_outlined, color: Color(0xFFE0A020)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${drafts.length} unfinished upload${drafts.length == 1 ? '' : 's'} safely hidden from your coach.',
                style: AppText.body(size: 12).copyWith(color: p.textPrimary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final draft in drafts)
          TextButton.icon(
            onPressed: () => Get.to(
              () => LogTransformationScreen(
                recoveryDraft: draft,
                onSaved: c.refreshAfterSave,
              ),
            ),
            icon: const Icon(Icons.refresh),
            label: Text(
              'Resume ${DateFormat('d MMM · h:mm a').format(draft.recordedAt.toLocal())}',
            ),
          ),
      ],
    ),
  );

  Widget _strength(AppPalette p) => _card(
    p,
    child: _honestEmpty(
      p,
      Icons.emoji_events_outlined,
      'Strength trends are next',
      'Your completed workout sets already preserve the evidence. This screen will use those records—never ask you to log the same lift twice.',
    ),
  );

  Widget _unlinked(AppPalette p) => _card(
    p,
    child: Column(
      children: [
        Icon(Icons.link_off_rounded, color: p.accent, size: 40),
        const SizedBox(height: 12),
        Text(
          'Connect to a coach',
          style: AppText.title(size: 17).copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'Link your membership to keep a coach-supported transformation history.',
          textAlign: TextAlign.center,
          style: AppText.body(size: 12).copyWith(color: p.textMuted),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Find a Coach',
          icon: Icons.search,
          onPressed: () => Get.to(() => const JoinCoachScreen()),
        ),
      ],
    ),
  );

  Widget _error(AppPalette p, ProgressController c) => _card(
    p,
    child: Column(
      children: [
        Icon(Icons.cloud_off_outlined, color: p.accent, size: 36),
        const SizedBox(height: 10),
        Text(
          'Could not load Transformation',
          style: AppText.title(size: 16).copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'Your data was not replaced with zeros. Check your connection and retry.',
          textAlign: TextAlign.center,
          style: AppText.body(size: 12).copyWith(color: p.textMuted),
        ),
        const SizedBox(height: 14),
        PrimaryButton(label: 'Retry', icon: Icons.refresh, onPressed: c.retry),
      ],
    ),
  );

  Widget _honestEmpty(AppPalette p, IconData icon, String title, String body) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Icon(icon, color: p.textMuted, size: 34),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.title(size: 15).copyWith(color: p.textPrimary),
            ),
            const SizedBox(height: 5),
            Text(
              body,
              textAlign: TextAlign.center,
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
          ],
        ),
      );

  Widget _card(AppPalette p, {required Widget child, bool accent = false}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: AppRadii.cardR,
          border: Border.all(
            color: accent ? p.accent.withValues(alpha: .4) : p.border,
          ),
        ),
        child: child,
      );

  Widget _loading(AppPalette p) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Container(
        height: 30,
        width: 130,
        decoration: BoxDecoration(
          color: p.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      const SizedBox(height: 22),
      Container(
        height: 48,
        decoration: BoxDecoration(
          color: p.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      const SizedBox(height: 16),
      Container(
        height: 300,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: AppRadii.cardR,
        ),
      ),
    ],
  );
}
