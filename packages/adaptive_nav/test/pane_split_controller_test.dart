import 'package:adaptive_nav/adaptive_nav.dart';
import 'package:flutter_test/flutter_test.dart';

/// The controller on its own: what a drag commits, and to which branch.
void main() {
  test('a drag that moved nothing commits nothing', () {
    final List<(Object, double)> commits = <(Object, double)>[];
    final PaneSplitController split = PaneSplitController(
      initial: <Object, double>{'a': 0.4},
      onCommit: (Object id, double f) => commits.add((id, f)),
    );
    addTearDown(split.dispose);
    int notified = 0;
    split.addListener(() => notified++);

    split
      ..beginDrag('a')
      ..drag('a', 0.4)
      ..endDrag();

    expect(commits, isEmpty);
    expect(notified, 0);
    expect(split.isDragging, isFalse);

    split
      ..beginDrag('a')
      ..drag('a', 0.5)
      ..endDrag();
    expect(commits, <(Object, double)>[('a', 0.5)]);
  });

  test('a drag writes to the branch it began on', () {
    final List<(Object, double)> commits = <(Object, double)>[];
    final PaneSplitController split = PaneSplitController(
      onCommit: (Object id, double f) => commits.add((id, f)),
    );
    addTearDown(split.dispose);

    split
      ..beginDrag('a')
      ..drag('a', 0.45)
      // The active branch changed under the finger.
      ..drag('b', 0.6)
      ..endDrag();

    expect(split.fractionOf('a'), 0.45);
    expect(split.fractionOf('b'), isNull);
    expect(commits, <(Object, double)>[('a', 0.45)]);
  });

  test('a tap on the handle does not shut out a late restore', () {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);

    split
      ..beginDrag('staff')
      ..endDrag()
      ..restore(<Object, double>{'staff': 0.6});

    expect(split.fractionOf('staff'), 0.6);
  });

  test('a real drag does', () {
    final PaneSplitController split = PaneSplitController();
    addTearDown(split.dispose);

    split
      ..beginDrag('staff')
      ..drag('staff', 0.45)
      ..endDrag()
      ..restore(<Object, double>{'staff': 0.6});

    expect(split.fractionOf('staff'), 0.45);
  });

  test('a drag back to where it began ends for the listeners too', () {
    final List<(Object, double)> commits = <(Object, double)>[];
    final PaneSplitController split = PaneSplitController(
      initial: <Object, double>{'a': 0.4},
      onCommit: (Object id, double f) => commits.add((id, f)),
    );
    addTearDown(split.dispose);
    final List<bool> dragging = <bool>[];
    split.addListener(() => dragging.add(split.isDragging));

    split
      ..beginDrag('a')
      ..drag('a', 0.5)
      ..drag('a', 0.4)
      ..endDrag();

    expect(dragging, <bool>[true, true, false]);
    expect(commits, isEmpty);
  });

  test('a drag back to where it began does not shut out a restore', () {
    final PaneSplitController split = PaneSplitController(
      initial: <Object, double>{'a': 0.4},
    );
    addTearDown(split.dispose);

    split
      ..beginDrag('a')
      ..drag('a', 0.5)
      ..drag('a', 0.4)
      ..endDrag()
      ..restore(<Object, double>{'a': 0.6});

    expect(split.fractionOf('a'), 0.6);
  });

  test('a restore during a drag leaves the dragged branch alone', () {
    final List<(Object, double)> commits = <(Object, double)>[];
    final PaneSplitController split = PaneSplitController(
      initial: <Object, double>{'a': 0.4},
      onCommit: (Object id, double f) => commits.add((id, f)),
    );
    addTearDown(split.dispose);

    split
      ..beginDrag('a')
      ..restore(<Object, double>{'a': 0.7, 'b': 0.3});
    expect(split.fractionOf('a'), 0.4);
    expect(split.fractionOf('b'), 0.3);

    split.endDrag();
    expect(commits, isEmpty);

    split
      ..beginDrag('a')
      ..drag('a', 0.5)
      ..restore(<Object, double>{'a': 0.7})
      ..endDrag();
    expect(split.fractionOf('a'), 0.5);
    expect(commits, <(Object, double)>[('a', 0.5)]);
  });
}
