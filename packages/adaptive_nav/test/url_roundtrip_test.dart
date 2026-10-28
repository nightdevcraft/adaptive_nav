import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/demo_app.dart';

/// `NavState -> path -> NavState` on the visible location, plus the codec
/// itself.
void main() {
  test('codec encodes/decodes each route symmetrically', () {
    const DemoCodec codec = DemoCodec();
    const List<DemoRoute> routes = <DemoRoute>[
      DemoList(),
      DemoDetail(7),
      DemoEdit(7),
      DemoHome(),
    ];
    for (final DemoRoute r in routes) {
      expect(codec.decode(codec.encode(r)), equals(r));
    }
  });

  test('parser round-trips the visible top route', () async {
    final DemoHarness h = DemoHarness();
    h.delegate.push(const DemoDetail(5));
    final NavState<DemoRoute> state = h.delegate.state;

    final RouteInformation ri = h.parser.restoreRouteInformation(state)!;
    final NavState<DemoRoute> parsed = await h.parser.parseRouteInformation(ri);

    expect(parsed.activeBranch, equals(state.activeBranch));
    expect(parsed.active.top.route, equals(state.active.top.route));
  });

  test('deeplink to a home route lands on its branch', () async {
    final DemoHarness h = DemoHarness();
    final NavState<DemoRoute> parsed = await h.parser.parseRouteInformation(
      RouteInformation(uri: Uri.parse('/home')),
    );
    expect(parsed.activeBranch, 1);
    expect(parsed.active.top.route, const DemoHome());
  });
}
