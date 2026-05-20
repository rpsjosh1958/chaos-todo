part of '../app.dart';

extension on _AppState {
  Component _buildContent(BuildContext context) {
    final bgColor = switch (_cachedStressLevel) {
      2 => '#FFE5CC', 1 => '#FFF3E0', _ => '#FAFAF8',
    };

    return div(
      attributes: const {'style': 'position:fixed;inset:0;overflow:hidden;'},
      [
        div(
          id: 'chaos-canvas',
          attributes: {
            'style': 'position:absolute;inset:0;'
                'background:$bgColor;'
                'transition:background 1400ms ease;',
          },
          [for (final t in _tasks) _buildPill(t)],
        ),

        // Watermark — hidden while help is open
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
                'transition:opacity 600ms ease;'
                'opacity:${_wmCondition != null && !_helpOpen ? "1" : "0"};',
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
              [path(attributes: const {'d': 'M4 10.5l4 4 8-8'}, const [])],
            ),
          ],
        ),

        // Tweaks toggle
        div(
          id: 'tweaks-toggle',
          events: {
            'click': (_) {
              _rebuild(() => _tweaksOpen = !_tweaksOpen);
              Timer(Duration.zero, _initFlatpickr);
            },
          },
          [Component.text('⚙')],
        ),

        // PiP toggle (Chrome/Edge only — hidden on unsupported browsers)
        if (_pipSupported)
          div(
            id: 'pip-toggle',
            classes: _pipActive ? 'active' : '',
            events: {'click': (_) => _togglePip()},
            [Component.text('⧉')],
          ),

        // One-time hint bubbles
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

