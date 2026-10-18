import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/images/artwork_providers.dart';
import '../../data/library_providers.dart';
import '../../data/models/book_format.dart';
import '../../data/lookup/lookup_match.dart';
import '../../data/models/entry.dart';
import '../../data/models/entry_id.dart';
import '../../data/models/entry_status.dart';
import '../../data/models/library.dart';
import '../../data/models/media_type.dart';
import '../../data/models/music_kind.dart';
import '../../data/models/platform_names.dart';
import '../../data/models/released.dart';
import '../../data/models/season.dart';
import '../../data/models/tag_category.dart';
import '../../data/operations/operations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/chip_grid.dart';
import '../../widgets/chips.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/labels.dart';
import '../../widgets/page_header.dart';
import '../../widgets/segmented_control.dart';
import '../settings/display_preferences.dart';
import 'new_entry_screen.dart';
import 'released_sheet.dart';
import 'seasons.dart';
import 'rating_sheet.dart';
import 'replace_dialogs.dart';
import 'similar_tags.dart';
import 'tag_dialogs.dart';
import 'tag_picker_sheet.dart';
import 'creator_tags.dart';

/// Opens the form (A8) for a new entry, prefilled from a lookup [match] or
/// just a [type] and [title]. Resolves with the saved entry, or null.
Future<Entry?> openNewEntryForm(
  BuildContext context, {
  MediaType? type,
  String? title,
  LookupMatch? match,
  List<String> tags = const [],
}) {
  return Navigator.of(context, rootNavigator: true).push<Entry>(
    MaterialPageRoute(
      builder: (_) => EntryFormScreen.create(
        type: type,
        title: title,
        match: match,
        tags: tags,
      ),
    ),
  );
}

/// Opens the form (A8) to edit [entry]. Resolves with the saved entry, or
/// null when the user went back.
Future<Entry?> openEditEntryForm(BuildContext context, Entry entry) {
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push<Entry>(MaterialPageRoute(builder: (_) => EntryFormScreen.edit(entry)));
}

/// The add / edit entry form (A8). Saving applies [AddEntry] or
/// [UpdateEntry], preceded by an [AddTag] for every tag created in the tag
/// picker, and pops with the saved entry. Saving an album whose songs are
/// saved, or a song whose album is, asks first (D12, D13).
class EntryFormScreen extends ConsumerStatefulWidget {
  const EntryFormScreen.edit(Entry this.entry, {super.key})
    : type = null,
      title = null,
      match = null,
      tags = const [];

  const EntryFormScreen.create({
    super.key,
    this.type,
    this.title,
    this.match,
    this.tags = const [],
  }) : entry = null;

  final Entry? entry;
  final MediaType? type;
  final String? title;
  final LookupMatch? match;

  /// Tags a new entry starts with, e.g. a plan's tags from its pool (S4).
  final List<String> tags;

  bool get isEditing => entry != null;

