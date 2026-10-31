import '../lookup/check_day_store.dart';
import '../lookup/lookup_failure.dart';
import '../lookup/lookup_match.dart';
import '../lookup/lookup_service.dart';
import '../lookup/lookup_source.dart';
import '../lookup/movie_dates.dart';
import '../lookup/text_clean.dart';
import '../models/follow_kind.dart';
import '../models/media_type.dart';
import 'check_control.dart';
import 'creator_lookup.dart';
import 'creator_status.dart';
import 'follows.dart';

/// What a run of the creator check did.
typedef CreatorCheckResult = ({
  /// Whether the record of found releases was written.
  bool wrote,

  /// Releases found this run that were not recorded before.
  int found,
});

/// The check of the creators the owner follows (DESIGN.md 10c; Settings ›
/// Upcoming releases): for each creator due today it learns, once and then
/// every ninety days, who they are to the lookup (its id for them, and
/// whether they have died or dissolved: TMDB's `deathday` for directors and
/// actors, Wikidata's P570 and P576 for the rest, asked for many names at
/// once), and for each one followed asks the lookup for their new releases
/// (TMDB's credits, Open Library's works, Deezer's albums, IGDB's games),
/// recording those still ahead or just out in [releases] for Library ›
/// Coming soon: everything upcoming. A creator no longer active is skipped
/// unless the owner ticked them anyway. A found book is kept only when it
/// has an edition in the [languages] the owner reads, dated by that
/// edition (DESIGN.md 10c); a found movie's dates by kind go to
/// [movieDates] and its date is the first of them. Nothing is written to
/// `library.json`.
///
/// Offline or rate limited, the lookup is not asked further and the day is
/// not recorded, so the next open takes it up again; the records written so
/// far stay.
class CreatorCheck {
  CreatorCheck({
    required this.lookups,
    required this.statuses,
    required this.releases,
    required this.store,
    MovieDateStore? movieDates,
  }) : movieDates = movieDates ?? MemoryMovieDateStore();

  final LookupService lookups;
  final CreatorStatusStore statuses;
  final FoundReleaseStore releases;
  final CheckDayStore store;
  final MovieDateStore movieDates;

  /// How many names one Wikidata query asks about.
  static const inactiveBatch = 50;

  bool _running = false;

  /// The lookups that follow creators of [kind] (studios have two: TMDB for
  /// movies, IGDB for games), with the source each one is.
  List<(LookupSource, CreatorLookup)> lookupsFor(FollowKind kind) => [
    for (final source in lookups.sources)
      if (source.isConfigured)
        if (source case final CreatorLookup lookup
            when lookup.creatorKinds.contains(kind))
          (source, lookup),
  ];

  /// The lookup that knows who is no longer active, or null.
  InactiveLookup? get inactiveLookup {
    for (final source in lookups.sources) {
      if (!source.isConfigured) continue;
      if (source.inactiveLookup case final lookup?) return lookup;
    }
    return null;
  }

  /// Whether the creators of [kind] learn who is no longer active from
  /// Wikidata: TMDB says it itself for directors and actors.
  static bool asksWikidata(FollowKind kind) =>
      kind != FollowKind.directors && kind != FollowKind.actors;

