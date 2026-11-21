import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_info.dart';
import '../../data/covers/cover_files.dart';
import '../../data/images/large_cover_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/libri_logo.dart';
import '../../widgets/page_header.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/setting_row.dart';

/// Opens About (Settings › About Libri) above everything, like Settings.
Future<void> openAboutScreen(BuildContext context) {
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push<void>(MaterialPageRoute(builder: (_) => const AboutScreen()));
}

/// A service Libri looks things up in, credited on Settings › About Libri.
class DataSource {
  const DataSource({
    required this.name,
    required this.description,
    required this.url,
    this.logo,
    this.logoOnDark,
    this.logoHeight = 16,
  });

  final String name;
  final String description;

  /// The website the row opens.
  final String url;

  /// The service's own logo, where its terms ask for one (TMDB, Deezer):
  /// the official file, never redrawn, shown small so the page stays calm.
  final String? logo;

  /// The variant for the dark theme, when the service has one (Deezer's
  /// white wordmark); null shows [logo] on both themes.
  final String? logoOnDark;

  /// Height in dp; set per logo so their wordmarks look the same size.
  final double logoHeight;

  String? logoFor(Brightness brightness) =>
      brightness == Brightness.dark ? logoOnDark ?? logo : logo;
}

/// The services Libri looks things up in, in the order of Settings › About
/// Libri.
const dataSources = [
  DataSource(
    name: 'TMDB',
    description:
        'Movies and shows. This product uses the TMDB API but is not '
        'endorsed or certified by TMDB.',
    url: 'https://www.themoviedb.org',
    logo: 'assets/logos/tmdb/tmdb.png',
    logoHeight: 13,
  ),
  DataSource(
    name: 'IGDB',
    description: 'Games: details and covers from IGDB.com.',
    url: 'https://www.igdb.com',
  ),
  DataSource(
    name: 'Apple Books',
    description:
        'Books: descriptions and covers, and those Open Library lacks.',
    url: 'https://books.apple.com',
  ),
  DataSource(
    name: 'Open Library',
    description: 'Books: details and covers from the Internet Archive.',
    url: 'https://openlibrary.org',
  ),
  DataSource(
    name: 'Google Books',
    description: 'Books: details of those it found before Apple Books.',
    url: 'https://books.google.com',
  ),
  DataSource(
    name: 'Deezer',
    description: 'Music: artists, albums, songs and covers.',
    url: 'https://www.deezer.com',
    logo: 'assets/logos/deezer/deezer.png',
    logoOnDark: 'assets/logos/deezer/deezer_on_dark.png',
    logoHeight: 22,
  ),
  DataSource(
    name: 'Apple Music',
    description:
        'Music: artist photos, and more albums, songs and covers when you '
        'ask for them.',
    url: 'https://music.apple.com',
  ),
  DataSource(
    name: 'AniList',
    description: 'Anime: details and covers.',
    url: 'https://anilist.co',
  ),
  DataSource(
    name: 'ARM',
    description: 'Anime: which TMDB show and season an AniList entry is.',
    url: 'https://arm.haglund.dev',
  ),
  DataSource(
    name: 'Wikidata',
    description: 'Books: which series a book belongs to, and its number.',
    url: 'https://www.wikidata.org',
  ),
];

