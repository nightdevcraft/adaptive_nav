import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'devices.dart';

/// iPhone Duo between its displays, as the hardware moves: one half swings
/// about the hinge onto the other.
///
/// Drawn the way the device is held upright closed: the half that moves is on
/// the left, hinged at its right edge, and the half that stays is the one the
/// outer display ends up over. [quarterTurns] turns the whole thing for the
/// other way of holding it; the pictures are taken the way the display was
/// held and turned back here.
///
/// Flat open it is exactly the inner device's frame, and shut it is exactly
/// the outer one's — hinge barrel and buttons included — so the live device
/// takes over at either end without anything jumping.
class FoldModel extends StatelessWidget {
  const FoldModel({
    super.key,
    required this.closed,
    this.quarterTurns = 0,
    this.innerShot,
    this.outerShot,
    this.innerDim = 0,
    this.outerDim = 0,
    this.inner = duoInnerLandscape,
    this.outer = duoOuterPortrait,
  });

  /// 0 is flat open, 1 is shut.
  final double closed;
  final int quarterTurns;

  /// Pictures of the displays; `null` draws it off.
  final ui.Image? innerShot;
  final ui.Image? outerShot;

  /// How far each display has gone dark, 0 to 1. A dimming display blurs
  /// with it, as it does on the device.
  final double innerDim;
  final double outerDim;

  /// The open device held with the hinge upright.
  final Pose inner;

  /// The shut device held upright.
  final Pose outer;

  /// How thick a half is, seen on its free edge as it swings.
  static const double _thickness = 7;

  /// A half standing up towards the viewer grows by at most a quarter.
  static const double _perspective = 0.0004;

  @override
  Widget build(BuildContext context) {
    final double t = closed;
    final double angle = math.pi * t;
    final Size innerFrame = inner.frameSize;
    final Size panel = Size.lerp(
      Size(innerFrame.width / 2, innerFrame.height),
      outer.frameSize,
      t,
    )!;
    final int unturn = (4 - quarterTurns) % 4;
    // How edge-on the moving half is to the viewer: its face catches the
    // least light then.
    final double edgeOn = math.sin(angle);

    final Widget innerLeft = _InnerHalf(
      pose: inner,
      hingeOnLeft: false,
      dim: math.max(innerDim, 0.45 * edgeOn),
      content: _Shot(image: innerShot, turns: unturn, half: _Side.left),
    );
    final Widget innerRight = _InnerHalf(
      pose: inner,
      hingeOnLeft: true,
      dim: innerDim,
      content: _Shot(image: innerShot, turns: unturn, half: _Side.right),
    );
    // Past a quarter turn the back shows, and the rotation mirrors it. Mirror
    // it once more so the outer display reads the right way round; it is
    // drawn as it is seen in the end, hinge on the left.
    final Widget outerFace = Transform.flip(
      flipX: true,
      child: _OuterFace(
        pose: outer,
        dim: math.max(outerDim, 0.45 * edgeOn),
        content: _Shot(image: outerShot, turns: unturn),
      ),
    );

    final Widget lid = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fill(child: angle <= math.pi / 2 ? innerLeft : outerFace),
        // The free edge, standing back from the display by the half's
        // thickness. Flat it is edge-on and unseen; it shows as the half
        // swings up.
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: _thickness,
          child: Transform(
            alignment: Alignment.centerLeft,
            transform: Matrix4.identity()..rotateY(-math.pi / 2),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(3)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0xFF4A4A50),
                    Color(0xFF26262A),
                    Color(0xFF3A3A3F),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final Widget model = SizedBox(
      width: panel.width * 2,
      height: panel.height,
      child: Transform.translate(
        // Keep what will be left of the device centred: the open device is
        // centred on its hinge, the shut one on the half that stays.
        offset: Offset(-panel.width / 2 * t, 0),
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            // One shadow for the device as seen: the half that stays, plus
            // as much of the moving half as still reaches out past the hinge.
            Positioned(
              left: panel.width * (1 - math.max(0.0, math.cos(angle))),
              top: 0,
              right: 0,
              height: panel.height,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(36)),
                  boxShadow: <BoxShadow>[
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
              ),
            ),
            Positioned(
              left: panel.width,
              top: 0,
              width: panel.width,
              height: panel.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  // The buttons are on this half. Open they are where the
                  // inner device has them; shut, where the outer one does —
                  // they stand proud of the closed half, so they stay seen.
                  ..._buttons(t),
                  Positioned.fill(child: innerRight),
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              width: panel.width,
              height: panel.height,
              child: Transform(
                alignment: Alignment.centerRight,
                // Negative: the moving half comes towards the viewer and
                // closes over the other, so the outer display ends up on top.
                // The perspective is mild, as a camera a phone's length away
                // sees it: stronger, and the near edge balloons out of the
                // frame as the half stands up.
                transform: Matrix4.identity()
                  ..setEntry(3, 2, _perspective)
                  ..rotateY(-angle),
                child: lid,
              ),
            ),
          ],
        ),
      ),
    );
    return RotatedBox(quarterTurns: quarterTurns, child: model);
  }

  /// The buttons of the half that stays, in its own coordinates.
  List<Widget> _buttons(double t) {
    final double half = inner.frameSize.width / 2;
    double lerp(double a, double b) => a + (b - a) * t;
    final List<Bump> open = <Bump>[
      for (final Bump b in inner.buttons)
        if (b.edge == AxisDirection.up)
          Bump(b.edge, b.offset - half, b.length)
        else
          b,
    ];
    final List<Bump> shut = outer.buttons;
    const double depth = 4;
    const Decoration look = BoxDecoration(
      color: Color(0xFF3A3A3F),
      borderRadius: BorderRadius.all(Radius.circular(2)),
    );
    return <Widget>[
      for (int i = 0; i < open.length && i < shut.length; i++)
        if (open[i].edge == AxisDirection.up)
          Positioned(
            left: lerp(open[i].offset, shut[i].offset),
            top: -depth + 1,
            width: open[i].length,
            height: depth,
            child: const DecoratedBox(decoration: look),
          )
        else
          Positioned(
            right: -depth + 1,
            top: lerp(open[i].offset, shut[i].offset),
            width: depth,
            height: open[i].length,
            child: const DecoratedBox(decoration: look),
          ),
    ];
  }
}

