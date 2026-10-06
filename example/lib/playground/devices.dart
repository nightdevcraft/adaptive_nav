import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';

enum Device { desktop, phone, tablet, duo, galaxyFold }

/// Where the system draws the Dynamic Island, if anywhere.
enum Island { none, top, right }

/// Where a foldable's hinge runs.
enum Hinge { none, leading, bottom, centreVertical, centreHorizontal }

/// A button standing proud of the frame.
@immutable
class Bump {
  const Bump(this.edge, this.offset, this.length);

  /// [AxisDirection.up] is the top edge, [AxisDirection.left] the left one.
  final AxisDirection edge;

  /// From the start of the edge — its top or its left end — in frame
  /// coordinates.
  final double offset;
  final double length;
}

/// One posture of a device: its window, its safe area and how it looks.
///
/// The window and the insets are what the package sees and are the ones the
/// tests use, measured on simulators. Everything else is drawing.
@immutable
class Pose {
  const Pose({
    required this.size,
    required this.radius,
    this.padding = EdgeInsets.zero,
    this.bezel = const EdgeInsets.all(12),
    this.island = Island.none,
    this.hinge = Hinge.none,
    this.camera = false,
    this.clock = true,
    this.buttons = const <Bump>[],
    this.punch,
    this.reportsFold = false,
  });

  final Size size;
  final EdgeInsets padding;

  /// The display's corners.
  final BorderRadius radius;

  /// The frame around the display; thicker on the side that carries a hinge.
  final EdgeInsets bezel;
  final Island island;
  final Hinge hinge;

  /// The outer camera of iPhone Duo, always visible at the top of the column.
  final bool camera;

  /// Folded and turned, iPhone Duo shows no clock in its column.
  final bool clock;
  final List<Bump> buttons;

  /// The centre of a punch-hole camera, in display coordinates.
  final Offset? punch;

  /// Android hands the app the fold as a display feature; iOS does not yet.
  final bool reportsFold;

  Size get frameSize => bezel.inflateSize(size);
}

const Pose phonePortrait = Pose(
  size: Size(402, 874),
  padding: EdgeInsets.only(top: 62, bottom: 34),
  radius: BorderRadius.all(Radius.circular(55)),
  island: Island.top,
  buttons: <Bump>[
    Bump(AxisDirection.left, 150, 32),
    Bump(AxisDirection.left, 210, 60),
    Bump(AxisDirection.left, 285, 60),
    Bump(AxisDirection.right, 230, 95),
  ],
);

// Turned with the top to the right, the way the island ends up opposite the
// rail. iOS reports the landscape insets symmetrically, which keeps a phone
// out of the rule for a system bar standing on its end.
const Pose phoneLandscape = Pose(
  size: Size(874, 402),
  padding: EdgeInsets.only(left: 62, right: 62, bottom: 21),
  radius: BorderRadius.all(Radius.circular(55)),
  island: Island.right,
  buttons: <Bump>[
    Bump(AxisDirection.up, 716, 32),
    Bump(AxisDirection.up, 628, 60),
    Bump(AxisDirection.up, 553, 60),
    Bump(AxisDirection.down, 573, 95),
  ],
);

const Pose tabletPortrait = Pose(
  size: Size(820, 1180),
  padding: EdgeInsets.only(top: 24, bottom: 20),
  radius: BorderRadius.all(Radius.circular(18)),
  bezel: EdgeInsets.all(18),
  buttons: <Bump>[
    Bump(AxisDirection.up, 720, 56),
    Bump(AxisDirection.right, 90, 50),
    Bump(AxisDirection.right, 150, 50),
  ],
);

const Pose tabletLandscape = Pose(
  size: Size(1180, 820),
  padding: EdgeInsets.only(top: 24, bottom: 20),
  radius: BorderRadius.all(Radius.circular(18)),
  bezel: EdgeInsets.all(18),
  buttons: <Bump>[
    Bump(AxisDirection.left, 80, 56),
    Bump(AxisDirection.up, 1026, 50),
    Bump(AxisDirection.up, 966, 50),
  ],
);

// iPhone Duo folds like a book. Closed and upright, the hinge is the left
// edge and the camera sits at the top of the column on the right; open, the
// same hinge runs down the middle of a display that is wider than it is tall.
// Turning it moves the hinge across, so "upright" closed and "landscape" open
// are one way of holding it.

const double _duoInnerRadius = 34;
const double _duoOuterRadius = 42;
// Square along the hinge: the display runs right up to it, and the barrel is
// a straight edge, not a rounded corner.
const double _duoHingeCorner = 0;

