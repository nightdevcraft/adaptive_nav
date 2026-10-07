import 'dart:js_interop';

@JS('window.open')
external JSAny? _open(JSString url, JSString target);

/// Set by `index.html`: a no-op unless the page was built with a Metrika
/// counter, and absent altogether under `flutter run`.
@JS('playgroundGoal')
external JSFunction? get _goal;

/// Opens [url] in a new tab.
void openUrl(String url) {
  _open(url.toJS, '_blank'.toJS);
}

/// Reports a goal to Yandex Metrika, if the page has a counter.
void reachGoal(String name) {
  _goal?.callAsFunction(null, name.toJS);
}
