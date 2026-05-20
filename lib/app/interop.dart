part of '../app.dart';

// ── Document Picture-in-Picture interop ───────────────────────────────────

@JS('documentPictureInPicture')
external _DocPiP? get _docPiP;

extension type _DocPiP._(JSObject _) implements JSObject {
  external JSPromise<_PiPWin> requestWindow(_PiPReqOpts opts);
}

extension type _PiPReqOpts._(JSObject _) implements JSObject {
  external factory _PiPReqOpts({int width, int height});
}

extension type _PiPWin._(JSObject _) implements JSObject {
  external JSObject get document;
  external void close();
  external void addEventListener(String type, JSFunction listener);
  external int get innerWidth;
  external int get innerHeight;
}

// ── Flatpickr interop ─────────────────────────────────────────────────────

@JS('flatpickr')
external _FPInstance _flatpickr(web.HTMLElement el, _FPConfig config);

extension type _FPConfig._(JSObject _) implements JSObject {
  external factory _FPConfig({
    bool enableTime,
    bool noCalendar,
    bool enableSeconds,
    // ignore: non_constant_identifier_names
    bool time_24hr,
    String dateFormat,
    String defaultDate,
    JSFunction onChange,
  });
}

extension type _FPInstance._(JSObject _) implements JSObject {
  external void destroy();
  external void setDate(String date, bool triggerChange);
}
