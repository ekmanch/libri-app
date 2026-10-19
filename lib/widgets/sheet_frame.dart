import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// The inside of a bottom sheet: grabber, optional title row, content.
/// Side padding is 20 px like the screens. The sheet itself comes from
/// [showAppSheet], which applies the theme's shape and scrim.
///
/// The whole sheet pulls down to close, not just the grabber. A
/// scrollable body takes the pull once it is scrolled to the top, so a
/// finger on the content moves the sheet the way it would on the grabber.
class SheetFrame extends StatefulWidget {
  const SheetFrame({
    super.key,
    this.title,
    this.action,
    this.header,
    required this.child,
    this.footer,
    this.scrollable = false,
  });

  final String? title;

  /// Trailing widget on the title row, e.g. a "Reset" text button.
  final Widget? action;

  /// A custom header instead of [title] and [action], pinned above the
  /// content like they are: the tag picker's title row and search field.
  final Widget? header;
  final Widget child;

  /// Pinned under the content, e.g. the "Show N entries" button.
  final Widget? footer;

  /// True when the content may be taller than the screen.
  final bool scrollable;

  @override
  State<SheetFrame> createState() => _SheetFrameState();
}

class _SheetFrameState extends State<SheetFrame> {
  final _frameKey = GlobalKey();
  final _scroll = ScrollController();

  /// The finger being followed.
  int? _pointer;
  VelocityTracker? _tracker;

  /// True once the body itself has taken the finger's drag. A scroller
  /// inside it that takes the drag instead (a wheel in A25, a row that
  /// scrolls sideways) never moves the sheet.
  bool _bodyDragging = false;

  /// True while the finger moves the sheet instead of the body.
  bool _pulling = false;

  /// True from the first pull until the next touch: the body neither
  /// scrolls nor flings, so it does not move under the sheet.
  bool _sheetMoved = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  AnimationController? get _sheet =>
      context.getInheritedWidgetOfExactType<_SheetDrag>()?.controller;

  bool get _atTop =>
      !_scroll.hasClients ||
      _scroll.position.pixels <= _scroll.position.minScrollExtent;

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _tracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    _bodyDragging = false;
    _pulling = false;
    _sheetMoved = false;
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _tracker!.addPosition(event.timeStamp, event.position);
    final sheet = _sheet;
    if (sheet == null || !_bodyDragging) return;
    final dy = event.delta.dy;
    if (!_pulling) {
      // Closing already.
      if (sheet.status == AnimationStatus.reverse) return;
      // Down past the top of the body: from here the sheet follows.
      if (!_atTop || dy <= 0) return;
      _pulling = true;
      _sheetMoved = true;
      // Running in reverse, the sheet takes its linear reverse curve
      // ([_sheetMotion]) and keeps it until it is open or gone, so it
      // follows the finger 1:1 and a flick closes it at an even pace. On
      // the opening curve it lagged far behind the finger, and closing
      // started slowly.
      sheet
        ..reverse()
        ..stop();
    }
    final height = _frameKey.currentContext?.size?.height ?? 0;
    if (height > 0) sheet.value -= dy / height;
  }

  void _up(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    final velocity = _tracker!.getVelocity().pixelsPerSecond.dy;
    _tracker = null;
    final sheet = _sheet;
    if (!_pulling || sheet == null) return;
    _pulling = false;
    // The same rule as the grabber: a fling down or a sheet more than
    // half gone closes it, otherwise it springs back.
    final route = ModalRoute.of(context);
    final close = velocity > 700 || (velocity > -700 && sheet.value < 0.5);
    if (close && (route?.isCurrent ?? false)) {
      Navigator.pop(context);
    } else {
      sheet.forward();
    }
  }

  bool _scrolled(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.depth == 0 &&
        notification.dragDetails != null &&
        _pointer != null) {
      _bodyDragging = true;
    }
    return false;
  }

  /// No stretch or glow at the top while the pull moves the sheet.
  bool _overscrolled(OverscrollIndicatorNotification notification) {
    if (notification.depth == 0 &&
        notification.leading &&
        _bodyDragging &&
        _sheet != null) {
      notification.disallowIndicator();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grabber = Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: theme.colorScheme.outline,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
    final title = widget.title;
    final header = widget.header != null
        ? Padding(padding: const EdgeInsets.only(top: 8), child: widget.header)
        : title == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.headlineSmall),
                ),
                ?widget.action,
              ],
            ),
          );
    // The keyboard (a sheet with a text field: the plan note, the tag
    // picker's search, the typed year in A26) pushes the sheet up and
    // shrinks a scrollable body, so the field stays in view.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    const sides = EdgeInsets.symmetric(horizontal: 20);
    return Padding(
      key: _frameKey,
      padding: EdgeInsets.fromLTRB(0, 10, 0, 20 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          grabber,
          if (header != null) Padding(padding: sides, child: header),
          const SizedBox(height: 12),
          // The scroll view spans the sheet's full width with the side
          // margin inside it, so it clips at the sheet's edges, not at the
          // margin: a chip's outline or a row that bleeds (the decade row
          // in A2) is not cut off.
          if (widget.scrollable)
            Flexible(
              child: Listener(
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _up,
                child: NotificationListener<OverscrollIndicatorNotification>(
                  onNotification: _overscrolled,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _scrolled,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      physics: _PullPhysics(frozen: () => _sheetMoved),
                      padding: sides,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            )
          else
            Padding(padding: sides, child: widget.child),
          if (widget.footer != null) ...[
            const SizedBox(height: 12),
            Padding(padding: sides, child: widget.footer),
          ],
        ],
      ),
    );
  }
}

