import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/lookup/lookup_failure.dart';
import '../../data/lookup/lookup_match.dart';
import '../../data/lookup/lookup_providers.dart';
import '../../data/lookup/lookup_service.dart';
import '../../data/models/entry.dart';
import '../../data/models/media_type.dart';
import '../../theme/app_theme.dart';
import '../../widgets/lookup_notice.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/chips.dart';
import '../../widgets/labels.dart';
import '../../widgets/page_header.dart';
import '../../widgets/search_field.dart';
import '../../widgets/section_heading.dart';
import 'entry_form_screen.dart';

/// Starts a new entry (Add / edit entry › New entry: pick a match, then the
/// form), full screen above the floating navigation. Resolves with the saved
/// entry, or null.
Future<Entry?> openNewEntryScreen(
  BuildContext context, {
  MediaType? type,
  String? title,
  List<String> tags = const [],
}) {
  return Navigator.of(context, rootNavigator: true).push<Entry>(
    MaterialPageRoute(
      builder: (_) => NewEntryScreen(
        initialType: type,
        initialTitle: title,
        initialTags: tags,
      ),
    ),
  );
}

/// "Look up again" from the form (Add / edit entry): the same screen as
/// Add / edit entry › New entry: pick a match, started on the entry's type and
/// title, that hands the picked match back instead of opening a form. Resolves
/// with null when nothing was picked.
Future<LookupMatch?> openMatchPicker(
  BuildContext context, {
  required MediaType type,
  required String title,
}) {
  return Navigator.of(context, rootNavigator: true).push<LookupMatch>(
    MaterialPageRoute(
      builder: (_) =>
          NewEntryScreen(initialType: type, initialTitle: title, pick: true),
    ),
  );
}

/// Add / edit entry › New entry: pick a match. The title typed here is looked
/// up online once typing pauses; a match is fetched in full and opens the form
/// prefilled, "Fill in the details myself" opens it with just the title and
/// type. With [pick] the screen is "Look up again": a match is handed back to
/// the form that asked, and there is no "Fill in" button. Nothing here names a
/// provider.
class NewEntryScreen extends ConsumerStatefulWidget {
  const NewEntryScreen({
    super.key,
    this.initialType,
    this.initialTitle,
    this.initialTags = const [],
    this.pick = false,
  });

  final MediaType? initialType;
  final String? initialTitle;
  final List<String> initialTags;
  final bool pick;

  /// How long typing pauses before the lookup runs.
  static const debounce = Duration(milliseconds: 400);

  @override
  ConsumerState<NewEntryScreen> createState() => _NewEntryScreenState();
}

class _NewEntryScreenState extends ConsumerState<NewEntryScreen> {
  late final _query = TextEditingController(text: widget.initialTitle ?? '');
  late MediaType? _type = widget.initialType;

  Timer? _debounce;

  /// Counts lookups started, so an answer to an older one is dropped.
  int _request = 0;

  /// The last answer, or null before the first one for this query.
  LookupResult? _result;

  /// A lookup is pending or in flight.
  bool _loading = false;

  /// The match being fetched in full before the form opens.
  LookupMatch? _opening;

  String get _text => _query.text.trim();

