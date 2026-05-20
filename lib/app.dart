import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:universal_web/web.dart' as web;
import 'model.dart';

part 'app/interop.dart';
part 'app/pip.dart';
part 'app/physics.dart';
part 'app/watermark.dart';
part 'app/drag.dart';
part 'app/tasks.dart';
part 'app/build.dart';

// ── Physics constants ─────────────────────────────────────────────────────

const double _topBound = 78.0;
const double _zoneR = 40.0;
const double _zoneOffset = 36.0;
const double _zoneNearDist = 120.0;
const double _zoneDropDist = 70.0;
const int _dyingMs = 480;
const int _pipW = 440;
const int _pipH = 320;

class App extends StatefulComponent {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  // ── Task list & physics ───────────────────────────────────────────────────
  final List<Task> _tasks = [];
  DragState? _drag;
  int _freezeUntil = 0;
  bool _isDoneZoneNear = false;
  double _vw = 800;
  double _vh = 600;
  String? _oldestId;
  int _lastClassSyncMs = 0;
  final _rng = Random();

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _tweaksOpen = false;
  bool _helpOpen = false;
  bool _showHints = true;
  Timer? _hintTimer;
  int _cachedStressLevel = 0;

  // ── Watermark ─────────────────────────────────────────────────────────────
  String? _wmCondition;
  String _wmMessage = '';
  final List<int> _recentAddMs = [];
  final List<int> _recentCompleteMs = [];
  int _lastActivityMs = 0;
  int _escapeWatermarkUntilMs = 0;

  // ── Picture-in-Picture ────────────────────────────────────────────────────
  _PiPWin? _pipWinRef;
  web.Document? _pipDoc;
  web.HTMLElement? _pipCanvas;
  JSFunction? _pipHideFn;
  JSFunction? _pipResizeFn;

  // ── Flatpickr / deadline ──────────────────────────────────────────────────
  _FPInstance? _fpInstance;
  String? _deadlinePreset;

  // ── Tweakable settings ────────────────────────────────────────────────────
  double _driftSpeed = 1.0;
  late DateTime _deadline;
  int _stressThreshold = 12;

  // ── Stream subscriptions ──────────────────────────────────────────────────
  StreamSubscription<int>? _tickSub;
  StreamSubscription<web.Event>? _keydownSub;
  StreamSubscription<web.Event>? _pointermoveSub;
  StreamSubscription<web.Event>? _pointerupSub;
  StreamSubscription<web.Event>? _resizeSub;

  // ── Derived getters ───────────────────────────────────────────────────────
  bool get _pipSupported => _docPiP != null;
  bool get _pipActive => _pipDoc != null;

  (double, double) get _zoneCenter =>
      (_vw - _zoneOffset - _zoneR, _vh - _zoneOffset - _zoneR);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _vw = web.window.innerWidth.toDouble();
    _vh = web.window.innerHeight.toDouble();
    _deadline = DateTime.now().add(const Duration(hours: 1));
    _lastActivityMs = DateTime.now().millisecondsSinceEpoch;

    _tickSub = Stream.periodic(const Duration(milliseconds: 16), (_) => 0)
        .listen((_) => _tick());

    _keydownSub = web.EventStreamProvider<web.Event>('keydown')
        .forTarget(web.window)
        .listen(_onKeydown);

    _pointermoveSub = web.EventStreamProvider<web.Event>('mousemove')
        .forTarget(web.window)
        .listen(_onWinMouseMove);

    _pointerupSub = web.EventStreamProvider<web.Event>('mouseup')
        .forTarget(web.window)
        .listen(_onWinMouseUp);

    _resizeSub = web.EventStreamProvider<web.Event>('resize')
        .forTarget(web.window)
        .listen((_) {
      _vw = web.window.innerWidth.toDouble();
      _vh = web.window.innerHeight.toDouble();
    });

    Timer(Duration.zero, () {
      (web.document.getElementById('chaos-input') as web.HTMLInputElement?)
          ?.focus();
    });

    _hintTimer = Timer(const Duration(milliseconds: 3800), () {
      setState(() => _showHints = false);
    });
  }

  @override
  void dispose() {
    _tickSub?.cancel();
    _keydownSub?.cancel();
    _pointermoveSub?.cancel();
    _pointerupSub?.cancel();
    _resizeSub?.cancel();
    _hintTimer?.cancel();
    _pipWinRef?.close();
    _fpInstance?.destroy();
    super.dispose();
  }

  void _rebuild(void Function() fn) => setState(fn);

  @override
  Component build(BuildContext context) => _buildContent(context);
}
