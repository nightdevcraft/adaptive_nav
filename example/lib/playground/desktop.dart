import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'devices.dart';

/// Builds the app for a window whose content area is [size].
typedef ScreenBuilder = Widget Function(Size size);

/// A desktop with one window. Drag the title bar to move it, an edge or a
/// corner to resize it (the opposite edge stays put), and use the green button
/// or a double click on the title bar to zoom it.
class DesktopStage extends StatefulWidget {
  const DesktopStage({super.key, required this.screen});

  final ScreenBuilder screen;

  @override
  State<DesktopStage> createState() => _DesktopStageState();
}

/// Which edges a grab moves. All four is the title bar: a move.
@immutable
class _Edges {
  const _Edges({
    this.left = false,
    this.top = false,
    this.right = false,
    this.bottom = false,
  });

  final bool left;
  final bool top;
  final bool right;
  final bool bottom;

  bool get isMove => left && top && right && bottom;
}

const _Edges _move = _Edges(left: true, top: true, right: true, bottom: true);

class _DesktopStageState extends State<DesktopStage> {
  static const double _titleBar = 30;
  static const Size _min = Size(320, 300);

  /// How far a grab zone reaches either side of an edge.
  static const double _reach = 5;
  static const double _corner = 12;

  Rect? _rect;
  Rect? _beforeZoom;
  Rect? _grabRect;
  Offset? _grabAt;
  bool _resizing = false;
  bool _animate = false;

  static double _clamp(double v, double lo, double hi) =>
      math.max(lo, math.min(v, hi));

  Rect _initial(Size area) {
    final double w = _clamp(
      1100,
      math.min(_min.width, area.width),
      area.width - 80,
    );
    final double h = _clamp(
      740,
      math.min(_min.height, area.height),
      area.height - 64,
    );
    return Rect.fromLTWH(
      (area.width - w) / 2,
      math.max(16, (area.height - h) * 0.35),
      w,
      h,
    );
  }

  /// Keeps the window on the desktop when the browser window shrinks.
  Rect _fit(Rect r, Size area) {
    final double w = math.min(math.max(r.width, _min.width), area.width);
    final double h = math.min(math.max(r.height, _min.height), area.height);
    return Rect.fromLTWH(
      _clamp(r.left, 0, area.width - w),
      _clamp(r.top, 0, area.height - h),
      w,
      h,
    );
  }

  void _start(Offset global) {
    _grabRect = _rect;
    _grabAt = global;
    setState(() {
      _animate = false;
      _resizing = true;
    });
  }

  void _drag(_Edges e, Offset global, Size area) {
    final Rect s = _grabRect!;
    final Offset d = global - _grabAt!;
    if (e.isMove) {
      setState(() {
        _beforeZoom = null;
        _rect = Rect.fromLTWH(
          _clamp(s.left + d.dx, 0, area.width - s.width),
          _clamp(s.top + d.dy, 0, area.height - s.height),
          s.width,
          s.height,
        );
      });
      return;
    }
    double l = s.left, t = s.top, r = s.right, b = s.bottom;
    if (e.left) l = _clamp(s.left + d.dx, 0, s.right - _min.width);
    if (e.right) r = _clamp(s.right + d.dx, s.left + _min.width, area.width);
    if (e.top) t = _clamp(s.top + d.dy, 0, s.bottom - _min.height);
    if (e.bottom) b = _clamp(s.bottom + d.dy, s.top + _min.height, area.height);
    setState(() {
      _beforeZoom = null;
      _rect = Rect.fromLTRB(l, t, r, b);
    });
  }

  void _end() => setState(() => _resizing = false);