  @override
  void initState() {
    super.initState();
    if (_text.isNotEmpty) _lookUp();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    if (_text.isEmpty) {
      setState(() {
        _result = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(NewEntryScreen.debounce, _lookUp);
  }

  void _pickType(MediaType? type) {
    if (type == _type) return;
    setState(() => _type = type);
    _debounce?.cancel();
    if (_text.isNotEmpty) _lookUp();
  }

  Future<void> _lookUp() async {
    final query = _text;
    final type = _type;
    final id = ++_request;
    setState(() => _loading = true);
    final result = await ref
        .read(lookupServiceProvider)
        .search(query, type: type);
    if (!mounted || id != _request) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  Future<void> _open({LookupMatch? match}) async {
    var picked = match;
    if (match != null) {
      setState(() => _opening = match);
      final source = ref.read(lookupServiceProvider).sourceOf(match.source);
      if (source != null) {
        try {
          picked = await source.details(match);
        } on LookupException {
          // The search already had the essentials; the form opens with them.
        }
      }
      if (!mounted) return;
      setState(() => _opening = null);
    }
    if (widget.pick) {
      Navigator.pop(context, picked);
      return;
    }
    final saved = await openNewEntryForm(
      context,
      type: _type,
      title: _text,
      match: picked,
      tags: widget.initialTags,
    );
    if (saved != null && mounted) Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final query = _text;
    final result = _result;
    final matches = result?.matches ?? const <LookupMatch>[];

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: widget.pick ? 'Look up again' : 'New entry',
              onBack: () => Navigator.pop(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Title',
                    style: theme.textTheme.labelSmall!.copyWith(
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SearchField(
                    controller: _query,
                    hintText: 'Title',
                    autofocus: query.isEmpty,
                    textCapitalization: TextCapitalization.words,
                    onChanged: _onQueryChanged,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    PillChip(
                      label: 'All',
                      selected: _type == null,
                      onTap: () => _pickType(null),
                    ),
                    for (final t in MediaType.values) ...[
                      const SizedBox(width: 8),
                      PillChip(
                        label: t.label,
                        selected: _type == t,
                        dotColor: colors.forType(t),
                        onTap: () => _pickType(t),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // A thin line under the chips while a lookup is pending or in
            // flight, so refining a query never blanks the rows.
            SizedBox(
              height: 2,
              child: _loading && query.isNotEmpty
                  ? Semantics(
                      label: 'Looking up',
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: query.isEmpty
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      children: [
                        if (result == null)
                          LookupNotice('Looking up "$query"…', spinner: true)
                        else if (result.notConfigured)
                          LookupNotice(
                            _type == null
                                ? 'Lookups are not set up on this build '
                                      '(no API keys).'
                                : 'Lookups for ${_type!.label.toLowerCase()} '
                                      'are not set up on this build '
                                      '(no API key).',
                          )
                        else if (result.allFailed case final failure?)
                          LookupNotice(
                            failure == LookupFailure.offline
                                ? 'Could not reach the lookup. Check your '
                                      'connection and try again.'
                                : 'The lookup did not answer. Try again in a '
                                      'moment.',
                            onRetry: _lookUp,
                          )
                        else if (matches.isEmpty && result.partlyFailed)
                          LookupNotice(
                            'Some lookups could not be reached, so a match '
                            'may be missing. Try again in a moment.',
                            onRetry: _lookUp,
                          )
                        else if (matches.isEmpty)
                          LookupNotice(
                            _type == null
                                ? 'No matches for "$query".'
                                : 'No matches among ${_type!.label.toLowerCase()}.',
                          )
                        else ...[
                          const SectionHeading(
                            'Is it one of these?',
                            padding: EdgeInsets.fromLTRB(0, 14, 0, 2),
                          ),
                          for (final match in matches)
                            _MatchRow(
                              match: match,
                              opening: _opening == match,
                              onTap: _opening == null
                                  ? () => _open(match: match)
                                  : null,
                            ),
                          if (result.partlyFailed)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                'Some lookups could not be reached.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall!.copyWith(
                                  color: colors.muted,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
            if (!widget.pick)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (matches.isNotEmpty) ...[
                      Text(
                        'Not listed?',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                    ],
                    AppButton(
                      label: 'Fill in the details myself',
                      kind: AppButtonKind.outline,
                      onPressed: _opening == null ? () => _open() : null,
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

/// A centered muted line for the states without rows, with a spinner
/// while looking up, or a "Try again" after a failure.
class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.match,
    required this.onTap,
    this.opening = false,
  });

  final LookupMatch match;
  final VoidCallback? onTap;

  /// The full details are being fetched for this row.
  final bool opening;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final kind = match.type == MediaType.music
        ? (match.album == null ? 'Album' : 'Song')
        : match.type.singular;
    final year = match.released?.year;
    final subtitle = [
      ?match.creator,
      ?match.album,
      if (match.platforms.isNotEmpty) match.platforms.join(', '),
    ].where((s) => s.isNotEmpty).join(' · ');
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            CachedImage(
              url: match.coverUrl,
              width: 44,
              height: match.type == MediaType.music ? 44 : 66,
              borderRadius: BorderRadius.circular(8),
              placeholder: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [kind, if (year != null) '$year'].join(' · ').toUpperCase(),
                    style: theme.textTheme.labelSmall!.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: colors.forType(match.type),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Two lines, so a long title keeps the part that tells
                  // it from the others ("The Last of Us: Left Behind").
                  Text(
                    match.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall!.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (opening)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              )
            else
              StrokeIcon(AppIcons.chevronRight, size: 18, color: colors.muted),
          ],
        ),
      ),
    );
  }
}
