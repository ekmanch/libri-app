import 'dart:io';

/// Whether the phone is on mobile data, for Only on Wi-Fi (Settings ›
/// Upcoming releases): the scheduled checks skip the day's run on mobile
/// data; Check now runs anyway.
abstract class NetworkKind {
  /// True only when the phone is known to be on mobile data. Unknown (no
  /// interface says either way, a desktop) is false, so nothing is skipped
  /// by mistake.
  Future<bool> isOnMobileData();
}

/// Reads the network interfaces that are up: Android names its Wi-Fi
/// interface `wlan0` and its mobile data `rmnet…` (Qualcomm), `ccmni…`
/// (MediaTek) or `pdp…`; a wired or Wi-Fi interface with an address means
/// not mobile. Without a package, so it is a best effort.
class InterfaceNetworkKind implements NetworkKind {
  const InterfaceNetworkKind();

  static final _wifiOrWired = RegExp(r'^(wlan|wifi|wl|eth|en|ap)\d*');
  static final _mobile = RegExp(r'^(rmnet|ccmni|pdp|ppp|wwan|usb)\w*');

  @override
  Future<bool> isOnMobileData() async {
    final List<NetworkInterface> interfaces;
    try {
      interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
      );
    } on Object {
      return false;
    }
    var mobile = false;
    for (final interface in interfaces) {
      if (interface.addresses.isEmpty) continue;
      final name = interface.name.toLowerCase();
      if (_wifiOrWired.hasMatch(name)) return false;
      if (_mobile.hasMatch(name)) mobile = true;
    }
    return mobile;
  }
}

/// A fixed answer, for tests.
class FixedNetworkKind implements NetworkKind {
  const FixedNetworkKind({this.mobile = false});

  final bool mobile;

  @override
  Future<bool> isOnMobileData() async => mobile;
}
