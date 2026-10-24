/// Game platform names as the app shows and saves them: spelled out
/// ("PlayStation 5", not "PS5"), one spelling per platform, so a lookup's
/// "PS5" and a typed "playstation 5" become the same chip.
String normalizePlatform(String name) {
  final trimmed = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  final key = trimmed.toLowerCase().replaceAll(RegExp(r'[\s\-_./]'), '');
  return _aliases[key] ?? trimmed;
}

/// "PlayStation 5, PC" in an entry's `platform` field, as a list of
/// spelled-out names ("PS5" reads as "PlayStation 5").
List<String> splitPlatforms(String? text) => [
  for (final part in (text ?? '').split(','))
    if (part.trim().isNotEmpty) normalizePlatform(part),
];

const _aliases = {
  'ps': 'PlayStation',
  'ps1': 'PlayStation',
  'psx': 'PlayStation',
  'psone': 'PlayStation',
  'playstation': 'PlayStation',
  'playstation1': 'PlayStation',
  'ps2': 'PlayStation 2',
  'playstation2': 'PlayStation 2',
  'ps3': 'PlayStation 3',
  'playstation3': 'PlayStation 3',
  'ps4': 'PlayStation 4',
  'playstation4': 'PlayStation 4',
  'ps5': 'PlayStation 5',
  'playstation5': 'PlayStation 5',
  'psp': 'PlayStation Portable',
  'playstationportable': 'PlayStation Portable',
  'psvita': 'PlayStation Vita',
  'vita': 'PlayStation Vita',
  'playstationvita': 'PlayStation Vita',
  'xbox': 'Xbox',
  'xbox360': 'Xbox 360',
  'x360': 'Xbox 360',
  'xb1': 'Xbox One',
  'xbone': 'Xbox One',
  'xboxone': 'Xbox One',
  'xsx': 'Xbox Series X|S',
  'xss': 'Xbox Series X|S',
  'xboxseries': 'Xbox Series X|S',
  'xboxseriesx': 'Xbox Series X|S',
  'xboxseriess': 'Xbox Series X|S',
  'xboxseriesxs': 'Xbox Series X|S',
  'xboxseriesx|s': 'Xbox Series X|S',
  'ns': 'Switch',
  'switch': 'Switch',
  'nintendoswitch': 'Switch',
  'ns2': 'Switch 2',
  'switch2': 'Switch 2',
  'nintendoswitch2': 'Switch 2',
  'snes': 'Super Nintendo',
  'supernintendo': 'Super Nintendo',
  'supernintendoentertainmentsystem': 'Super Nintendo',
  'pc': 'PC',
  'windows': 'PC',
  'win': 'PC',
  'mac': 'Mac',
  'macos': 'Mac',
  'linux': 'Linux',
  'steamdeck': 'Steam Deck',
  'ios': 'iOS',
  'android': 'Android',
};
