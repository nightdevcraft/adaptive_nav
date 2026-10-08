import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

import 'main.dart' show ExampleApp;
import 'playground/desktop.dart';
import 'playground/devices.dart';
import 'playground/fold_model.dart';
import 'playground/header.dart';
import 'playground/open_url.dart'
    if (dart.library.js_interop) 'playground/open_url_web.dart';

/// The example app in a choice of devices, built for the web.
///
/// There is one [ExampleApp] for the life of the page. Switching devices,
/// rotating, folding and resizing only change its `MediaQuery`, just like a
/// real rotation does, so open screens keep their state.
///
/// ```sh
/// flutter run -d chrome -t lib/playground.dart
/// ```
void main() => runApp(const Playground());

class Playground extends StatefulWidget {
  const Playground({super.key});

  @override
  State<Playground> createState() => _PlaygroundState();
}

const Color _kStage = Color(0xFFF2F2F7);

/// Where a fold is. The app takes its new size the moment one starts and
/// stays live underneath; what moves on top is a model carrying a picture of
/// the display that was on.
enum _Fold { idle, moving }

/// The share of a fold the hardware spends moving; the rest is the other
/// display waking up — dark, then grey and out of focus, then sharp — as it
/// does on the simulator.
const double _kMoving = 0.62;

class _PlaygroundState extends State<Playground> with TickerProviderStateMixin {
  /// Keeps the one [ExampleApp] alive as it moves between frames.
  final GlobalKey _appKey = GlobalKey(debugLabel: 'example app');

  /// One instance, so a rebuild here — every frame of a fold — does not
  /// rebuild the app: an identical widget is skipped.
  late final Widget _app = ExampleApp(key: _appKey);