const Pose duoOuterPortrait = Pose(
  size: Size(466, 678),
  padding: EdgeInsets.only(right: 84, bottom: 34),
  radius: BorderRadius.only(
    topLeft: Radius.circular(_duoHingeCorner),
    bottomLeft: Radius.circular(_duoHingeCorner),
    topRight: Radius.circular(_duoOuterRadius),
    bottomRight: Radius.circular(_duoOuterRadius),
  ),
  bezel: EdgeInsets.fromLTRB(15, 9, 9, 9),
  hinge: Hinge.leading,
  camera: true,
  buttons: <Bump>[
    Bump(AxisDirection.up, 220, 48),
    Bump(AxisDirection.up, 280, 48),
    Bump(AxisDirection.right, 190, 70),
  ],
);

// Turned a quarter anticlockwise: the hinge is at the bottom and the camera
// in the top-left corner, still at the top of the system's column.
const Pose duoOuterLandscape = Pose(
  size: Size(678, 466),
  padding: EdgeInsets.only(left: 84, bottom: 34),
  radius: BorderRadius.only(
    topLeft: Radius.circular(_duoOuterRadius),
    topRight: Radius.circular(_duoOuterRadius),
    bottomLeft: Radius.circular(_duoHingeCorner),
    bottomRight: Radius.circular(_duoHingeCorner),
  ),
  bezel: EdgeInsets.fromLTRB(9, 9, 9, 15),
  hinge: Hinge.bottom,
  camera: true,
  clock: false,
  buttons: <Bump>[
    Bump(AxisDirection.left, 222, 48),
    Bump(AxisDirection.left, 162, 48),
    Bump(AxisDirection.up, 190, 70),
  ],
);

const Pose duoInnerLandscape = Pose(
  size: Size(951, 669),
  padding: EdgeInsets.only(right: 84, bottom: 34),
  radius: BorderRadius.all(Radius.circular(_duoInnerRadius)),
  bezel: EdgeInsets.all(9),
  hinge: Hinge.centreVertical,
  buttons: <Bump>[
    Bump(AxisDirection.up, 690, 48),
    Bump(AxisDirection.up, 750, 48),
    Bump(AxisDirection.right, 190, 70),
  ],
);

const Pose duoInnerPortrait = Pose(
  size: Size(669, 951),
  padding: EdgeInsets.only(top: 82, bottom: 34),
  radius: BorderRadius.all(Radius.circular(_duoInnerRadius)),
  bezel: EdgeInsets.all(9),
  hinge: Hinge.centreHorizontal,
  buttons: <Bump>[
    Bump(AxisDirection.left, 231, 48),
    Bump(AxisDirection.left, 171, 48),
    Bump(AxisDirection.up, 190, 70),
  ],
);

// Galaxy Z Fold8 — the wide one: open it is 4:3 and wider than tall, shut its
// cover display is 10:16. Sizes are the panels' pixels (2448 × 1848 and
// 1248 × 1972) over Samsung's default density of 2.625, so they are close to
// what the device reports but not measured on one. Insets are Android's:
// a status bar on top, the gesture handle at the bottom, and in landscape the
// cover's camera cut-out on the side. It folds like iPhone Duo — shut, the
// hinge is the left edge — and its buttons are on the right.

// Square corners, display and frame alike: the Fold8 is a slab, not a
// pebble.
const double _foldInnerRadius = 0;
const double _foldCoverRadius = 0;
const double _foldHingeCorner = 0;

const Pose foldInnerLandscape = Pose(
  size: Size(933, 704),
  padding: EdgeInsets.only(top: 32, bottom: 24),
  radius: BorderRadius.all(Radius.circular(_foldInnerRadius)),
  bezel: EdgeInsets.all(8),
  hinge: Hinge.centreVertical,
  reportsFold: true,
  buttons: <Bump>[
    Bump(AxisDirection.right, 130, 64),
    Bump(AxisDirection.right, 215, 40),
  ],
);

const Pose foldInnerPortrait = Pose(
  size: Size(704, 933),
  padding: EdgeInsets.only(top: 32, bottom: 24),
  radius: BorderRadius.all(Radius.circular(_foldInnerRadius)),
  bezel: EdgeInsets.all(8),
  hinge: Hinge.centreHorizontal,
  reportsFold: true,
  buttons: <Bump>[
    Bump(AxisDirection.up, 130, 64),
    Bump(AxisDirection.up, 215, 40),
  ],
);

