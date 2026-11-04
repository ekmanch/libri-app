import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/entry.dart';
import '../models/entry_kind.dart';
import '../models/entry_status.dart';
import '../models/library.dart';
import '../models/media_type.dart';
import '../models/season.dart';
import '../models/season_span.dart';
import '../models/season_split.dart';
import '../operations/entry_operations.dart';
import '../operations/library_operation.dart';
import '../operations/season_operations.dart';
import '../storage/json_file.dart';
import '../upcoming/check_control.dart';
import 'lookup_failure.dart';
import 'lookup_service.dart';
import 'lookup_source.dart';
import 'season_parts.dart';

/// What the daily check keeps on the device (never in `library.json`):
/// the day it last ran, and the seasons it found missing from the lookup
/// on that run, as `"<entry id>#<season>"`.
abstract class SeasonCheckStore {
  Future<DateTime?> lastRun();

  Future<Set<String>> missing();

  Future<void> recordRun(DateTime day, Set<String> missing);
}

/// `season_check.json` under the cache folder:
/// `{"checked": "2026-10-18", "missing": ["shows/carrie-2026#2"]}`. A
/// cleared cache only means one extra check, and a dropped season waiting
/// one more day.
class FileSeasonCheckStore implements SeasonCheckStore {
  FileSeasonCheckStore(Directory cache)
    : _file = JsonFile(
        File('${cache.path}${Platform.pathSeparator}season_check.json'),
      );

  final JsonFile _file;

  @override
  Future<DateTime?> lastRun() async {
    final checked = (await _file.read())?['checked'];
    return checked is String ? DateTime.tryParse(checked) : null;
  }

  @override
  Future<Set<String>> missing() async {
    final missing = (await _file.read())?['missing'];
    return {
      if (missing is List)
        for (final key in missing)
          if (key is String) key,
    };
  }

  @override
  Future<void> recordRun(DateTime day, Set<String> missing) => _file.write({
    'checked':
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}',
    'missing': [...missing]..sort(),
  });
}

class MemorySeasonCheckStore implements SeasonCheckStore {
  DateTime? _day;
  Set<String> _missing = {};

  @override
  Future<DateTime?> lastRun() async => _day;

  @override
  Future<Set<String>> missing() async => _missing;

  @override
  Future<void> recordRun(DateTime day, Set<String> missing) async {
    _day = day;
    _missing = missing;
  }
}

/// A season the lookup dropped that has a status, so the user is asked
/// whether to keep it (Show & seasons › Announced season dropped).
typedef DroppedSeason = ({String entryId, int season, EntryStatus status});

/// What one daily check found: operations to apply at once, and seasons
/// to ask about.
typedef SeasonCheckResult = ({
  List<LibraryOperation> operations,
  List<DroppedSeason> dropped,
});

/// The daily check (DESIGN.md 10c). Once a day it asks the lookup about
/// every show linked to TMDB, and every anime linked to AniList (or, with
/// no AniList id, to a TMDB show) that is not a movie, that is not DNF, and
/// once about any such entry without seasons whatever its status:
///
/// - An anime stored without a kind learns it from the lookup: a movie is
///   marked so and left alone from then on; a series is marked so and gets
///   its seasons like a show.
/// - An anime series without its TMDB show (`Entry.tmdb`) gets the one the
///   lookup finds ([SetTmdbShow]).
/// - The seasons are read in the split the show's are in ([_inSplit]:
///   its `seasons_from`, or the split its seasons' shape fits); the check
///   never re-splits or merges. A show with no seasons yet gets the split
///   Libri picks on its own, written as its `seasons_from`. Seasons set by
///   hand (every season manual) are not asked about.
/// - Seasons numbered above the show's highest that have a date are added,
///   marked New on a show that had seasons; a show that had none gets them
///   quietly, its own date dropped and its status carried over.
/// - Seasons not out yet that Libri added get the lookup's new date.
/// - A season not out yet that Libri added, missing from the lookup or on
///   a show marked Canceled there on two checks in a row, is removed when
///   it has no status, and asked about when it has one.
/// - A show whose stored status differs from what its seasons give (a
///   season has come out) gets it written.
/// - An anime series in AniList's own split has the parts of its seasons
///   still to come recorded in [parts] (`season_parts.json`), for Coming
///   soon's "Season 3, Part 2" rows; a show not asked keeps its parts, a
///   show gone from the library loses them.
///
/// Seasons added in the form, kept when asked, or already out are never
/// removed. The day is recorded only when no lookup was offline or rate
/// limited, so a check without a connection runs again on the next open.
class SeasonCheck {
  SeasonCheck({
    required this.lookups,
    required this.store,
    ComingPartsStore? parts,
  }) : parts = parts ?? MemoryComingPartsStore();