/// About (Settings › About Libri): the app icon, the name, the version and
/// build from the build itself, the open-source licenses, and a credit per data
/// source that opens its website.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key, this.openUrl});

  /// Opens a source's website; the browser unless a test records the URL.
  final Future<void> Function(Uri url)? openUrl;

  static const _heading = EdgeInsets.fromLTRB(0, 20, 0, 2);

  /// "1,012 of 1,104 on this phone · 187.3 MB", and what the last run
  /// fetched while the app has been open: "Last run: 692 in 3 min 12 s".
  static String largeCoversLine(LargeCoverStatus status) {
    final last = status.last;
    final count = last == null
        ? '${status.files}'
        : '${status.files} of ${last.wanted}';
    final size = status.files == 0 ? '' : ' · ${coverSizeLabel(status.bytes)}';
    final line = '$count on this phone$size';
    if (last == null || last.fetched == 0) return line;
    final seconds = last.took.inSeconds;
    final took = seconds < 60
        ? '$seconds s'
        : '${seconds ~/ 60} min ${seconds % 60} s';
    return '$line\nLast run: ${last.fetched} in $took';
  }

  Future<void> _open(Uri url) async {
    if (openUrl != null) return openUrl!(url);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } on Object {
      // No browser to open it: nothing to do.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final version = ref.watch(appVersionProvider).value;
    final build = ref.watch(appBuildNumberProvider).value;
    final versionLine = switch ((version, build)) {
      (null, _) => 'Version …',
      (final v, null) || (final v, '') => 'Version $v',
      (final v, final b) => 'Version $v (build $b)',
    };
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(title: 'About', onBack: () => Navigator.pop(context)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                    child: Column(
                      children: [
                        const LibriLogo(width: 134),
                        const SizedBox(height: 16),
                        Text(
                          appName,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium!.copyWith(
                            fontSize: 30,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          versionLine,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium!.copyWith(
                            fontSize: 15,
                            color: colors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SectionHeading('App', padding: _heading),
                  SettingRow(
                    label: 'Open-source licenses',
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: appName,
                      applicationVersion: version == null
                          ? null
                          : 'Version $version',
                      applicationIcon: const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: LibriLogo(width: 84),
                      ),
                    ),
                  ),
                  // The larger versions of the covers (Library › Cover,
                  // larger), fetched in the background: what is there.
                  const _LargeCoversRow(),
                  const SectionHeading('Data sources', padding: _heading),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 6, 0, 2),
                    child: Text(
                      'Used when you add something, to fetch details and '
                      'covers.',
                      style: theme.textTheme.bodyMedium!.copyWith(
                        fontSize: 13.5,
                        height: 1.4,
                        color: colors.muted,
                      ),
                    ),
                  ),
                  for (final source in dataSources)
                    _SourceRow(
                      source: source,
                      onTap: () => _open(Uri.parse(source.url)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Larger covers" with what is on the phone, counted when the screen
/// opens.
class _LargeCoversRow extends ConsumerStatefulWidget {
  const _LargeCoversRow();

  @override
  ConsumerState<_LargeCoversRow> createState() => _LargeCoversRowState();
}

class _LargeCoversRowState extends ConsumerState<_LargeCoversRow> {
  LargeCoverStatus? _status;

  @override
  void initState() {
    super.initState();
    final last = ref.read(largeCoverPassProvider).progress;
    ref.read(largeImageCacheProvider).size().then((size) {
      if (!mounted) return;
      setState(
        () => _status = (files: size.files, bytes: size.bytes, last: last),
      );
    });
  }

  @override
  Widget build(BuildContext context) => SettingRow(
    label: 'Larger covers',
    detail: switch (_status) {
      null => '…',
      final status => AboutScreen.largeCoversLine(status),
    },
  );
}

/// One credit: the name, what the source is used for, its logo when it
/// has one, and an external-link icon, since the row leaves the app.
class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source, required this.onTap});

  final DataSource source;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final logo = source.logoFor(theme.brightness);
    return Semantics(
      button: true,
      label: '${source.name}, opens website',
      value: source.description,
      excludeSemantics: true,
      child: RowInkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.divider)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: theme.textTheme.bodyLarge!.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      source.description,
                      style: theme.textTheme.bodyMedium!.copyWith(
                        fontSize: 13.5,
                        height: 1.4,
                        color: colors.muted,
                      ),
                    ),
                    if (logo != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Image.asset(
                          logo,
                          height: source.logoHeight,
                          excludeFromSemantics: true,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: StrokeIcon(
                  AppIcons.externalLink,
                  size: 18,
                  color: colors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
