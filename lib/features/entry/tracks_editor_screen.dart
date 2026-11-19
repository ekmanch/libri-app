import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_providers.dart';
import '../../data/models/entry.dart';
import '../../data/models/track.dart';
import '../../data/operations/operations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/page_header.dart';
import '../../widgets/section_heading.dart';
import 'track_paste.dart';

/// Opens Music › Edit tracks on [album], an album without an online match.
Future<void> openTracksEditor(BuildContext context, Entry album) {
  return Navigator.of(context)
      .push<void>(MaterialPageRoute(builder: (_) => TracksEditorScreen(album)));
}

/// A length as it is typed on the number pad, the colons put in: 431 is
/// "4:31", 10203 is "1:02:03". At most five digits.
String trackLengthFromDigits(String typed) {
  final all = typed.replaceAll(RegExp(r'\D'), '');
  final d = all.length > 5 ? all.substring(0, 5) : all;
  if (d.length <= 2) return d;
  final seconds = d.substring(d.length - 2);
  if (d.length <= 4) return '${d.substring(0, d.length - 2)}:$seconds';
  return '${d.substring(0, d.length - 4)}:'
      '${d.substring(d.length - 4, d.length - 2)}:$seconds';
}

class _LengthFormatter extends TextInputFormatter {
  const _LengthFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = trackLengthFromDigits(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// One row: what is typed, and what the track carries unseen, so its rating
/// follows it through a rename and a move.
class _Row {
  _Row({String title = '', String length = '', this.id, this.rating})
    : title = TextEditingController(text: title),
      length = TextEditingController(text: length);

  final key = UniqueKey();
  final TextEditingController title;
  final TextEditingController length;
  final focus = FocusNode();
  final String? id;
  final int? rating;

  void dispose() {
    title.dispose();
    length.dispose();
    focus.dispose();
  }
}

/// Music › Edit tracks: an album's own track list, made by hand. Only an
/// album without an online match has one. A row per track (the handle to
/// drag it by, its number, a title, a length, a button to remove it), "+ Add
/// track", and Paste a list, where every line becomes a track
/// ([parseTrackList]). Save stores the rows that have a title, none when
/// there are none; Back with changes asks before dropping them (Music › Edit
/// tracks: discard changes?).
class TracksEditorScreen extends ConsumerStatefulWidget {
  const TracksEditorScreen(this.album, {super.key});

  final Entry album;

  @override
  ConsumerState<TracksEditorScreen> createState() => _TracksEditorScreenState();
}

class _TracksEditorScreenState extends ConsumerState<TracksEditorScreen> {
  late final List<_Row> _rows = [
    for (final track in widget.album.tracks ?? const <Track>[])
      _Row(
        title: track.title,
        length: track.length ?? '',
        id: track.id,
        rating: track.rating,
      ),
  ];
  final _paste = TextEditingController();
  bool _dirty = false;

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    _paste.dispose();
    super.dispose();
  }

  void _changed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// What Save stores: the rows with a title, in order, numbered from 1.
  List<Track> get _tracks {
    final titled = [
      for (final row in _rows)
        if (row.title.text.trim().isNotEmpty) row,
    ];
    return [
      for (final (i, row) in titled.indexed)
        Track(
          n: i + 1,
          title: row.title.text.trim(),
          length: row.length.text.trim().isEmpty
              ? null
              : row.length.text.trim(),
          id: row.id,
          rating: row.rating,
        ),
    ];
  }

  void _add() {
    final row = _Row();
    setState(() {
      _rows.add(row);
      _dirty = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) row.focus.requestFocus();
    });
  }

  /// Done on the keyboard: on to the next row, a new one after the last.
  void _next(int index) {
    if (index + 1 < _rows.length) {
      _rows[index + 1].focus.requestFocus();
    } else {
      _add();
    }
  }

  void _remove(int index) {
    setState(() {
      _rows.removeAt(index).dispose();
      _dirty = true;
    });
  }