  final LookupService lookups;
  final SeasonCheckStore store;

  /// The coming parts of seasons as last recorded.
  final ComingPartsStore parts;

  bool _running = false;

  static const _none = (
    operations: <LibraryOperation>[],
    dropped: <DroppedSeason>[],
  );

  /// Whether the check asks the lookup about [entry]: a show linked to
  /// TMDB, or an anime linked to AniList or a TMDB show that is not a movie
  /// (a series, or one whose kind is not known yet).
  static bool isAsked(Entry entry) {
    final source = entry.source ?? '';
    final linked = switch (entry.type) {
      MediaType.shows => source.startsWith('tmdb:tv:'),
      MediaType.anime =>
        entry.kind != EntryKind.movie &&
            (source.startsWith('anilist:') || source.startsWith('tmdb:tv:')),
      _ => false,
    };
    return linked &&
        (entry.status != EntryStatus.dnf || (entry.seasons?.isEmpty ?? true));
  }

  static String _key(String entryId, int season) => '$entryId#$season';

  /// Runs the check when it is due today (always with [force]: Check now),
  /// asking about every show [isAsked], or with [include] only those it
  /// says (the scheduler's daily and weekly shares, DESIGN.md 10c: the
  /// rest keep what the last run knew). [control] hears of each show asked
  /// and can stop the run, which then records no day.
  Future<SeasonCheckResult> run(
    Library library,
    DateTime now, {
    bool force = false,
    bool Function(Entry show)? include,
    CheckControl? control,
  }) async {
    if (_running) return _none;
    final today = DateTime(now.year, now.month, now.day);
    if (!force) {
      final last = await store.lastRun();
      if (last != null && !last.isBefore(today)) return _none;
    }
    final ctl = control ?? CheckControl.none;
    _running = true;
    try {
      final previous = await store.missing();
      final missing = <String>{};
      final operations = <LibraryOperation>[];
      final dropped = <DroppedSeason>[];
      final touched = <String>{};
      final kept = await parts.read();
      final ids = {for (final e in library.entries) e.id};
      final coming = [
        for (final p in kept)
          if (ids.contains(p.entryId)) p,
      ];
      var partsChanged = coming.length != kept.length;
      var complete = true;
      for (final show in library.entries.where(isAsked)) {
        if (include != null && !include(show)) {
          // Not this show's day: what was missing stays missing.
          missing.addAll(previous.where((k) => k.startsWith('${show.id}#')));
          continue;
        }
        if (ctl.cancelled) {
          complete = false;
          break;
        }
        final source = lookups.sourceOf(show.source!);
        if (source == null || !source.isConfigured) continue;
        // Seasons set by hand (Add / edit entry › Split into: Set by hand):
        // no source touches them.
        if (show.seasonsByHand) {
          ctl.tick();
          continue;
        }
        final anime = show.type == MediaType.anime;
        final ShowSeasons? fetched;
        ({List<Season> seasons, String? from})? inSplit;
        try {
          fetched = await source.seasons(show.source!, anime: anime);
          if (fetched != null &&
              (!anime || (show.kind ?? fetched.kind) == EntryKind.series)) {
            inSplit = await _inSplit(source, show, fetched, today);
          }
        } on LookupException catch (e) {
          if (e.failure == LookupFailure.offline ||
              e.failure == LookupFailure.rateLimited) {
            complete = false;
            break;
          }
          // Not found or a bad answer: nothing learned, so a season it
          // missed before stays missed. A server error (5xx) is not an
          // answer either, and leaves the day's check to run again.
          if (e.isTransient) complete = false;
          missing.addAll(previous.where((k) => k.startsWith('${show.id}#')));
          ctl.tick();
          continue;
        }
        ctl.tick();
        if (fetched == null) continue;
        // An anime stored without a kind: the lookup's. A movie has no
        // seasons to add; a series goes on like a show.
        if (anime && show.kind == null) {
          final kind = fetched.kind;
          if (kind == null) continue;
          operations.add(SetKind(show.id, kind));
          if (kind == EntryKind.movie) continue;
        }
        // An anime series without its TMDB show (the episode titles come
        // from there): the lookup's, written so every device reads the same.
        if (anime &&
            show.tmdb == null &&
            (show.kind ?? fetched.kind) == EntryKind.series) {
          if (await source.tmdbShow(show.source!) case final linked?) {
            operations.add(SetTmdbShow(show.id, linked));
          }
        }
        // The split the seasons are in could not be told: the show is
        // left as it is until a split is picked in the form.
        if (inSplit == null) {
          missing.addAll(previous.where((k) => k.startsWith('${show.id}#')));
          continue;
        }
        // The coming parts of its seasons, in the lookup's own split only
        // (a part is its own season elsewhere).
        if (anime && source.isOwnSplit(show.seasonsFrom)) {
          final found = await source.seasonParts(show.source!);
          final mine = [
            for (final p in found)
              ComingPart(
                entryId: show.id,
                season: p.season,
                part: p.part,
                released: p.released,
              ),
          ];
          final before = [
            for (final p in coming)
              if (p.entryId == show.id) p,
          ];
          if (!listEquals(before, mine)) {
            coming
              ..removeWhere((p) => p.entryId == show.id)
              ..addAll(mine);
            partsChanged = true;
          }
        }
        final existing = show.seasons ?? const <Season>[];
        final highest = existing.isEmpty ? 0 : existing.last.season;
        final listed = {for (final s in inSplit.seasons) s.season: s};

        final added = [
          for (final s in Season.listable(inSplit.seasons))
            if (s.season > highest)
              existing.isEmpty ? s : s.copyWith(fresh: true),
        ];
        if (added.isNotEmpty) {
          operations.add(
            AddSeasons(
              show.id,
              added,
              from: existing.isEmpty ? inSplit.from : null,
            ),
          );
        }

        final redated = <Season>[];
        for (final s in existing) {
          if (s.isManual || s.isReleasedOn(today)) continue;
          final date = listed[s.season]?.released;
          if (date != null && date != s.released) {
            redated.add(Season(season: s.season, released: date));
          }
        }
        if (redated.isNotEmpty) {
          operations.add(SetSeasonDates(show.id, redated));
        }

        for (final s in existing) {
          if (s.isManual || s.isReleasedOn(today)) continue;
          if (!fetched.canceled && listed.containsKey(s.season)) continue;
          final key = _key(show.id, s.season);
          missing.add(key);
          if (!previous.contains(key)) continue;
          if (s.status case final status?) {
            dropped.add((entryId: show.id, season: s.season, status: status));
          } else {
            operations.add(RemoveSeason(show.id, s.season));
          }
        }
        if (added.isNotEmpty || redated.isNotEmpty) touched.add(show.id);
      }
      if (complete) {
        // A show whose status its seasons no longer give: a season came
        // out. The operations above write it already for their shows.
        for (final show in library.entries) {
          final seasons = show.seasons;
          if (!show.usesSeasons ||
              seasons == null ||
              seasons.isEmpty ||
              touched.contains(show.id)) {
            continue;
          }
          if (Season.showStatus(seasons, today) != show.status) {
            operations.add(RefreshShowStatus(show.id));
          }
        }
        await store.recordRun(today, missing);
      }
      if (partsChanged) await parts.write(coming);
      return (operations: operations, dropped: dropped);
    } finally {
      _running = false;
    }
  }