/// Keeps a scrollable body still while [SheetFrame] moves the sheet.
class _PullPhysics extends ScrollPhysics {
  const _PullPhysics({required this.frozen, super.parent});

  final bool Function() frozen;

  @override
  _PullPhysics applyTo(ScrollPhysics? ancestor) =>
      _PullPhysics(frozen: frozen, parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      frozen() ? 0 : super.applyPhysicsToUserOffset(position, offset);

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => super.createBallisticSimulation(position, frozen() ? 0 : velocity);
}

/// Hands the sheet's animation controller from [showAppSheet] down to
/// [SheetFrame], which moves the sheet with it.
class _SheetDrag extends InheritedWidget {
  const _SheetDrag({required this.controller, required super.child});

  final AnimationController controller;

  @override
  bool updateShouldNotify(_SheetDrag oldWidget) =>
      controller != oldWidget.controller;
}

/// Material's decelerating curve to open, a linear one to close: a sheet
/// pulled down follows the finger and leaves at once (see
/// [_SheetFrameState._move]).
const _sheetMotion = AnimationStyle(reverseCurve: Curves.linear);

/// Opens a modal bottom sheet styled by the theme, on the root navigator so
/// it covers the floating navigation. With [inheritTheme] the sheet keeps
/// the opener's theme, e.g. the seasonal accent inside a plan (S7, D2).
///
/// A sheet never takes the whole screen: at most [maxHeightFactor] of it,
/// so the screen it came from stays in view above it (A22, D14).
///
/// A text field behind the sheet gives up its focus first. Otherwise the
/// field takes it back when the sheet closes and the keyboard pops up
/// again, after every rating, tag or date picked on the entry form.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool inheritTheme = false,
  double maxHeightFactor = 0.88,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  final theme = Theme.of(context);
  // The sheet's own controller, so the body can move the sheet too. It is
  // disposed once the sheet has finished sliding out.
  final controller = BottomSheet.createAnimationController(
    Navigator.of(context, rootNavigator: true),
  );
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    transitionAnimationController: controller,
    sheetAnimationStyle: _sheetMotion,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
    ),
    builder: (context) {
      final child = _SheetDrag(
        controller: controller,
        child: SafeArea(top: false, child: builder(context)),
      );
      return inheritTheme ? Theme(data: theme, child: child) : child;
    },
  ).whenComplete(() {
    void disposeWhenGone(AnimationStatus status) {
      if (status != AnimationStatus.dismissed) return;
      controller.removeStatusListener(disposeWhenGone);
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }

    if (controller.isDismissed) {
      disposeWhenGone(AnimationStatus.dismissed);
    } else {
      controller.addStatusListener(disposeWhenGone);
    }
  });
}
