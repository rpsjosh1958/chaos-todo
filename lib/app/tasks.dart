part of '../app.dart';

extension on _AppState {
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

    _rebuild(() {
      _tasks.add(Task(
        id: '$nowMs${_rng.nextInt(99999)}',
        text: text, x: x, y: y, vx: vx, vy: vy,
        createdAtMs: nowMs,
      ));
      _updateOldest();
    });
  }

  void _seedTasks() {
    final now = DateTime.now().millisecondsSinceEpoch;
    const samples = [
      ('reply to David', 0.2), ('draft Q3 plan', 1.5),
      ('renew domain', 3.5),   ('call mum', 7.0),
      ('tax paperwork', 14.0), ('fix kitchen tap', 22.0),
      ('write that essay', 0.5), ('send invoice', 2.4),
      ('book dentist', 5.0),
    ];
    _rebuild(() {
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
    _rebuild(() {
      _tasks.clear();
      _oldestId = null;
      _cachedStressLevel = 0;
      _recentAddMs.clear();
      _recentCompleteMs.clear();
      _lastActivityMs = DateTime.now().millisecondsSinceEpoch;
    });
    _syncPipStructure();
  }

  void _startDying(Task t, double pillCx, double pillCy) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final (zx, zy) = _zoneCenter;
    t.isDying = true;
    t.dyingStartMs = nowMs;
    t.dyingToX = zx;
    t.dyingToY = zy;
    t.dyingStartAngle = atan2(pillCy - zy, pillCx - zx);
    t.dyingStartRadius = sqrt(pow(pillCx - zx, 2) + pow(pillCy - zy, 2));
    t.dyingInitialW = t.renderWidth;
    t.dyingInitialScale = 1.0;
    t.dyingInitialP = t.pillGrowthFraction(_deadline);
    _completedTasks.add(CompletedTask(text: t.text, completedAtMs: nowMs));
  }
}
