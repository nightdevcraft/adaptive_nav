import 'dart:convert';
import 'dart:ui' show DisplayFeature;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'geometry.dart';
import 'geometry_provider.dart';

/// Draws the geometry over [child] and logs every change, for measuring a
/// posture.
///
/// The reserved regions are filled (the fold red, the cameras blue; outlined
/// while inactive) and the safe area is outlined green. A small button opens
/// a panel with the numbers and a "Copy" that puts them on the clipboard as
/// JSON. Each change is also printed as a line starting with `duo_probe `,
/// which is easy to pick out of the Xcode console; a long one continues on
/// `duo_probe+ ` lines.
///
/// The JSON carries both what UIKit says and what Flutter's `MediaQuery`
/// says, so a posture can be compared in one place.
///
/// Wants a [DuoGeometryProvider] above it. Works inside or outside a
/// `WidgetsApp`.
class DuoGeometryProbe extends StatelessWidget {
  const DuoGeometryProbe({super.key, required this.child, this.log = true});

  final Widget child;

  /// Print a `duo_probe` line on every change.
  final bool log;

  @override
  Widget build(BuildContext context) {
    final Widget body = _ProbeBody(log: log, child: child);
    // Above a WidgetsApp there is no MediaQuery yet; without one the probe
    // would not rebuild when the window's metrics change.
    return MediaQuery.maybeOf(context) == null
        ? MediaQuery.fromView(view: View.of(context), child: body)
        : body;
  }
}

class _ProbeBody extends StatefulWidget {
  const _ProbeBody({required this.log, required this.child});

  final bool log;
  final Widget child;

  @override
  State<_ProbeBody> createState() => _ProbeBodyState();
}

class _ProbeBodyState extends State<_ProbeBody> {
  bool _open = false;
  String? _logged;

  @override
  Widget build(BuildContext context) {
    final DuoGeometry? geometry = DuoGeometryScope.maybeOf(context);
    final MediaQueryData media = MediaQuery.of(context);
    final Map<String, Object?> snapshot = duoProbeSnapshot(geometry, media);
    final String json = jsonEncode(snapshot);
    if (widget.log && json != _logged) {
      _logged = json;
      _logLine(json);
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: <Widget>[
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GeometryPainter(geometry, media.padding),
              ),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: _open
                ? _Panel(
                    text: _describe(geometry, media),
                    onCopy: () => Clipboard.setData(ClipboardData(text: json)),
                    onClose: () => setState(() => _open = false),
                  )
                : _Chip(onTap: () => setState(() => _open = true)),
          ),
        ],
      ),
    );
  }
}

/// The iOS console cuts a line at about 1000 bytes, and a snapshot with a
/// fold and two cameras is longer. Past [_chunk] characters the JSON goes out
/// as `duo_probe <start>` and then `duo_probe+ <more>` lines, which join back
/// with nothing in between.
const int _chunk = 900;

void _logLine(String json) {
  for (int i = 0; i < json.length; i += _chunk) {
    final String part = json.substring(
      i,
      i + _chunk < json.length ? i + _chunk : json.length,
    );
    debugPrint(i == 0 ? 'duo_probe $part' : 'duo_probe+ $part');
  }
}

/// What [DuoGeometryProbe] logs and copies: UIKit's map next to Flutter's
/// `MediaQuery`.
@visibleForTesting
Map<String, Object?> duoProbeSnapshot(
  DuoGeometry? geometry,
  MediaQueryData media,
) {
  Map<String, double> insets(EdgeInsets e) => <String, double>{
    'left': e.left,
    'top': e.top,
    'right': e.right,
    'bottom': e.bottom,
  };
  return <String, Object?>{
    'uikit': geometry?.raw,
    'flutter': <String, Object?>{
      'size': <String, double>{
        'width': media.size.width,
        'height': media.size.height,
      },
      'devicePixelRatio': media.devicePixelRatio,
      'padding': insets(media.padding),
      'viewPadding': insets(media.viewPadding),
      'viewInsets': insets(media.viewInsets),
      'displayFeatures': <Object?>[
        for (final DisplayFeature f in media.displayFeatures)
          <String, Object?>{
            'type': f.type.name,
            'state': f.state.name,
            'bounds': <String, double>{
              'left': f.bounds.left,
              'top': f.bounds.top,
              'right': f.bounds.right,
              'bottom': f.bounds.bottom,
            },
          },
      ],
    },
  };
}

