import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

/// App-wide connectivity gate.
///
/// Listens to radio-state changes (`connectivity_plus`) AND re-checks on
/// app-resume, but every decision is confirmed with a REAL reachability probe
/// (a DNS lookup with a timeout) — so "connected to Wi-Fi but no actual
/// internet" (captive portals, dead routers) is correctly treated as offline.
///
/// [isOnline] drives the global `NoInternetScreen` overlay mounted in
/// `GetMaterialApp.builder`; the overlay auto-dismisses the moment this flips
/// back to true.
class ConnectivityController extends GetxController
    with WidgetsBindingObserver {
  /// Optimistic default (true) so a healthy connection never flashes the
  /// offline screen on cold start; the initial probe corrects it within the
  /// lookup timeout if we're actually offline.
  final RxBool isOnline = true.obs;

  /// Drives the Refresh button's spinner while a manual re-check runs.
  final RxBool isChecking = false.obs;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;

  // Hosts probed for real reachability (any one succeeding = online).
  static const List<String> _probeHosts = ['google.com', 'cloudflare.com'];
  static const Duration _probeTimeout = Duration(seconds: 4);

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    // Re-verify on any radio change (Wi-Fi ↔ mobile ↔ none).
    _sub = _connectivity.onConnectivityChanged.listen((_) => _verify());
    _verify();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.onClose();
  }

  // Networks can change while the app is backgrounded without firing a stream
  // event — re-verify whenever the app comes back to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _verify();
  }

  /// Manual re-check from the offline screen's Refresh button.
  Future<void> recheck() async {
    if (isChecking.value) return;
    isChecking.value = true;
    try {
      await _verify();
    } finally {
      isChecking.value = false;
    }
  }

  Future<void> _verify() async {
    bool online;
    try {
      final radio = await _connectivity.checkConnectivity();
      final hasRadio = radio.any((r) => r != ConnectivityResult.none);
      online = hasRadio && await _hasRealInternet();
    } catch (_) {
      online = false;
    }
    if (isOnline.value != online) isOnline.value = online;
  }

  /// True only if a host actually resolves — filters out "radio up, internet
  /// down" false positives.
  Future<bool> _hasRealInternet() async {
    for (final host in _probeHosts) {
      try {
        final res = await InternetAddress.lookup(host).timeout(_probeTimeout);
        if (res.isNotEmpty && res.first.rawAddress.isNotEmpty) return true;
      } catch (_) {
        // try the next host
      }
    }
    return false;
  }
}
