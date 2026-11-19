import 'dart:async';
import 'dart:ui';

/// Procreate's multi-finger shortcuts.
enum TouchGesture {
  /// Two-finger tap (repeats while held).
  undo,

  /// Three-finger tap (repeats while held).
  redo,

  /// Three-finger scrub back and forth.
  clearLayer,

  /// Four-finger tap.
  fullScreen,

  /// A quick pinch in.
  fitCanvas,

  /// Three fingers swiped up.
  copyPasteMenu,
}

/// Recognises [TouchGesture]s from raw touches, alongside the pinch that
/// pans and zooms: a tap is short and still, a scrub reverses sideways,
/// a quick pinch closes fast. Times are pointer timestamps.
class TouchGestureTracker {
  TouchGestureTracker({
    required this.onGesture,
    this.tapTime = const Duration(milliseconds: 300),
    this.holdDelay = const Duration(milliseconds: 500),
    this.repeatEvery = const Duration(milliseconds: 120),
  });

  final void Function(TouchGesture gesture) onGesture;
  final Duration tapTime, repeatEvery;

  /// How long two fingers rest before undo repeats (a preference).
  Duration holdDelay;

  /// Movement still counted as a tap, in logical pixels.
  static const slop = 24.0;

  /// A scrub: this many direction changes, each leg at least [scrubLeg].
  static const scrubTurns = 3, scrubLeg = 25.0;

  final Map<int, Offset> _start = {}, _last = {};
  Duration? _began;
  int _most = 0;
  bool _moved = false, _held = false, _done = false;
  Timer? _hold, _repeat;

  // Scrub: the three-finger centroid's sideways legs.
  double? _anchorX;
  int _direction = 0, _turns = 0;

  // Quick pinch: two-finger spread when the second finger landed.
  double? _spread;
  Duration? _pinchStart;

  /// No fingers down.
  bool get idle => _start.isEmpty;

  void down(int pointer, Offset position, Duration time) {
    if (_start.isEmpty) {
      _began = time;
      _most = 0;
      _moved = _held = _done = false;
      _anchorX = null;
      _direction = _turns = 0;
      _spread = null;
    }
    _start[pointer] = position;
    _last[pointer] = position;
    if (_start.length > _most) _most = _start.length;
    if (_start.length == 2) {
      final [a, b] = _last.values.toList();
      _spread = (a - b).distance;
      _pinchStart = time;
    } else {
      _spread = null;
    }
    _anchorX = _start.length == 3 ? _centroidX : null;
    _armHold();
  }

  void move(int pointer, Offset position, Duration time) {
    if (!_start.containsKey(pointer)) return;
    _last[pointer] = position;
    if ((position - _start[pointer]!).distance > slop && !_moved) {
      _moved = true;
      _stopHold();
    }
    if (_start.length == 3 && !_done) _scrub();
  }

  void up(int pointer, Duration time) {
    if (!_start.containsKey(pointer)) return;
    // The first finger off ends a two-finger pinch.
    final spread = _spread, pinchStart = _pinchStart;
    if (spread != null && pinchStart != null && _start.length == 2 && !_done) {
      final [a, b] = _last.values.toList();
      final closed = (a - b).distance;
      if (time - pinchStart < const Duration(milliseconds: 350) &&
          closed < spread * .6 &&
          spread - closed > 60) {
        _done = true;
        onGesture(TouchGesture.fitCanvas);
      }
    }
    _spread = null;
    // Three fingers that went down together: a swipe up, not a scrub.
    // (Android takes three fingers down for a screenshot.)
    if (_most == 3 && _start.length == 3 && !_done) {
      final moves = [for (final id in _start.keys) _last[id]! - _start[id]!];
      if (moves.every((m) => m.dy < -80 && m.dx.abs() < -m.dy * .6)) {
        _done = true;
        onGesture(TouchGesture.copyPasteMenu);
      }
    }
    _start.remove(pointer);
    _last.remove(pointer);
    _stopHold();
    if (_start.isNotEmpty) return;
    final began = _began;
    if (began == null || _moved || _held || _done) return;
    if (time - began > tapTime) return;
    switch (_most) {
      case 2:
        onGesture(TouchGesture.undo);
      case 3:
        onGesture(TouchGesture.redo);
      case 4:
        onGesture(TouchGesture.fullScreen);
    }
  }

  void cancel(int pointer) {
    _start.remove(pointer);
    _last.remove(pointer);
    _moved = true;
    _stopHold();
  }

  void dispose() => _stopHold();

  double get _centroidX =>
      _last.values.fold(0.0, (x, p) => x + p.dx) / _last.length;

  void _scrub() {
    final x = _centroidX, anchor = _anchorX ?? x;
    final leg = x - anchor;
    if (leg.abs() < scrubLeg) return;
    final direction = leg.sign.toInt();
    if (direction != _direction) {
      if (_direction != 0) _turns++;
      _direction = direction;
    }
    _anchorX = x;
    if (_turns >= scrubTurns) {
      _done = true;
      onGesture(TouchGesture.clearLayer);
    }
  }

  /// Two or three still fingers held: undo or redo repeatedly.
  void _armHold() {
    _stopHold();
    final fingers = _start.length;
    if (fingers != 2 && fingers != 3) return;
    _hold = Timer(holdDelay, () {
      if (_moved || _start.length != fingers) return;
      _held = true;
      final gesture = fingers == 2 ? TouchGesture.undo : TouchGesture.redo;
      onGesture(gesture);
      _repeat = Timer.periodic(repeatEvery, (_) => onGesture(gesture));
    });
  }

  void _stopHold() {
    _hold?.cancel();
    _repeat?.cancel();
    _hold = _repeat = null;
  }
}
