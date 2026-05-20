import 'dart:async';
import 'dart:math';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:universal_web/web.dart' as web;
import 'model.dart';

// Physics constants
const double _topBound = 78.0;
const double _zoneR = 40.0;
const double _zoneOffset = 36.0;
const double _zoneNearDist = 120.0;
const double _zoneDropDist = 70.0;
const int _dyingMs = 480;

class App extends StatefulComponent {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final List<Task> _tasks = [];
  DragState? _drag;
  int _freezeUntil = 0;
  bool _isDoneZoneNear = false;
  double _vw = 800;
  double _vh = 600;
  String? _oldestId;
  bool _tweaksOpen = false;
  int _cachedStressLevel = 0;
  bool _showHints = true;
  Timer? _hintTimer;

  // Watermark state
  String? _wmCondition;
  String _wmMessage = '';

  // Activity tracking for watermark conditions
  final List<int> _recentAddMs = [];
  final List<int> _recentCompleteMs = [];
  int _lastActivityMs = 0;
  int _escapeWatermarkUntilMs = 0;

  // Tweakable settings
  double _driftSpeed = 1.0;
  double _growthMinutes = 1.0;
  int _stressThreshold = 12;

  StreamSubscription<int>? _tickSub;
  StreamSubscription<web.Event>? _keydownSub;
  StreamSubscription<web.Event>? _pointermoveSub;
  StreamSubscription<web.Event>? _pointerupSub;
  StreamSubscription<web.Event>? _resizeSub;

  final _rng = Random();
  int _lastClassSyncMs = 0;

  static const _wmMessages = <String, List<String>>{
    'escape': [
      'moment of silence',
      'everyone stop',
      'okay. breathe.',
    ],
    'on-a-roll': [
      'there they go',
      "satisfying, isn't it",
      'look at you go',
      'the void thanks you',
    ],
    'rapid-add': [
      'productive? or panicking?',
      'okay okay okay okay',
      "we're logging everything, don't worry",
      'have you tried a notebook',
    ],
    'empty': [
      'nothing to do?',
    ],
    'very-old': [
      "that's been there a while huh",
      'it remembers you',
      'it has a name now',
      'older than some friendships',
    ],
    'full-amber': [
      "we don't talk about this screen",
      "you're doing amazing sweetie",
      'this is a safe space',
      'breathe. just breathe.',
    ],
    'near-amber': [
      'getting spicy in here',
      'bold strategy',
      'the vibes are shifting',
      'management would like a word',
    ],
    'idle': [
      'still here?',
      'the tasks are waiting too',
      'no rush. (there is rush.)',
      "they've noticed you stopped",
    ],
  };

  @override
  void initState() {
    super.initState();
    _vw = web.window.innerWidth.toDouble();
    _vh = web.window.innerHeight.toDouble();
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
    super.dispose();
  }

  // ── Physics tick ──────────────────────────────────────────────────────────

  void _tick() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final frozen = nowMs < _freezeUntil;
    bool structureChanged = false;

    for (var i = _tasks.length - 1; i >= 0; i--) {
      final t = _tasks[i];

      if (t.isDying) {
        final elapsed = nowMs - t.dyingStartMs;
        if (elapsed >= _dyingMs) {
          _tasks.removeAt(i);
          structureChanged = true;
          continue;
        }
        _applyDyingTransform(t, nowMs);
        continue;
      }

      final scale = t.pillScale(_growthMinutes);

      if (!t.isDragging && !frozen) {
        double mult = _driftSpeed;
        if (nowMs < t.boostUntilMs) mult *= 3.0;
        if (t.isHovered) mult *= 0.04;

        t.x += t.vx * mult;
        t.y += t.vy * mult;

        // Boundary — account for visual extents after CSS scale(factor)
        final scaledHalfW = t.renderWidth * scale / 2;
        final scaledHalfH = Task.pillHeight * scale / 2;
        final centerX = t.x + t.renderWidth / 2;
        final centerY = t.y + Task.pillHeight / 2;

        if (centerX - scaledHalfW < 0) {
          t.x = scaledHalfW - t.renderWidth / 2;
          t.vx = t.vx.abs();
        }
        if (centerX + scaledHalfW > _vw) {
          t.x = _vw - scaledHalfW - t.renderWidth / 2;
          t.vx = -t.vx.abs();
        }
        if (centerY - scaledHalfH < _topBound) {
          t.y = _topBound + scaledHalfH - Task.pillHeight / 2;
          t.vy = t.vy.abs();
        }
        if (centerY + scaledHalfH > _vh) {
          t.y = _vh - scaledHalfH - Task.pillHeight / 2;
          t.vy = -t.vy.abs();
        }
      }

      // Shudder offset
      double ox = 0, oy = 0;
      if (nowMs < t.shudderUntilMs) {
        ox = (_rng.nextDouble() - 0.5) * 5;
        oy = (_rng.nextDouble() - 0.5) * 5;
      }

      _applyPillTransform(t, ox, oy, scale);
    }

