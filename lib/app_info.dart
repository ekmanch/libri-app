import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The app's name, shown on the splash (F1), the welcome screen (F2) and
/// in Settings, About (S6).
const appName = 'Libri';

/// The version from the build (`version:` in pubspec.yaml), for About.
final appVersionProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
);

/// The build number from the build (after the "+" in `version:`), for About.
final appBuildNumberProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).buildNumber,
);
