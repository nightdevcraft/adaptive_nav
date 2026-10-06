import 'dart:js_interop';

@JS('window.open')
external JSAny? _open(JSString url, JSString target);

/// Opens [url] in a new tab.
void openUrl(String url) {
  _open(url.toJS, '_blank'.toJS);
}