    if (structureChanged) {
      setState(() => _updateOldest());
      return;
    }

    // Low-frequency class sync (~500ms)
    if (nowMs - _lastClassSyncMs > 500) {
      _lastClassSyncMs = nowMs;

      // Prune stale timestamps
      _recentAddMs.removeWhere((t) => nowMs - t > 12000);
      _recentCompleteMs.removeWhere((t) => nowMs - t > 8000);

      final newOldest = _computeOldestId();
      final newStress = _computeStressLevel();
      final newCondition = _detectWmCondition(nowMs);

      final changed = newOldest != _oldestId ||
          newStress != _cachedStressLevel ||
          newCondition != _wmCondition;

      if (changed) {
        setState(() {
          _oldestId = newOldest;
          _cachedStressLevel = newStress;
          if (newCondition != _wmCondition) {
            _wmCondition = newCondition;
            if (newCondition != null) {
              final msgs = _wmMessages[newCondition]!;
              _wmMessage = msgs[_rng.nextInt(msgs.length)];
            }
          }
        });
      }
    }
  }

  void _applyPillTransform(Task t, double ox, double oy, double scale) {
    final el = web.document.getElementById('pill-${t.id}') as web.HTMLElement?;
    if (el == null) return;
    final rw = el.offsetWidth.toDouble();
    if (rw > 0) t.renderWidth = rw;
    final p = (scale - 1.0).clamp(0.0, 1.0);
    final g = (255 - 155 * p).round();
    final b = (255 - 165 * p).round();
    el.setAttribute(
      'style',
      'position:absolute;left:0;top:0;'
      'background:rgb(255,$g,$b);'
      'transform:translate3d(${(t.x + ox).toStringAsFixed(1)}px,${(t.y + oy).toStringAsFixed(1)}px,0)'
      ' scale(${scale.toStringAsFixed(3)});'
      'opacity:1;',
    );
  }

  void _applyDyingTransform(Task t, int nowMs) {
    final el = web.document.getElementById('pill-${t.id}') as web.HTMLElement?;
    if (el == null) return;
    final elapsed = (nowMs - t.dyingStartMs).clamp(0, _dyingMs).toDouble();
    final u = elapsed / _dyingMs;
    final eased = u * u;
    final ang = t.dyingStartAngle + eased * pi * 2.4;
    final rad = t.dyingStartRadius * (1 - eased);
    final cx = t.dyingToX + cos(ang) * rad;
    final cy = t.dyingToY + sin(ang) * rad;
    final scaleVal = (t.dyingInitialScale * (1.0 - eased)).clamp(0.0, t.dyingInitialScale);
    final tx = cx - t.dyingInitialW / 2;
    final ty = cy - Task.pillHeight / 2;
    final opacity = (1.0 - u).clamp(0.0, 1.0);
    final p = (t.dyingInitialScale - 1.0).clamp(0.0, 1.0);
    final g = (255 - 155 * p).round();
    final b = (255 - 165 * p).round();
    el.setAttribute(
      'style',
      'position:absolute;left:0;top:0;pointer-events:none;z-index:60;'
      'background:rgb(255,$g,$b);'
      'transform:translate3d(${tx.toStringAsFixed(1)}px,${ty.toStringAsFixed(1)}px,0)'
      ' scale(${scaleVal.toStringAsFixed(3)});'
      'opacity:${opacity.toStringAsFixed(3)};',
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String? _computeOldestId() {
    Task? oldest;
    for (final t in _tasks) {
      if (t.isDying) continue;
      if (oldest == null || t.createdAtMs < oldest.createdAtMs) oldest = t;
    }
    return oldest?.id;
  }

  int _computeStressLevel() {
    final count = _tasks.where((t) => !t.isDying).length;
    if (count >= _stressThreshold * 2) return 2;
    if (count >= _stressThreshold) return 1;
    return 0;
  }

  // Returns the highest-priority watermark condition key, or null.
  // Priority: escape > on-a-roll > rapid-add > empty > very-old >
  //           full-amber > near-amber > idle
  String? _detectWmCondition(int nowMs) {
    if (nowMs < _escapeWatermarkUntilMs) return 'escape';

    if (_recentCompleteMs.length >= 2) return 'on-a-roll';

    if (_recentAddMs.length >= 3) return 'rapid-add';

    final active = _tasks.where((t) => !t.isDying).toList();
    final count = active.length;

    if (count == 0) return 'empty';

    final hasVeryLargePill =
        active.any((t) => t.pillScale(_growthMinutes) > 1.75);
    if (hasVeryLargePill) return 'very-old';

    if (count >= _stressThreshold) return 'full-amber';

    if (count >= _stressThreshold - 3) return 'near-amber';

    if (_lastActivityMs > 0 && nowMs - _lastActivityMs > 30000) return 'idle';

    return null;
  }

  void _updateOldest() => _oldestId = _computeOldestId();

  (double, double) get _zoneCenter =>
      (_vw - _zoneOffset - _zoneR, _vh - _zoneOffset - _zoneR);

  // ── Task management ───────────────────────────────────────────────────────

  void _addTask(String text) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _recentAddMs.add(nowMs);
    _lastActivityMs = nowMs;

    final x = _vw * (0.15 + _rng.nextDouble() * 0.55) - 70;
    final yRange = (_vh - _topBound - 170).clamp(80.0, double.infinity);
    final y = _topBound + 50 + _rng.nextDouble() * yRange;

    final angle = _rng.nextDouble() * pi * 2;
    final speed = 0.35 + _rng.nextDouble() * 0.25;
    double vx = cos(angle) * speed;
    double vy = sin(angle) * speed;
    if (vx.abs() < 0.18) vx = vx < 0 ? -0.18 : 0.18;
    if (vy.abs() < 0.18) vy = vy < 0 ? -0.18 : 0.18;

    setState(() {
      _tasks.add(Task(
        id: '$nowMs${_rng.nextInt(99999)}',
        text: text,
        x: x,
        y: y,
        vx: vx,
        vy: vy,
        createdAtMs: nowMs,
      ));
      _updateOldest();
    });
  }

  void _seedTasks() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final samples = [
      ('reply to David', 0.2), ('draft Q3 plan', 1.5),
      ('renew domain', 3.5),   ('call mum', 7.0),
      ('tax paperwork', 14.0), ('fix kitchen tap', 22.0),
      ('write that essay', 0.5), ('send invoice', 2.4),
      ('book dentist', 5.0),
    ];
    setState(() {
      for (final (text, ageMin) in samples) {
        final angle = _rng.nextDouble() * pi * 2;
        final speed = 0.35 + _rng.nextDouble() * 0.25;
        double vx = cos(angle) * speed;
        double vy = sin(angle) * speed;
        if (vx.abs() < 0.18) vx = vx < 0 ? -0.18 : 0.18;
        if (vy.abs() < 0.18) vy = vy < 0 ? -0.18 : 0.18;
        final x = _vw * (0.15 + _rng.nextDouble() * 0.55) - 70;
        final yRange = (_vh - _topBound - 170).clamp(80.0, double.infinity);
        final y = _topBound + 50 + _rng.nextDouble() * yRange;
        _tasks.add(Task(
          id: '${now - (ageMin * 60000).toInt()}${_rng.nextInt(9999)}',
          text: text, x: x, y: y, vx: vx, vy: vy,
          createdAtMs: now - (ageMin * 60000).toInt(),
        ));
      }
      _updateOldest();
    });
  }

  void _clearAll() {
    setState(() {
      _tasks.clear();
      _oldestId = null;
      _cachedStressLevel = 0;
      _recentAddMs.clear();
      _recentCompleteMs.clear();
      _lastActivityMs = DateTime.now().millisecondsSinceEpoch;
    });
  }

  void _startDying(Task t, double pillCx, double pillCy) {
    final (zx, zy) = _zoneCenter;
    t.isDying = true;
    t.dyingStartMs = DateTime.now().millisecondsSinceEpoch;
    t.dyingToX = zx;
    t.dyingToY = zy;
    t.dyingStartAngle = atan2(pillCy - zy, pillCx - zx);
    t.dyingStartRadius = sqrt(pow(pillCx - zx, 2) + pow(pillCy - zy, 2));
    t.dyingInitialW = t.renderWidth;
    t.dyingInitialScale = t.pillScale(_growthMinutes);
  }

  // ── Keyboard ─────────────────────────────────────────────────────────────

  void _onKeydown(web.Event e) {
    final ke = e as web.KeyboardEvent;
    if (ke.key == 'Escape') {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _freezeUntil = nowMs + 1200;
      _escapeWatermarkUntilMs = nowMs + 2600;
      _lastActivityMs = nowMs;
      final msgs = _wmMessages['escape']!;
      setState(() {
        _wmCondition = 'escape';
        _wmMessage = msgs[_rng.nextInt(msgs.length)];
      });
    }
  }

  // ── Drag ─────────────────────────────────────────────────────────────────

  void _onPillMouseDown(Task t, web.Event e) {
    if (t.isDying) return;
    final me = e as web.MouseEvent;
    if (me.button != 0) return;
    e.preventDefault();

    _lastActivityMs = DateTime.now().millisecondsSinceEpoch;
    t.isDragging = true;
    _drag = DragState(
      task: t,
      offsetX: me.clientX.toDouble() - t.x,
      offsetY: me.clientY.toDouble() - t.y,
    );

    (web.document.getElementById('pill-${t.id}') as web.HTMLElement?)
        ?.classList.add('dragging');
  }

  void _onWinMouseMove(web.Event e) {
    final d = _drag;
    if (d == null) return;
    final me = e as web.MouseEvent;

    final x = me.clientX.toDouble() - d.offsetX;
    final y = me.clientY.toDouble() - d.offsetY;
    d.task.x = x;
    d.task.y = y;

    final el = web.document.getElementById('pill-${d.task.id}') as web.HTMLElement?;
    if (el != null) {
      final scale = d.task.pillScale(_growthMinutes);
      final p = (scale - 1.0).clamp(0.0, 1.0);
      final g = (255 - 155 * p).round();
      final b = (255 - 165 * p).round();
      el.setAttribute(
        'style',
        'position:absolute;left:0;top:0;'
        'background:rgb(255,$g,$b);'
        'transform:translate3d(${x.toStringAsFixed(1)}px,${y.toStringAsFixed(1)}px,0)'
        ' scale(${scale.toStringAsFixed(3)});'
        'opacity:1;',
      );
    }

    final (zx, zy) = _zoneCenter;
    final near = sqrt(
          pow(x + d.task.renderWidth / 2 - zx, 2) +
          pow(y + Task.pillHeight / 2 - zy, 2),
        ) < _zoneNearDist;
    if (near != _isDoneZoneNear) {
      setState(() => _isDoneZoneNear = near);
    }
  }

  void _onWinMouseUp(web.Event e) {
    final d = _drag;
    if (d == null) return;

    final t = d.task;
    final pillCx = t.x + t.renderWidth / 2;
    final pillCy = t.y + Task.pillHeight / 2;
    final (zx, zy) = _zoneCenter;
    final dist = sqrt(pow(pillCx - zx, 2) + pow(pillCy - zy, 2));

    t.isDragging = false;
    _drag = null;

    (web.document.getElementById('pill-${t.id}') as web.HTMLElement?)
        ?.classList.remove('dragging');

    if (dist < _zoneDropDist) {
      _recentCompleteMs.add(DateTime.now().millisecondsSinceEpoch);
      _lastActivityMs = DateTime.now().millisecondsSinceEpoch;
    }

    setState(() {
      _isDoneZoneNear = false;
      if (dist < _zoneDropDist) {
        _startDying(t, pillCx, pillCy);
        _updateOldest();
      } else {
        final ang = _rng.nextDouble() * pi * 2;
        final sp = 0.4 + _rng.nextDouble() * 0.3;
        t.vx = cos(ang) * sp;
        t.vy = sin(ang) * sp;
        if (t.vx.abs() < 0.18) t.vx = t.vx < 0 ? -0.18 : 0.18;
        if (t.vy.abs() < 0.18) t.vy = t.vy < 0 ? -0.18 : 0.18;
      }
    });
  }

  void _onPillDoubleClick(Task t) {
    if (t.isDying) return;
    _lastActivityMs = DateTime.now().millisecondsSinceEpoch;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    t.shudderUntilMs = nowMs + 600;
    t.boostUntilMs = nowMs + 600 + 3000;
    final ang = atan2(t.vy, t.vx) + (_rng.nextDouble() - 0.5) * 0.4;
    final sp = 0.55 + _rng.nextDouble() * 0.25;
    t.vx = cos(ang) * sp;
    t.vy = sin(ang) * sp;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Component build(BuildContext context) {
    final bgColor = switch (_cachedStressLevel) {
      2 => '#FFE5CC',
      1 => '#FFF3E0',
      _ => '#FAFAF8',
    };

    return div(
      attributes: const {'style': 'position:fixed;inset:0;overflow:hidden;'},
      [
        // Canvas
        div(
          id: 'chaos-canvas',
          attributes: {
            'style': 'position:absolute;inset:0;'
                'background:$bgColor;'
                'transition:background 1400ms ease;',
          },
          [for (final t in _tasks) _buildPill(t)],
        ),

        // Watermark — persistent element, opacity-transitioned
        div(
          key: const ValueKey('watermark'),
          attributes: {
            'style': 'position:fixed;top:50%;left:50%;'
                'transform:translate(-50%,-50%);'
                'font-size:clamp(36px,7vw,82px);font-weight:900;'
                'color:rgba(44,44,42,0.055);'
                'white-space:nowrap;pointer-events:none;'
                'user-select:none;-webkit-user-select:none;'
                'letter-spacing:-0.02em;z-index:1;'
                'transition:opacity 1000ms ease;'
                'opacity:${_wmCondition != null ? "1" : "0"};',
          },
          [Component.text(_wmCondition != null ? _wmMessage : '​')],
        ),

        // Input
        input(
          id: 'chaos-input',
          classes: 'chaos-input',
          attributes: const {
            'autocomplete': 'off',
            'autocorrect': 'off',
            'spellcheck': 'false',
            'placeholder': 'what needs doing?',
          },
          events: {
            'keydown': (e) {
              final ke = e as web.KeyboardEvent;
              if (ke.key != 'Enter') return;
              ke.preventDefault();
              final el = web.document.getElementById('chaos-input')
                  as web.HTMLInputElement?;
              final text = el?.value.trim() ?? '';
              if (text.isNotEmpty) {
                _addTask(text);
                if (el != null) el.value = '';
              }
            },
          },
        ),

        // Done zone
        div(
          id: 'done-zone',
          classes: 'done-zone${_isDoneZoneNear ? ' near' : ''}',
          [
            svg(
              attributes: const {
                'width': '20', 'height': '20', 'viewBox': '0 0 20 20',
                'fill': 'none', 'stroke': 'currentColor',
                'stroke-width': '1.5', 'stroke-linecap': 'round',
                'stroke-linejoin': 'round',
              },
              [
                path(
                  attributes: const {'d': 'M4 10.5l4 4 8-8'},
                  const [],
                ),
              ],
            ),
          ],
        ),

        // Tweaks toggle
        div(
          id: 'tweaks-toggle',
          events: {
            'click': (_) => setState(() => _tweaksOpen = !_tweaksOpen),
          },
          [Component.text('⚙')],
        ),

        // One-time hint bubbles (visible ~3.8 s)
        if (_showHints) ...[
          div(
            key: const ValueKey('hint-tweak'),
            classes: 'hint-bubble',
            attributes: const {'style': 'bottom:62px;left:78px;'},
            [Component.text('tweak things')],
          ),
          div(
            key: const ValueKey('hint-done'),
            classes: 'hint-bubble',
            attributes: const {'style': 'bottom:62px;right:124px;'},
            [Component.text('drop here when done →')],
          ),
        ],

        // Tweaks panel
        if (_tweaksOpen) _buildTweaksPanel(),
      ],
    );
  }

  Component _buildPill(Task t) {
    final isOldest = t.id == _oldestId && !t.isDying;
    final scale = t.pillScale(_growthMinutes);
    final p = (scale - 1.0).clamp(0.0, 1.0);
    final g = (255 - 155 * p).round();
    final b = (255 - 165 * p).round();

    return div(
      id: 'pill-${t.id}',
      key: ValueKey(t.id),
      classes: isOldest ? 'pill oldest' : 'pill',
      attributes: {
        'style': 'position:absolute;left:0;top:0;'
            'background:rgb(255,$g,$b);'
            'transform:translate3d(${t.x.toStringAsFixed(1)}px,${t.y.toStringAsFixed(1)}px,0)'
            ' scale(${scale.toStringAsFixed(3)});'
            'opacity:1;',
      },
      events: {
        'mousedown': (e) => _onPillMouseDown(t, e),
        'mouseenter': (_) => t.isHovered = true,
        'mouseleave': (_) => t.isHovered = false,
        'dblclick': (_) => _onPillDoubleClick(t),
      },
      [Component.text(t.text)],
    );
  }

  Component _buildTweaksPanel() {
    return div(
      id: 'tweaks-panel',
      [
        div(
          classes: 'tweaks-header',
          [
            Component.text('Tweaks'),
            div(
              classes: 'tweaks-close',
              events: {'click': (_) => setState(() => _tweaksOpen = false)},
              [Component.text('×')],
            ),
          ],
        ),

        // Drift speed
        div(
          classes: 'tweak-section',
          [
            div(classes: 'tweak-row', [
              Component.text('drift speed '),
              Component.text('${_driftSpeed.toStringAsFixed(1)}×'),
            ]),
            input(
              type: InputType.range,
              attributes: const {'min': '0', 'max': '3', 'step': '0.1'},
              value: _driftSpeed.toString(),
              onInput: (v) =>
                  setState(() => _driftSpeed = (v as num).toDouble()),
            ),
          ],
        ),

        // Growth rate
        div(
          classes: 'tweak-section',
          [
            div(classes: 'tweak-row', [
              Component.text('growth over '),
              Component.text('${_growthMinutes.toStringAsFixed(1)} min'),
            ]),
            input(
              type: InputType.range,
              attributes: const {'min': '0.1', 'max': '5', 'step': '0.1'},
              value: _growthMinutes.toString(),
              onInput: (v) =>
                  setState(() => _growthMinutes = (v as num).toDouble()),
            ),
          ],
        ),

        // Stress threshold
        div(
          classes: 'tweak-section',
          [
            div(classes: 'tweak-row', [
              Component.text('stress at '),
              Component.text('$_stressThreshold tasks'),
            ]),
            input(
              type: InputType.range,
              attributes: const {'min': '3', 'max': '30', 'step': '1'},
              value: _stressThreshold.toString(),
              onInput: (v) =>
                  setState(() => _stressThreshold = (v as num).toInt()),
            ),
          ],
        ),

        // Action buttons
        div(
          classes: 'tweak-actions',
          [
            div(
              classes: 'tweak-btn',
              events: {'click': (_) => _seedTasks()},
              [Component.text('seed tasks')],
            ),
            div(
              classes: 'tweak-btn ghost',
              events: {'click': (_) => _clearAll()},
              [Component.text('clear all')],
            ),
          ],
        ),

        div(
          classes: 'tweak-hints',
          [
            span(classes: 'hint-key', [Component.text('↵')]),
            Component.text(' add  '),
            span(classes: 'hint-key', [Component.text('Esc')]),
            Component.text(' pause  '),
            span(classes: 'hint-key', [Component.text('dbl-click')]),
            Component.text(' panic'),
          ],
        ),
      ],
    );
  }
}
