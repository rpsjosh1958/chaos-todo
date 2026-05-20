part of '../app.dart';

extension on _AppState {
  // ── Picture-in-Picture ──────────────────────────────────────────────────

  Future<void> _togglePip() async {
    if (_pipActive) {
      _closePip();
      return;
    }
    if (!_pipSupported) return;

    final pipWin = await _docPiP!
        .requestWindow(_PiPReqOpts(width: _pipW, height: _pipH))
        .toDart;

    _pipWinRef = pipWin;
    _pipDoc = pipWin.document as web.Document;

    final styles = web.document.querySelectorAll('style');
    for (var i = 0; i < styles.length; i++) {
      final node = styles.item(i);
      if (node != null) {
        _pipDoc!.head?.appendChild(_pipDoc!.adoptNode(node.cloneNode(true)));
      }
    }

    _pipDoc!.body?.setAttribute('style', 'margin:0;padding:0;overflow:hidden;');

    final canvas = _pipDoc!.createElement('div') as web.HTMLElement;
    _pipDoc!.body?.appendChild(canvas);
    _pipCanvas = canvas;
    _updatePipCanvas();

    _syncPipStructure();

    _pipResizeFn = (() { _updatePipCanvas(); }).toJS;
    pipWin.addEventListener('resize', _pipResizeFn!);

    _pipHideFn = (() { _closePip(); }).toJS;
    pipWin.addEventListener('pagehide', _pipHideFn!);

    _rebuild(() {});
  }

  void _closePip() {
    _pipWinRef?.close();
    _pipWinRef = null;
    _pipDoc = null;
    _pipCanvas = null;
    _pipHideFn = null;
    _pipResizeFn = null;
    _rebuild(() {});
  }

  // ── Flatpickr ────────────────────────────────────────────────────────────