  @override
  void initState() {
    super.initState();
    // The first picture and the first blur cost a shader compile on the web.
    // Pay it now rather than in the first frames of the first fold.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ui.Image? warm = await _shoot();
      warm?.dispose();
    });
  }

  Device _device = Device.duo;

  /// Phone and tablet.
  bool _landscape = false;

  /// iPhone Duo held with its hinge upright: closed, that is the outer display
  /// in portrait; open, the inner one in landscape.
  bool _hingeUpright = true;
  bool _unfolded = true;

  /// What a running fold started from.
  bool _foldedFrom = true;

  _Fold _phase = _Fold.idle;
  ui.Image? _shot;

  /// On a `RepaintBoundary` around the display, to take its picture.
  final GlobalKey _displayKey = GlobalKey(debugLabel: 'display');

  late final AnimationController _fold = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..addListener(() => setState(() {}));

  bool get _busy => _phase != _Fold.idle || _turning;

  /// A turn of the device in progress, from [_turnFrom], clockwise when
  /// [_turnSign] is 1.
  bool _turning = false;
  Pose? _turnFrom;
  double _turnSign = 1;
  ui.Image? _turnShot;

  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..addListener(() => setState(() {}));

  /// The pose on show for the current device; the desktop has none.
  Pose? get _pose => switch (_device) {
    Device.desktop => null,
    Device.phone => _landscape ? phoneLandscape : phonePortrait,
    Device.tablet => _landscape ? tabletLandscape : tabletPortrait,
    Device.duo || Device.galaxyFold => _foldable(_unfolded),
  };

  bool get _isFoldable => _device == Device.duo || _device == Device.galaxyFold;

  /// Turns the device a quarter, the way the simulator does: the hardware
  /// turns with the picture on it going round too, and then the picture
  /// swings back upright and gives way to the new layout. The app takes its
  /// new size at the start, out of sight.
  Future<void> _rotate() async {
    final Pose? from = _pose;
    if (_busy || from == null) {
      return;
    }
    final ui.Image? shot = await _shoot();
    if (!mounted) {
      shot?.dispose();
      return;
    }
    reachGoal('rotate');
    setState(() {
      _turnFrom = from;
      _turnShot = shot;
      if (_isFoldable) {
        // Upright to turned is a quarter anticlockwise: the hinge goes from
        // the left edge to the bottom.
        _turnSign = _hingeUpright ? -1 : 1;
        _hingeUpright = !_hingeUpright;
      } else {
        // Portrait to landscape is a quarter clockwise: the top, and the
        // island with it, ends up on the right.
        _turnSign = _landscape ? -1 : 1;
        _landscape = !_landscape;
      }
      _turning = true;
    });
    _turn.value = 0;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    await _turn.forward(from: 0);
    if (!mounted) {
      return;
    }
    setState(() {
      _turning = false;
      _turnShot?.dispose();
      _turnShot = null;
    });
  }

  Widget _picture(Size size) {
    final ui.Image? shot = _turnShot;
    return SizedBox.fromSize(
      size: size,
      child: shot == null
          ? const ColoredBox(color: Colors.black)
          : RawImage(image: shot, fit: BoxFit.fill),
    );
  }

  final ThemeData _theme = ThemeData(colorSchemeSeed: Colors.indigo);

  /// The desktop keeps the browser's platform.
  late final ThemeData _iosTheme = _theme.copyWith(
    platform: TargetPlatform.iOS,
  );
  late final ThemeData _androidTheme = _theme.copyWith(
    platform: TargetPlatform.android,
  );

  ThemeData get _deviceTheme => switch (_device) {
    Device.desktop => _theme,
    Device.phone || Device.tablet || Device.duo => _iosTheme,
    Device.galaxyFold => _androidTheme,
  };

  @override
  void dispose() {
    _fold.dispose();
    _turn.dispose();
    _turnShot?.dispose();
    _shot?.dispose();
    super.dispose();
  }

  /// The foldable on show, open or shut, in the way it is held.
  Pose _foldable(bool unfolded) => _device == Device.galaxyFold
      ? (unfolded
            ? (_hingeUpright ? foldInnerLandscape : foldInnerPortrait)
            : (_hingeUpright ? foldCoverPortrait : foldCoverLandscape))
      : (unfolded
            ? (_hingeUpright ? duoInnerLandscape : duoInnerPortrait)
            : (_hingeUpright ? duoOuterPortrait : duoOuterLandscape));

  /// The fold as Android reports it, flat open. iOS reports none yet, so
  /// iPhone Duo gets an empty list, as the app would on the device.
  List<ui.DisplayFeature> _features(Pose pose) {
    if (!pose.reportsFold) {
      return const <ui.DisplayFeature>[];
    }
    final Size s = pose.size;
    return <ui.DisplayFeature>[
      ui.DisplayFeature(
        bounds: pose.hinge == Hinge.centreHorizontal
            ? Rect.fromLTWH(0, s.height / 2, s.width, 0)
            : Rect.fromLTWH(s.width / 2, 0, 0, s.height),
        type: ui.DisplayFeatureType.fold,
        state: ui.DisplayFeatureState.postureFlat,
      ),
    ];
  }

  Future<ui.Image?> _shoot() async {
    final RenderObject? r = _displayKey.currentContext?.findRenderObject();
    if (r is! RenderRepaintBoundary) {
      return null;
    }
    try {
      final double dpr = MediaQuery.devicePixelRatioOf(context);
      return await r.toImage(pixelRatio: dpr > 2 ? 2 : dpr);
    } catch (_) {
      return null;
    }
  }

  /// Pictures the display that is on, hands the app its new size out of
  /// sight, and swings the model across.
  Future<void> _toggleFold() async {
    if (_busy) {
      return;
    }
    final ui.Image? shot = await _shoot();
    if (!mounted) {
      shot?.dispose();
      return;
    }
    reachGoal(_unfolded ? 'fold' : 'unfold');
    setState(() {
      _foldedFrom = _unfolded;
      _unfolded = !_unfolded;
      _shot = shot;
      _phase = _Fold.moving;
    });
    // The app lays out at its new size in this frame, which can be a heavy
    // one the first time. Let it land before the clock starts, so it does not
    // eat the first frames of the motion; the model holds still meanwhile.
    _fold.value = 0;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    await _fold.forward(from: 0);
    if (!mounted) {
      return;
    }
    setState(() {
      _phase = _Fold.idle;
      _shot?.dispose();
      _shot = null;
    });
  }

  /// The model [p] of the way from where the fold started. The display that
  /// was on goes dark as it moves; the other is off until the hardware stops.
  Widget _model(double p) {
    final double fading = Curves.easeIn.transform(math.min(1.0, p * 1.25));
    final bool galaxy = _device == Device.galaxyFold;
    return FoldModel(
      inner: galaxy ? foldInnerLandscape : duoInnerLandscape,
      outer: galaxy ? foldCoverPortrait : duoOuterPortrait,
      closed: _unfolded ? 1 - p : p,
      quarterTurns: _hingeUpright ? 0 : 3,
      innerShot: _unfolded ? null : _shot,
      outerShot: _unfolded ? _shot : null,
      innerDim: _unfolded ? 1 : fading,
      outerDim: _unfolded ? fading : 1,
    );
  }

  /// The app as a window of [size] with [padding] for its safe area.
  ///
  /// No `MaterialApp` sits above this one, so the app's own reads this
  /// `MediaQuery` rather than the browser's.
  Widget _screen(
    Size size, [
    EdgeInsets padding = EdgeInsets.zero,
    List<ui.DisplayFeature> features = const <ui.DisplayFeature>[],
  ]) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      size: size,
      padding: padding,
      viewPadding: padding,
      viewInsets: EdgeInsets.zero,
      systemGestureInsets: EdgeInsets.zero,
      displayFeatures: features,
    ),
    child: Theme(
      data: _deviceTheme,
      child: SizedBox.fromSize(size: size, child: _app),
    ),
  );

  List<HeaderAction> get _actions => <HeaderAction>[
    if (_device != Device.desktop)
      HeaderAction(
        icon: Icons.screen_rotation,
        label: 'Rotate',
        onTap: _busy ? null : _rotate,
      ),
    if (_isFoldable)
      HeaderAction(
        icon: _unfolded ? Icons.close_fullscreen : Icons.open_in_full,
        label: _unfolded ? 'Fold' : 'Unfold',
        onTap: _busy ? null : _toggleFold,
        primary: true,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    // Not a MaterialApp: a second app would report its own route to the
    // browser and fight the example's URLs.
    return Localizations(
      locale: const Locale('en'),
      delegates: const <LocalizationsDelegate<dynamic>>[
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      child: Theme(
        data: _theme,
        child: Material(
          color: _kStage,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              PlaygroundHeader(
                device: _device,
                onDevice: _busy
                    ? null
                    : (Device d) {
                        setState(() => _device = d);
                        reachGoal('device_${d.name}');
                      },
                actions: _actions,
              ),
              Expanded(
                child: _device == Device.desktop
                    ? DesktopStage(screen: _screen)
                    : _deviceStage(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deviceStage() {
    final Pose pose;
    Size box;
    Widget? model;
    Widget? overlay;
    Matrix4? content;
    double dim = 0;

    switch (_device) {
      case Device.desktop:
        throw StateError('The desktop has its own stage.');
      case Device.phone:
        pose = _landscape ? phoneLandscape : phonePortrait;
        box = pose.frameSize;
      case Device.tablet:
        pose = _landscape ? tabletLandscape : tabletPortrait;
        box = pose.frameSize;
      case Device.duo || Device.galaxyFold:
        final Pose from = _foldable(_foldedFrom);
        // The live app is in the new pose from the moment a fold starts.
        pose = _foldable(_unfolded);
        final double v = _fold.value;
        if (_phase == _Fold.idle) {
          box = pose.frameSize;
        } else if (v < _kMoving) {
          final double p = Curves.easeInOutCubic.transform(v / _kMoving);
          box = Size.lerp(from.frameSize, pose.frameSize, p)!;
          model = _model(p);
        } else {
          box = pose.frameSize;
          final double q = (v - _kMoving) / (1 - _kMoving);
          dim = 0.92 * (1 - Curves.easeOutCubic.transform(q));
        }
    }

    final Pose? turnFrom = _turnFrom;
    if (_turning && turnFrom != null) {
      final double v = _turn.value;
      if (v < 0.5) {
        // The hardware turns, the old picture going round with it.
        final double p = Curves.easeInOutCubic.transform(v / 0.5);
        box = Size.lerp(turnFrom.frameSize, pose.frameSize, p)!;
        model = Transform.rotate(
          angle: _turnSign * math.pi / 2 * p,
          child: DeviceFrame(
            pose: turnFrom,
            systemUi: false,
            child: _picture(turnFrom.size),
          ),
        );
      } else {
        // As iOS does it: the old picture, now on its side, and the new
        // layout swing back upright together, both stretched from the old
        // proportions to the new ones, the old one fading out over the new.
        final double q = Curves.easeInOutCubic.transform((v - 0.5) / 0.5);
        final double angle = _turnSign * math.pi / 2 * (1 - q);
        final Size frameOf = Size.lerp(turnFrom.size, pose.size, q)!;
        Matrix4 swing(Size natural) => Matrix4.rotationZ(angle).multiplied(
          Matrix4.diagonal3Values(
            frameOf.width / natural.width,
            frameOf.height / natural.height,
            1,
          ),
        );
        content = swing(pose.size);
        overlay = Opacity(
          opacity: 1 - Curves.easeIn.transform(q),
          child: Center(
            child: OverflowBox(
              minWidth: 0,
              minHeight: 0,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: Transform(
                alignment: Alignment.center,
                transform: swing(turnFrom.size),
                child: _picture(turnFrom.size),
              ),
            ),
          ),
        );
      }
    }

    // A tablet is taller than most browser windows: scale the device down to
    // fit, never up. Hit testing follows the transform. The live device and
    // the model are scaled alike, so one takes over from the other in place.
    Widget scaled(Widget child) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox.fromSize(
            size: box,
            // Loose both ways: the stage's box only sets the scale, and a
            // device bigger or smaller than it keeps its own size.
            child: OverflowBox(
              minWidth: 0,
              minHeight: 0,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: child,
            ),
          ),
        ),
      ),
    );

    return Column(
      children: <Widget>[
        Expanded(
          // A device bigger than the stage's box paints past it, so clip here.
          // The clip extends below the stage to leave room for the frame's
          // shadow; the hint text is painted after the stage, on top of it.
          child: ClipRect(
            clipper: const _StageClip(bottom: _shadowReach),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: scaled(
                    IgnorePointer(
                      ignoring: _busy,
                      // Not painted at all while the model is on: in the new
                      // pose it can be taller or wider than the model and would
                      // show past it. It still lays out, so the app keeps its
                      // state and has its new size ready.
                      child: Opacity(
                        opacity: model == null ? 1 : 0,
                        child: DeviceFrame(
                          pose: pose,
                          displayKey: _displayKey,
                          dim: dim,
                          blur: 16 * dim,
                          overlay: overlay,
                          contentTransform: content,
                          child: _screen(
                            pose.size,
                            pose.padding,
                            _features(pose),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (model != null)
                  Positioned.fill(child: scaled(IgnorePointer(child: model))),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Text(
            _isFoldable
                ? 'Open a person, start an edit, then fold or rotate: '
                      'nothing remounts.'
                : 'Open a person, start an edit, then rotate or switch '
                      'devices: nothing remounts.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6B6B76), fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

/// How far below the device frame its shadow is still visible: the 22-point
/// offset plus about three sigmas of a 48-point blur.
const double _shadowReach = 96;

/// The stage's own rect, let out at the bottom by [bottom].
class _StageClip extends CustomClipper<Rect> {
  const _StageClip({required this.bottom});

  final double bottom;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, 0, size.width, size.height + bottom);

  @override
  bool shouldReclip(_StageClip oldClipper) => oldClipper.bottom != bottom;
}