  @override
  ConsumerState<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends ConsumerState<EntryFormScreen> {
  late final TextEditingController _title;
  late final TextEditingController _creator;

  /// The creator's tag is suggested once the field is left, not while a
  /// name is half typed.
  final _creatorFocus = FocusNode();
  late final TextEditingController _note;
  late final TextEditingController _otherPlatform;
  late final TextEditingController _album;
  late MediaType _type;
  late MusicKind? _kind;
  late Released? _released;
  late EntryStatus _status;
  late int? _rating;
  late List<String> _tags;
  final Map<String, TagCategory> _newTags = {};

  /// Tags the lookup suggested that are not in the library, in order.
  /// Matches to existing tags were put straight into [_tags].
  List<String> _suggestedNew = const [];

  /// Existing tags the lookup matched; they start selected and come back
  /// as suggestions when removed.
  List<String> _suggestedExisting = const [];

  /// The group a new suggestion is created in when it is not the type's
  /// default: the Actors group for the cast.
  final Map<String, TagCategory> _suggestedCategories = {};
  bool _suggestionsPrepared = false;

  /// The platform chips: from the lookup, the entry and the library, plus
  /// any typed under "Other…", in that order.
  final List<String> _platformOptions = [];
  final Set<String> _platformsOn = {};
  bool _otherPlatformOpen = false;
  late Set<BookFormat> _formats;
  late bool _seasonalOnly;
  late String _description;

  /// A show's seasons: the entry's, else the match's listable ones.
  late List<Season> _seasons;

  /// The lookup id, from the match or the entry. Cleared when the type
  /// changes, since the id would point at the wrong thing.
  String? _source;

  /// The match the form was filled from: the one it opened with, or one
  /// picked with "Look up again". While there is none the form offers to
  /// look the entry up.
  LookupMatch? _match;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    final match = widget.match;
    _match = match;
    _type = entry?.type ?? match?.type ?? widget.type ?? MediaType.movies;
    _kind =
        entry?.kind ??
        (_type == MediaType.music
            ? (match?.album == null ? MusicKind.album : MusicKind.song)
            : null);
    _title = TextEditingController(
      text: entry?.title ?? match?.title ?? widget.title ?? '',
    );
    _creator = TextEditingController(
      text: entry?.creator ?? match?.creator ?? '',
    );
    _released = entry?.released ?? match?.released;
    _note = TextEditingController(text: entry?.note ?? '');
    _otherPlatform = TextEditingController();
    for (final platform in [
      ...?match?.platforms,
      ...splitPlatforms(entry?.platform),
    ]) {
      _addPlatformOption(platform);
    }
    _platformsOn.addAll(splitPlatforms(entry?.platform));
    // A new game starts with the default platform from Settings picked,
    // when the game came out on it.
    if (entry == null && _type == MediaType.games) {
      final wanted = ref.read(displayPreferencesProvider).defaultPlatform;
      final name = wanted == null ? null : normalizePlatform(wanted);
      _platformsOn.addAll(
        _platformOptions.where((p) => p.toLowerCase() == name?.toLowerCase()),
      );
    }
    _album = TextEditingController(text: entry?.album ?? match?.album ?? '');
    _status = entry?.status ?? EntryStatus.want;
    _rating = entry?.rating;
    _tags = [...?entry?.tags, ...widget.tags];
    _formats = {...?entry?.formats};
    _seasonalOnly = entry?.seasonalOnly ?? false;
    _description = entry?.description ?? match?.description ?? '';
    _source = entry?.source ?? match?.source;
    _seasons = entry?.seasons ?? Season.listable(match?.seasons ?? const []);
    _seedSeason();
    _creatorFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _creator.dispose();
    _creatorFocus.dispose();
    _note.dispose();
    _otherPlatform.dispose();
    _album.dispose();
    super.dispose();
  }

  List<EntryStatus> get _statusOptions => EntryStatus.optionsFor(_type);

  /// Wide enough for the longest date, "Sep 30, 2000", so it never clips
  /// (A25).
  double _releasedWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'Sep 30, 2000',
        style: Theme.of(context).textTheme.bodyLarge!
            .copyWith(fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    // The field's padding, the chevron and its gap, the border and air.
    return math.max(150.0, width + 14 + 8 + 18 + 12 + 2 + 8);
  }

  Future<void> _pickReleased() => showReleasedSheet(
    context,
    initial: _released,
    onChanged: (released) => setState(() => _released = released),
  );

  bool get _canSave => !_saving && _title.text.trim().isNotEmpty;

  /// A show always has a season: one without (a new show filled in by
  /// hand) starts with Season 1, holding the date and status it had.
  void _seedSeason() {
    if (_type != MediaType.shows || _seasons.isNotEmpty) return;
    _seasons = [
      Season(season: 1, released: _released, status: _status, manual: true),
    ];
  }

  /// The status a show's seasons give; [_status] for anything else.
  EntryStatus get _effectiveStatus =>
      _type == MediaType.shows && _seasons.isNotEmpty
      ? Season.showStatus(_seasons, DateTime.now())
      : _status;

  /// A new season after the last, with no date or status yet. Added in the
  /// form, so the daily check never removes it.
  void _addSeason() => setState(() {
    final next = _seasons.isEmpty ? 1 : _seasons.last.season + 1;
    _seasons = [..._seasons, Season(season: next, manual: true)];
  });

  void _replaceSeason(Season season, Season? replacement) => setState(() {
    _seasons = [
      for (final s in _seasons)
        if (s.season != season.season) s else ?replacement,
    ];
  });

  void _setSeasonStatus(int number, EntryStatus? status) => setState(() {
    _seasons = [
      for (final s in _seasons)
        s.season == number
            ? s.copyWith(status: status, fresh: status == null ? s.fresh : null)
            : s,
    ];
  });

