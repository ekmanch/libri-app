import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/lookup/lookup_failure.dart';
import '../../data/lookup/lookup_match.dart';
import '../../data/lookup/lookup_service.dart';
import '../../data/lookup/music_lookup.dart';
import '../../data/lookup/text_clean.dart';
import '../../data/models/released.dart';

/// One of the music lookup's two lists (albums, songs) as it stands.
class MusicListState {
  /// The rows listed so far, every page asked.
  List<LookupMatch> matches = const [];

  /// How many the whole list holds, when known: the source's total for a
  /// search or an artist's albums; for an artist's songs only once the
  /// last is listed.
  int? total;

  /// Where the next page starts, or null at the end.
  int? next;

  /// A first page has been answered for the rows shown (they may be an
  /// older query's while [searching]).
  bool loaded = false;

  /// The first page is on its way.
  bool searching = false;

  /// A later page is on its way ("Loading more…").
  bool loadingMore = false;

  /// The last later page failed; nothing more is asked until a retry.
  bool moreFailed = false;

  /// Why the first page failed, or null.
  LookupFailure? failure;

  /// Counts the times the rows were replaced, so the list can start again
  /// at its top.
  int epoch = 0;

  /// Counts what was asked, so an answer to an older ask is dropped.
  int _generation = 0;

  void _clear() {
    _generation++;
    matches = const [];
    total = null;
    next = null;
    loaded = false;
    searching = false;
    loadingMore = false;
    moreFailed = false;
    failure = null;
    epoch++;
  }
}

/// The state of the music lookup (Add / edit entry › Music search: albums,
/// … songs, … an artist's albums, … an artist's songs), with the paging
/// rules of the desktop app (DESIGN.md 10c): pages of [musicPageSize], a
/// page under half full followed by the next at once, an artist's songs
/// listed once each, and the years of rows that came without one asked
/// album by album, stopped when another search starts.
///
/// The Albums and the Songs list live side by side, so a swipe between
/// them shows each as it was left; the one not looked at is asked only
/// when it is first shown.
class MusicLookupController extends ChangeNotifier {
  MusicLookupController(this._service, {this.scope = MusicScope.albums});

  final LookupService _service;

  /// The list shown: the form's "Album or song".
  MusicScope scope;

  /// The search typed, trimmed.
  String query = '';

  /// The artist whose albums or songs are listed, or null in a search.
  ArtistHit? artist;

  /// The artists matching the search, best known first.
  List<ArtistHit> artists = const [];

  /// The release dates asked for the albums of rows that came without one,
  /// by the album's lookup id.
  final years = <String, Released>{};

  final _lists = {
    for (final scope in MusicScope.values) scope: MusicListState(),
  };
  final _askedYears = <String>{};
  final _yearQueue = <String>[];
  bool _yearsRunning = false;
  int _yearsRun = 0;
  bool _disposed = false;

  MusicListState of(MusicScope scope) => _lists[scope]!;

  MusicListState get current => of(scope);

  /// The list being paged: the open artist's, else the search's.
  MusicList get list => switch (artist) {
    final artist? => MusicArtist.of(artist),
    null => MusicSearch(query),
  };

  /// The album a row's date is asked by: a song's album, an album itself.
  static String albumKey(LookupMatch match) =>
      match.albumSource ?? match.source;

  /// A row's date: its own, else its album's once asked.
  Released? releasedOf(LookupMatch match) =>
      match.released ?? years[albumKey(match)];

  /// Looks [text] up (the typing has paused, or the type was picked). The
  /// rows on screen stay until the answer; a search for other words leaves
  /// an open artist. The same search again asks only after a failure.
  void search(String text) {
    final wanted = text.trim();
    if (wanted.isEmpty) {
      query = '';
      artist = null;
      artists = const [];
      _stopYears();
      for (final list in _lists.values) {
        list._clear();
      }
      _notify();
      return;
    }
    if (wanted == query) {
      if (!current.loaded && !current.searching) unawaited(_load(scope));
      return;
    }
    query = wanted;
    artist = null;
    _stopYears();
    for (final entry in _lists.entries) {
      if (entry.key == scope) {
        // Kept on screen meanwhile; only what is on its way is dropped.
        entry.value
          .._generation += 1
          ..loadingMore = false
          ..moreFailed = false
          ..next = null;
      } else {
        entry.value._clear();
      }
    }
    _loadWithRemembered();
  }

  /// Asks the list shown again, after a failure.
  void retry() {
    final list = current;
    if (list.moreFailed) {
      more(retry: true);
    } else if (!list.searching) {
      unawaited(_load(scope));
    }
  }

  /// The switch, or a swipe: the other list, asked when not yet listed.
  void setScope(MusicScope to) {
    if (to == scope) return;
    scope = to;
    if (query.isNotEmpty && !current.loaded && !current.searching) {
      unawaited(_load(scope));
    } else {
      _notify();
    }
  }

  /// Lists only [hit]'s albums or songs, newest first.
  void openArtist(ArtistHit hit) => _setArtist(hit);

  /// Back from an artist to the search's results.
  void closeArtist() {
    if (artist != null) _setArtist(null);
  }