  void _zoom(Size area) => setState(() {
    _animate = true;
    if (_beforeZoom != null) {
      _rect = _beforeZoom;
      _beforeZoom = null;
    } else {
      _beforeZoom = _rect;
      _rect = Offset.zero & area;
    }
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final Size area = c.biggest;
        final Rect r = _rect = _fit(_rect ?? _initial(area), area);

        Widget grip(Rect zone, _Edges e, MouseCursor cursor) =>
            Positioned.fromRect(
              rect: zone,
              child: MouseRegion(
                cursor: cursor,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (DragStartDetails d) => _start(d.globalPosition),
                  onPanUpdate: (DragUpdateDetails d) =>
                      _drag(e, d.globalPosition, area),
                  onPanEnd: (_) => _end(),
                  onPanCancel: _end,
                ),
              ),
            );

        return Stack(
          children: <Widget>[
            const Positioned.fill(child: _Wallpaper()),
            AnimatedPositioned.fromRect(
              rect: r,
              duration: _animate
                  ? const Duration(milliseconds: 260)
                  : Duration.zero,
              curve: Curves.easeOutCubic,
              // Only after a real animation. With `Duration.zero` the
              // callback fires synchronously while this subtree is being laid
              // out, and a `setState` there leaves this element marked dirty
              // with no frame scheduled: the window then stops redrawing
              // until some other event asks for a frame.
              onEnd: () {
                if (_animate) {
                  setState(() => _animate = false);
                }
              },
              child: _Window(
                titleBar: _titleBar,
                zoomed: _beforeZoom != null,
                onZoom: () => _zoom(area),
                onMoveStart: _start,
                onMove: (Offset g) => _drag(_move, g, area),
                onMoveEnd: _end,
                showSize: _resizing,
                screen: widget.screen,
              ),
            ),
            if (!_animate) ...<Widget>[
              // Edges first, corners on top of them.
              grip(
                Rect.fromLTRB(
                  r.left - _reach,
                  r.top + _corner,
                  r.left + _reach,
                  r.bottom - _corner,
                ),
                const _Edges(left: true),
                SystemMouseCursors.resizeLeftRight,
              ),
              grip(
                Rect.fromLTRB(
                  r.right - _reach,
                  r.top + _corner,
                  r.right + _reach,
                  r.bottom - _corner,
                ),
                const _Edges(right: true),
                SystemMouseCursors.resizeLeftRight,
              ),
              grip(
                Rect.fromLTRB(
                  r.left + _corner,
                  r.top - _reach,
                  r.right - _corner,
                  r.top + 3,
                ),
                const _Edges(top: true),
                SystemMouseCursors.resizeUpDown,
              ),
              grip(
                Rect.fromLTRB(
                  r.left + _corner,
                  r.bottom - _reach,
                  r.right - _corner,
                  r.bottom + _reach,
                ),
                const _Edges(bottom: true),
                SystemMouseCursors.resizeUpDown,
              ),
              grip(
                Rect.fromCenter(
                  center: r.topLeft,
                  width: 2 * _corner,
                  height: 2 * _corner,
                ),
                const _Edges(left: true, top: true),
                SystemMouseCursors.resizeUpLeftDownRight,
              ),
              grip(
                Rect.fromCenter(
                  center: r.topRight,
                  width: 2 * _corner,
                  height: 2 * _corner,
                ),
                const _Edges(right: true, top: true),
                SystemMouseCursors.resizeUpRightDownLeft,
              ),
              grip(
                Rect.fromCenter(
                  center: r.bottomLeft,
                  width: 2 * _corner,
                  height: 2 * _corner,
                ),
                const _Edges(left: true, bottom: true),
                SystemMouseCursors.resizeUpRightDownLeft,
              ),
              grip(
                Rect.fromCenter(
                  center: r.bottomRight,
                  width: 2 * _corner,
                  height: 2 * _corner,
                ),
                const _Edges(right: true, bottom: true),
                SystemMouseCursors.resizeUpLeftDownRight,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Wallpaper extends StatelessWidget {
  const _Wallpaper();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFFD7DEF6),
          Color(0xFFE8E1F4),
          Color(0xFFF6E4EA),
        ],
      ),
    ),
  );
}

class _Window extends StatelessWidget {
  const _Window({
    required this.titleBar,
    required this.zoomed,
    required this.onZoom,
    required this.onMoveStart,
    required this.onMove,
    required this.onMoveEnd,
    required this.showSize,
    required this.screen,
  });

  final double titleBar;
  final bool zoomed;
  final VoidCallback onZoom;
  final ValueChanged<Offset> onMoveStart;
  final ValueChanged<Offset> onMove;
  final VoidCallback onMoveEnd;
  final bool showSize;
  final ScreenBuilder screen;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(zoomed ? 0 : 12);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 50,
            offset: Offset(0, 20),
          ),
          BoxShadow(color: Color(0x26000000), blurRadius: 1),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        // The real content size, also mid-zoom, so the app is told the size
        // it actually has.
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            final Size content = Size(c.maxWidth, c.maxHeight - titleBar);
            return Column(
              children: <Widget>[
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: onZoom,
                  onPanStart: (DragStartDetails d) =>
                      onMoveStart(d.globalPosition),
                  onPanUpdate: (DragUpdateDetails d) =>
                      onMove(d.globalPosition),
                  onPanEnd: (_) => onMoveEnd(),
                  child: Container(
                    height: titleBar,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[Color(0xFFF7F7F9), Color(0xFFEDEDF1)],
                      ),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFD9D9DF)),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        const _Light(Color(0xFFFF5F57)),
                        const SizedBox(width: 8),
                        const _Light(Color(0xFFFEBC2E)),
                        const SizedBox(width: 8),
                        _Light(const Color(0xFF28C840), onTap: onZoom),
                        Expanded(
                          child: Text(
                            'adaptive_nav',
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF4A4A52),
                            ),
                          ),
                        ),
                        const SizedBox(width: 52),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(child: screen(content)),
                      if (showSize)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xCC1C1C22),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${content.width.round()} × '
                                  '${content.height.round()}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Light extends StatelessWidget {
  const _Light(this.color, {this.onTap});

  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x1F000000), width: 0.5),
        ),
      ),
    ),
  );
}
