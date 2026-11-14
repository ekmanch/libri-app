/// A pasted track list read into tracks (Music › Edit tracks, "Paste a
/// list"). The rules are the desktop app's (libri-kde,
/// `screens/entry/tracks.rs`), so a list pastes the same on both.
library;

/// One pasted line: a title and a length, '' when it has none.
typedef PastedTrack = ({String title, String length});

/// The tracks of a pasted list, one per line that holds a title or a length.
/// A number in front goes ("1.", "01 -", "3)"; a bare "1 " only when every
/// line starts with one, so "99 Problems" alone keeps its name), and a length
/// at the end is picked up ("4:31", "(4:31)").
List<PastedTrack> parseTrackList(String pasted) {
  final lines = [
    for (final line in pasted.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  final allNumbered =
      lines.length > 1 &&
      lines.every((line) => _stripNumber(line, bare: true) != null);
  return [
    for (final line in lines)
      _splitLength(_stripNumber(line, bare: allNumbered) ?? line),
  ].where((t) => t.title.isNotEmpty || t.length.isNotEmpty).toList();
}

final _number = RegExp(r'^(\d{1,3})(?!\d)');
final _mark = RegExp(r'^\s*(?:[.)\-–—]|:(?!\d))\s*[-–—]*\s*');
final _space = RegExp(r'^\s+');

/// [line] without its leading track number, when it has one: up to three
/// digits, then a mark (". ) - – — :" with spaces around it), or with [bare]
/// only a space. A line that is nothing but the number keeps it.
String? _stripNumber(String line, {required bool bare}) {
  final number = _number.firstMatch(line);
  if (number == null) return null;
  final after = line.substring(number.end);
  final marked = _mark.firstMatch(after);
  final String rest;
  if (marked != null) {
    rest = after.substring(marked.end);
  } else if (bare && _space.hasMatch(after)) {
    rest = after.trimLeft();
  } else {
    return null;
  }
  return rest.isEmpty ? null : rest;
}

final _length = RegExp(r'^\d{1,3}:\d{2}(?::\d{2})?$');
final _plain = RegExp(r'(?:^|\s)(\d[\d:]*)$');
final _bracketed = RegExp(r'[(\[](\d[\d:]*)\s*[)\]]$');
final _dash = RegExp(r'\s*[-–—]+$');

/// The title and the length at the end of [line]: "4:31", "1:02:03", in
/// brackets or not, after a dash or not.
PastedTrack _splitLength(String line) {
  final trimmed = line.trimRight();
  final match = _bracketed.firstMatch(trimmed) ?? _plain.firstMatch(trimmed);
  final length = match?.group(1);
  if (match == null || length == null || !_length.hasMatch(length)) {
    return (title: trimmed, length: '');
  }
  final title = trimmed
      .substring(0, match.start)
      .trimRight()
      .replaceFirst(_dash, '')
      .trimRight();
  return (title: title, length: length);
}
