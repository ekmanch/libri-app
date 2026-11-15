import '../models/platform_names.dart';
import '../models/released.dart';

/// The platforms whose release date counts for a game saved for
/// [platforms]: the default platform from Settings alone when it is among
/// them (the owner plays there, whatever else the entry names), else all
/// of them. Names are compared spelled out ("PS5" is "PlayStation 5").
List<String> datedPlatforms(
  Iterable<String> platforms,
  String? defaultPlatform,
) {
  final names = [for (final p in platforms) normalizePlatform(p)];
  if (defaultPlatform != null) {
    final wanted = normalizePlatform(defaultPlatform).toLowerCase();
    for (final name in names) {
      if (name.toLowerCase() == wanted) return [name];
    }
  }
  return names;
}

/// A game's release on the platforms it is saved for. [listed] says
/// whether the lookup lists the game on any of them; when it does,
/// [released] is its first release there, or null while that has no date
/// yet (a PC port announced without one). Not listed, the lookup knows
/// nothing of those platforms and the first release anywhere stands in.
typedef PlatformRelease = ({bool listed, Released? released});

/// The first release among [platforms] in [byPlatform], a lookup's
/// platforms by spelled-out name with the first release on each (null for
/// one without a date).
PlatformRelease releaseOn(
  Map<String, Released?> byPlatform,
  Iterable<String> platforms,
) {
  final dates = {
    for (final e in byPlatform.entries) e.key.toLowerCase(): e.value,
  };
  var listed = false;
  Released? first;
  for (final platform in platforms) {
    final key = normalizePlatform(platform).toLowerCase();
    if (!dates.containsKey(key)) continue;
    listed = true;
    final released = dates[key];
    if (released == null) continue;
    if (first == null || released.availableFrom.isBefore(first.availableFrom)) {
      first = released;
    }
  }
  return (listed: listed, released: first);
}
