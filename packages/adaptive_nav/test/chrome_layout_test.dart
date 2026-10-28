import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '_harness/resize.dart';

/// [defaultChromeLayout] — and, above all, the devices it must leave alone.
///
/// The policy exists for iPhone Duo, which puts its status bar on its side and
/// asks apps to follow. Every number below was measured on a simulator under
/// Xcode 27.1; the point of the first group is that none of the new rules can
/// fire on anything that is not a Duo.
void main() {
  group('other devices keep the layout they had', () {
    // The rule the package has always used, to compare against.
    ChromePlacement byWidthAlone(Size window, EdgeInsets padding) =>
        (window.width - padding.horizontal) >= 600
        ? ChromePlacement.left
        : ChromePlacement.bottom;

    // With no scope above, and with one that has no opinion: a provider on
    // a device without a vertical bar reports exactly that.
    void unchanged(String name, Size window, EdgeInsets padding) {
      test(name, () {
        expect(
          defaultChromeLayout(window, padding),
          byWidthAlone(window, padding),
          reason: '$name must decide exactly as the width breakpoint alone',
        );
        expect(
          defaultChromeLayout(window, padding, const SystemGeometry()),
          byWidthAlone(window, padding),
          reason: '$name, with a geometry that has no vertical bar',
        );
      });
    }

    // iPhone 18 Pro, measured.
    unchanged(
      'iPhone portrait',
      const Size(402, 874),
      const EdgeInsets.only(top: 62, bottom: 34),
    );
    // The one that could have gone wrong: a notched iPhone in landscape has
    // large horizontal insets. They are symmetric, and the rule wants one
    // side only.
    unchanged(
      'iPhone landscape',
      const Size(874, 402),
      const EdgeInsets.only(left: 62, right: 62, bottom: 20),
    );
    // A single notch, one-sided — but bezel, and narrower than a bar.
    unchanged(
      'iPhone landscape, one-sided notch',
      const Size(874, 402),
      const EdgeInsets.only(left: 59, bottom: 20),
    );
    unchanged(
      'iPad portrait',
      const Size(834, 1194),
      const EdgeInsets.only(top: 24, bottom: 20),
    );
    unchanged(
      'iPad landscape',
      const Size(1194, 834),
      const EdgeInsets.only(top: 24, bottom: 20),
    );
    unchanged('desktop window', const Size(1200, 900), EdgeInsets.zero);
    unchanged('narrow desktop window', const Size(500, 900), EdgeInsets.zero);
    unchanged(
      'Android phone portrait',
      const Size(411, 867),
      const EdgeInsets.only(top: 24, bottom: 48),
    );
    // A display cutout is one-sided, so only its width keeps it out.
    unchanged(
      'Android phone landscape with a cutout',
      const Size(867, 411),
      const EdgeInsets.only(left: 48, bottom: 24),
    );
  });

  // Rule 2 reads the top inset alone, so unlike the side-bar rule it is not
  // fenced off to iPhone Duo. Nothing measured reports a deep top inset on a
  // window this wide, but the behaviour is defined and worth pinning.
  group('a deep top inset means horizontal bars', () {
    test('even on a window wide enough for a rail', () {
      expect(
        defaultChromeLayout(
          const Size(1000, 800),
          const EdgeInsets.only(top: 82, bottom: 20),
        ),
        ChromePlacement.bottom,
        reason: 'the top inset is read before the width breakpoint',
      );
    });

    test('a tablet-shaped inset is too shallow to count', () {
      expect(
        defaultChromeLayout(
          const Size(1000, 800),
          const EdgeInsets.only(top: 24, bottom: 20),
        ),
        ChromePlacement.left,
      );
    });
  });

  group('iPhone Duo follows the system bar', () {
    test('outer display: the chrome goes to the side the status bar is on', () {
      expect(
        defaultChromeLayout(kDuoOuterPortrait, kDuoOuterPortraitPadding),
        ChromePlacement.right,
      );
      expect(
        defaultChromeLayout(kDuoOuterLandscape, kDuoOuterLandscapePadding),
        ChromePlacement.left,
      );
    });

    // Wide enough for a rail anywhere, and the bar's side wins anyway: Apple
    // keeps the bar where it was on the outer display, and the system's
    // column is on that side.
    test('inner display, landscape: the chrome joins the bar, wide or not', () {
      expect(
        defaultChromeLayout(kDuoInnerLandscape, kDuoInnerLandscapePadding),
        ChromePlacement.right,
      );
    });

    test('Split View, right half: the bar is in this window', () {
      expect(
        defaultChromeLayout(kDuoSplit, kDuoSplitRightPadding),
        ChromePlacement.right,
      );
    });

    // What the padding cannot see: the left half has no side inset, so the
    // fallback reads it as a narrow window and gives it a bottom bar. The
    // system wants the bar on the left edge here; only a [SystemGeometry]
    // says so.
    test('Split View, left half: a bottom bar, the fallback\'s limit', () {
      expect(
        defaultChromeLayout(kDuoSplit, kDuoSplitLeftPadding),
        ChromePlacement.bottom,
      );
    });

    // Apple's stated exception, and the reason the top inset is part of the
    // rule: 669 points would otherwise read as a tablet and get a rail.
    test('inner display, portrait: horizontal bars', () {
      expect(
        defaultChromeLayout(kDuoInnerPortrait, kDuoInnerPortraitPadding),
        ChromePlacement.bottom,
      );
    });
  });

  group('the system\'s own side comes first', () {
    const SystemGeometry left = SystemGeometry(
      verticalBar: ChromePlacement.left,
    );
    const SystemGeometry right = SystemGeometry(
      verticalBar: ChromePlacement.right,
    );

    test('Split View, left half: the left edge, as the system asks', () {
      expect(
        defaultChromeLayout(kDuoSplit, kDuoSplitLeftPadding, left),
        ChromePlacement.left,
      );
    });

    test('at any width', () {
      expect(
        defaultChromeLayout(const Size(1200, 800), EdgeInsets.zero, right),
        ChromePlacement.right,
      );
      expect(
        defaultChromeLayout(const Size(400, 800), EdgeInsets.zero, left),
        ChromePlacement.left,
      );
    });

    test('over a deep top inset', () {
      expect(
        defaultChromeLayout(kDuoInnerPortrait, kDuoInnerPortraitPadding, right),
        ChromePlacement.right,
      );
    });

    test('it agrees with the padding where both speak', () {
      expect(
        defaultChromeLayout(kDuoOuterPortrait, kDuoOuterPortraitPadding, right),
        ChromePlacement.right,
      );
      expect(
        defaultChromeLayout(
          kDuoOuterLandscape,
          kDuoOuterLandscapePadding,
          left,
        ),
        ChromePlacement.left,
      );
      expect(
        defaultChromeLayout(
          kDuoInnerLandscape,
          kDuoInnerLandscapePadding,
          right,
        ),
        ChromePlacement.right,
      );
    });

    // Right-to-left is not measured. A one-sided bar inset across the window
    // from the reported side is where the system's column really is.
    test('a bar inset on the other side wins over it', () {
      expect(
        defaultChromeLayout(kDuoOuterPortrait, kDuoOuterPortraitPadding, left),
        ChromePlacement.right,
      );
      expect(
        defaultChromeLayout(
          kDuoOuterLandscape,
          kDuoOuterLandscapePadding,
          right,
        ),
        ChromePlacement.left,
      );
    });

    // A notch, or a symmetric pair, is not a bar and does not argue.
    test('an inset that is not a bar does not', () {
      expect(
        defaultChromeLayout(
          const Size(874, 402),
          const EdgeInsets.only(left: 62, right: 62, bottom: 20),
          right,
        ),
        ChromePlacement.right,
      );
      expect(
        defaultChromeLayout(
          const Size(874, 402),
          const EdgeInsets.only(right: 59, bottom: 20),
          left,
        ),
        ChromePlacement.left,
      );
    });

    test('no vertical bar: the padding decides, as without one', () {
      const SystemGeometry none = SystemGeometry(
        statusArea: Rect.fromLTRB(535, 0, 669, 82),
      );
      expect(
        defaultChromeLayout(kDuoInnerPortrait, kDuoInnerPortraitPadding, none),
        ChromePlacement.bottom,
      );
      expect(
        defaultChromeLayout(kDuoSplit, kDuoSplitLeftPadding, none),
        ChromePlacement.bottom,
      );
    });
  });

  group('the rail shares the system bar column', () {
    // The outer display, where the camera sits at the end of that column.
    test('the column is the wider of the two, not their sum', () {
      const double bar = 84;
      expect(
        PaneMetrics.systemBarInset(
          padding: kDuoOuterPortraitPadding,
          placement: ChromePlacement.right,
        ),
        bar,
      );
      expect(
        PaneMetrics.railColumnWidth(
          railWidth: kDefaultRailWidth,
          systemBar: bar,
        ),
        bar,
      );
    });

    // The rail across the window from the bar — only a custom layout puts it
    // there now — has nothing to do with it.
    test('a bar on the far side is not the rail\'s column', () {
      expect(
        PaneMetrics.systemBarInset(
          padding: kDuoInnerLandscapePadding,
          placement: ChromePlacement.left,
        ),
        0,
      );
      expect(
        PaneMetrics.railColumnWidth(railWidth: kDefaultRailWidth),
        kDefaultRailWidth + kDefaultRailDividerWidth,
      );
    });

    test('a notch is not, so the rail still covers it', () {
      expect(
        PaneMetrics.systemBarInset(
          padding: const EdgeInsets.only(left: 59),
          placement: ChromePlacement.left,
        ),
        0,
      );
      expect(
        PaneMetrics.systemBarInset(
          padding: const EdgeInsets.only(left: 62, right: 62),
          placement: ChromePlacement.left,
        ),
        0,
      );
    });

    test('a bar has no side, so nothing is reserved', () {
      expect(
        PaneMetrics.systemBarInset(
          padding: kDuoOuterPortraitPadding,
          placement: ChromePlacement.bottom,
        ),
        0,
      );
    });
  });
}
