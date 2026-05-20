part of '../app.dart';

const _wmMessages = <String, List<String>>{
  'escape':     ['moment of silence', 'everyone stop', 'okay. breathe.'],
  'on-a-roll':  ['there they go', "satisfying, isn't it", 'look at you go', 'the void thanks you'],
  'rapid-add':  ['productive? or panicking?', 'okay okay okay okay', "we're logging everything, don't worry", 'have you tried a notebook'],
  'empty':      ['nothing to do?', 'be productive', 'time to get to work', 'get the bag'],
  'very-old':   ["that's been there a while huh", 'it remembers you', 'it has a name now', 'older than some friendships'],
  'full-amber': ["we don't talk about this screen", "you're doing amazing sweetie", 'this is a safe space', 'breathe. just breathe.'],
  'near-amber': ['getting spicy in here', 'bold strategy', 'the vibes are shifting', 'management would like a word'],
  'idle':       ['still here?', 'the tasks are waiting too', 'no rush. (there is rush.)', "they've noticed you stopped"],
};

extension on _AppState {
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

  String? _detectWmCondition(int nowMs) {
    if (nowMs < _escapeWatermarkUntilMs) return 'escape';
    if (_recentCompleteMs.length >= 2) return 'on-a-roll';
    if (_recentAddMs.length >= 3) return 'rapid-add';
    final active = _tasks.where((t) => !t.isDying).toList();
    final count = active.length;
    if (count == 0) return 'empty';
    if (active.any((t) => t.pillGrowthFraction(_deadline) > 0.75)) return 'very-old';
    if (count >= _stressThreshold) return 'full-amber';
    if (count >= _stressThreshold - 3) return 'near-amber';
    if (_lastActivityMs > 0 && nowMs - _lastActivityMs > 30000) return 'idle';
    return null;
  }

  void _updateOldest() => _oldestId = _computeOldestId();
}
