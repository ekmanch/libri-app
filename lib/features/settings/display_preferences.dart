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
    this.hiddenSeriesParts = const {},
    this.shownSeriesParts = const {},
    this.hiddenUpcoming = const {},
    this.upcomingWifiOnly = false,
    this.legacy = const LegacySettings(),
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

  /// The parts not in the library that the owner chose not to see, per
  /// series (Library › Series page: choose what to show): the series'
  /// [seriesKey] to the parts' lookup ids. A series with none is left out.
  final Map<String, Set<String>> hiddenSeriesParts;

  /// The parts the automatic rules count as extras that the owner chose to
  /// see after all (Library › Book series after the automatic rules), in
  /// the same form.
  final Map<String, Set<String>> shownSeriesParts;

  /// The rows of Library › Coming soon: everything that the
  /// owner marked Not interested, by [UpcomingItem.id]: an entry's id, or
  /// `"<entry id>#<season>"` for a show's season. Parts of a series are
  /// hidden through [hiddenSeriesParts] instead.
  final Set<String> hiddenUpcoming;

  /// Only on Wi-Fi (Settings › Upcoming releases): the scheduled checks
  /// skip a day on mobile data. About this phone, so kept here.
  final bool upcomingWifiOnly;

  /// Values read from a `preferences.json` written before `settings.json`
  /// existed, to be carried over into the synced settings once
  /// (`carryOverLegacySettings`); never written back.
  final LegacySettings legacy;

  Set<String> hiddenPartsOf(String seriesKey) =>
      hiddenSeriesParts[seriesKey] ?? const {};

  Set<String> shownPartsOf(String seriesKey) =>
      shownSeriesParts[seriesKey] ?? const {};

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
    Map<String, Set<String>>? hiddenSeriesParts,
    Map<String, Set<String>>? shownSeriesParts,
    Set<String>? hiddenUpcoming,
    bool? upcomingWifiOnly,
    LegacySettings? legacy,
  }) => DisplayPreferences(
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
    viewByType: viewByType ?? this.viewByType,
    musicViewByTab: musicViewByTab ?? this.musicViewByTab,
    sortByType: sortByType ?? this.sortByType,
    filteredSort: filteredSort ?? this.filteredSort,
    artistSort: artistSort ?? this.artistSort,
    hiddenSeriesParts: hiddenSeriesParts ?? this.hiddenSeriesParts,
    shownSeriesParts: shownSeriesParts ?? this.shownSeriesParts,
    hiddenUpcoming: hiddenUpcoming ?? this.hiddenUpcoming,
    upcomingWifiOnly: upcomingWifiOnly ?? this.upcomingWifiOnly,
    legacy: legacy ?? this.legacy,
  );

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
    'hidden_series_parts': _partsJson(hiddenSeriesParts),
    'shown_series_parts': _partsJson(shownSeriesParts),
    'hidden_upcoming': [...hiddenUpcoming]..sort(),
    'upcoming_wifi_only': upcomingWifiOnly,
    // The legacy values are read from an older file and never written: once
    // carried over they are gone.
  };

  static Map<String, List<String>> _partsJson(Map<String, Set<String>> parts) =>
      {
        for (final e in parts.entries) e.key: [...e.value]..sort(),
      };

  static Map<String, Set<String>> _partsFromJson(Object? raw) => {
    if (raw is Map)
      for (final MapEntry(:key, :value) in raw.entries)
        if (key is String && value is List && value.isNotEmpty)
          key: {...value.whereType<String>()},
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
      hiddenSeriesParts: _partsFromJson(json['hidden_series_parts']),
      shownSeriesParts: _partsFromJson(json['shown_series_parts']),
      hiddenUpcoming: switch (json['hidden_upcoming']) {
        final List<Object?> keys => {
          for (final k in keys)
            if (k is String) k,
        },
        _ => const {},
      },
      upcomingWifiOnly: json['upcoming_wifi_only'] == true,
      legacy: LegacySettings.fromJson(json),
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
      _sameParts(other.hiddenSeriesParts, hiddenSeriesParts) &&
      _sameParts(other.shownSeriesParts, shownSeriesParts) &&
      setEquals(other.hiddenUpcoming, hiddenUpcoming) &&
      other.upcomingWifiOnly == upcomingWifiOnly &&
      other.legacy == legacy;

  static bool _sameParts(
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
    _partsHash(hiddenSeriesParts),
    _partsHash(shownSeriesParts),
    Object.hashAllUnordered(hiddenUpcoming),
    upcomingWifiOnly,
    legacy,
  );

  static int _partsHash(Map<String, Set<String>> parts) =>
      Object.hashAllUnordered(
        parts.entries.map(
          (e) => Object.hash(e.key, Object.hashAllUnordered(e.value)),
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

  void setArtistSort(LibrarySort sort) =>
      state = state.copyWith(artistSort: sort);

  void setSort(MediaType type, LibrarySort sort) =>
      state = state.copyWith(sortByType: {...state.sortByType, type: sort});

  void setFilteredSort(LibrarySort sort) =>
      state = state.copyWith(filteredSort: sort);

  /// The parts of the series [seriesKey] to hide, and the extras to show;
  /// an empty set removes the series from that map.
  void setSeriesParts(
    String seriesKey, {
    required Set<String> hidden,
    required Set<String> shown,
  }) {
    Map<String, Set<String>> put(
      Map<String, Set<String>> all,
      Set<String> parts,
    ) => {
      for (final e in all.entries)
        if (e.key != seriesKey) e.key: e.value,
      if (parts.isNotEmpty) seriesKey: {...parts},
    };
    state = state.copyWith(
      hiddenSeriesParts: put(state.hiddenSeriesParts, hidden),
      shownSeriesParts: put(state.shownSeriesParts, shown),
    );
  }

  /// Not interested on a row of Library › Coming soon: everything
  /// (an entry or a season; a part goes through [setSeriesParts]). Since
  /// `settings.json` the keys live there (`SetNotInterested`); this stays
  /// for the carry-over of an older file.
  void hideUpcoming(String key) =>
      state = state.copyWith(hiddenUpcoming: {...state.hiddenUpcoming, key});

  void setUpcomingWifiOnly(bool on) =>
      state = state.copyWith(upcomingWifiOnly: on);

  /// The legacy values were carried over into `settings.json`: forget them,
  /// which saves the file without them.
  void clearLegacy() => state = state.copyWith(
    legacy: const LegacySettings(),
    hiddenUpcoming: const {},
  );
}

/// The settings a `preferences.json` from before `settings.json` may hold
/// (the plan defaults, the default platform; Not interested rows are in
/// `hiddenUpcoming`), each null when the file has no such key. Carried over
/// once into the synced settings, then cleared.
@immutable
class LegacySettings {
  const LegacySettings({
    this.timelineDefault,
    this.seasonalThemeDefault,
    this.defaultPlatform = _absent,
  });

  final bool? timelineDefault;
  final bool? seasonalThemeDefault;

  /// The platform, null for None, or [_absent] when the file has no key.
  final Object? defaultPlatform;

  static const _absent = Object();

  bool get hasDefaultPlatform => defaultPlatform != _absent;

  String? get platform =>
      hasDefaultPlatform ? defaultPlatform as String? : null;

  bool get isEmpty =>
      timelineDefault == null &&
      seasonalThemeDefault == null &&
      !hasDefaultPlatform;

  factory LegacySettings.fromJson(Map<String, Object?> json) {
    final platform = json['default_platform'];
    return LegacySettings(
      timelineDefault: json['timeline_default'] is bool
          ? json['timeline_default'] as bool
          : null,
      seasonalThemeDefault: json['seasonal_theme_default'] is bool
          ? json['seasonal_theme_default'] as bool
          : null,
      defaultPlatform: !json.containsKey('default_platform')
          ? _absent
          : platform is String
          ? platform
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LegacySettings &&
      other.timelineDefault == timelineDefault &&
      other.seasonalThemeDefault == seasonalThemeDefault &&
      other.defaultPlatform == defaultPlatform;

  @override
  int get hashCode =>
      Object.hash(timelineDefault, seasonalThemeDefault, defaultPlatform);
}

final displayPreferencesProvider =
    NotifierProvider<DisplayPreferencesNotifier, DisplayPreferences>(
      DisplayPreferencesNotifier.new,
    );
