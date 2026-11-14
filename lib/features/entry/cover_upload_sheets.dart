import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/covers/cover_picture.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/row_ink_well.dart';
import '../../widgets/sheet_frame.dart';

/// Where an upload comes from, picked in [showCoverSourceSheet].
enum CoverSourceChoice { photos, files, clipboard }

/// Add / edit entry › Pick a cover: upload from. "Upload a cover" with
/// Photo library, Files, and, only [withPaste] (the clipboard holds an
/// image), Paste image.
Future<CoverSourceChoice?> showCoverSourceSheet(
  BuildContext context, {
  required bool withPaste,
}) => showAppSheet<CoverSourceChoice>(
  context,
  builder: (context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    Widget row(
      CoverSourceChoice choice,
      StrokeIconData icon,
      String name,
      String sub,
    ) => DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: RowInkWell(
        onTap: () => Navigator.pop(context, choice),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.surfaceHigh,
                  ),
                  alignment: Alignment.center,
                  child: StrokeIcon(
                    icon,
                    size: 20,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.labelLarge!.copyWith(
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: theme.textTheme.bodySmall!.copyWith(
                          fontStyle: FontStyle.normal,
                          fontSize: 13.5,
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
      ),
    );

    return SheetFrame(
      title: 'Upload a cover',
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(
            CoverSourceChoice.photos,
            AppIcons.photo,
            'Photo library',
            'Pick from your photos',
          ),
          row(
            CoverSourceChoice.files,
            AppIcons.files,
            'Files',
            'Downloads and other folders',
          ),
          if (withPaste)
            row(
              CoverSourceChoice.clipboard,
              AppIcons.clipboard,
              'Paste image',
              'The image you copied',
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  },
);

/// Add / edit entry › Pick a cover: long-press your cover. The cover, "Your
/// cover", what it is used for, Delete file and Cancel. True for Delete
/// file.
Future<bool?> showCoverFileSheet(
  BuildContext context, {
  required Widget cover,
  required String detail,
}) => showAppSheet<bool>(
  context,
  builder: (context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    return SheetFrame(
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Row(
              children: [
                cover,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your cover',
                        style: theme.textTheme.titleMedium!.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: theme.textTheme.bodySmall!.copyWith(
                          fontStyle: FontStyle.normal,
                          fontSize: 13.5,
                          height: 1.4,
                          color: colors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'Delete file',
            kind: AppButtonKind.neutralDestructive,
            icon: const StrokeIcon(AppIcons.trash, size: 18),
            onPressed: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'Cancel',
            kind: AppButtonKind.outline,
            onPressed: () => Navigator.pop(context, false),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  },
);

/// What to do with your own file when an online cover is picked over it.
enum OwnFileChoice { delete, keep }

/// Add / edit entry › Pick a cover: switching to an online cover. "Delete
/// your file too?" with Delete my file, Keep my file and Cancel (null).
Future<OwnFileChoice?> showDeleteOwnFileDialog(
  BuildContext context, {
  required String title,
  required bool onGitHub,
}) => showAppDialog<OwnFileChoice>(
  context,
  builder: (context) => AppDialog(
    title: 'Delete your file too?',
    body:
        '$title will use the online cover. Your own cover file is still '
        'in your library${onGitHub ? ' on GitHub' : ''}.',
    note:
        'If you keep it, it stays under Your covers and you can switch '
        'back.',
    actionsLayout: DialogActionsLayout.column,
    actions: [
      AppButton(
        label: 'Delete my file',
        kind: AppButtonKind.neutralDestructive,
        onPressed: () => Navigator.pop(context, OwnFileChoice.delete),
      ),
      AppButton(
        label: 'Keep my file',
        kind: AppButtonKind.outline,
        onPressed: () => Navigator.pop(context, OwnFileChoice.keep),
      ),
      AppButton(
        label: 'Cancel',
        kind: AppButtonKind.text,
        onPressed: () => Navigator.pop(context),
      ),
    ],
  ),
);

/// Opens Add / edit entry › Fit your cover on the picked image; gives
/// where the frame was left along the image's long side (0 to 1), or null
/// for Back.
Future<double?> showCoverFitSheet(
  BuildContext context, {
  required Uint8List bytes,
  required int width,
  required int height,
  required bool square,
}) => showAppSheet<double>(
  context,
  maxHeightFactor: 0.94,
  builder: (context) => CoverFitSheet(
    bytes: bytes,
    imageWidth: width,
    imageHeight: height,
    square: square,
  ),
);

/// Add / edit entry › Fit your cover (and Fit your cover: a tall image):
/// only for an image clearly off the cover's shape. Crop only: the largest
/// upright 2:3 frame (1:1 for music) on the image, the rest dimmed,
/// dragged along the image's long side. No zoom and no whole-image option.
class CoverFitSheet extends StatefulWidget {
  const CoverFitSheet({
    super.key,
    required this.bytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.square,
  });

  final Uint8List bytes;
  final int imageWidth;
  final int imageHeight;
  final bool square;

  /// The room the preview has at most, in dp.
  static const maxPreviewHeight = 291.0;

  @override
  State<CoverFitSheet> createState() => _CoverFitSheetState();
}

class _CoverFitSheetState extends State<CoverFitSheet> {
  double _at = 0.5;

  double get _shape => widget.square ? 1.0 : 2 / 3;

  /// Wider than the shape: the frame slides sideways.
  bool get _wide => widget.imageWidth / widget.imageHeight > _shape;

  void _dragTo(Offset position, Size preview, Size frame) {
    final spare = _wide
        ? preview.width - frame.width
        : preview.height - frame.height;
    if (spare <= 0) return;
    final along = _wide
        ? position.dx - frame.width / 2
        : position.dy - frame.height / 2;
    setState(() => _at = (along / spare).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = LibraryColors.of(context);
    final shapeName = widget.square ? '1:1' : '2:3';
    final (savedWidth, savedHeight) = coverFittedSize(
      widget.imageWidth,
      widget.imageHeight,
      square: widget.square,
    );
    final hint = theme.textTheme.bodySmall!.copyWith(
      fontStyle: FontStyle.normal,
      fontSize: 13.5,
      color: colors.muted,
    );
    return SheetFrame(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Fit your cover', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(
            '${widget.imageWidth} × ${widget.imageHeight}. It isn’t '
            '$shapeName, so part of it is cut.',
            style: hint.copyWith(fontSize: 14, height: 1.4),
          ),
        ],
      ),
      scrollable: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 2),
          LayoutBuilder(
            builder: (context, constraints) {
              var scale = constraints.maxWidth / widget.imageWidth;
              final byHeight =
                  CoverFitSheet.maxPreviewHeight / widget.imageHeight;
              if (byHeight < scale) scale = byHeight;
              final preview = Size(
                widget.imageWidth * scale,
                widget.imageHeight * scale,
              );
              final frame = _wide
                  ? Size(preview.height * _shape, preview.height)
                  : Size(preview.width, preview.width / _shape);
              final left = _wide ? (preview.width - frame.width) * _at : 0.0;
              final top = _wide ? 0.0 : (preview.height - frame.height) * _at;
              return Center(
                child: Semantics(
                  label:
                      'The image. Drag ${_wide ? 'sideways' : 'up or down'} '
                      'to choose which part is kept',
                  // A drag along the image's long side only, so that on a
                  // tall image it wins over the sheet's own scroll and
                  // pull, which a pan in any direction would lose to.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _dragTo(d.localPosition, preview, frame),
                    onHorizontalDragStart: !_wide
                        ? null
                        : (d) => _dragTo(d.localPosition, preview, frame),
                    onHorizontalDragUpdate: !_wide
                        ? null
                        : (d) => _dragTo(d.localPosition, preview, frame),
                    onVerticalDragStart: _wide
                        ? null
                        : (d) => _dragTo(d.localPosition, preview, frame),
                    onVerticalDragUpdate: _wide
                        ? null
                        : (d) => _dragTo(d.localPosition, preview, frame),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: preview.width,
                        height: preview.height,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Image.memory(
                                widget.bytes,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                                excludeFromSemantics: true,
                                errorBuilder: (_, _, _) =>
                                    ColoredBox(color: colors.surfaceHigh),
                              ),
                            ),
                            // The part cut away is dimmed on either side.
                            Positioned(
                              left: 0,
                              top: 0,
                              width: _wide ? left : preview.width,
                              height: _wide ? preview.height : top,
                              child: ColoredBox(color: colors.scrim),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              width: _wide
                                  ? preview.width - left - frame.width
                                  : preview.width,
                              height: _wide
                                  ? preview.height
                                  : preview.height - top - frame.height,
                              child: ColoredBox(color: colors.scrim),
                            ),
                            Positioned(
                              left: left,
                              top: top,
                              width: frame.width,
                              height: frame.height,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    width: 2,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            _wide
                ? 'Drag sideways to choose which part is kept.'
                : 'Drag up or down to choose which part is kept.',
            style: hint,
          ),
          const SizedBox(height: 6),
          Text('Saved at $savedWidth × $savedHeight.', style: hint),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Back',
                  kind: AppButtonKind.outline,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  label: 'Use this cover',
                  onPressed: () => Navigator.pop(context, _at),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
