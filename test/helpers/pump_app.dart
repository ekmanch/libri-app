import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_codec.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/app_settings.dart';
import 'package:library_app/data/models/library.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/data/repository/library_repository.dart';
import 'package:library_app/dev/fake_lookup_overrides.dart';
import 'package:library_app/features/settings/display_preferences.dart';
import 'package:library_app/theme/app_theme.dart';

import 'package_info.dart';

/// The bundled fixture, read once per test file.
Library loadFixture() =>
    decodeLibrary(File(FixtureLibraryRepository.assetPath).readAsStringSync());

/// Pumps [home] inside a MaterialApp with the app theme and a provider
/// container whose repository serves [library] and whose lookups are the
/// fake (or [lookupOverrides]), and whose settings start as [settings].
/// Returns the container.
Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  Widget home, {
  Library? library,
  Size size = const Size(360, 780),
  DisplayPreferences? prefs,
  AppSettings? settings,
  LibraryRepository? repository,
  List<Override> overrides = const [],
  List<Override>? lookupOverrides,
}) async {
  final lib = library ?? loadFixture();
  mockPackageInfo();
  final container = ProviderContainer(
    overrides: [
      libraryRepositoryProvider.overrideWithValue(
        repository ??
            FixtureLibraryRepository(
              loadJson: () async => encodeLibrary(lib),
              settings: settings ?? AppSettings.defaults,
            ),
      ),
      ...lookupOverrides ?? fakeLookupOverrides(),
      ...overrides,
    ],
  );
  if (prefs != null) {
    container.read(displayPreferencesProvider.notifier).replace(prefs);
  }
  addTearDown(container.dispose);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(brightness: Brightness.dark),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}
