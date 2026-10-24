import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/entry.dart';
import '../../data/preferences/preferences_store.dart';
import '../../data/models/media_type.dart';
import '../../data/models/entry_kind.dart';
import '../../theme/app_theme.dart';
import '../library/library_sort.dart';
import '../music/music_tab.dart';
import 'entry_view.dart';

/// Display choices that live on the device, never in `library.json`. They
/// are saved through a [PreferencesStore] whenever one changes.
@immutable
class DisplayPreferences {
  const DisplayPreferences({
    this.themeMode = ThemeMode.dark,
    this.accent = Accents.defaultAccent,
    this.viewByType = const {},
    this.musicViewByTab = const {},
    this.sortByType = const {},
    this.filteredSort = LibrarySort.newestAdded,
    this.artistSort = LibrarySort.yearOldest,
    this.timelineDefault = false,
    this.seasonalThemeDefault = true,
    this.defaultPlatform = 'PC',
    this.hiddenSeriesParts = const {},
  });

  final ThemeMode themeMode;
  final AccentOption accent;

  /// View per type; missing means [EntryView.text]. Music is remembered
  /// per tab instead, in [musicViewByTab].
  final Map<MediaType, EntryView> viewByType;

  /// View per music tab (Library › Music: artists, text view); missing means
  /// [EntryView.text].
  final Map<MusicTab, EntryView> musicViewByTab;

  /// Sort per type's "See all" screen; missing means newest added.
  final Map<MediaType, LibrarySort> sortByType;

  /// Sort of the filtered results on the library home.
  final LibrarySort filteredSort;

  /// Order of the albums and songs on an artist's screen (Music › Artist, text
  /// view).
  final LibrarySort artistSort;

  /// What a new plan's Timeline and Seasonal theme switches start as (Plans ›
  /// New plan); set in Settings.
  final bool timelineDefault;
  final bool seasonalThemeDefault;

  /// Pre-selected on a new game that came out on it (Add / edit entry); null
  /// means none. The choices are listed in Settings.
  final String? defaultPlatform;

  /// The parts not in the library that the owner chose not to see, per
  /// series (Library › Series page: choose what to show): the series'
  /// [seriesKey] to the parts' lookup ids. A series with none is left out.
  final Map<String, Set<String>> hiddenSeriesParts;

  Set<String> hiddenPartsOf(String seriesKey) =>
      hiddenSeriesParts[seriesKey] ?? const {};

  static const platformChoices = [
    'PC',
    'PlayStation 5',
    'Xbox Series X|S',
    'Switch 2',
    'Steam Deck',
  ];

  EntryView viewFor(MediaType type) => viewByType[type] ?? EntryView.text;

  EntryView viewForMusic(MusicTab tab) => musicViewByTab[tab] ?? EntryView.text;

  /// The view that decides whether an entry's details show images: its
  /// type's view, or for music the Albums or Songs tab's.
  EntryView viewForEntry(Entry entry) => switch (entry.type) {
    MediaType.music => viewForMusic(
      entry.kind == EntryKind.song ? MusicTab.songs : MusicTab.albums,
    ),
    _ => viewFor(entry.type),
  };

  LibrarySort sortFor(MediaType type) =>
      sortByType[type] ?? LibrarySort.newestAdded;

  DisplayPreferences copyWith({
    ThemeMode? themeMode,
    AccentOption? accent,
    Map<MediaType, EntryView>? viewByType,
    Map<MusicTab, EntryView>? musicViewByTab,
    Map<MediaType, LibrarySort>? sortByType,
    LibrarySort? filteredSort,
    LibrarySort? artistSort,
    bool? timelineDefault,
    bool? seasonalThemeDefault,
    Object? defaultPlatform = _keep,
    Map<String, Set<String>>? hiddenSeriesParts,
  }) => DisplayPreferences(
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
    viewByType: viewByType ?? this.viewByType,
    musicViewByTab: musicViewByTab ?? this.musicViewByTab,
    sortByType: sortByType ?? this.sortByType,
    filteredSort: filteredSort ?? this.filteredSort,
    artistSort: artistSort ?? this.artistSort,
    timelineDefault: timelineDefault ?? this.timelineDefault,
    seasonalThemeDefault: seasonalThemeDefault ?? this.seasonalThemeDefault,
    defaultPlatform: defaultPlatform == _keep
        ? this.defaultPlatform
        : defaultPlatform as String?,
    hiddenSeriesParts: hiddenSeriesParts ?? this.hiddenSeriesParts,
  );