  /// The seasons of [show] as the split its seasons are in has them now,
  /// and the split's id to write with a show's first seasons (section
  /// 10c). [regular] is the provider's own list, read already.
  ///
  /// - `seasons_from` names the split: that split's seasons, or null when
  ///   the provider no longer has it (nothing learned).
  /// - No seasons yet: the split Libri picks on its own
  ///   ([SeasonSplit.automatic]) among every split the sources offer, its
  ///   id written with the seasons; the provider's own list when there
  ///   are none.
  /// - Seasons from before splits: the provider's own list when it fits
  ///   them ([SeasonSplit.fits]); for an anime that fits with seasons
  ///   beyond them, the TMDB show's own list is asked for first, in case
  ///   it fits exactly (seasons still the TMDB show's one season, not
  ///   AniList's two: adding AniList's would re-split them by stealth),
  ///   else the own list stands and its new seasons are added; when the
  ///   own list does not fit at all, the split among every one the sources
  ///   offer that fits best ([SeasonSplit.fitting]), else null and the
  ///   show is left alone.
  ///
  /// Checks never re-split or merge: they update and add within the split
  /// found here.
  Future<({List<Season> seasons, String? from})?> _inSplit(
    LookupSource source,
    Entry show,
    ShowSeasons regular,
    DateTime today,
  ) async {
    final anime = show.type == MediaType.anime;
    final existing = show.seasons ?? const <Season>[];
    bool isOwn(SeasonSplit s) => s.ids.any(source.isOwnSplit);
    List<Season> seasonsOf(SeasonSplit s) =>
        isOwn(s) ? regular.seasons : s.toSeasons();

    if (show.seasonsFrom case final from?) {
      if (source.isOwnSplit(from)) {
        return (seasons: regular.seasons, from: null);
      }
      final split = await source.splitSeasons(
        show.source!,
        from,
        anime: anime,
        tmdb: show.tmdb,
      );
      return split == null ? null : (seasons: split.seasons, from: null);
    }
    Future<List<SeasonSplit>> splits() async {
      final found = await source.seasonSplits(show.source!, tmdb: show.tmdb);
      return found == null ? const [] : SeasonSplit.distinct(found);
    }

    if (existing.isEmpty) {
      final auto = SeasonSplit.automatic(await splits());
      if (auto == null) return (seasons: regular.seasons, from: null);
      return (seasons: seasonsOf(auto), from: auto.id);
    }
    // Only dated seasons count: an undated one is never added anyway.
    final own = SeasonSplit(
      ids: const ['own'],
      seasons: [
        for (final s in Season.listable(regular.seasons))
          SeasonSpan(season: s.season, released: s.released),
      ],
    );
    final fitsOwn = own.fits(existing, today);
    // A show has one regular list, TMDB's: nothing else could fit it
    // exactly, so the groups are not read for it.
    if (fitsOwn && (!anime || own.beyond(existing) == 0)) {
      return (seasons: regular.seasons, from: null);
    }
    final all = await splits();
    if (fitsOwn) {
      for (final s in all) {
        if (!isOwn(s) &&
            s.ids.any(SeasonSplit.isRegular) &&
            s.fits(existing, today) &&
            s.beyond(existing) == 0) {
          return (seasons: s.toSeasons(), from: null);
        }
      }
      return (seasons: regular.seasons, from: null);
    }
    final fit = SeasonSplit.fitting(all, existing, today);
    return fit == null ? null : (seasons: seasonsOf(fit), from: null);
  }
}
