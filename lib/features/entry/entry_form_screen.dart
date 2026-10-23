import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../data/models/entry_kind.dart';
import '../../data/models/platform_names.dart';
import '../../data/models/released.dart';
import '../../data/models/season.dart';
import '../../data/models/series.dart';
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

/// Opens the form (Add / edit entry) for a new entry, prefilled from a lookup
/// [match] or just a [type] and [title]. Resolves with the saved entry, or
/// null.
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

/// Opens the form (Add / edit entry) to edit [entry]. Resolves with the saved
/// entry, or null when the user went back.
Future<Entry?> openEditEntryForm(BuildContext context, Entry entry) {
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push<Entry>(MaterialPageRoute(builder: (_) => EntryFormScreen.edit(entry)));
}

/// A tag the lookup matched, with the role it is for (null for a genre).
typedef _Suggestion = ({String tag, TagCategory? category});

/// The add / edit entry form. Saving applies [AddEntry] or [UpdateEntry],
/// preceded by an [AddTag] for every tag created in the tag picker, and pops
/// with the saved entry. Saving an album whose songs are saved, or a song whose
/// album is, asks first (Add / edit entry › Saving an album: songs already
/// saved; Saving a song: album already saved). A show, and an anime marked a
/// series, has seasons instead of a date (Add / edit entry › Edit a show);
/// movies, books, games and anime movies have Series and Number fields.
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

  /// Tags a new entry starts with, e.g. a plan's tags from its pool (Plans ›
  /// All Halloween: add, edit, remove).
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

  /// Album or song for music; series or movie for anime, null while not
  /// known (an anime from before kinds, until picked).
  late EntryKind? _kind;
  late Released? _released;

  /// The date is an Apple Books ebook's year, with no Open Library year to
  /// go by (Add / edit entry › Book: year from the ebook edition). Held
  /// here only, never saved; cleared once the owner touches the date.
  bool _releasedFromEbook = false;
  late EntryStatus _status;
  late int? _rating;
  late List<String> _tags;

  /// Tags to create when the entry is saved, with their categories.
  final Map<String, List<TagCategory>> _newTags = {};

  /// Existing tags whose categories change when the entry is saved (a long
  /// press or "+ Add to Actors" in the picker, or a lookup that found a
  /// person under another people category), with their new categories.
  final Map<String, List<TagCategory>> _recategorized = {};

  /// For each tag in more than one category, the categories it is picked
  /// in on this entry (Add / edit entry › Tag in two categories: entry
  /// form); a tag missing here is picked in all of them.
  late Map<String, List<TagCategory>> _tagCategories;

  /// Tags the lookup suggested that are not in the library, in order.
  /// Matches to existing tags were put straight into [_tags].
  List<String> _suggestedNew = const [];

  /// Existing tags the lookup matched, each with the role it is for (null
  /// for a genre); they start selected and come back as suggestions when
  /// removed. A person the library has only under another category of the
  /// same kind is offered with the new role instead of going on at once.
  List<_Suggestion> _suggestedExisting = const [];

  /// The category a new suggestion starts in when it is not the type's
  /// default: Directors for the director, Actors for the cast.
  final Map<String, TagCategory> _suggestedCategories = {};
  bool _suggestionsPrepared = false;

  /// The platform chips: from the lookup, the entry and the library, plus
  /// any typed under "Other…", in that order.
  final List<String> _platformOptions = [];
  final Set<String> _platformsOn = {};
  bool _otherPlatformOpen = false;
  late Set<BookFormat> _formats;

  /// A book's page count, digits only; empty when unknown.
  late final TextEditingController _pages;

  /// The series the entry is in and its number, for the types that can be
  /// (Library › Movie in a series); empty when none.
  late final TextEditingController _seriesName;
  late final TextEditingController _seriesNumber;
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
        switch (_type) {
          MediaType.music =>
            match?.album == null ? EntryKind.album : EntryKind.song,
          MediaType.anime => match?.kind,
          _ => null,
        };
    _title = TextEditingController(
      text: entry?.title ?? match?.title ?? widget.title ?? '',
    );
    _creator = TextEditingController(
      text: entry?.creator ?? match?.creator ?? '',
    );
    _released = entry?.released ?? match?.released;
    _releasedFromEbook = entry == null && (match?.releasedFromEbook ?? false);
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
    _tagCategories = {...?entry?.tagCategories};
    _formats = {...?entry?.formats};
    _pages = TextEditingController(
      text: '${entry?.pages ?? match?.pages ?? ''}',
    );
    final series = entry?.series ?? match?.series;
    _seriesName = TextEditingController(text: series?.name ?? '');
    _seriesNumber = TextEditingController(text: '${series?.number ?? ''}');
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
    _pages.dispose();
    _seriesName.dispose();
    _seriesNumber.dispose();
    super.dispose();
  }

  List<EntryStatus> get _statusOptions => EntryStatus.optionsFor(_type);

  /// Wide enough for the longest date, "Sep 30, 2000", so it never clips
  /// (Add / edit entry › Released: wheel picker).
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

  /// Opening the picker, whatever it ends with, settles the ebook hint.
  Future<void> _pickReleased() async {
    await showReleasedSheet(
      context,
      initial: _released,
      onChanged: (released) => setState(() {
        _released = released;
        _releasedFromEbook = false;
      }),
    );
    if (mounted) setState(() => _releasedFromEbook = false);
  }

  /// Books only, and only while adding.
  bool get _showsEbookHint =>
      _releasedFromEbook &&
      _released != null &&
      _type == MediaType.books &&
      !widget.isEditing;

  bool get _canSave => !_saving && _title.text.trim().isNotEmpty;

  /// A show, or an anime marked a series: seasons instead of a date.
  bool get _usesSeasons =>
      _type == MediaType.shows ||
      (_type == MediaType.anime && _kind == EntryKind.series);

  /// Whether the Series and Number fields show (Library › Movie in a
  /// series): movies, books, games and anime that are not a series.
  bool get _hasSeries => Entry.typeHasSeries(_type, _kind);

  /// A show always has a season: one without (a new show filled in by
  /// hand) starts with Season 1, holding the date and status it had.
  void _seedSeason() {
    if (!_usesSeasons || _seasons.isNotEmpty) return;
    _seasons = [
      Season(season: 1, released: _released, status: _status, manual: true),
    ];
  }

  /// The status a show's seasons give; [_status] for anything else.
  EntryStatus get _effectiveStatus => _usesSeasons && _seasons.isNotEmpty
      ? Season.showStatus(_seasons, DateTime.now())
      : _status;

  /// An anime's kind: a series gets seasons (its first from the date and
  /// status it had); back to a movie, the date and status come from Season
  /// 1 and the seasons are left behind.
  void _pickAnimeKind(EntryKind kind) => setState(() {
    if (kind == _kind) return;
    if (kind == EntryKind.movie && _seasons.isNotEmpty) {
      _released ??= _seasons.first.released;
      _status = _effectiveStatus;
    }
    _kind = kind;
    _seedSeason();
  });

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

  /// One season in the form (Add / edit entry › Edit a show): its name and a
  /// button that removes it, then its release date (Add / edit entry ›
  /// Released: wheel picker) and its status pill, which opens the same sheet as
  /// details. A date fixed here is the user's, so the daily check leaves it
  /// alone.
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
              // One season: the Status control sets it (Add / edit entry › Edit
              // a show).
              if (_seasons.length > 1) ...[
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
                              ? s.copyWith(
                                  status: EntryStatus.done,
                                  fresh: null,
                                )
                              : s,
                      ];
                    }),
                  ),
                ),
              ],
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
    final matched = <_Suggestion>[];
    final fresh = <String>[];
    for (final raw in match.tags) {
      final name = canonicalTag(raw);
      if (name.isEmpty) continue;
      final hit = existing.contains(name)
          ? name
          : findSimilarTag(name, existing);
      if (hit != null) {
        if (!matched.any((s) => s.tag == hit)) {
          matched.add((tag: hit, category: null));
        }
      } else if (!fresh.contains(name)) {
        fresh.add(name);
      }
      if (matched.length + fresh.length == 6) break;
    }
    for (final s in matched) {
      if (!_tags.contains(s.tag)) _tags.add(s.tag);
    }
    // The creator's tag, when the library has it in its group, goes on
    // like a matched genre; a new one is offered under the field (see
    // _creatorSuggestions). The top-billed cast of a movie or show, at most
    // three, outside the six: an actor the library has goes on at once, the
    // rest are offered as new tags in the Actors group. People match by
    // exact slug only, and per category: a person the library has only
    // under another people category is offered with the new role
    // ("#clint-eastwood · Actor"), and a tap adds the category. The
    // language the lookup names goes the same way, in Languages.
    for (final t in [..._creatorTags, ..._actorTags, ..._languageTags]) {
      final categories = library.categoriesOf(t.tag);
      if (categories.isEmpty) {
        if (!fresh.contains(t.tag)) {
          fresh.add(t.tag);
          _suggestedCategories[t.tag] = t.category;
        }
        continue;
      }
      final suggestion = (tag: t.tag, category: t.category);
      if (matched.contains(suggestion)) continue;
      matched.add(suggestion);
      if (categories.contains(t.category) ||
          !categories.first.sharesKindWith(t.category)) {
        _tick(t.tag, t.category, library);
      }
    }
    _suggestedExisting = matched;
    _suggestedNew = fresh;
  }

  /// The categories of [tag] as they will be once the entry is saved.
  List<TagCategory> _categoriesOf(String tag, Library library) =>
      _newTags[tag] ?? _recategorized[tag] ?? library.categoriesOf(tag);

  /// Whether [tag] is on the entry as [category] (null: at all).
  bool _hasTagAs(String tag, TagCategory? category, Library library) {
    if (!_tags.contains(tag)) return false;
    if (category == null) return true;
    final categories = _categoriesOf(tag, library);
    if (!categories.contains(category)) return false;
    return categories.length < 2 ||
        (_tagCategories[tag]?.contains(category) ?? true);
  }

  /// Puts [tag] on the entry, as [category] when one is given: a tag in
  /// more than one category is ticked in that one; a tag the library has
  /// only under other categories of the same kind gets this one too, as
  /// "+ Add to Actors" in the picker does; any other tag goes on as it is.
  void _tick(String tag, TagCategory? category, Library library) {
    var categories = _categoriesOf(tag, library);
    if (category != null &&
        categories.isNotEmpty &&
        !categories.contains(category) &&
        categories.first.sharesKindWith(category)) {
      // On the entry already: it keeps the categories it had here.
      if (_tags.contains(tag) && !_tagCategories.containsKey(tag)) {
        _tagCategories[tag] = categories;
      }
      categories = [
        for (final c in TagCategory.values)
          if (c == category || categories.contains(c)) c,
      ];
      if (_newTags.containsKey(tag)) {
        _newTags[tag] = categories;
      } else {
        _recategorized[tag] = categories;
      }
    }
    if (!_tags.contains(tag)) _tags.add(tag);
    if (categories.length < 2) {
      _tagCategories.remove(tag);
      return;
    }
    final picked = _tagCategories[tag] ?? (category == null ? categories : []);
    _tagCategories[tag] = [
      for (final c in categories)
        if (c == category || picked.contains(c)) c,
    ];
  }

  /// The categories [tag] is picked in on this entry, for the chips.
  List<TagCategory> _categoriesOn(String tag, Library library) {
    final categories = _categoriesOf(tag, library);
    if (categories.length < 2) return const [];
    final picked = _tagCategories[tag];
    if (picked == null) return categories;
    return [
      for (final c in categories)
        if (picked.contains(c)) c,
    ];
  }

  /// "#clint-eastwood · Actor" for a suggestion whose tag the library has
  /// in more than one category, or under another one; "#tag" otherwise.
  String _suggestionLabel(_Suggestion s, Library library) {
    final (:tag, :category) = s;
    final categories = _categoriesOf(tag, library);
    if (category == null || categories.isEmpty) return '#$tag';
    if (categories.length > 1 || !categories.contains(category)) {
      return tagLabel(tag, [category]);
    }
    return '#$tag';
  }

  /// The tags for the creator field as it reads now: #stephen-king for an
  /// author, #naughty-dog for a studio, #pixar for a Pixar film whoever
  /// directed it (Add / edit entry, DESIGN.md section 7).
  List<CreatorTag> get _creatorTags => creatorTags(
    type: _type,
    creator: _creator.text,
    companies: _match?.companies ?? const [],
  );

  /// The actor tags for the lookup's billed cast (Add / edit entry):
  /// #kate-siegel, at most three, for movies and shows.
  List<CreatorTag> get _actorTags =>
      actorTags(type: _type, cast: _match?.cast ?? const []);

  /// The language tag for the lookup's original language (#japanese), in
  /// Languages; none for English, or Japanese on an anime.
  List<CreatorTag> get _languageTags =>
      languageTags(type: _type, language: _match?.language);

  /// The creator tags not on the entry, offered under the field once the
  /// field is left. Ones the lookup already matched come back through
  /// [_suggestions] when removed.
  List<CreatorTag> _creatorSuggestions(Library library) =>
      _creatorFocus.hasFocus
      ? const []
      : [
          for (final t in _creatorTags)
            if (!_hasTagAs(t.tag, t.category, library) &&
                !_suggestedExisting.contains((
                  tag: t.tag,
                  category: t.category,
                )) &&
                !_suggestedNew.contains(t.tag))
              t,
        ];

  Future<void> _addCreatorSuggestion(CreatorTag t, Library library) async {
    if (library.allTags.contains(t.tag) || _newTags.containsKey(t.tag)) {
      setState(() => _tick(t.tag, t.category, library));
      return;
    }
    final categories = await showNewTagDialog(
      context,
      name: t.tag,
      initial: t.category,
    );
    if (categories == null || !mounted) return;
    setState(() {
      _newTags[t.tag] = categories;
      _tick(t.tag, null, library);
    });
  }

  /// The suggestions not on the entry right now (not as their role, for a
  /// person).
  List<_Suggestion> _suggestions(Library library) => [
    for (final s in _suggestedExisting)
      if (!_hasTagAs(s.tag, s.category, library)) s,
    for (final tag in _suggestedNew)
      if (!_tags.contains(tag)) (tag: tag, category: _suggestedCategories[tag]),
  ];

  Future<void> _addSuggestion(_Suggestion s, Library library) async {
    if (!_suggestedNew.contains(s.tag)) {
      setState(() => _tick(s.tag, s.category, library));
      return;
    }
    final categories = await showNewTagDialog(
      context,
      name: s.tag,
      initial: s.category ?? TagCategory.defaultFor(_type),
    );
    if (categories == null || !mounted) return;
    setState(() {
      _newTags[s.tag] = categories;
      _tick(s.tag, null, library);
    });
  }

  /// "Look up again": the match picker (Add / edit entry › New entry: pick a
  /// match) on this entry's type and title; a pick sets the source and
  /// replaces the lookup's fields (creator, released, description, pages,
  /// album) with the match's where it has them, since a pick means another
  /// book, or the right one this time. The title, note, status, tags and
  /// formats are the owner's and stay.
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
    if (match.creator case final creator?) _creator.text = creator;
    if (match.released case final released?) {
      _released = released;
      _releasedFromEbook = !widget.isEditing && match.releasedFromEbook;
    }
    if (match.description.isNotEmpty) _description = match.description;
    if (match.pages case final pages?) _pages.text = '$pages';
    // Seasons that are all the user's own (a show filled in by hand, or
    // one from before seasons) give way to the lookup's, with the status
    // carried over.
    if (_type == MediaType.anime && match.kind != null) {
      _kind = match.kind;
    }
    final fetched = Season.listable(match.seasons);
    if (_usesSeasons &&
        fetched.isNotEmpty &&
        _seasons.every((s) => s.isManual)) {
      _seasons = carryOverStatus(fetched, _effectiveStatus, DateTime.now());
    }
    _seedSeason();
    if (_type == MediaType.music) {
      _kind = match.album == null ? EntryKind.album : EntryKind.song;
      if (match.album case final album?) _album.text = album;
    }
    if (match.series case final series?) {
      _seriesName.text = series.name;
      _seriesNumber.text = '${series.number ?? ''}';
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
      _kind = switch (type) {
        MediaType.music =>
          EntryKind.musicKinds.contains(_kind) ? _kind : EntryKind.album,
        MediaType.anime => EntryKind.animeKinds.contains(_kind) ? _kind : null,
        _ => null,
      };
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
      categories: _tagCategories,
      created: _newTags,
      recategorized: _recategorized,
      type: _type,
    );
    if (pick == null || !mounted) return;
    setState(() {
      _tags = pick.selected;
      _tagCategories = {...pick.categories};
      _newTags
        ..clear()
        ..addAll(pick.created);
      _recategorized
        ..clear()
        ..addAll(pick.recategorized);
    });
  }

  /// The Series and Number fields, side by side, the number 96 dp wide.
  Widget _seriesFields() {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FieldLabel('Series'),
                AppTextField(
                  controller: _seriesName,
                  hintText: 'Optional',
                  textCapitalization: TextCapitalization.words,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FieldLabel('Number'),
                AppTextField(
                  controller: _seriesNumber,
                  hintText: '#',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Entry _buildEntry(Iterable<String> existingIds) {
    final title = _title.text.trim();
    final creator = _creator.text.trim();
    final isShow = _usesSeasons;
    // A show has no date of its own: its seasons do (Add / edit entry › Edit a
    // show).
    final released = isShow ? null : _released;
    final isMusic = _type == MediaType.music;
    final platform = _platformOptions.where(_platformsOn.contains).join(', ');
    final album = _album.text.trim();
    final pages = int.tryParse(_pages.text.trim());
    final seriesName = _seriesName.text.trim();
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
      tagCategories: _tags.any(_tagCategories.containsKey)
          ? {
              for (final MapEntry(key: tag, value: categories)
                  in _tagCategories.entries)
                if (_tags.contains(tag)) tag: categories,
            }
          : null,
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
      pages: _type == MediaType.books && pages != null && pages > 0
          ? pages
          : null,
      series: _hasSeries && seriesName.isNotEmpty
          ? Series(
              name: seriesName,
              number: int.tryParse(_seriesNumber.text.trim()),
            )
          : null,
      kind: isMusic || _type == MediaType.anime ? _kind : null,
      album: isMusic && _kind == EntryKind.song && album.isNotEmpty
          ? album
          : null,
      tracks: isMusic && _kind == EntryKind.album ? base?.tracks : null,
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
      if (entry.kind == EntryKind.song) {
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
    for (final MapEntry(key: name, value: categories) in _newTags.entries) {
      if (_tags.contains(name)) {
        await repository.apply(AddTag(name, categories));
      }
    }
    for (final MapEntry(key: name, value: categories)
        in _recategorized.entries) {
      await repository.apply(SetTagCategories(name, categories));
    }
    final Entry saved;
    if (widget.isEditing) {
      await repository.apply(UpdateEntry(entry));
      saved = entry;
      // A pick replaces the cover, whether it brought a new source or the
      // one the entry had (the same book, whose cover may come from
      // elsewhere now), as does a source edited by hand.
      if (_match != null || entry.source != widget.entry!.source) {
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
    final suggestions = library == null
        ? const <_Suggestion>[]
        : _suggestions(library);
    final creatorSuggestions = library == null
        ? const <CreatorTag>[]
        : _creatorSuggestions(library);
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
                    SegmentedControl<EntryKind>(
                      segments: const [
                        SegmentOption(EntryKind.album, 'Album'),
                        SegmentOption(EntryKind.song, 'Song'),
                      ],
                      selected: _kind ?? EntryKind.album,
                      onChanged: (kind) => setState(() => _kind = kind),
                    ),
                  ],
                  if (_type == MediaType.anime) ...[
                    const SizedBox(height: 14),
                    const FieldLabel('Series or movie'),
                    // Nothing picked for an anime from before kinds, until
                    // the owner says which it is.
                    SegmentedControl<EntryKind?>(
                      segments: const [
                        SegmentOption(EntryKind.series, 'Series'),
                        SegmentOption(EntryKind.movie, 'Movie'),
                      ],
                      selected: _kind,
                      onChanged: (kind) => _pickAnimeKind(kind!),
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
                          if (_showsEbookHint) ...[
                            const SizedBox(height: 6),
                            Text(
                              "Year from the ebook edition. Check if it's "
                              'a reprint.',
                              style: Theme.of(context).textTheme.bodySmall!
                                  .copyWith(fontSize: 12.5, height: 1.35),
                            ),
                          ],
                        ],
                      );
                      if (_usesSeasons) return creatorField;
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
                  // Series and Number (Library › Movie in a series): under
                  // the creator, or under a book's Pages and Formats, as drawn.
                  if (_hasSeries && _type != MediaType.books) _seriesFields(),
                  if (_usesSeasons) ...[
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
                  if (_type == MediaType.music && _kind == EntryKind.song) ...[
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
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: _releasedWidth(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const FieldLabel('Pages'),
                            AppTextField(
                              controller: _pages,
                              hintText: 'Optional',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              maxLength: 5,
                            ),
                          ],
                        ),
                      ),
                    ),
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
                  if (_hasSeries && _type == MediaType.books) _seriesFields(),
                  const SizedBox(height: 14),
                  const FieldLabel('Status'),
                  if (_usesSeasons && _seasons.length > 1)
                    // The seasons set it (Add / edit entry › Edit a show).
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
                          if (_usesSeasons && _seasons.isNotEmpty) {
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
                        : 'Tags, ${_tags.map((t) => tagLabel(t, library == null ? const [] : _categoriesOn(t, library))).join(', ')}',
                    onTap: _pickTags,
                    child: _tags.isEmpty
                        ? const Text('Choose from your tags')
                        : Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              // A tag in more than one category is one chip
                              // per category it is picked in here
                              // ("#clint-eastwood · Actor").
                              for (final tag in _tags)
                                if (library != null &&
                                    _categoriesOf(tag, library).length > 1)
                                  for (final c in _categoriesOn(tag, library))
                                    TagChip(
                                      tag,
                                      detail: c.roleLabel,
                                      isNew: _newTags.containsKey(tag),
                                    )
                                else
                                  TagChip(
                                    tag,
                                    isNew: _newTags.containsKey(tag),
                                  ),
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
                            label: _suggestionLabel((
                              tag: t.tag,
                              category: t.category,
                            ), library!),
                            badge:
                                library.allTags.contains(t.tag) ||
                                    _newTags.containsKey(t.tag)
                                ? null
                                : 'new',
                            semanticsLabel: 'Add #${t.tag}',
                            onTap: () => _addCreatorSuggestion(t, library),
                          ),
                        for (final s in suggestions)
                          DashedChip(
                            label: _suggestionLabel(s, library!),
                            badge: _suggestedNew.contains(s.tag) ? 'new' : null,
                            semanticsLabel:
                                'Add ${_suggestionLabel(s, library)}',
                            onTap: () => _addSuggestion(s, library),
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