const Pose foldCoverPortrait = Pose(
  size: Size(475, 751),
  padding: EdgeInsets.only(top: 32, bottom: 24),
  radius: BorderRadius.only(
    topLeft: Radius.circular(_foldHingeCorner),
    bottomLeft: Radius.circular(_foldHingeCorner),
    topRight: Radius.circular(_foldCoverRadius),
    bottomRight: Radius.circular(_foldCoverRadius),
  ),
  bezel: EdgeInsets.fromLTRB(14, 8, 8, 8),
  hinge: Hinge.leading,
  punch: Offset(237.5, 16),
  buttons: <Bump>[
    Bump(AxisDirection.right, 130, 64),
    Bump(AxisDirection.right, 215, 40),
  ],
);

const Pose foldCoverLandscape = Pose(
  size: Size(751, 475),
  padding: EdgeInsets.only(left: 32, top: 24, bottom: 16),
  radius: BorderRadius.only(
    topLeft: Radius.circular(_foldCoverRadius),
    topRight: Radius.circular(_foldCoverRadius),
    bottomLeft: Radius.circular(_foldHingeCorner),
    bottomRight: Radius.circular(_foldHingeCorner),
  ),
  bezel: EdgeInsets.fromLTRB(8, 8, 8, 14),
  hinge: Hinge.bottom,
  punch: Offset(16, 237.5),
  buttons: <Bump>[
    Bump(AxisDirection.up, 130, 64),
    Bump(AxisDirection.up, 215, 40),
  ],
);

const Color kFrameRim = Color(0xFF5A5A60);
const List<Color> kFrameMetal = <Color>[
  Color(0xFF3C3C41),
  Color(0xFF1C1C1F),
  Color(0xFF2F2F33),
];

/// The frame's corners around a display with [r] corners and a [by] bezel.
///
/// A square display corner — along a hinge — keeps the frame square there too,
/// only eased enough not to cut.
BorderRadius growRadius(BorderRadius r, EdgeInsets by) {
  Radius grow(Radius corner, double a, double b) =>
      Radius.circular(corner.x == 0 ? 2 : corner.x + math.max(a, b));
  return BorderRadius.only(
    topLeft: grow(r.topLeft, by.left, by.top),
    topRight: grow(r.topRight, by.right, by.top),
    bottomLeft: grow(r.bottomLeft, by.left, by.bottom),
    bottomRight: grow(r.bottomRight, by.right, by.bottom),
  );
}

/// A device around [child], which is laid out at the pose's window size.
///
/// [displayKey] goes on a `RepaintBoundary` around the display, so a fold can
/// take a picture of what is on it. [dim] and [blur] are for a display waking
/// up after one.
class DeviceFrame extends StatelessWidget {
  const DeviceFrame({
    super.key,
    required this.pose,
    required this.child,
    this.displayKey,
    this.dim = 0,
    this.blur = 0,
    this.systemUi = true,
    this.overlay,
    this.contentTransform,
  });

  final Pose pose;
  final Widget child;
  final Key? displayKey;
  final double dim;
  final double blur;

  /// Off when [child] is a picture of a display that already has it.
  final bool systemUi;

  /// Drawn over the whole display, status glyphs included.
  final Widget? overlay;

  /// Applied to what is on the display, about its centre, without touching
  /// its layout — for a turn swinging it upright.
  final Matrix4? contentTransform;

