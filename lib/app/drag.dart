part of '../app.dart';

extension on _AppState {
  // ── Keyboard ──────────────────────────────────────────────────────────────

  void _onKeydown(web.Event e) {
    final ke = e as web.KeyboardEvent;
    if (ke.key == 'Escape') {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      _freezeUntil = nowMs + 1200;
      _escapeWatermarkUntilMs = nowMs + 2600;
      _lastActivityMs = nowMs;
      final msgs = _wmMessages['escape']!;
      _rebuild(() {
        _wmCondition = 'escape';
        _wmMessage = msgs[_rng.nextInt(msgs.length)];
      });
      _updatePipWatermark();
    }
  }

  // ── Drag ──────────────────────────────────────────────────────────────────

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
      final p = d.task.pillGrowthFraction(_deadline);
      final bgG = (255 - 217 * p).round().clamp(0, 255);
      final fgR = (44 + 211 * p).round().clamp(0, 255);
      final fgG = (44 + 211 * p).round().clamp(0, 255);
      final fgB = (42 + 213 * p).round().clamp(0, 255);
      el.setAttribute(
        'style',
        'position:absolute;left:0;top:0;'
        'background:rgb(255,$bgG,$bgG);'
        'color:rgb($fgR,$fgG,$fgB);'
        'transform:translate3d(${x.toStringAsFixed(1)}px,${y.toStringAsFixed(1)}px,0);'
        'opacity:1;',
      );
    }

    final (zx, zy) = _zoneCenter;
    final near = sqrt(
          pow(x + d.task.renderWidth / 2 - zx, 2) +
          pow(y + Task.pillHeight / 2 - zy, 2),
        ) < _zoneNearDist;
    if (near != _isDoneZoneNear) {
      _rebuild(() => _isDoneZoneNear = near);
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

    _rebuild(() {
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
}