        if (_tweaksOpen) _buildTweaksPanel(),
        if (_helpOpen) _buildHelpPanel(),
      ],
    );
  }

  Component _buildPill(Task t) {
    final isOldest = t.id == _oldestId && !t.isDying;
    final p = t.pillGrowthFraction(_deadline);
    final bgG = (255 - 217 * p).round().clamp(0, 255);
    final fgR = (44 + 211 * p).round().clamp(0, 255);
    final fgG = (44 + 211 * p).round().clamp(0, 255);
    final fgB = (42 + 213 * p).round().clamp(0, 255);

    return div(
      id: 'pill-${t.id}',
      key: ValueKey(t.id),
      classes: isOldest ? 'pill oldest' : 'pill',
      attributes: {
        'style': 'position:absolute;left:0;top:0;'
            'background:rgb(255,$bgG,$bgG);'
            'color:rgb($fgR,$fgG,$fgB);'
            'transform:translate3d(${t.x.toStringAsFixed(1)}px,${t.y.toStringAsFixed(1)}px,0);'
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
              events: {'click': (_) => _rebuild(() => _tweaksOpen = false)},
              [Component.text('×')],
            ),
          ],
        ),

        div(classes: 'tweak-section', [
          div(classes: 'tweak-row', [
            Component.text('drift speed '),
            Component.text('${_driftSpeed.toStringAsFixed(1)}×'),
          ]),
          input(
            type: InputType.range,
            attributes: const {'min': '0', 'max': '3', 'step': '0.1'},
            value: _driftSpeed.toString(),
            onInput: (v) => _rebuild(() => _driftSpeed = (v as num).toDouble()),
          ),
        ]),

        div(classes: 'tweak-section', [
          div(classes: 'tweak-row', [
            Component.text('done by'),
          ]),
          div(classes: 'deadline-row', [
            input(
              key: const ValueKey('deadline-input'),
              type: InputType.text,
              attributes: const {'id': 'deadline-input', 'readonly': 'true'},
            ),
            div(classes: 'deadline-presets', [
              div(
                classes: 'deadline-preset${_deadlinePreset == "2h" ? " active" : ""}',
                events: {'click': (_) => _quickDeadline(const Duration(hours: 2), '2h')},
                [Component.text('2h')],
              ),
              div(
                classes: 'deadline-preset${_deadlinePreset == "2m" ? " active" : ""}',
                events: {'click': (_) => _quickDeadline(const Duration(minutes: 2), '2m')},
                [Component.text('2m')],
              ),
              div(
                classes: 'deadline-preset${_deadlinePreset == "30s" ? " active" : ""}',
                events: {'click': (_) => _quickDeadline(const Duration(seconds: 30), '30s')},
                [Component.text('30s')],
              ),
            ]),
          ]),
        ]),

        div(classes: 'tweak-section', [
          div(classes: 'tweak-row', [
            Component.text('stress at '),
            Component.text('$_stressThreshold tasks'),
          ]),
          input(
            type: InputType.range,
            attributes: const {'min': '3', 'max': '30', 'step': '1'},
            value: _stressThreshold.toString(),
            onInput: (v) => _rebuild(() => _stressThreshold = (v as num).toInt()),
          ),
        ]),

        div(classes: 'tweak-actions', [
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
        ]),

        div(classes: 'tweak-hints', [
          span(classes: 'hint-key', [Component.text('Enter')]),
          Component.text(' add  '),
          span(classes: 'hint-key', [Component.text('Esc')]),
          Component.text(' pause  '),
          span(classes: 'hint-key', [Component.text('dbl-click')]),
          Component.text(' panic'),
        ]),

        div(
          classes: 'tweak-btn ghost tweak-help-btn',
          events: {
            'click': (_) => _rebuild(() {
              _tweaksOpen = false;
              _helpOpen = true;
            }),
          },
          [Component.text('how does this work?')],
        ),
      ],
    );
  }

  Component _buildHelpPanel() {
    return div(
      key: const ValueKey('help-panel'),
      classes: 'help-panel',
      [
        // Header
        div(classes: 'help-header', [
          Component.text('how chaos works'),
          div(
            classes: 'help-close',
            events: {'click': (_) => _rebuild(() => _helpOpen = false)},
            [Component.text('×')],
          ),
        ]),

        div(classes: 'help-body', [

          _helpSection('Adding tasks',
            'Type anything into the field at the top and press Enter. '
            'Your task becomes a floating pill that drifts around the screen.'),

          _helpSection('Deadline & colour',
            'Every pill shares one deadline — set it in Tweaks under Done by. '
            'A newly added task is born white. As time runs out the pill fades to red '
            'and its text turns white.\n\n'
            'The curve stays light for the first half of the window, '
            'then accelerates to red as the deadline approaches. '
            'Picking "2h" means a task added now has two hours before it goes fully red.'),

          _helpSection('Done zone',
            'Drag any pill to the circle in the bottom-right corner and release. '
            'It spirals in and disappears. That\'s it — task done.'),

          _helpSection('Panic  (double-click)',
            'Double-click a pill and it shudders, then bolts off at triple speed. '
            'Useful for tasks you\'re actively choosing to ignore right now.'),

          _helpSection('Freeze  (Esc)',
            'Pressing Escape pauses all pills for about a second. '
            'The watermark shows a brief calming message. Breathe.'),

          _helpSection('Stress level',
            'The background warms as your task count rises. '
            'At the stress threshold (default 12) it shifts to warm cream. '
            'At double the threshold it goes amber. '
            'Adjust the threshold in Tweaks.'),

          _helpSection('Drift speed',
            'The Drift speed slider in Tweaks controls how fast pills wander. '
            'Set it to 0 to freeze them in place, or crank it up for chaos.'),

          _helpSection('Picture-in-Picture',
            'The ⧉ button opens an always-on-top mini window using the '
            'Document Picture-in-Picture API (Chrome/Edge only). '
            'Your tasks will haunt every other window you open.'),

        ]),
      ],
    );
  }

  Component _helpSection(String title, String body) {
    return div(classes: 'help-section', [
      div(classes: 'help-section-title', [Component.text(title)]),
      div(classes: 'help-section-body', [Component.text(body)]),
    ]);
  }
}