  @override
  Widget build(BuildContext context) {
    final Size frame = pose.frameSize;
    final EdgeInsets b = pose.bezel;
    final BorderRadius outer = growRadius(pose.radius, b);
    return SizedBox.fromSize(
      size: frame,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (final Bump bump in pose.buttons) _bump(bump),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: outer,
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x38000000),
                    blurRadius: 48,
                    offset: Offset(0, 22),
                  ),
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              // The hinge is drawn inside the silhouette, so it reads as part
              // of the body rather than a slab bolted on.
              child: ClipRRect(
                borderRadius: outer,
                child: Stack(
                  children: <Widget>[
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: kFrameMetal,
                          ),
                        ),
                      ),
                    ),
                    ..._hinge(frame),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: outer,
                  border: Border.all(color: kFrameRim),
                ),
              ),
            ),
          ),
          Positioned(
            key: const ValueKey<String>('display'),
            left: b.left,
            top: b.top,
            width: pose.size.width,
            height: pose.size.height,
            child: ClipRRect(
              borderRadius: pose.radius,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: ImageFiltered(
                      enabled: blur > 0,
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: blur,
                        sigmaY: blur,
                      ),
                      child: Transform(
                        alignment: Alignment.center,
                        transform: contentTransform ?? Matrix4.identity(),
                        child: RepaintBoundary(
                          key: displayKey,
                          child: Stack(
                            children: <Widget>[
                              Positioned.fill(child: child),
                              if (systemUi)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: SystemUi(pose: pose),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (dim > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: dim),
                        ),
                      ),
                    ),
                  if (overlay case final Widget o)
                    Positioned.fill(child: IgnorePointer(child: o)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bump(Bump bump) {
    const double depth = 4;
    const Decoration look = BoxDecoration(
      color: Color(0xFF3A3A3F),
      borderRadius: BorderRadius.all(Radius.circular(2)),
    );
    return switch (bump.edge) {
      AxisDirection.up => Positioned(
        left: bump.offset,
        top: -depth + 1,
        width: bump.length,
        height: depth,
        child: const DecoratedBox(decoration: look),
      ),
      AxisDirection.down => Positioned(
        left: bump.offset,
        bottom: -depth + 1,
        width: bump.length,
        height: depth,
        child: const DecoratedBox(decoration: look),
      ),
      AxisDirection.left => Positioned(
        left: -depth + 1,
        top: bump.offset,
        width: depth,
        height: bump.length,
        child: const DecoratedBox(decoration: look),
      ),
      AxisDirection.right => Positioned(
        right: -depth + 1,
        top: bump.offset,
        width: depth,
        height: bump.length,
        child: const DecoratedBox(decoration: look),
      ),
    };
  }

  /// The hinge barrel along an edge, or the seam where the two halves meet.
  List<Widget> _hinge(Size frame) {
    const List<Color> barrel = <Color>[
      Color(0xFF17171A),
      Color(0xFF4A4A50),
      Color(0xFF2A2A2E),
      Color(0xFF1E1E21),
    ];
    const Color seam = Color(0xFF161618);
    switch (pose.hinge) {
      case Hinge.none:
        return const <Widget>[];
      case Hinge.leading:
        return <Widget>[
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: pose.bezel.left - 3,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: barrel),
              ),
            ),
          ),
        ];
      case Hinge.bottom:
        return <Widget>[
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: pose.bezel.bottom - 3,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: barrel,
                ),
              ),
            ),
          ),
        ];
      case Hinge.centreVertical:
        return <Widget>[
          Positioned(
            left: frame.width / 2 - 1,
            width: 2,
            top: 0,
            height: pose.bezel.top,
            child: const ColoredBox(color: seam),
          ),
          Positioned(
            left: frame.width / 2 - 1,
            width: 2,
            bottom: 0,
            height: pose.bezel.bottom,
            child: const ColoredBox(color: seam),
          ),
        ];
      case Hinge.centreHorizontal:
        return <Widget>[
          Positioned(
            top: frame.height / 2 - 1,
            height: 2,
            left: 0,
            width: pose.bezel.left,
            child: const ColoredBox(color: seam),
          ),
          Positioned(
            top: frame.height / 2 - 1,
            height: 2,
            right: 0,
            width: pose.bezel.right,
            child: const ColoredBox(color: seam),
          ),
        ];
    }
  }
}

/// Status glyphs, the camera, the Dynamic Island, the home indicator and the
/// crease, drawn over the app where the system would draw them.
class SystemUi extends StatelessWidget {
  const SystemUi({super.key, required this.pose});

  final Pose pose;

  static const Color _ink = Color(0xE6000000);

