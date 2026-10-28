import 'package:flutter/foundation.dart';

/// User-chosen master-detail pane widths: the master's share of the pane area,
/// per branch.
///
/// The app owns the controller. It seeds it with whatever was persisted
/// ([restore]) and writes the choice back from [onCommit]; the package only
/// reads the fraction and moves it during a drag. Kept inside the shell
/// instead, a width would survive neither a branch switch nor a restart, and
/// it does not belong in `NavState` — a view setting is not navigation.
class PaneSplitController extends ChangeNotifier {
  PaneSplitController({Map<Object, double>? initial, this.onCommit})
    : _fractions = <Object, double>{...?initial};

  /// A branch missing from the map is laid out with
  /// `MasterDetailConfig.paneRatio`, at `portraitPaneRatio` in a portrait
  /// window, or on the window centre where
  /// `MasterDetailConfig.alignToWindowCenter` is on.
  final Map<Object, double> _fractions;

  // Branches the user has already dragged, so a late restore cannot overwrite
  // a fresh choice: storage reads are async and the shell may already have
  // accepted a drag by the time one lands. A drag back to where it began is
  // not a choice.
  final Set<Object> _touched = <Object>{};

  /// Called on release, not on every drag frame.
  final void Function(Object branchId, double fraction)? onCommit;

  Object? _draggingBranch;

  double? _fractionAtStart;

  /// Whether listeners have heard of this drag, and so must hear it end.
  bool _notifiedDuringDrag = false;

  /// Whether a drag is in progress. The shell does not need this; it is here
  /// for apps that want to highlight the divider while it is being pulled.
  bool get isDragging => _draggingBranch != null;

  /// Master fraction for a branch, or `null` if the user never set one.
  double? fractionOf(Object branchId) => _fractions[branchId];

  /// Applies a persisted choice, leaving alone any branch already dragged in
  /// this session and the one being dragged now: the finger is on it.
  void restore(Map<Object, double> fractions) {
    bool changed = false;
    for (final MapEntry<Object, double> e in fractions.entries) {
      if (_touched.contains(e.key) ||
          e.key == _draggingBranch ||
          _fractions[e.key] == e.value) {
        continue;
      }
      _fractions[e.key] = e.value;
      changed = true;
    }
    if (changed) {
      notifyListeners();
    }
  }

  void beginDrag(Object branchId) {
    _draggingBranch = branchId;
    _fractionAtStart = _fractions[branchId];
    _notifiedDuringDrag = false;
  }

  /// [fraction] has already been clamped by the shell.
  ///
  /// During a drag only its own branch moves: the active one can change.
  void drag(Object branchId, double fraction) {
    final Object? dragging = _draggingBranch;
    if ((dragging != null && branchId != dragging) ||
        _fractions[branchId] == fraction) {
      return;
    }
    _fractions[branchId] = fraction;
    if (dragging == null) {
      // Set outside a drag: nothing to wait for.
      _touched.add(branchId);
    } else {
      _notifiedDuringDrag = true;
    }
    notifyListeners();
  }

  /// Commits the drag if it moved. A drag back to where it began still
  /// notifies, as listeners saw it move, but commits nothing.
  void endDrag() {
    final Object? branch = _draggingBranch;
    _draggingBranch = null;
    if (branch == null) {
      return;
    }
    final double? fraction = _fractions[branch];
    final bool moved = fraction != null && fraction != _fractionAtStart;
    if (moved) {
      _touched.add(branch);
    }
    if (moved || _notifiedDuringDrag) {
      notifyListeners();
    }
    if (moved) {
      onCommit?.call(branch, fraction);
    }
  }
}