  /// Sentinel for [copyWith], so a null [defaultPlatform] can be set.
  static const _keep = Object();

  /// The stored form. Enums are written by name and the accent by its id,
  /// so reordering an enum never changes a saved choice.
  Map<String, Object?> toJson() => {
    'version': 1,
    'theme': themeMode.name,
    'accent': accent.id,
    'view': {for (final e in viewByType.entries) e.key.name: e.value.name},
    'music_view': {
      for (final e in musicViewByTab.entries) e.key.name: e.value.name,
    },
    'sort': {for (final e in sortByType.entries) e.key.name: e.value.name},
    'filtered_sort': filteredSort.name,
    'artist_sort': artistSort.name,
    'timeline_default': timelineDefault,
    'seasonal_theme_default': seasonalThemeDefault,
    'default_platform': defaultPlatform,
    'hidden_series_parts': {
      for (final e in hiddenSeriesParts.entries) e.key: [...e.value]..sort(),
    },
  };

  /// Reads [toJson]'s form. Anything missing or unknown, such as a value
  /// from a newer build, falls back to its default.
  factory DisplayPreferences.fromJson(Map<String, Object?> json) {
    const defaults = DisplayPreferences();
    T? byName<T extends Enum>(List<T> values, Object? name) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return null;
    }

    Map<K, V> mapOf<K extends Enum, V extends Enum>(
      Object? raw,
      List<K> keys,
      List<V> values,
    ) => {
      if (raw is Map)
        for (final MapEntry(:key, :value) in raw.entries)
          ?byName(keys, key): ?byName(values, value),
    };