  /// The column's glyphs are centred this far in from the window edge, not
  /// on the middle of the column — see `SystemBarMetrics.axisFromEdge`.
  static const double _axis = 48;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets p = pose.padding;
    final Size s = pose.size;
    final bool columnLeft =
        p.left >= kVerticalBarInset && p.right < kVerticalBarInset;
    final bool columnRight =
        p.right >= kVerticalBarInset && p.left < kVerticalBarInset;
    return Stack(
      children: <Widget>[
        if (pose.hinge == Hinge.centreVertical)
          Positioned(
            left: s.width / 2 - 8,
            width: 16,
            top: 0,
            bottom: 0,
            child: const _Crease(Axis.vertical),
          ),
        if (pose.hinge == Hinge.centreHorizontal)
          Positioned(
            top: s.height / 2 - 8,
            height: 16,
            left: 0,
            right: 0,
            child: const _Crease(Axis.horizontal),
          ),
        if (columnLeft || columnRight)
          Positioned(
            left: (columnLeft ? _axis : s.width - _axis) - 30,
            width: 60,
            top: 0,
            child: _column(),
          )
        else if (p.top >= 20)
          Positioned(left: 0, right: 0, top: 0, height: p.top, child: _bar()),
        if (pose.punch case final Offset c)
          Positioned(
            left: c.dx - 6,
            top: c.dy - 6,
            width: 12,
            height: 12,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
            ),
          ),
        if (pose.island == Island.top)
          Positioned(
            top: 11,
            left: s.width / 2 - 63,
            width: 126,
            height: 37,
            child: const _Dot(),
          ),
        if (pose.island == Island.right)
          Positioned(
            right: 11,
            top: s.height / 2 - 63,
            width: 37,
            height: 126,
            child: const _Dot(),
          ),
        if (p.bottom >= 20)
          Positioned(
            left: columnLeft ? p.left : 0,
            right: columnRight ? p.right : 0,
            bottom: 8,
            child: Center(
              child: Container(
                width: s.shortestSide > 600 ? 200 : 140,
                height: 5,
                decoration: BoxDecoration(
                  color: _ink,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _bar() {
    final bool small = pose.padding.top < 40;
    final TextStyle time = TextStyle(
      color: _ink,
      fontSize: small ? 12 : 15,
      fontWeight: FontWeight.w600,
    );
    final double icon = small ? 13 : 16;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: pose.island == Island.top ? 36 : 22,
      ),
      child: Row(
        children: <Widget>[
          Text('9:41', style: time),
          const Spacer(),
          Icon(Icons.signal_cellular_alt, size: icon, color: _ink),
          const SizedBox(width: 4),
          Icon(Icons.wifi, size: icon, color: _ink),
          const SizedBox(width: 4),
          Icon(Icons.battery_full, size: icon, color: _ink),
        ],
      ),
    );
  }

  /// iPhone Duo's status bar standing on its end, as the simulator draws it:
  /// the camera at the top, the clock under it and the connection inside the
  /// battery ring, all on one axis.
  Widget _column() => Column(
    children: <Widget>[
      SizedBox(height: pose.camera ? 29 : 30),
      if (pose.camera) const _Camera(),
      if (pose.clock) ...<Widget>[
        SizedBox(height: pose.camera ? 17 : 0),
        const Text(
          '9:41',
          style: TextStyle(
            color: _ink,
            fontSize: 16,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 8),
        const _RingWifi(),
      ],
    ],
  );
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black,
      borderRadius: BorderRadius.all(Radius.circular(24)),
    ),
  );
}

class _Camera extends StatelessWidget {
  const _Camera();

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: const BoxDecoration(
      color: Colors.black,
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Container(
      width: 13,
      height: 13,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: Alignment(-0.3, -0.3),
          colors: <Color>[Color(0xFF2A3350), Color(0xFF07080C)],
        ),
      ),
    ),
  );
}

/// Wi-Fi inside the battery ring, which is open at the bottom where the
/// signal dots sit.
class _RingWifi extends StatelessWidget {
  const _RingWifi();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 40,
    height: 44,
    child: CustomPaint(
      painter: _RingPainter(),
      child: Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Center(child: Icon(Icons.wifi, size: 20, color: SystemUi._ink)),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter();

  static const double _gap = 1.9; // radians left open at the bottom

  @override
  void paint(Canvas canvas, Size size) {
    const double stroke = 3;
    const double r = 19 - stroke / 2;
    final Offset c = Offset(size.width / 2, 19);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      math.pi / 2 + _gap / 2,
      2 * math.pi - _gap,
      false,
      Paint()
        ..color = SystemUi._ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    final Paint dot = Paint()..color = const Color(0x66000000);
    for (int i = 0; i < 4; i++) {
      canvas.drawCircle(Offset(c.dx - 7.5 + 5 * i, c.dy + r + 3), 1.5, dot);
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => false;
}

class _Crease extends StatelessWidget {
  const _Crease(this.axis);

  final Axis axis;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: axis == Axis.vertical
            ? Alignment.centerLeft
            : Alignment.topCenter,
        end: axis == Axis.vertical
            ? Alignment.centerRight
            : Alignment.bottomCenter,
        colors: const <Color>[
          Color(0x00000000),
          Color(0x09000000),
          Color(0x00000000),
        ],
      ),
    ),
  );
}
