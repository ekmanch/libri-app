import 'dart:convert';

import 'models/app_settings.dart';

/// The one place `settings.json` text is produced (DESIGN.md section 8).
/// Canonical like `library.json`: two-space indent, one trailing newline,
/// keys in the model's order and only the keys that differ from the
/// defaults, so a save is a minimal git diff. A new file is
/// `{"version": 1}`.
const _encoder = JsonEncoder.withIndent('  ');

/// Decodes [text]. Not a JSON object, or a version this build does not
/// know, is a [FormatException]; the caller keeps the file aside.
AppSettings decodeSettings(String text) {
  final json = jsonDecode(text);
  if (json is! Map<String, Object?>) {
    throw const FormatException('settings.json is not a JSON object');
  }
  final version = json['version'];
  if (version != null && version != AppSettings.version) {
    throw FormatException('settings.json version $version is not supported');
  }
  return AppSettings.fromJson(json);
}

String encodeSettings(AppSettings settings) =>
    '${_encoder.convert(settings.toJson())}\n';

/// The text of a new file, and of settings that are all defaults.
final String emptySettingsText = encodeSettings(AppSettings.defaults);
