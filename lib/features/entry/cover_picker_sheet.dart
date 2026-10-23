import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/lookup/lookup_failure.dart';
import '../../data/lookup/lookup_match.dart';
import '../../data/lookup/lookup_providers.dart';
import '../../data/lookup/lookup_service.dart';
import '../../data/models/entry.dart';
import '../../data/models/entry_status.dart';
import '../../data/models/media_type.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/cover_choice.dart';
import '../../widgets/cover_placeholder.dart';
import '../../widgets/labels.dart';
import '../../widgets/lookup_notice.dart';
import '../../widgets/sheet_frame.dart';

/// A cover picked in [CoverPickerSheet]: the id to store as `cover_from`
/// (null for the match's own cover) and the image to show until the entry
/// is saved.
typedef CoverPick = ({String? coverFrom, String? url});

/// Opens Add / edit entry › Pick a cover for an entry of [type] titled
/// [title]: the match's own cover ([ownCoverUrl]) first, then the covers of
/// the other matches the lookup finds for the title. A tap picks one at
/// once through [onPicked]; Done closes.
Future<void> showCoverPicker(
  BuildContext context, {
  required MediaType type,
  required String title,
  String? creator,
  String? source,
  String? ownCoverUrl,
  int? ownYear,
  required String? coverFrom,
  required ValueChanged<CoverPick> onPicked,
}) => showAppSheet<void>(
  context,
  builder: (context) => CoverPickerSheet(
    type: type,
    title: title,
    creator: creator,
    source: source,
    ownCoverUrl: ownCoverUrl,
    ownYear: ownYear,
    coverFrom: coverFrom,
    onPicked: onPicked,
  ),
);

/// Add / edit entry › Pick a cover: "Pick a cover", "Other matches for
/// “Shōgun”. Only the cover changes.", Done, and the covers three to a row,
/// each with its title, year and edition (no source names). The match's
/// own cover comes first, captioned "The match’s cover"; the picked one is
/// ringed. Only the cover changes: the title, year, description, series and
/// source stay as they are.
class CoverPickerSheet extends ConsumerStatefulWidget {
  const CoverPickerSheet({
    super.key,
    required this.type,
    required this.title,
    this.creator,
    this.source,
    this.ownCoverUrl,
    this.ownYear,
    required this.coverFrom,
    required this.onPicked,
  });

  final MediaType type;
  final String title;
  final String? creator;

  /// The entry's own lookup id; its match is not offered twice.
  final String? source;
  final String? ownCoverUrl;

  /// The entry's year, for the caption of the match's own cover.
  final int? ownYear;
  final String? coverFrom;
  final ValueChanged<CoverPick> onPicked;

  /// "1975 · Hardcover": the edition's year (else the match's) and edition,
  /// the dot kept with the edition so a wrap never leaves it dangling.
  static String caption(LookupMatch match) =>
      captionOf(match.editionYear ?? match.released?.year, match.edition);

  static String captionOf(int? year, String? edition) =>
      [if (year != null) '$year', ?edition].join(' ·\u00a0');

  @override
  ConsumerState<CoverPickerSheet> createState() => _CoverPickerSheetState();
}

class _CoverPickerSheetState extends ConsumerState<CoverPickerSheet> {
  late String? _picked = widget.coverFrom;
  LookupResult? _result;

  @override
  void initState() {
    super.initState();
    _lookUp();
  }

  Future<void> _lookUp() async {
    setState(() => _result = null);
    final result = await ref
        .read(lookupServiceProvider)
        .coverChoices(widget.title, type: widget.type, creator: widget.creator);
    if (mounted) setState(() => _result = result);
  }

  void _pick(String? coverFrom, String? url) {
    setState(() => _picked = coverFrom);
    widget.onPicked((coverFrom: coverFrom, url: url));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final result = _result;
    final choices = [
      for (final match in result?.matches ?? const <LookupMatch>[])
        if (match.source != widget.source &&
            match.cacheCoverUrl != widget.ownCoverUrl)
          match,
    ];
    // A placeholder for a cover not found yet, drawn like the library's.
    final placeholderEntry = Entry(
      id: '',
      type: widget.type,
      title: widget.title,
      status: EntryStatus.want,
      added: DateTime(2000),
    );
    Widget cover(String? url, double width) {
      final w = CoverChoice.imageWidth(width);
      return CachedImage(
        url: url,
        width: w,
        height: w / CoverPlaceholder.aspectRatio(widget.type),
        placeholder: CoverPlaceholder(
          entry: placeholderEntry,
          width: w,
          fontSize: 11,
        ),
        borderRadius: BorderRadius.circular(8),
      );
    }

    return SheetFrame(
      scrollable: true,
      header: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pick a cover', style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  'Other matches for “${widget.title}”. Only the cover '
                  'changes.',
                  style: theme.textTheme.bodySmall!.copyWith(
                    fontStyle: FontStyle.normal,
                    color: colors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: 'Done',
            compact: true,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          CoverChoiceGrid(
            count: 1 + choices.length,
            runSpacing: 16,
            itemBuilder: (i, width) {
              if (i == 0) {
                return CoverChoice(
                  cover: cover(widget.ownCoverUrl, width),
                  title: widget.title,
                  width: width,
                  picked: _picked == null,
                  lines: [
                    if (widget.ownYear case final year?) '$year',
                    'The match’s cover',
                  ],
                  onTap: () => _pick(null, widget.ownCoverUrl),
                );
              }
              final match = choices[i - 1];
              final caption = CoverPickerSheet.caption(match);
              return CoverChoice(
                cover: cover(match.coverUrl ?? match.cacheCoverUrl, width),
                title: match.title,
                width: width,
                picked: _picked == match.coverFrom,
                lines: [if (caption.isNotEmpty) caption],
                onTap: () => _pick(match.coverFrom, match.cacheCoverUrl),
              );
            },
          ),
          if (result == null)
            const LookupNotice('Looking for covers…', spinner: true)
          else if (result.notConfigured)
            LookupNotice(
              'Lookups for ${widget.type.label.toLowerCase()} are not set up '
              'on this build (no API key).',
            )
          else if (result.allFailed case final failure?)
            LookupNotice(
              failure == LookupFailure.offline
                  ? 'Could not reach the lookup. Check your connection and '
                        'try again.'
                  : 'The lookup did not answer. Try again in a moment.',
              onRetry: _lookUp,
            )
          else if (result.partlyFailed)
            LookupNotice(
              'Some lookups could not be reached, so a cover may be '
              'missing. Try again in a moment.',
              onRetry: _lookUp,
            )
          else if (choices.isEmpty)
            const LookupNotice('No other covers for this title.'),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
