import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/lookup/lookup_providers.dart';
import '../../data/lookup/lookup_source.dart';
import '../../data/lookup/text_clean.dart';
import '../../data/models/entry.dart';
import '../../data/models/media_type.dart';
import '../../theme/app_theme.dart';
import '../../data/operations/operations.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/check_box_mark.dart';
import '../../widgets/chips.dart';
import '../../widgets/cover_choice.dart';
import '../../widgets/cover_image.dart';
import '../../widgets/entry_row.dart';
import '../../widgets/labels.dart';
import '../../widgets/page_header.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/section_heading.dart';
import '../../widgets/sheet_frame.dart';
import '../settings/display_preferences.dart';
import '../shell/app_shell.dart';
import 'entry_details_sheet.dart';
import 'new_entry_screen.dart';

/// One row of the Series section (Library › Movie in a series; Book in a
/// long series; All volumes in a series): a part of the series as the lookup
/// lists it, the entry in the library that is it, or both.
class SeriesRow {
  const SeriesRow({
    this.number,
    required this.title,
    this.year,
    this.entry,
    this.partKey,
    this.creator,
    this.extra = false,
  });

  final int? number;
  final String title;
  final int? year;

  /// The entry that is this part, when it is in the library.
  final Entry? entry;

  /// The fetched part's [seriesPartKey], by which it is hidden; null for an
  /// entry the lookup does not list.
  final String? partKey;

  /// The fetched part's authors, when the source names them.
  final String? creator;

  /// Whether the automatic rules count the fetched part as an extra, hidden
  /// until the owner shows it.
  final bool extra;

  bool get owned => entry != null;
}

/// The key a series' hidden parts are kept under on the device: its type
/// and its name as the library shows it, compared like a title.
String seriesKey(MediaType type, String name) =>
    '${type.name}:${titleKey(seriesDisplayName(name))}';

/// The key a part is hidden by: its lookup id, else its title.
String seriesPartKey(SeriesPart part) =>
    part.source ?? 'title:${titleKey(part.title)}';

/// Which parts of the series [key] the owner chose to hide and, of the
/// extras, to show (Library › Series page: choose what to show).
typedef SeriesPartChoices = ({Set<String> hidden, Set<String> shown});

SeriesPartChoices seriesPartChoices(DisplayPreferences prefs, String key) =>
    (hidden: prefs.hiddenPartsOf(key), shown: prefs.shownPartsOf(key));

/// Whether [row] is hidden: a part not in the library that the owner hid,
/// or an extra of the automatic rules they did not show. A part in the
/// library is never hidden.
bool isHiddenRow(SeriesRow row, SeriesPartChoices choices) =>
    !row.owned &&
    (choices.hidden.contains(row.partKey) ||
        (row.extra && !choices.shown.contains(row.partKey)));

/// [rows] without the hidden parts ([isHiddenRow]), and the hidden ones.
({List<SeriesRow> shown, List<SeriesRow> hidden}) splitHiddenRows(
  List<SeriesRow> rows,
  SeriesPartChoices choices,
) => (
  shown: [
    for (final r in rows)
      if (!isHiddenRow(r, choices)) r,
  ],
  hidden: [
    for (final r in rows)
      if (isHiddenRow(r, choices)) r,
  ],
);

/// "movie", "movies" for the parts of a movie or anime series; "volume",
/// "volumes" for a book's; "game", "games".
(String one, String many) seriesNouns(MediaType type) => switch (type) {
  MediaType.books => ('volume', 'volumes'),
  MediaType.games => ('game', 'games'),
  MediaType.movies || MediaType.anime => ('movie', 'movies'),
  MediaType.shows || MediaType.music => ('part', 'parts'),
};

/// The series name as the library shows it: TMDB names its collections
/// "The Lord of the Rings Collection"; the row says "The Lord of the Rings".
String seriesDisplayName(String name) {
  final match = RegExp(
    r'^(.+?)\s+collection$',
    caseSensitive: false,
  ).firstMatch(name.trim());
  return match?.group(1) ?? name.trim();
}

