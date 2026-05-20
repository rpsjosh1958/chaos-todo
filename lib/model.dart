import 'dart:math';

class Task {
  final String id;
  final String text;
  double x;
  double y;
  double vx;
  double vy;
  final int createdAtMs;

  bool isHovered;
  bool isDragging;
  int boostUntilMs;
  int shudderUntilMs;
  int nextPanicMs;

  bool isDying;
  int dyingStartMs;
  double dyingToX;
  double dyingToY;
  double dyingStartAngle;
  double dyingStartRadius;
  double dyingInitialW;
  double dyingInitialScale;
  double renderWidth;

  Task({
    required this.id,
    required this.text,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.createdAtMs,
    this.isHovered = false,
    this.isDragging = false,
    this.boostUntilMs = 0,
    this.shudderUntilMs = 0,
    this.nextPanicMs = 0,
    this.isDying = false,
    this.dyingStartMs = 0,
    this.dyingToX = 0,
    this.dyingToY = 0,
    this.dyingStartAngle = 0,
    this.dyingStartRadius = 0,
    this.dyingInitialW = 140,
    this.dyingInitialScale = 1.0,
    this.renderWidth = 140.0,
  });

  static const double baseWidth = 140.0;
  static const double pillHeight = 36.0;

  // Scale grows 1.0 → 2.0 starting 20 s after creation.
  // growthMinutes controls the duration of the growth phase.
  double pillScale(double growthMinutes) {
    const delaySeconds = 20.0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final ageSeconds = (nowMs - createdAtMs) / 1000.0;
    final growthAge = (ageSeconds - delaySeconds).clamp(0.0, double.infinity);
    final u = (growthAge / (growthMinutes * 60.0)).clamp(0.0, 1.0);
    final eased = 1.0 - pow(1.0 - u, 1.8);
    return 1.0 + eased;
  }
}

class DragState {
  final Task task;
  final double offsetX;
  final double offsetY;

  DragState({
    required this.task,
    required this.offsetX,
    required this.offsetY,
  });
}
