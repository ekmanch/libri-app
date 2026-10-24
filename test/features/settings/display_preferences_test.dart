import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:library_app/data/library_providers.dart';
import 'package:library_app/data/models/media_type.dart';
import 'package:library_app/data/preferences/preferences_store.dart';
import 'package:library_app/data/repository/fixture_library_repository.dart';
import 'package:library_app/features/library/library_sort.dart';
import 'package:library_app/features/music/music_tab.dart';
import 'package:library_app/features/settings/display_preferences.dart';
import 'package:library_app/features/settings/entry_view.dart';
import 'package:library_app/main.dart';
import 'package:library_app/theme/app_theme.dart';

void main() {
  testWidgets('theme and accent changes apply to the whole app at once', (
    tester,
  ) async {
    final text = File(FixtureLibraryRepository.assetPath).readAsStringSync();
    final container = ProviderContainer(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(
          FixtureLibraryRepository(loadJson: () async => text),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LibraryApp(),
      ),
    );
    await tester.pumpAndSettle();

    ThemeData theme() => Theme.of(tester.element(find.text('Library').first));
    expect(theme().brightness, Brightness.dark);
    expect(theme().colorScheme.primary, Accents.hotPink.fill);

    final violet = Accents.vivid.first;
    container.read(displayPreferencesProvider.notifier).setAccent(violet);
    await tester.pumpAndSettle();
    expect(theme().colorScheme.primary, violet.fill);
    expect(theme().colorScheme.primaryContainer, violet.fill);

    container
        .read(displayPreferencesProvider.notifier)
        .setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(theme().brightness, Brightness.light);
    expect(theme().colorScheme.primary, violet.ink);
    expect(theme().colorScheme.primaryContainer, violet.fill);
  });

  test('preferences default to dark and hot pink', () {
    const prefs = DisplayPreferences();
    expect(prefs.themeMode, ThemeMode.dark);
    expect(prefs.accent, Accents.hotPink);
    expect(prefs.copyWith(themeMode: ThemeMode.light).accent, Accents.hotPink);
  });
  final changed = DisplayPreferences(
    themeMode: ThemeMode.light,
    accent: Accents.pastel.first,
    viewByType: const {MediaType.movies: EntryView.grid},
    musicViewByTab: const {MusicTab.songs: EntryView.listWithPhotos},
    sortByType: const {MediaType.books: LibrarySort.titleAz},
    filteredSort: LibrarySort.yearNewest,
    artistSort: LibrarySort.titleAz,
    timelineDefault: true,
    seasonalThemeDefault: false,
    defaultPlatform: null,
    hiddenSeriesParts: const {
      'books:dune': {'wikidata:Q7', 'wikidata:Q8'},
    },
  );

  test('preferences survive the stored form', () {
    expect(DisplayPreferences.fromJson(changed.toJson()), changed);
    expect(
      DisplayPreferences.fromJson(const DisplayPreferences().toJson()),
      const DisplayPreferences(),
    );
    expect(DisplayPreferences.fromJson(const {}), const DisplayPreferences());
  });

  test('unknown or broken values fall back to the defaults', () {
    final prefs = DisplayPreferences.fromJson(const {
      'theme': 'sepia',
      'accent': 'vivid/Plaid',
      'view': {'movies': 'carousel', 'podcasts': 'grid', 'books': 'grid'},
      'sort': 'titleAz',
      'timeline_default': 'yes',
      'default_platform': 5,
      'hidden_series_parts': {'books:dune': 'wikidata:Q7', 'movies:x': []},
    });
    expect(prefs.themeMode, ThemeMode.dark);
    expect(prefs.accent, Accents.hotPink);
    expect(prefs.viewByType, {MediaType.books: EntryView.grid});
    expect(prefs.sortByType, isEmpty);
    expect(prefs.timelineDefault, isFalse);
    expect(prefs.defaultPlatform, isNull);
    expect(prefs.hiddenSeriesParts, isEmpty);
  });

  test('hiding parts replaces the series\' set; none removes it', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(displayPreferencesProvider.notifier);
    notifier.setHiddenParts('books:dune', {'wikidata:Q7'});
    notifier.setHiddenParts('books:berserk', {'a'});
    notifier.setHiddenParts('books:dune', {'wikidata:Q8'});
    expect(container.read(displayPreferencesProvider).hiddenSeriesParts, {
      'books:dune': {'wikidata:Q8'},
      'books:berserk': {'a'},
    });
    notifier.setHiddenParts('books:dune', {});
    expect(
      container.read(displayPreferencesProvider).hiddenPartsOf('books:dune'),
      isEmpty,
    );
    expect(container.read(displayPreferencesProvider).hiddenSeriesParts.keys, [
      'books:berserk',
    ]);
  });

  test('every change is saved to the store; the start values are not', () {
    final store = MemoryPreferencesStore();
    final container = ProviderContainer(
      overrides: [
        preferencesStoreProvider.overrideWithValue(store),
        initialDisplayPreferencesProvider.overrideWithValue(changed),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(displayPreferencesProvider.notifier);
    expect(container.read(displayPreferencesProvider), changed);
    expect(store.saved, isEmpty);

    notifier.setView(MediaType.games, EntryView.listWithPhotos);
    expect(
      DisplayPreferences.fromJson(store.saved).viewFor(MediaType.games),
      EntryView.listWithPhotos,
    );
    notifier.setThemeMode(ThemeMode.dark);
    expect(store.saved['theme'], 'dark');
  });
}
