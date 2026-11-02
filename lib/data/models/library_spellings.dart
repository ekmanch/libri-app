import 'entry.dart';
import 'entry_kind.dart';
import 'library.dart';
import 'media_type.dart';

/// [entry] with its creator, a song's album and its series name written as
/// the library already spells them (DESIGN.md section 2, Spellings), so a
/// lookup's "deafheaven" is saved as the "Deafheaven" already there and the
/// lists in the data repo keep one heading per artist.
///
/// A name matches when it is the same with case and spacing aside, in an
/// entry of the same type (for an album, by the same artist); the first such
/// entry in the library gives the spelling, as the artist list shows it.
/// [before] is the entry as saved, when it is an edit: a field whose name did
/// not change apart from its case keeps what was typed, since re-casing it is
/// a correction.
Entry withLibrarySpellings(Entry entry, Library library, {Entry? before}) {
  final others = [
    for (final e in library.entries)
      if (e.id != entry.id && e.type == entry.type) e,
  ];

  String? spelled(String? typed, String? was, Iterable<String?> known) {
    final key = spellingKey(typed);
    if (key.isEmpty || key == spellingKey(was)) return typed;
    for (final name in known) {
      if (spellingKey(name) == key) return name;
    }
    return typed;
  }

  final creator = spelled(entry.creator, before?.creator, [
    for (final e in others) e.creator,
  ]);
  final artist = spellingKey(creator);
  final album = entry.album == null
      ? null
      : spelled(entry.album, before?.album, [
          for (final e in others)
            if (entry.type == MediaType.music &&
                spellingKey(e.creator) == artist)
              e.kind == EntryKind.album ? e.title : e.album,
        ]);
  final series = entry.series;
  final seriesName = series == null
      ? null
      : spelled(series.name, before?.series?.name, [
          for (final e in others) e.series?.name,
        ]);
  return entry.copyWith(
    creator: creator,
    album: album,
    series: series == null ? null : series.copyWith(name: seriesName!),
  );
}

/// A name as the spellings compare it: case and runs of spaces aside.
String spellingKey(String? name) =>
    (name ?? '').trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
