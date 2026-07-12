import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/services/call_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';

/// The single in-call surface: outgoing "Calling…", connecting, connected
/// (timer + controls), reconnecting banner, and the ended beat. All state is
/// projected from [CallService] — this screen owns no call logic.
class CallScreen extends StatelessWidget {
  const CallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<CallService>();
    return PopScope(
      // Back must not abandon a live call silently — it hangs up honestly.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && c.inCall && c.phase.value != CallPhase.ended) {
          c.hangUp();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF10131A),
        body: SafeArea(
          child: Obx(() {
            final phase = c.phase.value;
            return Column(
              children: [
                const Spacer(flex: 2),
                _avatar(c),
                const SizedBox(height: 22),
                Text(
                  c.peerName.value.isEmpty ? 'Your Coach' : c.peerName.value,
                  style: AppText.title(size: 24)
                      .copyWith(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                _statusLine(c, phase),
                const Spacer(flex: 3),
                if (phase == CallPhase.reconnecting) _reconnectBanner(),
                const SizedBox(height: 18),
                _controls(c, phase),
                const SizedBox(height: 40),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _avatar(CallService c) {
    return Container(
      width: 108,
      height: 108,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: BrandColors.heroGradient),
      ),
      child: CircleAvatar(
        backgroundColor: const Color(0xFF1B2029),
        child: Text(
          _initials(c.peerName.value.isEmpty ? 'C' : c.peerName.value),
          style: AppText.title(size: 34).copyWith(color: Colors.white),
        ),
      ),
    );
  }

  Widget _statusLine(CallService c, CallPhase phase) {
    String label;
    switch (phase) {
      case CallPhase.dialing:
        label = 'Calling…';
        break;
      case CallPhase.connecting:
        label = 'Connecting…';
        break;
      case CallPhase.connected:
        label = _mmss(c.callSeconds.value);
        break;
      case CallPhase.reconnecting:
        label = _mmss(c.callSeconds.value);
        break;
      case CallPhase.ended:
        label = c.endLabel.value;
        break;
      case CallPhase.idle:
        label = '';
        break;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (phase == CallPhase.connected) ...[
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF34C759),
            ),
          ),
          const SizedBox(width: 7),
        ],
        Text(
          label,
          style: AppText.body(size: 15)
              .copyWith(color: Colors.white.withValues(alpha: 0.75)),
        ),
      ],
    );
  }

  Widget _reconnectBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFEF9F27).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: const Color(0xFFEF9F27).withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFFEF9F27)),
          ),
          const SizedBox(width: 10),
          Text(
            'Reconnecting…',
            style: AppText.body(size: 13)
                .copyWith(color: const Color(0xFFEF9F27)),
          ),
        ],
      ),
    );
  }

  Widget _controls(CallService c, CallPhase phase) {
    final live = phase == CallPhase.connected ||
        phase == CallPhase.reconnecting ||
        phase == CallPhase.connecting;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (live) ...[
          _roundButton(
            icon: c.isMuted.value ? Icons.mic_off : Icons.mic,
            label: c.isMuted.value ? 'Unmute' : 'Mute',
            active: c.isMuted.value,
            onTap: c.toggleMute,
          ),
          const SizedBox(width: 26),
        ],
        _roundButton(
          icon: Icons.call_end_rounded,
          label: phase == CallPhase.dialing ? 'Cancel' : 'End',
          background: const Color(0xFFE24B4A),
          onTap: c.hangUp,
          big: true,
        ),
        if (live) ...[
          const SizedBox(width: 26),
          _roundButton(
            icon: c.isSpeaker.value ? Icons.volume_up : Icons.volume_down,
            label: 'Speaker',
            active: c.isSpeaker.value,
            onTap: c.toggleSpeaker,
          ),
        ],
      ],
    );
  }

  Widget _roundButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    bool big = false,
    Color? background,
  }) {
    final size = big ? 70.0 : 58.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: background ??
              (active
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.12)),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                icon,
                size: big ? 30 : 24,
                color: background != null
                    ? Colors.white
                    : (active ? const Color(0xFF10131A) : Colors.white),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: AppText.body(size: 11.5)
              .copyWith(color: Colors.white.withValues(alpha: 0.7)),
        ),
      ],
    );
  }

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'C';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String _mmss(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