/// A part's title without the series name in front of it: "The Fellowship
/// of the Ring" for "The Lord of the Rings: The Fellowship of the Ring",
/// since every row would start the same way otherwise.
String seriesPartTitle(String title, String seriesName) {
  final prefix = RegExp(
    '^${RegExp.escape(seriesName)}\\s*[:,\\u2013\\u2014-]\\s+(.+)\$',
    caseSensitive: false,
  );
  final rest = prefix.firstMatch(title)?.group(1)?.trim();
  return rest == null || rest.isEmpty ? title : rest;
}

/// The entries of [entries] that are in the series [name] of [type], the
/// name compared like a title.
List<Entry> entriesInSeries(
  Iterable<Entry> entries,
  MediaType type,
  String name,
) => [
  for (final e in entries)
    if (e.type == type)
      if (e.series case final series? when sameTitle(series.name, name)) e,
];

/// The rows of the series [current] is in: the fetched [parts] in the
/// series' own order, each matched to the entry in [library] that is it (by
/// lookup id, else by number, else by title and year, else by title; each
/// rule tried on every part before the next), then the library's other
/// entries of the series, every row placed by its number (rows without one
/// after the rest, in the order they came). A matched part takes its
/// entry's number, title and year, since those are the owner's to edit
/// (Open Library may call volume 16 "Berserk #16-20"); the source's
/// number only counts where the entry has none. Without fetched parts the
/// rows are the library's entries alone.
List<SeriesRow> seriesRows({
  required Entry current,
  required Iterable<Entry> library,
  SeriesParts? parts,
}) {
  final name = current.series?.name;
  if (name == null) return const [];
  final owned = [
    current,
    for (final e in entriesInSeries(library, current.type, name))
      if (e.id != current.id) e,
  ];
  final left = [...owned];
  final fetched = parts?.parts ?? const <SeriesPart>[];
  final matched = List<Entry?>.filled(fetched.length, null);
  // One pass per rule over every part, so a weaker rule never takes an
  // entry a stronger one would give another part: the 2013 "Tomb Raider"
  // is part 18 by its id, not part 1 by its title. Extras come last in each
  // pass, so "The Journey of the Nine Companions", number 2 of a six-book
  // edition, never takes the owner's The Two Towers by its number.
  final order = [
    for (final (i, p) in fetched.indexed)
      if (!p.extra) i,
    for (final (i, p) in fetched.indexed)
      if (p.extra) i,
  ];
  void pass(bool Function(SeriesPart part, Entry e) test) {
    for (final i in order) {
      final part = fetched[i];
      if (matched[i] != null) continue;
      final j = left.indexWhere((e) => test(part, e));
      if (j >= 0) matched[i] = left.removeAt(j);
    }
  }

  bool sameYear(SeriesPart part, Entry e) =>
      part.year == null || e.year == null || part.year == e.year;
  bool titled(SeriesPart part, Entry e) => sameTitle(e.title, part.title);
  bool shortTitled(SeriesPart part, Entry e) => sameTitle(
    seriesPartTitle(e.title, name),
    seriesPartTitle(part.title, name),
  );

  pass((p, e) => p.source != null && e.source == p.source);
  pass((p, e) => p.number != null && e.series?.number == p.number);
  pass((p, e) => titled(p, e) && sameYear(p, e));
  pass((p, e) => shortTitled(p, e) && sameYear(p, e));
  pass(titled);
  pass(shortTitled);

  final rows = <SeriesRow>[];
  for (final (i, part) in fetched.indexed) {
    final entry = matched[i];
    rows.add(
      SeriesRow(
        number: entry?.series?.number ?? part.number,
        title: entry?.title ?? part.title,
        year: entry?.year ?? part.year,
        entry: entry,
        partKey: seriesPartKey(part),
        creator: part.creator,
        extra: part.extra,
      ),
    );
  }
  for (final e in left) {
    rows.add(
      SeriesRow(
        number: e.series?.number,
        title: e.title,
        year: e.year,
        entry: e,
      ),
    );
  }
  // A stable sort by number, rows without one last.
  final indexed = rows.indexed.toList()
    ..sort((a, b) {
      final x = a.$2.number, y = b.$2.number;
      if (x != null && y != null && x != y) return x.compareTo(y);
      if (x == null && y != null) return 1;
      if (x != null && y == null) return -1;
      return a.$1.compareTo(b.$1);
    });
  return [for (final (_, row) in indexed) row];
}

