import 'package:freezed_annotation/freezed_annotation.dart';

import '../models/released.dart';
import '../storage/json_file.dart';

part 'season_parts.freezed.dart';
part 'season_parts.g.dart';

/// A later part of a season of a show in the library that is not out yet,
/// as the daily season check recorded it from the lookup (section 10c;
/// owner's decision, 2026-11-04): Coming soon lists it as its own row,
/// "Season 3, Part 2". Kept on the phone (`season_parts.json`), never in
/// `library.json`.
@freezed
abstract class ComingPart with _$ComingPart {
  const ComingPart._();

  const factory ComingPart({
    required String entryId,
    required int season,
    required int part,
    @ReleasedConverter() required Released released,
  }) = _ComingPart;

  factory ComingPart.fromJson(Map<String, Object?> json) =>
      _$ComingPartFromJson(json);

  /// The key Not interested hides the row by: the season's key with the
  /// part after a dot, `anime/frieren#3.2`.
  String get key => '$entryId#$season.$part';
}

/// Where the coming parts the daily check found are kept.
abstract class ComingPartsStore {
  Future<List<ComingPart>> read();

  Future<void> write(List<ComingPart> parts);
}

/// `season_parts.json` under the cache folder: `{"parts": [...]}`. A
/// cleared cache means no recorded parts until the next check.
class FileComingPartsStore implements ComingPartsStore {
  FileComingPartsStore(this._file);

  final JsonFile _file;

  @override
  Future<List<ComingPart>> read() async {
    final parts = (await _file.read())?['parts'];
    if (parts is! List) return const [];
    final result = <ComingPart>[];
    for (final item in parts) {
      if (item is! Map<String, Object?>) continue;
      try {
        result.add(ComingPart.fromJson(item));
      } on Object {
        // An unreadable part is left out; the next check writes it again.
      }
    }
    return result;
  }

  @override
  Future<void> write(List<ComingPart> parts) => _file.write({
    'parts': [for (final p in parts) p.toJson()],
  });
}

class MemoryComingPartsStore implements ComingPartsStore {
  MemoryComingPartsStore([List<ComingPart>? parts])
    : _parts = parts ?? const [];

  List<ComingPart> _parts;

  @override
  Future<List<ComingPart>> read() async => _parts;

  @override
  Future<void> write(List<ComingPart> parts) async => _parts = parts;
}