  void _setArtist(ArtistHit? to) {
    artist = to;
    _stopYears();
    for (final list in _lists.values) {
      list._clear();
    }
    _loadWithRemembered();
  }

  /// Asks the list shown, and fills the other one when its first page is
  /// remembered from earlier, so a swipe back to it shows it at once; a
  /// list never asked waits until it is first shown.
  void _loadWithRemembered() {
    for (final other in MusicScope.values) {
      if (other == scope) continue;
      final request = MusicRequest(list: list, scope: other);
      if (_service.cachedMusicPage(request) case final page?) {
        of(other)._generation++;
        _answer(other, request, page, followUp: false);
      }
    }
    unawaited(_load(scope));
  }

  /// The next page of [of] (the list shown when null), when there is one
  /// and none is on its way. After a failed page only a [retry] asks.
  void more({MusicScope? of, bool retry = false}) {
    final scope = of ?? this.scope;
    final list = this.of(scope);
    if (list.next == null ||
        !list.loaded ||
        list.searching ||
        list.loadingMore ||
        (list.moreFailed && !retry)) {
      return;
    }
    unawaited(_load(scope, cursor: list.next!));
  }

  Future<void> _load(MusicScope scope, {int cursor = 0}) async {
    final list = of(scope);
    final first = cursor == 0;
    final generation = first ? ++list._generation : list._generation;
    final request = MusicRequest(list: this.list, scope: scope, cursor: cursor);
    var page = _service.cachedMusicPage(request);
    if (page == null) {
      if (first) {
        list.searching = true;
        list.failure = null;
      } else {
        list.loadingMore = true;
      }
      list.moreFailed = false;
      _notify();
      try {
        page = await _service.musicPage(request);
      } on LookupException catch (e) {
        if (_disposed || generation != list._generation) return;
        if (first) {
          list
            ..searching = false
            ..loaded = false
            ..matches = const []
            ..total = null
            ..next = null
            ..failure = e.failure
            ..epoch += 1;
          if (artist == null) artists = const [];
        } else {
          list
            ..loadingMore = false
            ..moreFailed = true;
        }
        _notify();
        return;
      }
      if (_disposed || generation != list._generation) return;
    }
    _answer(scope, request, page);
  }

  /// A page: the first replaces the rows and the artists, a later one adds
  /// to them (an artist's songs once each, as a single repeats its
  /// album's). Then the dates of the rows that came without one are asked.
  void _answer(
    MusicScope scope,
    MusicRequest request,
    MusicPage page, {
    bool followUp = true,
  }) {
    final list = of(scope);
    final first = request.cursor == 0;
    final rows = first ? <LookupMatch>[] : [...list.matches];
    final artistSongs = artist != null && scope == MusicScope.songs;
    for (final found in page.matches) {
      if (artistSongs && rows.any((m) => sameTitle(m.title, found.title))) {
        continue;
      }
      rows.add(found);
    }
    if (first) {
      list
        ..loaded = true
        ..searching = false
        ..failure = null
        ..epoch += 1;
      if (artist == null) artists = page.artists;
    }
    list
      ..matches = rows
      ..loadingMore = false
      ..moreFailed = false
      ..next = page.next
      ..total = page.total ?? (page.next == null ? rows.length : null);
    _askYears(rows);
    _notify();
    // Deezer drops what is not available from a page, so a short one may
    // not fill the list enough to scroll: the next comes at once.
    if (followUp &&
        page.matches.length < musicPageSize ~/ 2 &&
        list.next != null) {
      more(of: scope);
    }
  }

  /// Queues the albums of rows without a date, each asked once.
  void _askYears(List<LookupMatch> rows) {
    for (final found in rows) {
      final key = albumKey(found);
      if (found.released != null ||
          years.containsKey(key) ||
          !_askedYears.add(key)) {
        continue;
      }
      _yearQueue.add(key);
    }
    unawaited(_runYears());
  }

  /// One album at a time, so a page asked meanwhile never waits behind a
  /// queue of dates.
  Future<void> _runYears() async {
    if (_yearsRunning) return;
    _yearsRunning = true;
    final run = _yearsRun;
    while (_yearQueue.isNotEmpty && run == _yearsRun && !_disposed) {
      final key = _yearQueue.removeAt(0);
      try {
        final released = await _service.albumReleased(key);
        if (released != null) {
          years[key] = released;
          _notify();
        }
      } on LookupException catch (e) {
        // Offline or refused for now: the rest would fare no better.
        if (e.failure != LookupFailure.other && run == _yearsRun) {
          _askedYears.removeAll(_yearQueue);
          _askedYears.remove(key);
          _yearQueue.clear();
        }
      } on Object {
        // A row without a year is still a row.
      }
    }
    _yearsRunning = false;
    if (_yearQueue.isNotEmpty && !_disposed) unawaited(_runYears());
  }

  /// Another search starts: the dates still to ask are dropped (those
  /// learned are kept).
  void _stopYears() {
    _yearsRun++;
    _yearQueue.clear();
    _askedYears.removeWhere((key) => !years.containsKey(key));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _yearQueue.clear();
    super.dispose();
  }
}