/// Up to [SeriesSection.listedAll] rows are all shown; with more, the one
/// before this one, this one and the one after (the first three when this is
/// the first, the last three when it is the last).
List<SeriesRow> seriesWindow(List<SeriesRow> rows, int currentIndex) {
  if (rows.length <= SeriesSection.listedAll) return rows;
  final start = math.max(0, math.min(rows.length - 3, currentIndex - 1));
  return rows.sublist(start, start + 3);
}

/// The Series section of an entry's details, after Rating (Library › Movie in
/// a series; Book in a long series): the series name, "2 of 3 in your
/// library", and the parts, without the ones the owner hid. This one is highlighted; parts in the library
/// show their status and open their own details through [onOpen]; missing
/// ones are grayed with "+ Add", which starts a new entry looked up for that
/// title. Six parts or more show a window of three and "All 43 volumes ›",
/// which opens [AllSeriesScreen].
class SeriesSection extends ConsumerWidget {
  const SeriesSection({super.key, required this.entry, required this.onOpen});

  final Entry entry;

  /// Opens the details of another part, by its entry id.
  final ValueChanged<String> onOpen;

  static const listedAll = 5;

  /// "2 of 3 in your library".
  static String ownedLabel(List<SeriesRow> rows) =>
      '${rows.where((r) => r.owned).length} of ${rows.length} in your library';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final series = entry.series;
    if (series == null) return const SizedBox.shrink();
    final library = ref.watch(libraryProvider).value;
    final parts = ref.watch(seriesPartsProvider(entry.id)).value?.series;
    final choices = ref.watch(
      displayPreferencesProvider.select(
        (p) => seriesPartChoices(p, seriesKey(entry.type, series.name)),
      ),
    );
    final rows = splitHiddenRows(
      seriesRows(
        current: entry,
        library: library?.entries ?? const [],
        parts: parts,
      ),
      choices,
    ).shown;
    final currentIndex = rows.indexWhere((r) => r.entry?.id == entry.id);
    final shown = seriesWindow(rows, currentIndex);
    final (_, many) = seriesNouns(entry.type);
    final more = 'All ${rows.length} $many';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(
          'Series',
          padding: EdgeInsets.zero,
          trailing: ownedLabel(rows),
        ),
        const SizedBox(height: 4),
        Text(
          series.name,
          style: theme.textTheme.titleMedium!.copyWith(fontSize: 15),
        ),
        const SizedBox(height: 4),
        for (final row in shown)
          SeriesPartRow(
            row: row,
            series: series.name,
            type: entry.type,
            current: row.entry?.id == entry.id,
            onOpen: onOpen,
          ),
        if (rows.length > listedAll)
          Semantics(
            button: true,
            label: more,
            excludeSemantics: true,
            // No press highlight: the list opening is the feedback, as for
            // the seasons.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                final opened = await openAllSeries(context, entry.id);
                if (opened != null) onOpen(opened);
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.divider)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        more,
                        style: theme.textTheme.titleMedium!.copyWith(
                          fontSize: 15,
                        ),
                      ),
                    ),
                    StrokeIcon(
                      AppIcons.chevronRight,
                      size: 18,
                      color: colors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One part: its number, its title (without the series name in front) and
/// year. This one is highlighted and says so; one in the library shows its
/// status mark and a chevron and opens its details; one that is not is
/// grayed, says "Not in your library" and offers "+ Add".
class SeriesPartRow extends StatelessWidget {
  const SeriesPartRow({
    super.key,
    required this.row,
    required this.series,
    required this.type,
    required this.current,
    required this.onOpen,
  });

  final SeriesRow row;
  final String series;
  final MediaType type;
  final bool current;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final entry = row.entry;
    final title = seriesPartTitle(row.title, series);
    final missing = entry == null;
    final yearLine = [
      if (row.year case final year?) '$year',
      if (missing) 'Not in your library',
    ].join(' · ');
    final body = Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            row.number == null ? '' : '${row.number}',
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium!.copyWith(
              fontSize: 14,
              color: colors.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium!.copyWith(
                  fontSize: 15.5,
                  color: missing ? colors.muted : null,
                ),
              ),
              if (yearLine.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(
                  yearLine,
                  style: theme.textTheme.bodySmall!.copyWith(
                    fontStyle: FontStyle.normal,
                    fontSize: 13,
                    color: missing ? colors.placeholder : colors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (current)
          Text(
            'This one',
            style: theme.textTheme.labelMedium!.copyWith(
              fontSize: 12.5,
              color: theme.colorScheme.primary,
            ),
          )
        else if (entry != null) ...[
          StatusMark(entry.status),
          // The chevron runs into the margin, as drawn.
          const SizedBox(width: 4),
          StrokeIcon(AppIcons.chevronRight, size: 18, color: colors.muted),
        ] else
          DashedChip(
            label: 'Add',
            height: 32,
            semanticsLabel: 'Add $title',
            onTap: () =>
                openNewEntryScreen(context, type: type, title: row.title),
          ),
      ],
    );
    if (current) {
      return Semantics(
        label: '$title, this one',
        excludeSemantics: true,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -10,
              right: -10,
              top: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.selectedFill,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: body,
            ),
          ],
        ),
      );
    }
    final content = Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: body,
    );
    if (entry == null) {
      return Semantics(label: '$title, $yearLine', child: content);
    }
    // No press highlight: the other part's details opening is the feedback.
    return Semantics(
      button: true,
      label: 'Open $title, ${entry.status.lowerLabel}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onOpen(entry.id),
        child: content,
      ),
    );
  }
}