String _describe(DuoGeometry? g, MediaQueryData media) {
  String n(double v) => v.toStringAsFixed(1);
  String ins(EdgeInsets e) =>
      'L${n(e.left)} T${n(e.top)} R${n(e.right)} B${n(e.bottom)}';
  String rect(Rect r) =>
      '${n(r.left)},${n(r.top)} → ${n(r.right)},${n(r.bottom)} '
      '(${n(r.width)}×${n(r.height)})';

  final StringBuffer b = StringBuffer()
    ..writeln('Flutter ${n(media.size.width)}×${n(media.size.height)}')
    ..writeln('padding ${ins(media.padding)}')
    ..writeln('displayFeatures ${media.displayFeatures.length}');
  if (g == null) {
    b.writeln('UIKit: nothing yet');
    return b.toString();
  }
  b
    ..writeln(
      'UIKit ${n(g.size.width)}×${n(g.size.height)}'
      '${g.isSupported ? '' : '  (below iOS 27.1)'}',
    )
    ..writeln('safe ${ins(g.safeArea)}');
  if (g.cornerSafeArea case final EdgeInsets c) {
    b.writeln('corner ${ins(c)}');
  }
  b
    ..writeln(
      'bar ${g.verticalBarEdge.name} (raw ${g.verticalBarEdgeRaw}) '
      '→ ${g.verticalBarSide?.name ?? '—'}, ${g.layoutDirection.name}',
    )
    ..writeln('size class ${g.horizontalSizeClass}/${g.verticalSizeClass}')
    ..writeln(
      'hinge ${g.hingeStatus?.name ?? '—'} (raw ${g.hingeStatusRaw}) '
      '${g.hingeAngle?.toStringAsFixed(3) ?? ''}',
    );
  if (g.screenSize case final Size s) {
    b.writeln('screen ${n(s.width)}×${n(s.height)}');
  }
  if (g.frameInScreen case final Rect f) {
    b.writeln('in screen ${rect(f)}');
  }
  for (final ReservedRegion r in g.regions) {
    b.writeln(
      '${r.kind.name}${r.isActive ? '' : ' (inactive)'} '
      '${rect(r.frame)}',
    );
  }
  return b.toString();
}

class _GeometryPainter extends CustomPainter {
  _GeometryPainter(this.geometry, this.padding);

  final DuoGeometry? geometry;
  final EdgeInsets padding;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      padding.deflateRect(Offset.zero & size),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xCC00C853),
    );
    for (final ReservedRegion r
        in geometry?.regions ?? const <ReservedRegion>[]) {
      final Color color = r.kind == ReservedRegionKind.division
          ? const Color(0xFFFF1744)
          : const Color(0xFF2979FF);
      // A flat fold has no width; give it one so it shows.
      final Rect frame = r.frame.width == 0 || r.frame.height == 0
          ? r.frame.inflate(1)
          : r.frame;
      canvas.drawRect(
        frame,
        Paint()
          ..style = r.isActive ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = r.isActive ? color.withValues(alpha: 0.35) : color,
      );
    }
  }

  @override
  bool shouldRepaint(_GeometryPainter old) =>
      old.geometry != geometry || old.padding != padding;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text(
        'probe',
        style: TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 12,
          decoration: TextDecoration.none,
        ),
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.text,
    required this.onCopy,
    required this.onClose,
  });

  final String text;
  final VoidCallback onCopy;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    const TextStyle style = TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 11,
      height: 1.3,
      fontFamily: 'Menlo',
      decoration: TextDecoration.none,
    );
    Widget button(String label, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 16, 0),
        child: Text(
          label,
          style: style.copyWith(fontSize: 13, color: const Color(0xFF82B1FF)),
        ),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xE6000000),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(text, style: style),
            Row(
              children: <Widget>[
                button('Copy JSON', onCopy),
                button('Close', onClose),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