  void _addPasted() {
    final pasted = parseTrackList(_paste.text);
    if (pasted.isEmpty) return;
    setState(() {
      // Rows left empty make way for the list.
      _rows.removeWhere((row) {
        final empty =
            row.title.text.trim().isEmpty && row.length.text.trim().isEmpty;
        if (empty) row.dispose();
        return empty;
      });
      for (final track in pasted) {
        _rows.add(_Row(title: track.title, length: track.length));
      }
      _paste.clear();
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final tracks = _tracks;
    final navigator = Navigator.of(context);
    if (!_sameTracks(tracks, widget.album.tracks ?? const [])) {
      await ref
          .read(libraryRepositoryProvider)
          .apply(SetTracks(widget.album.id, tracks));
    }
    if (mounted) navigator.pop();
  }

  static bool _sameTracks(List<Track> a, List<Track> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _back() async {
    final navigator = Navigator.of(context);
    if (!_dirty) return navigator.pop();
    final discard = await showAppDialog<bool>(
      context,
      builder: (context) => AppDialog(
        title: 'Discard your changes?',
        body: 'The track list goes back to how it was.',
        actions: [
          AppButton(
            label: 'Keep editing',
            kind: AppButtonKind.outline,
            onPressed: () => Navigator.pop(context, false),
          ),
          AppButton(
            label: 'Discard',
            kind: AppButtonKind.destructive,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (discard == true && mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final album = widget.album;
    final muted = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14.5,
      height: 1.45,
      color: colors.muted,
    );
    final link = TextButton.styleFrom(
      foregroundColor: AccentColors.of(context).link,
      textStyle: theme.textTheme.labelMedium,
      padding: EdgeInsets.zero,
      minimumSize: const Size(48, 48),
      alignment: Alignment.centerLeft,
    );
    final pasted = parseTrackList(_paste.text).length;
    final artist = album.creator;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Tracks',
                onBack: _back,
                actions: [
                  AppButton(label: 'Save', compact: true, onPressed: _save),
                ],
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  buildDefaultDragHandles: false,
                  itemCount: _rows.length,
                  onReorderItem: (from, to) => setState(() {
                    final row = _rows.removeAt(from);
                    _rows.insert(to, row);
                    _dirty = true;
                  }),
                  header: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '${album.title}${artist == null ? '' : ' · $artist'}. '
                      'This album has no online match, so the list is yours '
                      'to keep.',
                      style: muted,
                    ),
                  ),
                  itemBuilder: (context, index) {
                    final row = _rows[index];
                    final number = index + 1;
                    return Padding(
                      key: row.key,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          // The drag starts on touch, without a long press.
                          ReorderableDragStartListener(
                            index: index,
                            child: Semantics(
                              label: 'Drag track $number to reorder',
                              child: Container(
                                width: 32,
                                height: 48,
                                alignment: Alignment.centerLeft,
                                color: Colors.transparent,
                                child: StrokeIcon(
                                  AppIcons.grip,
                                  size: 20,
                                  color: colors.placeholder,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 20,
                            child: Text(
                              '$number',
                              textAlign: TextAlign.right,
                              style: muted.copyWith(fontSize: 13.5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: AppTextField(
                              controller: row.title,
                              focusNode: row.focus,
                              hintText: 'Title',
                              compact: true,
                              semanticsLabel: 'Track $number title',
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => _changed(),
                              onSubmitted: (_) => _next(index),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            // Room for "1:02:03" at any text size.
                            width: MediaQuery.textScalerOf(context)
                                .scale(68)
                                .clamp(68, 100),
                            child: AppTextField(
                              controller: row.length,
                              hintText: '0:00',
                              compact: true,
                              semanticsLabel: 'Track $number length',
                              textAlign: TextAlign.right,
                              fontFamily: AppFonts.code,
                              keyboardType: TextInputType.number,
                              inputFormatters: const [_LengthFormatter()],
                              onChanged: (_) => _changed(),
                              onSubmitted: (_) => _next(index),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove track $number',
                            onPressed: () => _remove(index),
                            constraints: const BoxConstraints.tightFor(
                              width: 48,
                              height: 48,
                            ),
                            icon: StrokeIcon(
                              AppIcons.close,
                              size: 18,
                              color: colors.muted,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  footer: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'No tracks yet. Add them one by one, or paste a '
                            'whole list below.',
                            style: muted,
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _add,
                          style: link,
                          child: const Text('+ Add track'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: 16),
                        child: Divider(height: 1, color: colors.divider),
                      ),
                      const SectionHeading(
                        'Paste a list',
                        padding: EdgeInsets.only(bottom: 8),
                      ),
                      AppTextField(
                        controller: _paste,
                        maxLines: 4,
                        semanticsLabel: 'Paste a track list',
                        textCapitalization: TextCapitalization.none,
                        hintText:
                            'One track per line, e.g. from Wikipedia or '
                            'Discogs:\n1. Hometown Glory 4:31\n'
                            '2. I’ll Be Waiting 4:07',
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Numbers in front and lengths at the end are picked '
                        'up. Pasted tracks are added after the ones above.',
                        style: muted.copyWith(fontSize: 13.5),
                      ),
                      const SizedBox(height: 12),
                      AppButton(
                        label: switch (pasted) {
                          0 => 'Add from paste',
                          1 => 'Add 1 track',
                          _ => 'Add $pasted tracks',
                        },
                        kind: AppButtonKind.outline,
                        onPressed: pasted == 0 ? null : _addPasted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