  void _initFlatpickr() {
    final el = web.document.getElementById('deadline-input') as web.HTMLElement?;
    if (el == null) return;
    _fpInstance?.destroy();
    final d = _deadline;
    final defaultStr =
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}:'
        '${d.second.toString().padLeft(2, '0')}';
    _fpInstance = _flatpickr(
      el,
      _FPConfig(
        enableTime: true,
        noCalendar: true,
        enableSeconds: true,
        // ignore: non_constant_identifier_names
        time_24hr: false,
        dateFormat: 'H:i:S',
        defaultDate: defaultStr,
        onChange: ((JSAny dates, JSString dateStr, JSAny fp) {
          final s = dateStr.toDart;
          final parts = s.split(':');
          if (parts.length >= 2) {
            final h = int.tryParse(parts[0]) ?? 0;
            final m = int.tryParse(parts[1]) ?? 0;
            final sec = parts.length >= 3 ? (int.tryParse(parts[2]) ?? 0) : 0;
            final now = DateTime.now();
            var picked = DateTime(now.year, now.month, now.day, h, m, sec);
            if (picked.isBefore(now)) picked = picked.add(const Duration(days: 1));
            _rebuild(() {
              _deadline = picked;
              _deadlinePreset = null;
            });
          }
        }).toJS,
      ),
    );
  }

  void _quickDeadline(Duration d, String label) {
    final picked = DateTime.now().add(d);
    final timeStr =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}:'
        '${picked.second.toString().padLeft(2, '0')}';
    _fpInstance?.setDate(timeStr, false);
    _rebuild(() {
      _deadline = picked;
      _deadlinePreset = label;
    });
  }

  // ── PiP canvas sync ──────────────────────────────────────────────────────

  void _updatePipCanvas() {
    final canvas = _pipCanvas;
    if (canvas == null) return;
    final pw = (_pipWinRef?.innerWidth ?? _pipW).toDouble();
    final ph = (_pipWinRef?.innerHeight ?? _pipH).toDouble();
    final s = min(pw / _vw, ph / _vh);
    final bg = switch (_cachedStressLevel) {
      2 => '#FFE5CC', 1 => '#FFF3E0', _ => '#FAFAF8',
    };
    canvas.setAttribute(
      'style',
      'position:absolute;left:0;top:0;'
      'width:${_vw.toStringAsFixed(0)}px;'
      'height:${_vh.toStringAsFixed(0)}px;'
      'background:$bg;'
      'transform-origin:0 0;'
      'transform:scale($s);',
    );
  }

  void _syncPipStructure() {
    final doc = _pipDoc;
    final canvas = _pipCanvas;
    if (doc == null || canvas == null) return;

    final currentIds = {for (final t in _tasks) t.id};

    final toRemove = <web.Element>[];
    for (var i = 0; i < canvas.children.length; i++) {
      final child = canvas.children.item(i);
      if (child != null && child.id.startsWith('pill-')) {
        if (!currentIds.contains(child.id.substring(5))) toRemove.add(child);
      }
    }
    for (final el in toRemove) { el.remove(); }

    for (final t in _tasks) {
      if (doc.getElementById('pill-${t.id}') == null) {
        final pill = doc.createElement('div') as web.HTMLElement;
        pill.id = 'pill-${t.id}';
        pill.setAttribute('class', 'pill');
        pill.textContent = t.text;
        canvas.appendChild(pill);
      }
    }

    _updatePipWatermark();
  }

  void _updatePipWatermark() {
    final doc = _pipDoc;
    final canvas = _pipCanvas;
    if (doc == null || canvas == null) return;
    var el = doc.getElementById('pip-watermark') as web.HTMLElement?;
    if (el == null) {
      el = doc.createElement('div') as web.HTMLElement;
      el.id = 'pip-watermark';
      canvas.appendChild(el);
    }
    el.textContent = _wmCondition != null ? _wmMessage : '​';
    el.setAttribute(
      'style',
      'position:absolute;top:50%;left:50%;'
      'transform:translate(-50%,-50%);'
      'font-size:clamp(36px,7vw,82px);font-weight:900;'
      'color:rgba(44,44,42,0.055);'
      'white-space:nowrap;pointer-events:none;'
      'user-select:none;-webkit-user-select:none;'
      'letter-spacing:-0.02em;z-index:1;'
      'transition:opacity 1000ms ease;'
      'opacity:${_wmCondition != null ? "1" : "0"};',
    );
  }

  // ── PiP per-pill transforms ───────────────────────────────────────────────

  void _applyPipPillTransform(Task t, double ox, double oy) {
    final doc = _pipDoc;
    if (doc == null) return;
    final el = doc.getElementById('pill-${t.id}') as web.HTMLElement?;
    if (el == null) return;
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

  void _applyPipDyingTransform(Task t, int nowMs) {
    final doc = _pipDoc;
    if (doc == null) return;
    final el = doc.getElementById('pill-${t.id}') as web.HTMLElement?;
    if (el == null) return;
    final elapsed = (nowMs - t.dyingStartMs).clamp(0, _dyingMs).toDouble();
    final u = elapsed / _dyingMs;
    final eased = u * u;
    final ang = t.dyingStartAngle + eased * pi * 2.4;
    final rad = t.dyingStartRadius * (1 - eased);
    final cx = t.dyingToX + cos(ang) * rad;
    final cy = t.dyingToY + sin(ang) * rad;
    final scaleVal = (u < 0.15
        ? 1.0 + u * 1.0
        : 1.15 * (1.0 - (u - 0.15) / 0.85)).clamp(0.0, 2.0);
    final tx = cx - t.dyingInitialW / 2;
    final ty = cy - Task.pillHeight / 2;
    final opacity = (1.0 - u).clamp(0.0, 1.0);
    el.setAttribute(
      'style',
      'position:absolute;left:0;top:0;pointer-events:none;z-index:75;'
      'background:#22C55E;color:#FFFFFF;'
      'transform:translate3d(${tx.toStringAsFixed(1)}px,${ty.toStringAsFixed(1)}px,0)'
      ' scale(${scaleVal.toStringAsFixed(3)});'
      'opacity:${opacity.toStringAsFixed(3)};',
    );
  }
}