/// Opens every part of the series (Library › All volumes in a series). Resolves
/// with the id of a part the user tapped, to open its details, or null.
Future<String?> openAllSeries(BuildContext context, String entryId) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => AllSeriesScreen(entryId: entryId)),
    );

/// Opens the series page for a series row of the library list (Library ›
/// Series page (from a series row)), by one of its parts in the library.
Future<void> openSeriesPage(BuildContext context, String entryId) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AllSeriesScreen(entryId: entryId, fromList: true),
      ),
    );

/// Every part of a series, full screen (Library › All volumes in a series):
/// the series name with a back arrow, "43 volumes · 15 in your library", then
/// the rows of [SeriesPartRow], opened scrolled to this one with a few above
/// it in view. Tapping a part in the library pops with its id.
///
/// Opened from a series row of the library list ([fromList]; Library ›
/// Series page (from a series row)) it is the series page instead: no part
/// is "this one", a part in the library opens its details sheet and closing
/// it comes back here, and with two or more parts in the library the ⋮ menu
/// has Series cover, which picks the part whose cover stands for the series
/// in the list.
///
/// Parts the owner hid (Library › Series page: hidden parts) are left out
/// of the list and the counts; the ⋮ menu's Choose what to show picks them,
/// and "2 hidden parts · Show" at the end shows them until the page closes.
class AllSeriesScreen extends ConsumerStatefulWidget {
  const AllSeriesScreen({
    super.key,
    required this.entryId,
    this.fromList = false,
  });

  final String entryId;
  final bool fromList;

  @override
  ConsumerState<AllSeriesScreen> createState() => _AllSeriesScreenState();
}

enum _SeriesMenuAction { cover, show }

class _AllSeriesScreenState extends ConsumerState<AllSeriesScreen> {
  final _current = GlobalKey();
  bool _scrolled = false;

  /// Whether the hidden parts show for now ("Show" on the hidden row).
  bool _peek = false;