  /// Runs the check when it is due today (always with [force]: Check now)
  /// over the creators of [follows], or with [include] only those it says.
  /// [languages] are the ones the owner reads, for the books found.
  /// [control] hears of each creator asked and can stop the run, which
  /// then records no day.
  Future<CreatorCheckResult> run(
    Follows follows,
    DateTime now, {
    bool force = false,
    bool Function(Follow follow)? include,
    Set<String> languages = const {},
    CheckControl? control,
  }) async {
    const nothing = (wrote: false, found: 0);
    if (_running) return nothing;
    final today = DateTime(now.year, now.month, now.day);
    if (!force && !checkDueOn(await store.lastRun(), now)) return nothing;
    final ctl = control ?? CheckControl.none;
    _running = true;
    try {
      final known = Map.of(await statuses.read());
      final dates = Map.of(await movieDates.read());
      var datesChanged = false;
      final recorded = await releases.read();
      final kept = <String, List<FoundRelease>>{};
      for (final r in recorded) {
        // By kind and creator: a director who also acts is two follows,
        // and the actor one, off by default, must not drop the director's
        // releases (fixed 2026-10-31).
        kept.putIfAbsent('${r.kind.key}/${r.creatorId}', () => []).add(r);
      }
      var complete = true;
      var found = 0;
      var wrote = false;

      final due = <Follow>[
        for (final kind in FollowKind.values)
          if (kind.isCreator)
            for (final f in follows.of(kind))
              if (include == null || include(f)) f,
      ];

      // Who is no longer active, for many names at once, before the
      // creators are gone through one by one.
      final inactive = await _classify([
        for (final f in due)
          if (asksWikidata(f.kind) && _statusWanted(known[f.key], today)) f,
      ], onTransientFailure: () => complete = false);

      for (final f in due) {
        if (ctl.cancelled) {
          complete = false;
          break;
        }
        final lookupsOfKind = lookupsFor(f.kind);
        if (lookupsOfKind.isEmpty) continue;
        try {
          var status = known[f.key];
          if (_statusWanted(status, today)) {
            CreatorMatch? match;
            for (final (_, lookup) in lookupsOfKind) {
              match = await lookup.findCreator(f.kind, f.name);
              if (match != null) break;
            }
            status = CreatorStatus(
              kind: f.kind,
              id: f.id,
              providerId: match?.providerId ?? status?.providerId,
              inactive: inactive[f.key] ?? match?.inactive ?? status?.inactive,
              checkedOn: today,
            );
            known[f.key] = status;
            await statuses.write(known);
          }
          // A creator just learned to be no longer active is skipped too,
          // unless the owner ticked them anyway.
          final followed = f.followed && (status?.inactive == null || f.ticked);
          final providerId = status?.providerId;
          if (!followed || providerId == null) {
            if (!followed) kept.remove(f.key);
            ctl.tick();
            continue;
          }
          final matches = <LookupMatch>[];
          for (final (source, lookup) in lookupsOfKind) {
            // A studio's TMDB id is not asked of IGDB.
            if (!source.issued(providerId)) continue;
            matches.addAll(
              await lookup.creatorReleases(providerId, f.kind, today: today),
            );
          }
          final before = {for (final r in kept[f.key] ?? const []) r.key};
          final seen = <String>{};
          final sifted = <LookupMatch>[];
          for (final m in matches) {
            if (!seen.add(m.source)) continue;
            final source = lookups.sourceOf(m.source);
            if (m.type == MediaType.books && languages.isNotEmpty) {
              final edition = await source?.editionRelease(
                m.source,
                languages: languages,
              );
              if (edition != null) {
                if (!edition.inLanguages) continue;
                final named = inEditionScript(m, edition.title, f.name);
                if (edition.released case final released?) {
                  sifted.add(named.copyWith(released: released));
                  continue;
                }
                sifted.add(named);
                continue;
              }
            } else if (m.type == MediaType.movies) {
              final found = await source?.movieDates(m.source);
              if (found != null && !found.isEmpty) {
                if (dates[m.source] != found) datesChanged = true;
                dates[m.source] = found;
                sifted.add(m.copyWith(released: found.first));
                continue;
              }
            }
            sifted.add(m);
          }
          kept[f.key] = [
            for (final m in sifted)
              if (isRecentOrAhead(m.released, today) ||
                  isRecentOrAhead(dates[m.source]?.digital, today))
                FoundRelease(
                  kind: f.kind,
                  creatorId: f.id,
                  creatorName: f.name,
                  match: m,
                  foundOn: _foundOn(recorded, m.source) ?? now,
                ),
          ];
          found += kept[f.key]!.where((r) => !before.contains(r.key)).length;
          await releases.write(_flatten(kept, follows));
          wrote = true;
          ctl.tick();
        } on LookupException catch (e) {
          if (e.failure == LookupFailure.offline ||
              e.failure == LookupFailure.rateLimited) {
            complete = false;
            break;
          }
          // A server error is no answer and leaves the day to run again; a
          // 404 or a bad answer is nothing learned about this creator.
          if (e.isTransient) complete = false;
          ctl.tick();
        }
      }
      // Releases of creators no longer followed go.
      final pruned = _flatten(kept, follows);
      if (pruned.length != recorded.length || wrote) {
        await releases.write(pruned);
        wrote = true;
      }
      if (datesChanged) await movieDates.write(dates);
      if (complete) await store.recordRun(today);
      return (wrote: wrote, found: found);
    } finally {
      _running = false;
    }
  }

  /// Wikidata's answer for the creators in [follows], by follow key, in
  /// batches per kind. Not knowing who died is no reason to skip the
  /// releases: a failure is noted and the run goes on.
  Future<Map<String, Inactive>> _classify(
    List<Follow> follows, {
    required void Function() onTransientFailure,
  }) async {
    final lookup = inactiveLookup;
    final result = <String, Inactive>{};
    if (lookup == null || follows.isEmpty) return result;
    for (final kind in FollowKind.values) {
      final ofKind = [
        for (final f in follows)
          if (f.kind == kind) f,
      ];
      for (var i = 0; i < ofKind.length; i += inactiveBatch) {
        final batch = ofKind.sublist(
          i,
          (i + inactiveBatch).clamp(0, ofKind.length),
        );
        try {
          final answer = await lookup.inactiveOf(kind, [
            for (final f in batch) f.name,
          ]);
          for (final f in batch) {
            if (answer[f.name] case final why?) result[f.key] = why;
          }
        } on LookupException catch (e) {
          if (e.isTransient) onTransientFailure();
        }
      }
    }
    return result;
  }

  static bool _statusWanted(CreatorStatus? status, DateTime today) =>
      status == null || status.isStaleOn(today);

  static DateTime? _foundOn(List<FoundRelease> recorded, String source) {
    for (final r in recorded) {
      if (r.key == source) return r.foundOn;
    }
    return null;
  }

  /// Every kept release of a creator still in [follows] and followed, in
  /// kind order, each creator's in the lookup's order.
  static List<FoundRelease> _flatten(
    Map<String, List<FoundRelease>> kept,
    Follows follows,
  ) => [
    for (final kind in FollowKind.values)
      for (final f in follows.of(kind))
        if (f.followed) ...?kept[f.key],
  ];
}

/// [match] named as its edition in the owner's languages is: a work whose
/// title is in another script than that edition's ("ベルセルク 43" for
/// Dark Horse's "Berserk 43") takes the edition's title, and then the
/// followed creator's [name] when its creator line is in another script
/// too ("スタジオ我画, 三浦建太郎"). Otherwise [match] as it is.
LookupMatch inEditionScript(LookupMatch match, String? title, String name) {
  if (title == null || !otherScript(match.title, title)) return match;
  final creator = match.creator;
  return match.copyWith(
    title: title,
    creator: creator == null || otherScript(creator, title) ? name : null,
  );
}
