part of '../app.dart';

extension on _AppState {
  // ── Per-frame transforms ──────────────────────────────────────────────────

  void _applyPillTransform(Task t, double ox, double oy) {
    final el = web.document.getElementById('pill-${t.id}') as web.HTMLElement?;
    if (el == null) return;
    final rw = el.offsetWidth.toDouble();
    if (rw > 0) t.renderWidth = rw;
    final p = t.pillGrowthFraction(_deadline);
    final bgG = (255 - 217 * p).round().clamp(0, 255);
    final fgR = (44 + 211 * p).round().clamp(0, 255);
    final fgG = (44 + 211 * p).round().clamp(0, 255);
    final fgB = (42 + 213 * p).round().clamp(0, 255);
    el.setAttribute(
      'style',
      'position:absolute;left:0;top:0;'
      'background:rgb(255,$bgG,$bgG);'
      'color:rgb($fgR,$fgG,$fgB);'
      'transform:translate3d(${(t.x + ox).toStringAsFixed(1)}px,${(t.y + oy).toStringAsFixed(1)}px,0);'
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
    final scaleVal = (1.0 - eased).clamp(0.0, 1.0);
    final tx = cx - t.dyingInitialW / 2;
    final ty = cy - Task.pillHeight / 2;
    final opacity = (1.0 - u).clamp(0.0, 1.0);
    final p = t.dyingInitialP;
    final bgG = (255 - 217 * p).round().clamp(0, 255);
    final fgR = (44 + 211 * p).round().clamp(0, 255);
    final fgG = (44 + 211 * p).round().clamp(0, 255);
    final fgB = (42 + 213 * p).round().clamp(0, 255);
    el.setAttribute(
      'style',
      'position:absolute;left:0;top:0;pointer-events:none;z-index:60;'
      'background:rgb(255,$bgG,$bgG);'
      'color:rgb($fgR,$fgG,$fgB);'
      'transform:translate3d(${tx.toStringAsFixed(1)}px,${ty.toStringAsFixed(1)}px,0)'
      ' scale(${scaleVal.toStringAsFixed(3)});'
      'opacity:${opacity.toStringAsFixed(3)};',
    );
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
        _applyPipDyingTransform(t, nowMs);
        continue;
      }

      if (!t.isDragging && !frozen) {
        double mult = _driftSpeed;
        if (nowMs < t.boostUntilMs) mult *= 3.0;
        if (t.isHovered) mult *= 0.04;

        t.x += t.vx * mult;
        t.y += t.vy * mult;

        if (t.x < 0) { t.x = 0; t.vx = t.vx.abs(); }
        if (t.x + t.renderWidth > _vw) { t.x = _vw - t.renderWidth; t.vx = -t.vx.abs(); }
        if (t.y < _topBound) { t.y = _topBound; t.vy = t.vy.abs(); }
        if (t.y + Task.pillHeight > _vh) { t.y = _vh - Task.pillHeight; t.vy = -t.vy.abs(); }
      }

      double ox = 0, oy = 0;
      if (nowMs < t.shudderUntilMs) {
        ox = (_rng.nextDouble() - 0.5) * 5;
        oy = (_rng.nextDouble() - 0.5) * 5;
      }

      _applyPillTransform(t, ox, oy);
      _applyPipPillTransform(t, ox, oy);
    }

    if (structureChanged) {
      _syncPipStructure();
      _rebuild(() => _updateOldest());
      return;
    }

    if (nowMs - _lastClassSyncMs > 500) {
      _lastClassSyncMs = nowMs;

      _recentAddMs.removeWhere((t) => nowMs - t > 12000);
      _recentCompleteMs.removeWhere((t) => nowMs - t > 8000);

      final newOldest = _computeOldestId();
      final newStress = _computeStressLevel();
      final newCondition = _detectWmCondition(nowMs);

      final changed = newOldest != _oldestId ||
          newStress != _cachedStressLevel ||
          newCondition != _wmCondition;

      if (changed) {
        _rebuild(() {
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
        _updatePipCanvas();
        _updatePipWatermark();
      }
    }
  }
}
