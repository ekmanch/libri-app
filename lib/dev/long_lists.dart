import '../data/models/entry.dart';
import '../data/models/entry_id.dart';
import '../data/models/entry_status.dart';
import '../data/models/library.dart';
import '../data/models/media_type.dart';
import '../data/models/music_kind.dart';
import '../data/models/released.dart';
import '../data/models/tag_category.dart';

/// Development only: pads every type with generated entries so that the
/// long-list rail (Library › Long list: rail by release year to Long list:
/// music artists A–Z) and the grid's fast scroll (Library › Long grid:
/// fast-scroll thumb) can be tried on a device, and the Authors group with
/// enough tags to be a row that opens the full-screen list (Library › Filter
/// sheet; Filter: all Authors). Enabled with `--dart-define=LONG_LISTS=true`.
const longListsEnabled = bool.fromEnvironment('LONG_LISTS');

/// Author names spread over the alphabet, one tag each, so the Authors group is
/// long (over [longTagGroup]) and Library › Filter: all Authors has letter
/// sections.
const longListAuthors = [
  'Isaac Asimov',
  'Margaret Atwood',
  'Clive Barker',
  'Ray Bradbury',
  'Octavia E. Butler',
  'Agatha Christie',
  'Blake Crouch',
  'Philip K. Dick',
  'Charles Dickens',
  'Gillian Flynn',
  'Neil Gaiman',
  'Frank Herbert',
  'Joe Hill',
  'Shirley Jackson',
  'Stephen King',
  'Ursula K. Le Guin',
  'H. P. Lovecraft',
  'Richard Matheson',
  'Cormac McCarthy',
  'Jo Nesbø',
  'George Orwell',
  'Edgar Allan Poe',
  'Terry Pratchett',
  'Anne Rice',
  'Mary Shelley',
  'Dan Simmons',
  'Bram Stoker',
  'The Brothers Grimm',
  'Kurt Vonnegut',
  'Andy Weir',
];

/// [perType] extra entries per type, cloned from that type's first entry,
/// spread over the decades since 1925 and over the last two years of added
/// dates, with a mix of statuses. Music is spread over generated artists (some
/// starting with "The", one "Various Artists") and over albums and songs, so
/// the artist list (Library › Music: artists, text view) gets long too.
Library padForLongLists(Library library, {int perType = 120}) {
  final extra = <Entry>[];
  final authorTags = [for (final a in longListAuthors) slugify(a)];
  for (final type in MediaType.values) {
    final base = library.entriesOfType(type).firstOrNull;
    if (base == null) continue;
    final music = type == MediaType.music;
    final books = type == MediaType.books;
    for (var i = 0; i < perType; i++) {
      final kind = !music
          ? null
          : i % 4 == 3
          ? MusicKind.song
          : MusicKind.album;
      final statuses = EntryStatus.optionsFor(type);
      extra.add(
        base.copyWith(
          id: '${type.name}/long-$i',
          title: '${base.title} ${i + 1}',
          released: Released(1925 + (i * 7) % 100),
          added: DateTime(2026, 10, 9).subtract(Duration(days: i * 5)),
          status: statuses[i % statuses.length],
          // Every rating from 10 down to 4, and every fourth unrated, so
          // the rating sort's rail has sections to jump to.
          rating: i % 4 == 3 ? null : 10 - (i % 7),
          // Every generated book is by one of the authors, so each author
          // tag has entries behind it.
          tags: books ? [authorTags[i % authorTags.length]] : const [],
          tracks: null,
          seasonalOnly: false,
          creator: music
              ? _artistName(i)
              : books
              ? longListAuthors[i % authorTags.length]
              : base.creator,
          kind: kind ?? base.kind,
          album: kind == MusicKind.song ? 'Album ${i ~/ 4}' : null,
        ),
      );
    }
  }
  return library.copyWith(
    tags: {
      ...library.tags,
      TagCategory.authors: [
        ...?library.tags[TagCategory.authors],
        for (final tag in authorTags)
          if (!(library.tags[TagCategory.authors]?.contains(tag) ?? false)) tag,
      ],
    },
    entries: [...library.entries, ...extra],
  );
}

/// Names spread over the alphabet ("B-Side Project 1", "The C-Side
/// Project 2", a few starting with a digit), with every ninth "Various
/// Artists", so the rail, the "The" rule and the pinned-last rule can all
/// be tried.
String _artistName(int i) {
  if (i % 9 == 8) return 'Various Artists';
  final the = i % 3 == 0 ? 'The ' : '';
  final letter = i % 10 == 9
      ? '${i % 7}'
      : String.fromCharCode('A'.codeUnitAt(0) + i % 26);
  return '$the$letter-Side Project ${i ~/ 26 + 1}';
}