    final platform = json['default_platform'];
    final hidden = json['hidden_series_parts'];
    return DisplayPreferences(
      themeMode: byName(ThemeMode.values, json['theme']) ?? defaults.themeMode,
      accent: switch (json['accent']) {
        final String id => Accents.byId(id) ?? defaults.accent,
        _ => defaults.accent,
      },
      viewByType: mapOf(json['view'], MediaType.values, EntryView.values),
      musicViewByTab: mapOf(
        json['music_view'],
        MusicTab.values,
        EntryView.values,
      ),
      sortByType: mapOf(json['sort'], MediaType.values, LibrarySort.values),
      filteredSort:
          byName(LibrarySort.values, json['filtered_sort']) ??
          defaults.filteredSort,
      artistSort:
          byName(LibrarySort.values, json['artist_sort']) ??
          defaults.artistSort,
      timelineDefault: switch (json['timeline_default']) {
        final bool on => on,
        _ => defaults.timelineDefault,
      },
      seasonalThemeDefault: switch (json['seasonal_theme_default']) {
        final bool on => on,
        _ => defaults.seasonalThemeDefault,
      },
      defaultPlatform: !json.containsKey('default_platform')
          ? defaults.defaultPlatform
          : platform is String
          ? platform
          : null,
      hiddenSeriesParts: {
        if (hidden is Map)
          for (final MapEntry(:key, :value) in hidden.entries)
            if (key is String && value is List && value.isNotEmpty)
              key: {...value.whereType<String>()},
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DisplayPreferences &&
      other.themeMode == themeMode &&
      other.accent == accent &&
      mapEquals(other.viewByType, viewByType) &&
      mapEquals(other.musicViewByTab, musicViewByTab) &&
      mapEquals(other.sortByType, sortByType) &&
      other.filteredSort == filteredSort &&
      other.artistSort == artistSort &&
      other.timelineDefault == timelineDefault &&
      other.seasonalThemeDefault == seasonalThemeDefault &&
      other.defaultPlatform == defaultPlatform &&
      _sameHidden(other.hiddenSeriesParts, hiddenSeriesParts);

  static bool _sameHidden(
    Map<String, Set<String>> a,
    Map<String, Set<String>> b,
  ) =>
      a.length == b.length &&
      a.entries.every((e) => setEquals(b[e.key], e.value));

  @override
  int get hashCode => Object.hash(
    themeMode,
    accent,
    Object.hashAllUnordered(viewByType.entries.map((e) => (e.key, e.value))),
    Object.hashAllUnordered(
      musicViewByTab.entries.map((e) => (e.key, e.value)),
    ),
    Object.hashAllUnordered(sortByType.entries.map((e) => (e.key, e.value))),
    filteredSort,
    artistSort,
    timelineDefault,
    seasonalThemeDefault,
    defaultPlatform,
    Object.hashAllUnordered(
      hiddenSeriesParts.entries.map(
        (e) => Object.hash(e.key, Object.hashAllUnordered(e.value)),
      ),
    ),
  );
}

/// Where the preferences are saved. Outside the running app nothing is
/// kept; `main` overrides this with the file store.
final preferencesStoreProvider = Provider<PreferencesStore>(
  (ref) => MemoryPreferencesStore(),
);

/// The preferences as read at startup, before the first frame, so the app
/// opens in the saved theme without a flash. Overridden in `main`.
final initialDisplayPreferencesProvider = Provider<DisplayPreferences>(
  (ref) => const DisplayPreferences(),
);

class DisplayPreferencesNotifier extends Notifier<DisplayPreferences> {
  @override
  DisplayPreferences build() {
    listenSelf((previous, next) {
      if (previous != null && previous != next) {
        // A failed save only loses a display choice; the app goes on.
        ref
            .read(preferencesStoreProvider)
            .save(next.toJson())
            .catchError((Object _) {});
      }
    });
    return ref.watch(initialDisplayPreferencesProvider);
  }

  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);

  /// Swaps in a whole set of preferences, e.g. in tests.
  void replace(DisplayPreferences prefs) => state = prefs;

  void setAccent(AccentOption accent) => state = state.copyWith(accent: accent);

  void setView(MediaType type, EntryView view) =>
      state = state.copyWith(viewByType: {...state.viewByType, type: view});

  void setMusicView(MusicTab tab, EntryView view) => state = state.copyWith(
    musicViewByTab: {...state.musicViewByTab, tab: view},
  );

  void setTimelineDefault(bool on) =>
      state = state.copyWith(timelineDefault: on);

  void setSeasonalThemeDefault(bool on) =>
      state = state.copyWith(seasonalThemeDefault: on);

  void setDefaultPlatform(String? platform) =>
      state = state.copyWith(defaultPlatform: platform);

  void setArtistSort(LibrarySort sort) =>
      state = state.copyWith(artistSort: sort);

  void setSort(MediaType type, LibrarySort sort) =>
      state = state.copyWith(sortByType: {...state.sortByType, type: sort});

  void setFilteredSort(LibrarySort sort) =>
      state = state.copyWith(filteredSort: sort);

  /// The parts of the series [seriesKey] to hide; none removes the series.
  void setHiddenParts(String seriesKey, Set<String> parts) =>
      state = state.copyWith(
        hiddenSeriesParts: {
          for (final e in state.hiddenSeriesParts.entries)
            if (e.key != seriesKey) e.key: e.value,
          if (parts.isNotEmpty) seriesKey: {...parts},
        },
      );
}

final displayPreferencesProvider =
    NotifierProvider<DisplayPreferencesNotifier, DisplayPreferences>(
      DisplayPreferencesNotifier.new,
    );