  /// One season in the form (A37): its name and a button that removes it,
  /// then its release date (A25) and its status pill, which opens the same
  /// sheet as details. A date fixed here is the user's, so the daily check
  /// leaves it alone.
  Widget _seasonField(BuildContext context, Season season) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final released = season.released;
    final releasedText = released == null ? 'Not set' : releasedLabel(released);
    final name = 'Season ${season.season}';
    return Container(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Transform.translate(
                // The cross lines up with the fields' right edge.
                offset: const Offset(12, 0),
                child: IconButton(
                  onPressed: () => _replaceSeason(season, null),
                  tooltip: 'Remove $name',
                  color: colors.muted,
                  icon: const StrokeIcon(AppIcons.close, size: 18),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: FieldButton(
                  onTap: () => showReleasedSheet(
                    context,
                    initial: released,
                    onChanged: (value) => _replaceSeason(
                      season,
                      season.copyWith(released: value, manual: true),
                    ),
                  ),
                  placeholder: released == null,
                  semanticsLabel: '$name released, $releasedText',
                  padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
                  child: Text(
                    releasedText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SeasonStatusPill(
                season: season,
                onTap: () => showSeasonStatusSheet(
                  context,
                  seasons: _seasons,
                  season: season.season,
                  onPick: (status) => _setSeasonStatus(season.season, status),
                  onCatchUp: () => setState(() {
                    _seasons = [
                      for (final s in _seasons)
                        s.season < season.season
                            ? s.copyWith(status: EntryStatus.done, fresh: null)
                            : s,
                    ];
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "PlayStation 5, PC" in the entry's `platform` field, as a list of
  /// spelled-out names ("PS5" reads as "PlayStation 5").
  static List<String> splitPlatforms(String? text) => [
    for (final part in (text ?? '').split(','))
      if (part.trim().isNotEmpty) normalizePlatform(part),
  ];

  /// Adds a chip unless one with the same platform is there already.
  /// Returns the chip's name.
  String _addPlatformOption(String platform) {
    final name = normalizePlatform(platform);
    for (final p in _platformOptions) {
      if (p.toLowerCase() == name.toLowerCase()) return p;
    }
    _platformOptions.add(name);
    return name;
  }

  void _addOtherPlatform() {
    final name = _otherPlatform.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _platformsOn.add(_addPlatformOption(name));
      _otherPlatform.clear();
      _otherPlatformOpen = false;
    });
  }

  /// Sorts the lookup's suggested tags into matches to the library's tags
  /// (selected at once; a near miss like "sci-fi" counts as "scifi") and
  /// new names offered under the field. At most six in total.
  void _prepareSuggestions(Library library) {
    _suggestionsPrepared = true;
    final match = _match;
    if (match == null) return;
    final existing = library.allTags;
    final matched = <String>[];
    final fresh = <String>[];
    for (final raw in match.tags) {
      final name = canonicalTag(raw);
      if (name.isEmpty) continue;
      final hit = existing.contains(name)
          ? name
          : findSimilarTag(name, existing);
      if (hit != null) {
        if (!matched.contains(hit)) matched.add(hit);
      } else if (!fresh.contains(name)) {
        fresh.add(name);
      }
      if (matched.length + fresh.length == 6) break;
    }
    // The creator's tag, when the library has it, goes on like a matched
    // genre; a new one is offered under the field (see _creatorSuggestions).
    for (final t in _creatorTags) {
      if (existing.contains(t.tag) && !matched.contains(t.tag)) {
        matched.add(t.tag);
      }
    }
    // The top-billed cast of a movie or show, at most three, outside the
    // six: an actor the library has goes on at once, the rest are offered
    // as new tags in the Actors group. People match by exact slug only.
    for (final t in _actorTags) {
      if (existing.contains(t.tag)) {
        if (!matched.contains(t.tag)) matched.add(t.tag);
      } else if (!fresh.contains(t.tag)) {
        fresh.add(t.tag);
        _suggestedCategories[t.tag] = t.category;
      }
    }
    _suggestedExisting = matched;
    _suggestedNew = fresh;
    for (final tag in matched) {
      if (!_tags.contains(tag)) _tags.add(tag);
    }
  }

  /// The tags for the creator field as it reads now: #stephen-king for an
  /// author, #naughty-dog for a studio, #pixar for a Pixar film whoever
  /// directed it (A8, DESIGN.md section 7).
  List<CreatorTag> get _creatorTags => creatorTags(
    type: _type,
    creator: _creator.text,
    companies: _match?.companies ?? const [],
  );

  /// The actor tags for the lookup's billed cast (A8): #kate-siegel, at
  /// most three, for movies and shows.
  List<CreatorTag> get _actorTags =>
      actorTags(type: _type, cast: _match?.cast ?? const []);

  /// The creator tags not on the entry, offered under the field once the
  /// field is left. Ones the lookup already matched come back through
  /// [_suggestions] when removed.
  List<CreatorTag> _creatorSuggestions() => _creatorFocus.hasFocus
      ? const []
      : [
          for (final t in _creatorTags)
            if (!_tags.contains(t.tag) &&
                !_suggestedExisting.contains(t.tag) &&
                !_suggestedNew.contains(t.tag))
              t,
        ];

  Future<void> _addCreatorSuggestion(CreatorTag t, Library library) async {
    if (library.allTags.contains(t.tag) || _newTags.containsKey(t.tag)) {
      setState(() => _tags.add(t.tag));
      return;
    }
    final category = await showNewTagDialog(
      context,
      name: t.tag,
      initial: t.category,
    );
    if (category == null || !mounted) return;
    setState(() {
      _newTags[t.tag] = category;
      _tags.add(t.tag);
    });
  }

  /// The suggestions not on the entry right now.
  List<String> get _suggestions => [
    for (final tag in [..._suggestedExisting, ..._suggestedNew])
      if (!_tags.contains(tag)) tag,
  ];

  Future<void> _addSuggestion(String tag) async {
    if (_suggestedExisting.contains(tag)) {
      setState(() => _tags.add(tag));
      return;
    }
    final category = await showNewTagDialog(
      context,
      name: tag,
      initial: _suggestedCategories[tag] ?? TagCategory.defaultFor(_type),
    );
    if (category == null || !mounted) return;
    setState(() {
      _newTags[tag] = category;
      _tags.add(tag);
    });
  }

  /// "Look up again": A13 on this entry's type and title; a pick fills in
  /// what the form has empty and sets the source. The owner's own text is
  /// never overwritten.
  Future<void> _lookUpAgain() async {
    final match = await openMatchPicker(
      context,
      type: _type,
      title: _title.text.trim(),
    );
    if (match == null || !mounted) return;
    setState(() => _applyMatch(match));
  }

  void _applyMatch(LookupMatch match) {
    _match = match;
    _source = match.source;
    if (_title.text.trim().isEmpty) _title.text = match.title;
    if (_creator.text.trim().isEmpty && match.creator != null) {
      _creator.text = match.creator!;
    }
    _released ??= match.released;
    if (_description.isEmpty) _description = match.description;
    // Seasons that are all the user's own (a show filled in by hand, or
    // one from before seasons) give way to the lookup's, with the status
    // carried over.
    final fetched = Season.listable(match.seasons);
    if (_type == MediaType.shows &&
        fetched.isNotEmpty &&
        _seasons.every((s) => s.isManual)) {
      _seasons = carryOverStatus(fetched, _effectiveStatus, DateTime.now());
    }
    if (_type == MediaType.music) {
      _kind = match.album == null ? MusicKind.album : MusicKind.song;
      if (_album.text.trim().isEmpty && match.album != null) {
        _album.text = match.album!;
      }
    }
    for (final platform in match.platforms) {
      _addPlatformOption(platform);
    }
    // The tag suggestions are matched against the library on the next
    // build, as for a new entry.
    _suggestedExisting = const [];
    _suggestedNew = const [];
    _suggestedCategories.clear();
    _suggestionsPrepared = false;
  }

  void _pickType(MediaType type) {
    setState(() {
      if (type != _type) _source = null;
      _type = type;
      _kind = type == MediaType.music ? (_kind ?? MusicKind.album) : null;
      if (!_statusOptions.contains(_status)) _status = EntryStatus.want;
      _seedSeason();
    });
  }

  Future<void> _pickRating() async {
    final choice = await showRatingSheet(
      context,
      title: _title.text.trim().isEmpty ? 'New entry' : _title.text.trim(),
      current: _rating,
    );
    if (choice != null && mounted) setState(() => _rating = choice.rating);
  }

  Future<void> _pickTags() async {
    final library = await ref.read(libraryRepositoryProvider).load();
    if (!mounted) return;
    final pick = await showTagPickerSheet(
      context,
      library: library,
      selected: _tags,
      created: _newTags,
      type: _type,
    );
    if (pick == null || !mounted) return;
    setState(() {
      _tags = pick.selected;
      _newTags
        ..clear()
        ..addAll(pick.created);
    });
  }

  Entry _buildEntry(Iterable<String> existingIds) {
    final title = _title.text.trim();
    final creator = _creator.text.trim();
    final isShow = _type == MediaType.shows;
    // A show has no date of its own: its seasons do (A37).
    final released = isShow ? null : _released;
    final isMusic = _type == MediaType.music;
    final platform = _platformOptions.where(_platformsOn.contains).join(', ');
    final album = _album.text.trim();
    final base = widget.entry;
    final now = DateTime.now();
    return Entry(
      id:
          base?.id ??
          EntryId.generate(
            type: _type,
            title: title,
            year: (isShow ? _seasons.firstOrNull?.released : released)?.year
                .toString(),
            artist: creator.isEmpty ? null : creator,
            existingIds: existingIds,
          ),
      type: _type,
      title: title,
      released: released,
      creator: creator.isEmpty ? null : creator,
      status: _effectiveStatus,
      rating: _rating,
      tags: _tags,
      note: _note.text.trim(),
      description: _description,
      seasonalOnly: _seasonalOnly,
      added: base?.added ?? DateTime(now.year, now.month, now.day),
      source: _source,
      platform: _type == MediaType.games && platform.isNotEmpty
          ? platform
          : null,
      formats: _type == MediaType.books && _formats.isNotEmpty
          ? [
              for (final f in BookFormat.values)
                if (_formats.contains(f)) f,
            ]
          : null,
      kind: isMusic ? _kind : null,
      album: isMusic && _kind == MusicKind.song && album.isNotEmpty
          ? album
          : null,
      tracks: isMusic && _kind == MusicKind.album ? base?.tracks : null,
      seasons: isShow && _seasons.isNotEmpty ? _seasons : null,
    );
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final repository = ref.read(libraryRepositoryProvider);
    final library = await repository.load();
    var entry = _buildEntry(library.entries.map((e) => e.id));
    final replaced = <Entry>[];
    if (entry.type == MediaType.music && mounted) {
      final ReplaceChoice? choice;
      if (entry.kind == MusicKind.song) {
        final album = albumOfSong(
          library,
          entry,
          albumSource: _match?.albumSource,
        );
        choice = album == null
            ? ReplaceChoice.keepBoth
            : await showReplaceAlbumDialog(
                context,
                song: entry,
                album: album,
                adding: !widget.isEditing,
              );
        if (choice == ReplaceChoice.replace) replaced.add(album!);
      } else {
        final songs = songsFromAlbum(library, entry);
        choice = songs.isEmpty
            ? ReplaceChoice.keepBoth
            : await showReplaceSongsDialog(context, album: entry, songs: songs);
        if (choice == ReplaceChoice.replace) {
          entry = absorbSongs(entry, songs);
          replaced.addAll(songs);
        }
      }
      if (choice == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }
    }
    for (final MapEntry(key: name, value: category) in _newTags.entries) {
      if (_tags.contains(name)) await repository.apply(AddTag(name, category));
    }
    final Entry saved;
    if (widget.isEditing) {
      await repository.apply(UpdateEntry(entry));
      saved = entry;
      // A new source replaces the cover that was matched on the device.
      if (entry.source != widget.entry!.source) {
        ref.read(artworkResolverProvider).forget(entry.id);
      }
    } else {
      final result = await repository.apply(AddEntry(entry));
      saved = result.entries.last;
    }
    // After the save, so tags shared with the replaced entries survive the
    // pruning that a delete does.
    for (final old in replaced) {
      await repository.apply(DeleteEntry(old.id));
    }
    if (mounted) Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final editing = widget.isEditing;
    final library = ref.watch(libraryProvider).value;
    if (library != null && !_suggestionsPrepared) {
      // First build with the library: match the suggested tags. The
      // platform chips are only the ones the game came out on (fetched)
      // and the entry's own; anything else goes through "Other…".
      // Plain field writes, no setState.
      _prepareSuggestions(library);
    }
    final suggestions = _suggestions;
    final creatorSuggestions = library == null
        ? const <CreatorTag>[]
        : _creatorSuggestions();
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: editing ? 'Edit entry' : 'New entry',
              onBack: () => Navigator.pop(context),
              actions: [
                AppButton(
                  label: editing ? 'Save' : 'Add',
                  compact: true,
                  onPressed: _canSave ? _save : null,
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  if (_match == null) ...[
                    AppButton(
                      label: 'Look up again',
                      kind: AppButtonKind.outline,
                      onPressed: _lookUpAgain,
                    ),
                    const SizedBox(height: 14),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        // On light the surface is white, so the card needs
                        // its shadow to show.
                        boxShadow: colors.cardShadow,
                      ),
                      child: Row(
                        children: [
                          StrokeIcon(
                            AppIcons.sparkle,
                            size: 18,
                            color: colors.muted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Details fetched online. You can change anything.',
                              style: theme.textTheme.bodySmall!.copyWith(
                                fontStyle: FontStyle.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  const FieldLabel('Title'),
                  AppTextField(
                    controller: _title,
                    hintText: 'Title',
                    autofocus: !editing && _title.text.isEmpty,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),
                  const FieldLabel('Type'),
                  ChipGrid(
                    columns: 3,
                    gap: 8,
                    children: [
                      for (final type in MediaType.values)
                        PillChip(
                          label: type.label,
                          selected: type == _type,
                          dotColor: colors.forType(type),
                          horizontalPadding: 4,
                          onTap: () => _pickType(type),
                        ),
                    ],
                  ),
                  if (_type == MediaType.music) ...[
                    const SizedBox(height: 14),
                    const FieldLabel('Album or song'),
                    SegmentedControl<MusicKind>(
                      segments: const [
                        SegmentOption(MusicKind.album, 'Album'),
                        SegmentOption(MusicKind.song, 'Song'),
                      ],
                      selected: _kind ?? MusicKind.album,
                      onChanged: (kind) => setState(() => _kind = kind),
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Side by side while the creator keeps room for a name;
                  // stacked at a large text size on a small phone, so
                  // neither field is cut.
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final dateWidth = _releasedWidth(context);
                      final creatorField = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FieldLabel(creatorLabel(_type)),
                          AppTextField(
                            controller: _creator,
                            focusNode: _creatorFocus,
                            hintText: 'Optional',
                            textCapitalization: TextCapitalization.words,
                          ),
                        ],
                      );
                      final released = _released;
                      final releasedText = released == null
                          ? 'Not set'
                          : releasedLabel(released);
                      final releasedField = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const FieldLabel('Released'),
                          FieldButton(
                            onTap: _pickReleased,
                            placeholder: released == null,
                            semanticsLabel: 'Released, $releasedText',
                            padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
                            child: Text(
                              releasedText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      );
                      if (_type == MediaType.shows) return creatorField;
                      // The creator keeps at least 140 dp beside the date
                      // field: side by side on a 360 dp phone, stacked at a
                      // larger text size.
                      if (constraints.maxWidth - dateWidth - 12 <
                          MediaQuery.textScalerOf(context).scale(140)) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            creatorField,
                            const SizedBox(height: 14),
                            releasedField,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: creatorField),
                          const SizedBox(width: 12),
                          SizedBox(width: dateWidth, child: releasedField),
                        ],
                      );
                    },
                  ),
                  if (_type == MediaType.shows) ...[
                    const SizedBox(height: 14),
                    const FieldLabel('Seasons'),
                    for (final season in _seasons)
                      _seasonField(context, season),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DashedChip(
                        label: 'Add season',
                        height: 44,
                        onTap: _addSeason,
                      ),
                    ),
                  ],
                  if (_type == MediaType.music && _kind == MusicKind.song) ...[
                    const SizedBox(height: 14),
                    const FieldLabel('Album'),
                    AppTextField(
                      controller: _album,
                      hintText: 'Optional',
                      textCapitalization: TextCapitalization.words,
                    ),
                  ],
                  if (_type == MediaType.games) ...[
                    const SizedBox(height: 14),
                    const FieldLabel('Platforms'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final platform in _platformOptions)
                          PillChip(
                            label: platform,
                            selected: _platformsOn.contains(platform),
                            checked: true,
                            onTap: () => setState(() {
                              if (!_platformsOn.remove(platform)) {
                                _platformsOn.add(platform);
                              }
                            }),
                          ),
                        if (!_otherPlatformOpen)
                          DashedChip(
                            label: 'Other…',
                            height: 44,
                            semanticsLabel: 'Other platform',
                            onTap: () =>
                                setState(() => _otherPlatformOpen = true),
                          ),
                      ],
                    ),
                    if (_otherPlatformOpen) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _otherPlatform,
                              hintText: 'Type a platform',
                              autofocus: true,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _addOtherPlatform(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AppButton(
                            label: 'Add',
                            kind: AppButtonKind.outline,
                            compact: true,
                            onPressed: _addOtherPlatform,
                          ),
                        ],
                      ),
                    ],
                  ],
                  if (_type == MediaType.books) ...[
                    const SizedBox(height: 14),
                    const FieldLabel('Formats'),
                    Row(
                      children: [
                        for (final format in BookFormat.values) ...[
                          if (format != BookFormat.values.first)
                            const SizedBox(width: 8),
                          PillChip(
                            label: format.label,
                            selected: _formats.contains(format),
                            style: PillChipStyle.accent,
                            onTap: () => setState(() {
                              if (!_formats.remove(format)) {
                                _formats.add(format);
                              }
                            }),
                          ),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  const FieldLabel('Status'),
                  if (_type == MediaType.shows && _seasons.length > 1)
                    // The seasons set it (A37).
                    DerivedStatusField(status: _effectiveStatus)
                  else
                    StatusSegmentedControl(
                      selected: _effectiveStatus,
                      type: _type,
                      style: SegmentedStyle.accent,
                      onChanged: (status) {
                        if (status == null) return;
                        setState(() {
                          _status = status;
                          // A show with one season: that season's status.
                          if (_type == MediaType.shows && _seasons.isNotEmpty) {
                            _seasons = [
                              _seasons.single.copyWith(
                                status: status,
                                fresh: null,
                              ),
                            ];
                          }
                        });
                      },
                    ),
                  const SizedBox(height: 14),
                  const FieldLabel('Rating'),
                  FieldButton(
                    placeholder: _rating == null,
                    semanticsLabel: 'Rating, ${ratingLabel(_rating)}',
                    onTap: _pickRating,
                    child: Text(ratingLabel(_rating)),
                  ),
                  const SizedBox(height: 14),
                  const FieldLabel('Tags'),
                  FieldButton(
                    placeholder: _tags.isEmpty,
                    padding: _tags.isEmpty
                        ? const EdgeInsets.fromLTRB(14, 8, 12, 8)
                        : const EdgeInsets.fromLTRB(8, 8, 12, 8),
                    semanticsLabel: _tags.isEmpty
                        ? 'Tags, none chosen'
                        : 'Tags, ${_tags.map((t) => '#$t').join(', ')}',
                    onTap: _pickTags,
                    child: _tags.isEmpty
                        ? const Text('Choose from your tags')
                        : Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final tag in _tags)
                                TagChip(tag, isNew: _newTags.containsKey(tag)),
                            ],
                          ),
                  ),
                  if (suggestions.isNotEmpty ||
                      creatorSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Suggested · tap to add',
                      style: theme.textTheme.bodySmall!.copyWith(
                        fontSize: 12.5,
                        fontStyle: FontStyle.normal,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in creatorSuggestions)
                          DashedChip(
                            label: '#${t.tag}',
                            badge:
                                library!.allTags.contains(t.tag) ||
                                    _newTags.containsKey(t.tag)
                                ? null
                                : 'new',
                            semanticsLabel: 'Add #${t.tag}',
                            onTap: () => _addCreatorSuggestion(t, library),
                          ),
                        for (final tag in suggestions)
                          DashedChip(
                            label: '#$tag',
                            badge: _suggestedNew.contains(tag) ? 'new' : null,
                            semanticsLabel: 'Add #$tag',
                            onTap: () => _addSuggestion(tag),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  const FieldLabel('Note'),
                  AppTextField(
                    controller: _note,
                    hintText: 'Optional',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _seasonalOnly,
                    onChanged: (on) => setState(() => _seasonalOnly = on),
                    title: Text(
                      'Seasonal only',
                      style: theme.textTheme.bodyLarge,
                    ),
                    subtitle: Text(
                      'Only wanted in its season; hidden from the main lists.',
                      style: theme.textTheme.bodySmall,
                    ),
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

extension on BookFormat {
  String get label => switch (this) {
    BookFormat.audiobook => 'Audiobook',
    BookFormat.physical => 'Physical',
  };
}