enum _Side { left, right }

/// A picture of a display, or one half of it, stretched over a face.
class _Shot extends StatelessWidget {
  const _Shot({required this.image, required this.turns, this.half});

  final ui.Image? image;
  final int turns;

  /// `null` for the whole picture.
  final _Side? half;

  @override
  Widget build(BuildContext context) {
    final ui.Image? img = image;
    if (img == null) {
      return const ColoredBox(color: Colors.black);
    }
    final Widget picture = RotatedBox(
      quarterTurns: turns,
      child: RawImage(image: img, fit: BoxFit.fill),
    );
    final _Side? side = half;
    if (side == null) {
      return picture;
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) => ClipRect(
        child: OverflowBox(
          alignment: side == _Side.left
              ? Alignment.centerLeft
              : Alignment.centerRight,
          minWidth: c.maxWidth * 2,
          maxWidth: c.maxWidth * 2,
          minHeight: c.maxHeight,
          maxHeight: c.maxHeight,
          child: picture,
        ),
      ),
    );
  }
}

/// A display going dark: blurred and dimmed together.
class _Dimmed extends StatelessWidget {
  const _Dimmed({required this.dim, required this.child});

  final double dim;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double d = math.min(1.0, math.max(0.0, dim));
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: ImageFiltered(
            enabled: d > 0,
            imageFilter: ui.ImageFilter.blur(sigmaX: 12 * d, sigmaY: 12 * d),
            child: child,
          ),
        ),
        if (d > 0)
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: d)),
          ),
      ],
    );
  }
}

const BoxDecoration _metal = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: kFrameMetal,
  ),
);

/// Half of the inner device: its frame on three sides and none at the hinge,
/// where the display carries on into the other half.
class _InnerHalf extends StatelessWidget {
  const _InnerHalf({
    required this.pose,
    required this.hingeOnLeft,
    required this.dim,
    required this.content,
  });

  final Pose pose;
  final bool hingeOnLeft;
  final double dim;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    final double b = pose.bezel.top;
    final Radius corner = pose.radius.topLeft;
    final Radius outside = Radius.circular(corner.x + b);
    // Square at the hinge, both display and frame, as the live frame is.
    final BorderRadius display = hingeOnLeft
        ? BorderRadius.only(topRight: corner, bottomRight: corner)
        : BorderRadius.only(topLeft: corner, bottomLeft: corner);
    final BorderRadius frame = hingeOnLeft
        ? BorderRadius.only(topRight: outside, bottomRight: outside)
        : BorderRadius.only(topLeft: outside, bottomLeft: outside);
    final EdgeInsets bezel = hingeOnLeft
        ? EdgeInsets.fromLTRB(0, b, b, b)
        : EdgeInsets.fromLTRB(b, b, 0, b);
    return _Body(
      frame: frame,
      bezel: bezel,
      display: display,
      dim: dim,
      content: content,
    );
  }
}

/// The outer device as the live frame draws it, hinge barrel and all.
class _OuterFace extends StatelessWidget {
  const _OuterFace({
    required this.pose,
    required this.dim,
    required this.content,
  });

  final Pose pose;
  final double dim;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return _Body(
      frame: growRadius(pose.radius, pose.bezel),
      bezel: pose.bezel,
      display: pose.radius,
      dim: dim,
      content: content,
      barrel: pose.bezel.left - 3,
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.frame,
    required this.bezel,
    required this.display,
    required this.dim,
    required this.content,
    this.barrel = 0,
  });

  final BorderRadius frame;
  final EdgeInsets bezel;
  final BorderRadius display;
  final double dim;
  final Widget content;

  /// Width of a hinge barrel down the left edge, or 0.
  final double barrel;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: ClipRRect(
            borderRadius: frame,
            child: Stack(
              children: <Widget>[
                const Positioned.fill(child: DecoratedBox(decoration: _metal)),
                if (barrel > 0)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: barrel,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            Color(0xFF17171A),
                            Color(0xFF4A4A50),
                            Color(0xFF2A2A2E),
                            Color(0xFF1E1E21),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: frame,
              border: Border.all(color: kFrameRim),
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: bezel,
            child: ClipRRect(
              borderRadius: display,
              child: _Dimmed(dim: dim, child: content),
            ),
          ),
        ),
      ],
    );
  }
}