  void _scrollToCurrent() {
    if (_scrolled) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _current.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(target, alignment: 0.35);
    });
  }

  Future<void> _open(String id) async {
    if (widget.fromList) {
      await showEntryDetailsSheet(context, id);
      return;
    }
    Navigator.pop(context, id);
  }

  Future<void> _openMenu(
    BuildContext anchor, {
    required bool cover,
    required bool show,
  }) {
    final theme = Theme.of(anchor);
    final colors = LibraryColors.of(anchor);
    final button = anchor.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final origin = button.localToGlobal(Offset.zero, ancestor: overlay);
    PopupMenuItem<_SeriesMenuAction> item(
      _SeriesMenuAction action,
      StrokeIconData icon,
      String label,
    ) => PopupMenuItem(
      value: action,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          StrokeIcon(icon, size: 20, color: colors.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
        ],
      ),
    );
    return showMenu<_SeriesMenuAction>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromLTRB(
        overlay.size.width - 16 - 230,
        origin.dy + button.size.height - 4,
        16,
        0,
      ),
      constraints: const BoxConstraints(minWidth: 230, maxWidth: 230),
      popUpAnimationStyle: AppMotion.menu,
      items: [
        if (cover)
          item(_SeriesMenuAction.cover, AppIcons.image, 'Series cover'),
        if (show)
          item(_SeriesMenuAction.show, AppIcons.eye, 'Choose what to show'),
      ],
    ).then((action) {
      if (!mounted) return;
      final library = ref.read(libraryProvider).value;
      final entry = library?.entryById(widget.entryId);
      final series = entry?.series;
      if (entry == null || series == null) return;
      final rows = seriesRows(
        current: entry,
        library: library?.entries ?? const [],
        parts: ref.read(seriesPartsProvider(widget.entryId)).value?.series,
      );
      switch (action) {
        case _SeriesMenuAction.cover:
          showSeriesCoverSheet(
            context,
            seriesName: seriesDisplayName(series.name),
            parts: [for (final r in rows) ?r.entry],
          );
        case _SeriesMenuAction.show:
          showSeriesPartsSheet(
            context,
            seriesName: series.name,
            seriesKey: seriesKey(entry.type, series.name),
            rows: rows,
          );
        case null:
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final library = ref.watch(libraryProvider).value;
    final entry = library?.entryById(widget.entryId);
    final series = entry?.series;
    final parts = ref.watch(seriesPartsProvider(widget.entryId)).value?.series;
    final all = entry == null
        ? const <SeriesRow>[]
        : seriesRows(
            current: entry,
            library: library?.entries ?? const [],
            parts: parts,
          );
    final choices = ref.watch(
      displayPreferencesProvider.select(
        (p) => entry == null || series == null
            ? (hidden: const <String>{}, shown: const <String>{})
            : seriesPartChoices(p, seriesKey(entry.type, series.name)),
      ),
    );
    final (:shown, :hidden) = splitHiddenRows(all, choices);
    final rows = _peek ? all : shown;
    if (rows.isNotEmpty && !widget.fromList) _scrollToCurrent();
    final (_, many) = seriesNouns(entry?.type ?? MediaType.movies);
    final owned = [for (final r in all) ?r.entry];
    final name = series?.name ?? 'Series';
    final canCover = widget.fromList && owned.length >= 2;
    final canShow = all.any((r) => !r.owned);
    final hiddenLabel =
        '${hidden.length} hidden ${hidden.length == 1 ? 'part' : 'parts'}';
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: widget.fromList ? seriesDisplayName(name) : name,
              onBack: () => Navigator.pop(context),
              actions: [
                if (canCover || canShow)
                  Builder(
                    builder: (anchor) => Transform.translate(
                      // The dots line up with the page margin, as drawn.
                      offset: const Offset(10, 0),
                      child: IconButton(
                        onPressed: () =>
                            _openMenu(anchor, cover: canCover, show: canShow),
                        tooltip: 'Series options',
                        icon: const StrokeIcon(AppIcons.more, size: 22),
                      ),
                    ),
                  ),
              ],
            ),
            // Under the title, past the back arrow, like all seasons. Hidden
            // parts are not counted, even while they show.
            Padding(
              padding: const EdgeInsets.fromLTRB(68, 0, 20, 8),
              child: Text(
                '${shown.length} $many · ${owned.length} in your library',
                style: theme.textTheme.bodySmall!.copyWith(
                  fontStyle: FontStyle.normal,
                  fontSize: 13.5,
                  color: colors.muted,
                ),
              ),
            ),
            Expanded(
              child: entry == null || series == null
                  ? const SizedBox()
                  : SingleChildScrollView(
                      // From a series row the page sits inside the Library
                      // tab, under the pill and "+", so it scrolls clear.
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        widget.fromList ? AppShell.contentBottomPadding : 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final row in rows)
                            SeriesPartRow(
                              key: !widget.fromList && row.entry?.id == entry.id
                                  ? _current
                                  : null,
                              row: row,
                              series: series.name,
                              type: entry.type,
                              current:
                                  !widget.fromList && row.entry?.id == entry.id,
                              onOpen: _open,
                            ),
                          if (hidden.isNotEmpty)
                            Container(
                              constraints: const BoxConstraints(minHeight: 56),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      hiddenLabel,
                                      style: theme.textTheme.bodyMedium!
                                          .copyWith(
                                            fontSize: 14,
                                            color: colors.placeholder,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  TextButton(
                                    onPressed: () =>
                                        setState(() => _peek = !_peek),
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          theme.colorScheme.primary,
                                    ),
                                    child: Text(_peek ? 'Hide' : 'Show'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks which parts of a series that are not in the library show (Library ›
/// Series page: choose what to show): one row per such part in series order,
/// ticked unless hidden, with its number, year and, when they are not the
/// series' usual authors, its authors. Done keeps the unticked ones hidden
/// on the device, under [seriesKey]; closing the sheet any other way keeps
/// what was there.
Future<void> showSeriesPartsSheet(
  BuildContext context, {
  required String seriesName,
  required String seriesKey,
  required List<SeriesRow> rows,
}) => showAppSheet<void>(
  context,
  builder: (context) => SeriesPartsSheet(
    seriesName: seriesName,
    seriesKey: seriesKey,
    rows: rows,
  ),
);

class SeriesPartsSheet extends ConsumerStatefulWidget {
  const SeriesPartsSheet({
    super.key,
    required this.seriesName,
    required this.seriesKey,
    required this.rows,
  });

  /// The series' name, left out in front of the parts' titles.
  final String seriesName;
  final String seriesKey;

  /// Every row of the series; the ones not in the library are listed.
  final List<SeriesRow> rows;

  @override
  ConsumerState<SeriesPartsSheet> createState() => _SeriesPartsSheetState();
}

class _SeriesPartsSheetState extends ConsumerState<SeriesPartsSheet> {
  late final List<SeriesRow> _missing = [
    for (final r in widget.rows)
      if (!r.owned && r.partKey != null) r,
  ];

  late final SeriesPartChoices _saved = seriesPartChoices(
    ref.read(displayPreferencesProvider),
    widget.seriesKey,
  );

  /// The listed parts the owner hid, and the listed extras they show. Parts
  /// no longer listed (now in the library, or gone from the source) are
  /// let go on Done.
  late final Set<String> _hidden = {
    for (final r in _missing)
      if (_saved.hidden.contains(r.partKey)) r.partKey!,
  };
  late final Set<String> _shown = {
    for (final r in _missing)
      if (r.extra && _saved.shown.contains(r.partKey)) r.partKey!,
  };

  /// The authors most of the series' parts have, so a part by someone else
  /// can say who.
  late final String? _usualCreator = () {
    final counts = <String, int>{};
    for (final r in widget.rows) {
      if (r.creator case final c?) counts[c] = (counts[c] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }();

  void _done() {
    ref
        .read(displayPreferencesProvider.notifier)
        .setSeriesParts(widget.seriesKey, hidden: _hidden, shown: _shown);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return SheetFrame(
      scrollable: true,
      header: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Show in this series', style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  'Parts not in your library',
                  style: theme.textTheme.bodySmall!.copyWith(
                    fontStyle: FontStyle.normal,
                    color: colors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppButton(label: 'Done', compact: true, onPressed: _done),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in _missing) _partRow(row),
          const SizedBox(height: 14),
          Text(
            'Untick what you never want to see. Parts in your library always '
            'show, and parts the series gets later show until you hide them.',
            style: theme.textTheme.bodySmall!.copyWith(
              fontStyle: FontStyle.normal,
              fontSize: 13,
              color: colors.muted,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _partRow(SeriesRow row) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final on = !isHiddenRow(row, (hidden: _hidden, shown: _shown));
    final title = seriesPartTitle(row.title, widget.seriesName);
    final sub = [
      row.number == null ? 'No number' : 'Number ${row.number}',
      if (row.year case final year?) '$year',
      if (row.creator case final c? when c != _usualCreator) c,
    ].join(' · ');
    return Semantics(
      checked: on,
      label: title,
      excludeSemantics: true,
      child: RowInkWell(
        onTap: () => setState(() {
          final key = row.partKey!;
          if (row.extra) {
            on ? _shown.remove(key) : _shown.add(key);
          } else {
            on ? _hidden.add(key) : _hidden.remove(key);
          }
        }),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.divider)),
          ),
          child: Row(
            children: [
              CheckBoxMark(checked: on, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium!.copyWith(
                        color: on ? null : colors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: theme.textTheme.bodySmall!.copyWith(
                        fontStyle: FontStyle.normal,
                        fontSize: 13,
                        color: colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The part whose cover stands for a series in the library list: the one
/// marked `cover`, else the first of [parts] (part 1, in series order).
Entry seriesCoverEntry(List<Entry> parts) =>
    parts.firstWhere((p) => p.series?.cover == true, orElse: () => parts.first);

/// Picks the part whose cover stands for the series in the library list
/// (Library › Series page (from a series row): Series cover): the covers of
/// [parts], the parts in the library in series order, with the current one
/// ringed; Done applies [SetSeriesCover] when another was picked.
Future<void> showSeriesCoverSheet(
  BuildContext context, {
  required String seriesName,
  required List<Entry> parts,
}) => showAppSheet<void>(
  context,
  builder: (context) => SeriesCoverSheet(seriesName: seriesName, parts: parts),
);

class SeriesCoverSheet extends ConsumerStatefulWidget {
  const SeriesCoverSheet({
    super.key,
    required this.seriesName,
    required this.parts,
  });

  final String seriesName;
  final List<Entry> parts;

  @override
  ConsumerState<SeriesCoverSheet> createState() => _SeriesCoverSheetState();
}

class _SeriesCoverSheetState extends ConsumerState<SeriesCoverSheet> {
  late String _picked = seriesCoverEntry(widget.parts).id;

  Future<void> _done() async {
    final navigator = Navigator.of(context);
    if (_picked != seriesCoverEntry(widget.parts).id) {
      await ref.read(libraryRepositoryProvider).apply(SetSeriesCover(_picked));
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return SheetFrame(
      scrollable: true,
      header: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Series cover', style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  'Shown for ${widget.seriesName} in your library',
                  style: theme.textTheme.bodySmall!.copyWith(
                    fontStyle: FontStyle.normal,
                    color: colors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppButton(label: 'Done', compact: true, onPressed: _done),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CoverChoiceGrid(
            count: widget.parts.length,
            itemBuilder: (i, width) {
              final part = widget.parts[i];
              return CoverChoice(
                cover: CoverImage(
                  entry: part,
                  width: CoverChoice.imageWidth(width),
                  fontSize: 11,
                ),
                title: part.title,
                width: width,
                picked: part.id == _picked,
                lines: [
                  if (part.id == _picked)
                    i == 0 ? 'First in the series' : 'Your pick',
                ],
                onTap: () => setState(() => _picked = part.id),
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            'Only parts in your library can be the cover. The first in the '
            'series is used until you pick another.',
            style: theme.textTheme.bodySmall!.copyWith(
              fontStyle: FontStyle.normal,
              fontSize: 13,
              color: colors.muted,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
