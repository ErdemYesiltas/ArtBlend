import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/document.dart';
import '../drawing/adjustments.dart';
import '../drawing/brush_engine.dart';
import '../drawing/guides.dart';
import '../drawing/layer_transform.dart';
import '../drawing/symmetry.dart';
import '../drawing/text_layer.dart';
import 'canvas_crop.dart';
import 'canvas_navigation.dart';
import 'touch_gestures.dart';
import 'pen_probe.dart';
import 'quick_menu.dart';
import 'studio_controller.dart';

class DrawingSurface extends StatefulWidget {
  const DrawingSurface({
    super.key,
    required this.controller,
    required this.engine,
    required this.transformation,
    this.onQuickAction,
  });
  final StudioController controller;
  final BrushEngine engine;
  final TransformationController transformation;

  /// A QuickMenu button chosen by sliding the held finger onto it.
  final void Function(QuickAction action)? onQuickAction;
  @override
  State<DrawingSurface> createState() => DrawingSurfaceState();
}

class DrawingSurfaceState extends State<DrawingSurface> {
  int? _drawingPointer, _selectionPointer, _pickPointer;

  /// A sideways drag that changes the open adjustment's amount.
  int? _swipePointer;
  double _swipeX = 0;

  /// QuickShape: the pen held still (for the preference's delay) becomes
  /// a shape. A second finger then makes it perfect; Edit Shape drags its
  /// nodes.
  Timer? _holdTimer;
  Offset? _holdAt;
  int? _perfectPointer, _nodePointer, _nodeIndex;

  /// Pointers on the canvas; while any is, the bars over it fade.
  final Set<int> _engaged = {};

  void _release(int pointer) {
    _engaged.remove(pointer);
    if (_engaged.isEmpty) widget.controller.canvasEngaged.value = false;
  }

  /// The pointer liquifying.
  int? _liquifyPointer;

  /// Where and when the selection pointer went down: a tap places a
  /// polygon corner; automatic selection's threshold follows the slide.
  Offset? _selectionDown;
  double _autoThresholdStart = 0;

  /// The pointer dragging Clone's source disc.
  int? _discPointer;

  /// Edit Drawing Guide: the pointer on a guide point, and which (a
  /// vanishing point's index, or -1 the symmetry centre).
  int? _guidePointer;
  int _guideHandle = 0;

  /// Crop & Resize: the pointer on the crop, what it holds (a handle, -1
  /// the whole), and where it began.
  int? _cropPointer;

  /// Moves (or, by its handle, widens) the text box being edited.
  int? _textPointer;
  bool _textWiden = false;
  Offset _textFrom = Offset.zero;
  LayerText? _textStart;
  int _cropHandle = -1;
  Offset _cropFrom = Offset.zero;
  Rect _cropStart = Rect.zero;
  double _cropReach = 0;

  /// Motion Blur's slide start, and Perspective Blur's centre being moved,
  /// in document pixels.
  Offset? _slideStart;
  int? _centrePointer;
  final Set<int> _touches = {};
  bool _stylusDown = false;
  final Map<InkStroke, ui.Path> _paths = {};
  String? _documentId;

  /// A transform gesture: the draft and focal point it started from (again
  /// whenever fingers are added or lifted), and what one finger holds.
  LayerTransform? _gestureDraft;
  Offset? _gestureFocal, _transformDown;

  /// Snapping skips fast drags: the last focal point (screen) and when.
  Offset? _lastFocal;
  final Stopwatch _focalClock = Stopwatch()..start();
  Duration _lastFocalAt = Duration.zero;
  int _gesturePointers = 0;
  _Grab? _grab;
  final _canvasKey = GlobalKey();

  /// Navigation: touches by pointer (workspace pixels), and the gesture
  /// they began with — two fingers in any tool, one in the pan tool.
  final Map<int, Offset> _navPoints = {};
  Map<int, Offset>? _navFrom;
  Matrix4? _navStart;
  Size _workspace = Size.zero;

  TransformationController get _view => widget.transformation;

  /// Multi-finger shortcuts; the view as it was when the fingers landed,
  /// so a tap's tiny pinch drift is undone with it.
  late final _gestures = TouchGestureTracker(onGesture: _gesture);
  Matrix4? _viewBeforeGesture;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _quickTimer?.cancel();
    _gestures.dispose();
    super.dispose();
  }

  /// (Re)starts the wait for the pen to stay still at [at] (screen).
  void _armHold(Offset at) {
    _holdAt = at;
    _holdTimer?.cancel();
    final delay = widget.controller.quickShapeDelay;
    if (delay <= 0) return;
    _holdTimer = Timer(Duration(milliseconds: (delay * 1000).round()), () {
      if (_drawingPointer == null) return;
      widget.controller.holdStroke(
        perfect: HardwareKeyboard.instance.isShiftPressed,
      );
    });
  }

  /// Document pixels per [screen] pixels at the pointer of [event].
  double _documentReach(PointerEvent event, double scale, double screen) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return screen / scale;
    return (box.globalToLocal(event.position + Offset(screen, 0)) -
                box.globalToLocal(event.position))
            .distance /
        scale;
  }

  void _gesture(TouchGesture gesture) {
    final c = widget.controller;
    final before = _viewBeforeGesture;
    if (gesture != TouchGesture.fitCanvas && before != null) {
      _view.value = before;
    }
    switch (gesture) {
      case TouchGesture.undo:
        c.undo();
      case TouchGesture.redo:
        c.redo();
      case TouchGesture.clearLayer:
        unawaited(c.clearActiveLayer());
      case TouchGesture.fullScreen:
        if (c.quickMenuTrigger == QuickMenuTrigger.fourFingerTap) {
          final box = context.findRenderObject() as RenderBox?;
          c.openQuickMenu(
            box?.localToGlobal(box.size.center(Offset.zero)) ?? Offset.zero,
          );
        } else {
          c.toggleFullScreen();
        }
      case TouchGesture.fitCanvas:
        _view.value = Matrix4.identity();
      case TouchGesture.copyPasteMenu:
        c.showCopyPasteMenu();
    }
    // A gesture made, the fingers that made it pan nothing more.
    _navFrom = null;
    _navStart = null;
  }

  void _gestureDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch || _stylusDown) return;
    if (!widget.controller.touchGestures) return;
    _gestures.holdDelay = Duration(
      milliseconds: (widget.controller.undoDelay * 1000).round(),
    );
    if (event.pointer == _perfectPointer || event.pointer == _nodePointer) {
      return;
    }
    if (widget.controller.transformDraft != null) return;
    if (_gestures.idle) _viewBeforeGesture = _view.value.clone();
    _gestures.down(event.pointer, event.localPosition, event.timeStamp);
  }

  void _navDown(PointerDownEvent event) {
    final c = widget.controller;
    final panTool = c.tool == StudioTool.pan;
    if (event.pointer == _perfectPointer || event.pointer == _nodePointer) {
      return;
    }
    if (event.kind == PointerDeviceKind.touch && !_stylusDown) {
      _navPoints[event.pointer] = event.localPosition;
    } else if (panTool && event.buttons == kPrimaryMouseButton) {
      _navPoints[event.pointer] = event.localPosition;
    } else {
      return;
    }
    if (c.transformDraft != null || c.panel != null) return;
    final needed = panTool ? 1 : 2;
    if (_navPoints.length >= needed) {
      _navFrom = Map.of(_navPoints);
      _navStart = _view.value.clone();
    }
  }

  void _navMove(PointerMoveEvent event) {
    if (!_navPoints.containsKey(event.pointer)) return;
    _navPoints[event.pointer] = event.localPosition;
    final from = _navFrom, start = _navStart;
    if (from == null || start == null) return;
    final ids = from.keys.where(_navPoints.containsKey).take(2).toList();
    if (ids.length == 2) {
      _view.value = CanvasNavigation.pinch(
        start,
        from[ids[0]]!,
        from[ids[1]]!,
        _navPoints[ids[0]]!,
        _navPoints[ids[1]]!,
      );
    } else if (ids.length == 1 && from.length == 1) {
      final id = ids.first;
      _view.value = CanvasNavigation.around(
        start,
        from[id]!,
        pan: _navPoints[id]! - from[id]!,
      );
    }
  }

  void _navUp(PointerEvent event) {
    if (_navPoints.remove(event.pointer) == null) return;
    if (_navFrom == null) return;
    // Lifting one of two fingers ends the gesture; the other draws nothing.
    _navFrom = null;
    _navStart = null;
    _view.value = CanvasNavigation.snapped(
      _view.value,
      _workspace.center(Offset.zero),
    );
  }

  /// Trackpad pinch, twist and two-finger scroll (macOS).
  Matrix4? _trackpadStart;
  Offset _trackpadFocal = Offset.zero;

  void _wheel(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _view.value = CanvasNavigation.around(
        _view.value,
        event.localPosition,
        scale: math.exp(-event.scrollDelta.dy / 400),
      );
    }
  }

  InkPoint _point(PointerEvent event, double scale) {
    final hasPressure =
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    final denominator = event.pressureMax - event.pressureMin;
    final pressure = hasPressure && denominator > 0
        ? widget.controller.mapPressure(
            (event.pressure - event.pressureMin) / denominator,
          )
        : .5;
    return InkPoint(
      _canvasPoint(event).dx / scale,
      _canvasPoint(event).dy / scale,
      pressure,
    );
  }

  /// MyPaint x/y tilt in -1…1 from Flutter's polar tilt (0 = upright) and
  /// orientation (0 = pointing up, clockwise positive). Only a stylus has it.
  (double, double) _tilt(PointerEvent event) {
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      return (0, 0);
    }
    final amount = (event.tilt / (math.pi / 2)).clamp(0.0, 1.0);
    if (!amount.isFinite || !event.orientation.isFinite) return (0, 0);
    return (
      amount * math.sin(event.orientation),
      -amount * math.cos(event.orientation),
    );
  }

  void _down(PointerDownEvent event, double scale) =>
      PenProbe.instance.pointer(event, _handleDown(event, scale));

  /// What a pointer down did, for the pen log.
  String _handleDown(PointerDownEvent event, double scale) {
    final c = widget.controller;
    if (c.transformDraft != null) {
      _transformDown = _documentPoint(_canvasPoint(event), scale);
    }
    final stylus =
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    if (event.kind == PointerDeviceKind.touch) {
      _touches.add(event.pointer);
      // A finger beside a held shape makes it perfect.
      if (c.quickShape != null && _drawingPointer != null) {
        _perfectPointer = event.pointer;
        c.setQuickShapePerfect(true);
        return 'quickshape:perfect';
      }
      // While the pen is down every touch is a resting hand: it never draws
      // and never cancels the pen, however many contacts it makes.
      if (_stylusDown) {
        PenProbe.instance.foreignTouch(event);
        return 'touch:palm';
      }
      if (_touches.length > 1) {
        if (_drawingPointer != null) {
          PenProbe.instance.end('cancelled:multitouch');
        }
        c.cancelStroke();
        // A pinch: an open polygon stays, without the corner its first
        // finger placed.
        if (c.selectionPolygonOpen) {
          if (_selectionPointer != null) c.dropPolygonTouch();
        } else {
          c.cancelSelectionDraft();
        }
        c.cancelPick();
        _drawingPointer = null;
        _selectionPointer = null;
        _pickPointer = null;
        _swipePointer = null;
        _centrePointer = null;
        _discPointer = null;
        _cropPointer = null;
        _textPointer = null;
        if (_liquifyPointer != null) {
          // A pinch, not a Liquify stroke: take back what it began.
          c
            ..endLiquify()
            ..undoLiquify();
          _liquifyPointer = null;
        }
        return 'touch:multitouch-cancel';
      }
      if (!c.fingerDrawing &&
          c.liquify == null &&
          c.clone == null &&
          c.canvasCrop == null &&
          c.textEditing == null &&
          c.singleTouchMode == null &&
          !c.guideEditing &&
          c.tool != StudioTool.selection &&
          c.tool != StudioTool.eyedropper) {
        return 'touch:finger-drawing-off';
      }
    }
    if (stylus) {
      _stylusDown = true;
      if (_drawingPointer != null) PenProbe.instance.end('cancelled:stylus');
      c.cancelStroke();
      // Only what a touch was drawing goes; a polygon keeps its corners.
      if (_selectionPointer != null) {
        if (c.selectionPolygonOpen) {
          c.dropPolygonTouch();
        } else {
          c.cancelSelectionDraft();
        }
      }
      c.cancelPick();
      _drawingPointer = null;
      _selectionPointer = null;
      _pickPointer = null;
    }
    if (_drawingPointer != null || _pickPointer != null) return 'busy';
    if (c.panel != null) return 'panel:${c.panel!.name}';
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != kPrimaryMouseButton) {
      return 'mouse:secondary';
    }
    if (c.singleTouchMode != null) {
      _singlePointer = event.pointer;
      _singleFrom = event.localPosition;
      _singleView = _view.value.clone();
      return 'single-touch';
    }
    if (c.editedText case final text?) {
      final point = _documentPoint(_canvasPoint(event), scale);
      final box = textBounds(text);
      final reach = _documentReach(event, scale, 24);
      if (!text.vertical &&
          (point - Offset(box.right, box.center.dy)).distance <= reach) {
        _textWiden = true;
      } else if (box.inflate(reach / 2).contains(point)) {
        _textWiden = false;
      } else {
        c.finishText();
        return 'text:done';
      }
      _textPointer = event.pointer;
      _textFrom = point;
      _textStart = text;
      return _textWiden ? 'text:widen' : 'text:move';
    }
    // An open adjustment: the pencil paints where it applies, otherwise a
    // sideways slide changes its amount.
    if (c.guideEditing) {
      final point = _documentPoint(_canvasPoint(event), scale);
      final size = c.document.dimensions.size;
      final guide = c.guide;
      final reach = _documentReach(event, scale, 28);
      int? grabbed;
      var best = reach;
      final points = [
        if (guide.kind == GuideKind.perspective) ...guide.vanishingOn(size),
      ];
      for (var i = 0; i < points.length; i++) {
        final d = (points[i] - point).distance;
        if (d <= best) {
          best = d;
          grabbed = i;
        }
      }
      if (c.symmetry != SymmetryKind.off &&
          (guide.symmetryCentreOn(size) - point).distance <= best) {
        grabbed = -1;
      }
      if (grabbed == null &&
          guide.kind == GuideKind.perspective &&
          guide.vanishing.length < DrawingGuide.maxVanishing) {
        // A new vanishing point where the canvas was touched.
        c.setGuide(
          guide.copyWith(
            vanishing: [
              ...guide.vanishing,
              Offset(point.dx / size.width, point.dy / size.height),
            ],
          ),
        );
        grabbed = guide.vanishing.length;
      }
      if (grabbed == null) return 'guide:none';
      _guidePointer = event.pointer;
      _guideHandle = grabbed;
      return 'guide';
    }
    if (c.canvasCrop case final crop?) {
      if (crop.resample) return 'crop:resample';
      final point = _documentPoint(_canvasPoint(event), scale);
      final handle = cropHandleAt(
        crop.rect,
        point,
        _documentReach(event, scale, 24),
      );
      if (handle == null) return 'crop:outside';
      _cropPointer = event.pointer;
      _cropHandle = handle;
      _cropFrom = point;
      _cropStart = crop.rect;
      _cropReach = _documentReach(event, scale, 10);
      return 'crop';
    }
    if (c.clone case final session?) {
      final point = _documentPoint(_canvasPoint(event), scale);
      if ((point - session.disc).distance <= _documentReach(event, scale, 36)) {
        _discPointer = event.pointer;
        return 'clone:disc';
      }
      if (c.beginStroke(
        _point(event, scale),
        simulatePressure: !stylus,
        time: event.timeStamp,
      )) {
        _drawingPointer = event.pointer;
      }
      return 'clone:stroke';
    }
    if (c.liquify != null) {
      final point = _point(event, scale);
      c.beginLiquify(Offset(point.x, point.y), point.pressure);
      _liquifyPointer = event.pointer;
      return 'liquify';
    }
    if (c.shapeEdit case final shape?) {
      final point = _documentPoint(_canvasPoint(event), scale);
      final reach = _documentReach(event, scale, 28);
      final nodes = shape.nodes;
      int? nearest;
      var best = reach;
      for (var i = 0; i < nodes.length; i++) {
        final d = (nodes[i] - point).distance;
        if (d <= best) {
          best = d;
          nearest = i;
        }
      }
      if (nearest == null) {
        c.finishShapeEdit();
        return 'shape:done';
      }
      _nodePointer = event.pointer;
      _nodeIndex = nearest;
      return 'shape:node';
    }
    if (c.adjustment case final session?) {
      if (!session.pencil) {
        final adjustment = session.adjustment;
        if (adjustment.kind.swipe == null) return 'adjust:none';
        final point = _documentPoint(_canvasPoint(event), scale);
        if (adjustment.centred) {
          final size = c.document.dimensions.size;
          final centre = Offset(
            adjustment['x'] * size.width,
            adjustment['y'] * size.height,
          );
          // The disc takes touches within 40 screen pixels.
          final box =
              _canvasKey.currentContext?.findRenderObject() as RenderBox?;
          final reach = box == null
              ? 40 / scale
              : (box.globalToLocal(event.position + const Offset(40, 0)) /
                            scale -
                        point)
                    .distance;
          if ((point - centre).distance <= reach) {
            _centrePointer = event.pointer;
            c.beginAdjustmentChange();
            return 'adjust:centre';
          }
        }
        _slideStart = adjustment.kind == AdjustmentKind.motionBlur
            ? point
            : null;
        _swipePointer = event.pointer;
        _swipeX = event.position.dx;
        c.beginAdjustmentChange();
        return 'adjust:swipe';
      }
      if (c.beginStroke(
        _point(event, scale),
        simulatePressure: !stylus,
        time: event.timeStamp,
      )) {
        _drawingPointer = event.pointer;
      }
      return 'adjust:pencil';
    }
    if (c.tool == StudioTool.pan) return 'pan';
    // ColorDrop goes on: each tap fills another area.
    if (c.fillSession != null) {
      unawaited(c.colorDrop(_documentPoint(_canvasPoint(event), scale)));
      return 'fill';
    }
    // Option/Alt + click or pen picks a colour from any drawing tool.
    if (c.tool == StudioTool.eyedropper ||
        (HardwareKeyboard.instance.isAltPressed &&
            (c.tool == StudioTool.brush ||
                c.tool == StudioTool.smudge ||
                c.tool == StudioTool.eraser))) {
      if (c.beginPick(_documentPoint(_canvasPoint(event), scale))) {
        _pickPointer = event.pointer;
      }
      return 'pick';
    }
    if (c.tool == StudioTool.selection) {
      if (c.beginSelection(
        _documentPoint(_canvasPoint(event), scale),
        reach: _documentReach(event, scale, 24),
      )) {
        _selectionPointer = event.pointer;
        _selectionDown = event.position;
        _autoThresholdStart = c.autoThreshold;
      }
      return 'selection';
    }
    final (tiltX, tiltY) = _tilt(event);
    // A finger may paint with its own tool while the pen keeps the brush.
    final fingerTool = event.kind == PointerDeviceKind.touch
        ? switch (c.fingerTool) {
            FingerTool.same => null,
            FingerTool.smudge => StudioTool.smudge,
            FingerTool.eraser => StudioTool.eraser,
          }
        : null;
    if (c.beginStroke(
      _point(event, scale),
      simulatePressure: !stylus,
      tiltX: tiltX,
      tiltY: tiltY,
      time: event.timeStamp,
      as: fingerTool,
    )) {
      _drawingPointer = event.pointer;
      _armHold(event.localPosition);
      PenProbe.instance.begin(
        event,
        brush: c.brush.id,
        smoothing: c.smoothing.toJson(),
      );
      return 'stroke';
    }
    return 'rejected:initialized=${c.initialized} '
        'transition=${c.documentTransition} tool=${c.tool.name} '
        'locked=${c.document.activeLayer.locked} '
        'visible=${c.document.activeLayer.visible}';
  }

  void _up(PointerEvent event, {bool cancel = false}) {
    PenProbe.instance.pointer(
      event,
      event.pointer == _drawingPointer
          ? 'stroke'
          : event.pointer == _selectionPointer
          ? 'selection'
          : event.pointer == _pickPointer
          ? 'pick'
          : 'none',
    );
    _transformDown = null;
    _touches.remove(event.pointer);
    if (event.pointer == _perfectPointer) {
      _perfectPointer = null;
      widget.controller.setQuickShapePerfect(false);
      return;
    }
    if (event.pointer == _nodePointer) {
      _nodePointer = null;
      return;
    }
    if (event.pointer == _liquifyPointer) {
      _liquifyPointer = null;
      widget.controller.endLiquify();
      return;
    }
    if (event.pointer == _discPointer) {
      _discPointer = null;
      return;
    }
    if (event.pointer == _cropPointer) {
      _cropPointer = null;
      return;
    }
    if (event.pointer == _guidePointer) {
      _guidePointer = null;
      return;
    }
    if (event.pointer == _drawingPointer) _holdTimer?.cancel();
    if (event.pointer == _swipePointer) _swipePointer = null;
    if (event.pointer == _centrePointer) _centrePointer = null;
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      _stylusDown = false;
    }
    if (event.pointer == _textPointer) {
      _textPointer = null;
      _textStart = null;
      return;
    }
    if (event.pointer == _singlePointer) {
      _singlePointer = null;
      _singleView = null;
      return;
    }
    if (event.pointer == _pickPointer) {
      if (cancel) {
        widget.controller.cancelPick();
      } else {
        widget.controller.finishPick();
      }
      _pickPointer = null;
      return;
    }
    if (event.pointer == _selectionPointer) {
      if (cancel) {
        widget.controller.cancelSelectionDraft();
      } else {
        // However long the pen rests, barely moving is a tap (a corner).
        final down = _selectionDown;
        final tap = down != null && (event.position - down).distance < 8;
        widget.controller.finishSelection(tap: tap);
      }
      _selectionPointer = null;
      return;
    }
    if (event.pointer != _drawingPointer) return;
    if (cancel) {
      widget.controller.cancelStroke();
      PenProbe.instance.end('cancelled:pointer');
    } else {
      PenProbe.instance.sample(event);
      widget.controller.finishStroke();
      PenProbe.instance.end(
        'finished',
        awaitNative: widget.controller.smudgeBrush.isNative,
      );
    }
    _drawingPointer = null;
  }

  /// The drawing point under the global position [global], or null when
  /// the canvas is not laid out (a colour dropped on it, say).
  Offset? documentPoint(Offset global) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.width == 0) return null;
    final dims = widget.controller.document.dimensions;
    return box.globalToLocal(global) / (box.size.width / dims.width);
  }

  /// Pointer position on the canvas, wherever the pointer went down: the
  /// workspace listens so a stroke may start beside the canvas and enter it.
  Offset _canvasPoint(PointerEvent event) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null
        ? event.localPosition
        : box.globalToLocal(event.position);
  }

  /// Widget pixels per document pixel of the canvas at zoom 1.
  Offset _documentPoint(Offset point, double scale) => point / scale;

  /// A double tap on the active text layer's text opens it for editing.
  (int, Duration, Offset)? _tapStart;
  (Duration, Offset)? _lastTap;

  /// Single-touch pad: the finger or pen moving, zooming or turning the
  /// canvas, where it went down and the view then.
  int? _singlePointer;
  Offset _singleFrom = Offset.zero;
  Matrix4? _singleView;

  void _singleMove(PointerMoveEvent e) {
    final start = _singleView, mode = widget.controller.singleTouchMode;
    if (e.pointer != _singlePointer || start == null || mode == null) return;
    final centre = _workspace.center(Offset.zero);
    final at = e.localPosition;
    _view.value = switch (mode) {
      SingleTouchMode.move => CanvasNavigation.around(
        start,
        _singleFrom,
        pan: at - _singleFrom,
      ),
      SingleTouchMode.zoom => CanvasNavigation.around(
        start,
        centre,
        scale: math.exp(-(at.dy - _singleFrom.dy) / 200),
      ),
      SingleTouchMode.rotate => CanvasNavigation.around(
        start,
        centre,
        rotation: (at - centre).direction - (_singleFrom - centre).direction,
      ),
    };
  }

  /// QuickMenu by touch and hold: the finger, where it went down (global),
  /// and, once the menu is open, the finger that opened it.
  Timer? _quickTimer;
  int? _quickArmed, _quickPointer;
  Offset _quickFrom = Offset.zero;

  void _quickDown(PointerDownEvent e, double scale) {
    final c = widget.controller;
    if (e.kind == PointerDeviceKind.mouse &&
        e.buttons == kSecondaryMouseButton) {
      c.openQuickMenu(e.position);
      return;
    }
    _quickTimer?.cancel();
    _quickArmed = null;
    final calm =
        c.liquify == null &&
        c.clone == null &&
        c.adjustment == null &&
        c.canvasCrop == null &&
        c.textEditing == null &&
        c.transformDraft == null &&
        !c.guideEditing &&
        !c.selectionPolygonOpen &&
        c.tool != StudioTool.eyedropper;
    final hold =
        c.quickMenuTrigger == QuickMenuTrigger.touchHold || c.eyedropperHold;
    if (!hold ||
        e.kind != PointerDeviceKind.touch ||
        _engaged.length != 1 ||
        _stylusDown ||
        c.quickMenuAt != null ||
        !calm) {
      return;
    }
    _quickArmed = e.pointer;
    _quickFrom = e.position;
    final at = _documentPoint(_canvasPoint(e), scale);
    _quickTimer = Timer(const Duration(milliseconds: 500), () {
      final pointer = _quickArmed;
      if (pointer == null || !mounted) return;
      // The finger was not drawing after all (nor holding a shape).
      if (pointer == _drawingPointer) {
        _holdTimer?.cancel();
        c.cancelStroke();
        _drawingPointer = null;
      }
      if (pointer == _selectionPointer) {
        c.cancelSelectionDraft();
        _selectionPointer = null;
      }
      _quickArmed = null;
      if (c.eyedropperHold) {
        // The finger picks a colour until it lifts, the loupe under it.
        if (c.beginPick(at)) _pickPointer = pointer;
        return;
      }
      _quickPointer = pointer;
      c.openQuickMenu(_quickFrom);
    });
  }

  void _quickMove(PointerMoveEvent e) {
    if (e.pointer == _quickArmed &&
        (e.position - _quickFrom).distance > TouchGestureTracker.slop / 2) {
      _quickTimer?.cancel();
      _quickArmed = null;
    }
    if (e.pointer == _quickPointer) {
      widget.controller.hoverQuickMenu(e.position);
    }
  }

  /// Whether [e] was the finger holding the QuickMenu open.
  bool _quickUp(PointerEvent e) {
    if (e.pointer == _quickArmed) {
      _quickTimer?.cancel();
      _quickArmed = null;
    }
    if (e.pointer != _quickPointer) return false;
    _quickPointer = null;
    final c = widget.controller;
    final slot = c.quickMenuHover;
    // Lifted on a button: that one; elsewhere the menu stays for a tap.
    if (slot != null) widget.onQuickAction?.call(c.quickMenu.slots[slot]);
    return true;
  }

  void _tapDown(PointerDownEvent e, double scale) {
    final single =
        _engaged.length == 1 &&
        (e.kind != PointerDeviceKind.mouse || e.buttons == kPrimaryMouseButton);
    _tapStart = single
        ? (e.pointer, e.timeStamp, _documentPoint(_canvasPoint(e), scale))
        : null;
    if (!single) _lastTap = null;
  }

  void _tapUp(PointerUpEvent e, double scale) {
    final start = _tapStart;
    _tapStart = null;
    if (start == null || start.$1 != e.pointer) return;
    final point = _documentPoint(_canvasPoint(e), scale);
    final reach = _documentReach(e, scale, 20);
    if (e.timeStamp - start.$2 > const Duration(milliseconds: 350) ||
        (point - start.$3).distance > reach) {
      _lastTap = null;
      return;
    }
    final last = _lastTap;
    _lastTap = (e.timeStamp, point);
    if (last == null ||
        e.timeStamp - last.$1 > const Duration(milliseconds: 450) ||
        (point - last.$2).distance > reach * 2) {
      return;
    }
    _lastTap = null;
    final c = widget.controller;
    final layer = c.document.activeLayer;
    final text = layer.text;
    if (c.textEditing != null ||
        text == null ||
        !layer.visible ||
        !textBounds(text).inflate(reach).contains(point)) {
      return;
    }
    c.editText(layer.id);
  }

  /// The brush outline follows a hovering pen or mouse, and any one pointer
  /// drawing; a second finger (a pinch) hides it.
  void _trackCursor(PointerEvent e, double scale) {
    final c = widget.controller;
    final drawing = switch (c.tool) {
      StudioTool.brush || StudioTool.smudge || StudioTool.eraser => true,
      _ => false,
    };
    c.setCursor(
      drawing &&
              _engaged.length <= 1 &&
              c.transformDraft == null &&
              c.textEditing == null
          ? _documentPoint(_canvasPoint(e), scale)
          : null,
    );
  }

  void _transformStart(ScaleStartDetails details, double scale) {
    final c = widget.controller;
    if (c.documentTransition) return;
    final draft = c.transformDraft;
    final focal = details.pointerCount == 1 && _transformDown != null
        ? _transformDown!
        : _documentPoint(details.localFocalPoint, scale);
    _transformDown = null;
    _gestureDraft = draft;
    _gestureFocal = focal;
    _gesturePointers = details.pointerCount;
    _lastFocal = details.focalPoint;
    _lastFocalAt = details.sourceTimeStamp ?? _focalClock.elapsed;
    _grab = draft == null || details.pointerCount > 1
        ? null
        : _grabAt(draft, focal, scale);
  }

  /// The handle (or mesh place) under [focal], if any.
  _Grab? _grabAt(LayerTransform draft, Offset focal, double scale) {
    final mode = widget.controller.transformMode;
    final reach = 18 / scale / widget.transformation.value.getMaxScaleOnAxis();
    int? near(List<Offset> points) {
      int? best;
      var distance = reach;
      for (var i = 0; i < points.length; i++) {
        final d = (points[i] - focal).distance;
        if (d <= distance) {
          best = i;
          distance = d;
        }
      }
      return best;
    }

    final mesh = draft.mesh;
    if (mesh?.length == 16) {
      if (mode != TransformMode.warp) return null;
      final at = draft.meshAt(focal, reach: reach);
      return at == null ? null : _Grab.warp(at.$1, at.$2);
    }
    final distort = mesh?.length == 4;
    if (mesh != null && !distort) return null;
    final corners = draft.corners;
    if (near(corners) case final i?) {
      return _Grab.corner(i, focal - corners[i]);
    }
    if (distort || mode == TransformMode.freeform) {
      final sides = draft.sides;
      if (near(sides) case final i?) return _Grab.side(i, focal - sides[i]);
    }
    return null;
  }

  void _transformUpdate(ScaleUpdateDetails details, double scale) {
    final c = widget.controller;
    final focal = _documentPoint(details.localFocalPoint, scale);
    // Fingers added or lifted: carry on from what is shown now.
    if (details.pointerCount != _gesturePointers) {
      _gestureDraft = c.transformDraft;
      _gestureFocal = focal;
      _gesturePointers = details.pointerCount;
      _grab = null;
      return;
    }
    final draft = _gestureDraft, from = _gestureFocal;
    if (draft == null || from == null) return;
    final grab = _grab;
    // How fast the drag goes, in screen pixels a second.
    final now = details.sourceTimeStamp ?? _focalClock.elapsed;
    final lastFocal = _lastFocal;
    final seconds = (now - _lastFocalAt).inMicroseconds / 1e6;
    final speed = lastFocal == null || seconds <= 0
        ? 0.0
        : (details.focalPoint - lastFocal).distance / seconds;
    _lastFocal = details.focalPoint;
    _lastFocalAt = now;
    var guides = const <(Offset, Offset)>[];
    LayerTransform next;
    if (details.pointerCount > 1) {
      next = draft.pinched(from, focal, details.scale, details.rotation);
      if (c.transformMagnetics) {
        next = next.withShownRotation(snapAngle(next.shownRotation));
      }
    } else if (grab == null) {
      var delta = focal - from;
      if (c.transformMagnetics) delta = lockToAxis(delta);
      next = draft.translated(delta);
      if (c.transformSnapping && speed < c.snapVelocity) {
        final zoom = widget.transformation.value.getMaxScaleOnAxis();
        final targets = c.snapTargets;
        final (move, lines) = snapBounds(
          next.shownBounds,
          targets.xs,
          targets.ys,
          c.snapDistance / scale / zoom,
          c.document.dimensions.rect,
        );
        next = next.translated(move);
        guides = lines;
      }
    } else {
      final point = focal - grab.offset;
      final distort = draft.mesh?.length == 4;
      next = switch (grab.kind) {
        _GrabKind.corner when distort => draft.withCorner(grab.index, point),
        _GrabKind.corner => draft.resizedByCorner(
          grab.index,
          point,
          uniform:
              c.transformMode == TransformMode.uniform || c.transformMagnetics,
        ),
        _GrabKind.side when distort => draft.withSideMoved(
          grab.index,
          focal - from,
        ),
        _GrabKind.side => draft.resizedBySide(grab.index, point),
        _GrabKind.warp => draft.warped(grab.u, grab.v, focal - from),
      };
    }
    c.showSnapGuides(guides);
    c.previewTransform(next);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_documentId != widget.controller.document.id ||
          _paths.length > 5000) {
        _paths.clear();
        _documentId = widget.controller.document.id;
      }
      // Fit the canvas, whatever its aspect, into the workspace.
      final dimensions = widget.controller.document.dimensions;
      final scale = math.max(
        64 / math.max(dimensions.width, dimensions.height),
        math.min(
          (constraints.maxWidth - 112) / dimensions.width,
          (constraints.maxHeight - 64) / dimensions.height,
        ),
      );
      final canvasSize = dimensions.size * scale;
      final panning = widget.controller.tool == StudioTool.pan;
      _workspace = constraints.biggest;
      return MouseRegion(
        onExit: (_) => widget.controller.setCursor(null),
        cursor: panning
            ? SystemMouseCursors.grab
            : widget.controller.transformDraft != null
            ? SystemMouseCursors.move
            : SystemMouseCursors.precise,
        child: Listener(
          key: const ValueKey('drawing-workspace'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            widget.controller.stopPlayback();
            _engaged.add(e.pointer);
            widget.controller.canvasEngaged.value = true;
            if (_engaged.length > 1) {
              _quickTimer?.cancel();
              _quickArmed = null;
            }
            _quickDown(e, scale);
            _tapDown(e, scale);
            _down(e, scale);
            _navDown(e);
            _gestureDown(e);
          },
          onPointerSignal: _wheel,
          onPointerPanZoomStart: (e) {
            _trackpadStart = _view.value.clone();
            _trackpadFocal = e.localPosition;
          },
          onPointerPanZoomUpdate: (e) {
            final start = _trackpadStart;
            if (start == null) return;
            _view.value = CanvasNavigation.around(
              start,
              _trackpadFocal,
              pan: e.pan,
              scale: e.scale,
              rotation: e.rotation,
            );
          },
          onPointerPanZoomEnd: (_) {
            _trackpadStart = null;
            _view.value = CanvasNavigation.snapped(
              _view.value,
              _workspace.center(Offset.zero),
            );
          },
          onPointerHover: (e) => _trackCursor(e, scale),
          onPointerMove: (e) {
            if (e.pointer == _singlePointer) {
              _singleMove(e);
              return;
            }
            _quickMove(e);
            if (e.pointer == _quickPointer) return;
            _trackCursor(e, scale);
            _gestures.move(e.pointer, e.localPosition, e.timeStamp);
            _navMove(e);
            if (e.pointer == _pickPointer) {
              widget.controller.movePick(
                _documentPoint(_canvasPoint(e), scale),
              );
            }
            if (e.pointer == _centrePointer) {
              widget.controller.moveAdjustmentCentre(
                _documentPoint(_canvasPoint(e), scale),
              );
            }
            if (e.pointer == _swipePointer && _slideStart != null) {
              widget.controller.slideMotionBlur(
                _documentPoint(_canvasPoint(e), scale) - _slideStart!,
              );
            } else if (e.pointer == _swipePointer) {
              final width = context.size?.width ?? 0;
              if (width > 0) {
                widget.controller.adjustAmountBy(
                  (e.position.dx - _swipeX) / width,
                );
              }
              _swipeX = e.position.dx;
            }
            if (e.pointer == _selectionPointer &&
                widget.controller.selectionShape == SelectionShape.automatic) {
              final width = context.size?.width ?? 0;
              final down = _selectionDown;
              if (width > 0 && down != null) {
                widget.controller.setAutoThreshold(
                  _autoThresholdStart + (e.position.dx - down.dx) / width,
                );
              }
            }
            if (e.pointer == _selectionPointer) {
              widget.controller.appendSelection(
                _documentPoint(_canvasPoint(e), scale),
              );
            }
            if (e.pointer == _guidePointer) {
              final c = widget.controller;
              final size = c.document.dimensions.size;
              final p = _documentPoint(_canvasPoint(e), scale);
              // Guide points stay within reach: a little past the canvas.
              final at = Offset(
                (p.dx / size.width).clamp(-1.0, 2.0),
                (p.dy / size.height).clamp(-1.0, 2.0),
              );
              final guide = c.guide;
              if (_guideHandle < 0) {
                c.setGuide(
                  guide.copyWith(
                    symmetryCentre: Offset(
                      at.dx.clamp(0.0, 1.0),
                      at.dy.clamp(0.0, 1.0),
                    ),
                  ),
                );
              } else if (_guideHandle < guide.vanishing.length) {
                c.setGuide(
                  guide.copyWith(
                    vanishing: [...guide.vanishing]..[_guideHandle] = at,
                  ),
                );
              }
            }
            if (e.pointer == _textPointer && _textStart != null) {
              final start = _textStart!;
              final delta = _documentPoint(_canvasPoint(e), scale) - _textFrom;
              widget.controller.setText(
                (t) => _textWiden
                    ? t.copyWith(width: start.width + delta.dx)
                    : t.copyWith(origin: start.origin + delta),
              );
            }
            if (e.pointer == _cropPointer) {
              final c = widget.controller;
              c.setCanvasCrop(
                rect: dragCrop(
                  _cropStart,
                  _cropHandle,
                  _documentPoint(_canvasPoint(e), scale) - _cropFrom,
                  c.document.dimensions,
                  _cropReach,
                ),
              );
            }
            if (e.pointer == _discPointer) {
              widget.controller.moveCloneDisc(
                _documentPoint(_canvasPoint(e), scale),
              );
            }
            if (e.pointer == _liquifyPointer) {
              final point = _point(e, scale);
              widget.controller.moveLiquify(
                Offset(point.x, point.y),
                point.pressure,
              );
            }
            if (e.pointer == _nodePointer) {
              widget.controller.moveShapeNode(
                _nodeIndex!,
                _documentPoint(_canvasPoint(e), scale),
              );
            }
            if (e.pointer == _drawingPointer) {
              final c = widget.controller;
              if (c.quickShape != null) {
                c.setQuickShapePerfect(
                  _perfectPointer != null ||
                      HardwareKeyboard.instance.isShiftPressed,
                );
              } else if ((e.localPosition - (_holdAt ?? e.localPosition))
                      .distance >
                  6) {
                _armHold(e.localPosition);
              }
              PenProbe.instance.sample(e);
              final (tiltX, tiltY) = _tilt(e);
              widget.controller.appendPoint(
                _point(e, scale),
                tiltX: tiltX,
                tiltY: tiltY,
                time: e.timeStamp,
              );
            }
          },
          onPointerUp: (e) {
            if (e.kind != PointerDeviceKind.mouse) {
              widget.controller.setCursor(null);
            }
            if (_quickUp(e)) {
              _release(e.pointer);
              _gestures.cancel(e.pointer);
              _navUp(e);
              _touches.remove(e.pointer);
              return;
            }
            _release(e.pointer);
            _gestures.up(e.pointer, e.timeStamp);
            _navUp(e);
            _up(e);
            _tapUp(e, scale);
          },
          onPointerCancel: (e) {
            _quickUp(e);
            _release(e.pointer);
            _gestures.cancel(e.pointer);
            _navUp(e);
            _up(e, cancel: true);
          },
          // The turned or zoomed canvas stays inside the workspace: painting
          // and touches never reach the menus around it.
          child: ClipRect(
            child: ValueListenableBuilder<Matrix4>(
              valueListenable: widget.transformation,
              builder: (context, matrix, _) => Transform(
                transform: matrix,
                child: Center(
                  child: Container(
                    width: canvasSize.width,
                    height: canvasSize.height,
                    decoration: const BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 24,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: GestureDetector(
                      dragStartBehavior: DragStartBehavior.down,
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: widget.controller.transformDraft != null
                          ? (d) => _transformStart(d, scale)
                          : null,
                      onScaleUpdate: widget.controller.transformDraft != null
                          ? (d) => _transformUpdate(d, scale)
                          : null,
                      onScaleEnd: widget.controller.transformDraft != null
                          ? (_) {
                              _gestureDraft = null;
                              _gestureFocal = null;
                              _grab = null;
                              _lastFocal = null;
                              widget.controller.endSnap();
                            }
                          : null,
                      child: KeyedSubtree(
                        key: _canvasKey,
                        child: ClipRect(
                          key: const ValueKey('drawing-surface'),
                          child: CustomPaint(
                            painter: DocumentPainter(
                              controller: widget.controller,
                              engine: widget.engine,
                              paths: _paths,
                              zoom: matrix.getMaxScaleOnAxis(),
                              view: CanvasView(
                                widget.transformation,
                                constraints.biggest,
                                canvasSize,
                              ),
                            ),
                            size: canvasSize,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Two light greys in a 2×2 checker, tiled to show transparency.
final ui.Image _checker = () {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 2, 2),
    Paint()..color = const Color(0xffffffff),
  );
  final grey = Paint()..color = const Color(0xffd9d9d9);
  canvas.drawRect(const Rect.fromLTWH(1, 0, 1, 1), grey);
  canvas.drawRect(const Rect.fromLTWH(0, 1, 1, 1), grey);
  return recorder.endRecording().toImageSync(2, 2);
}();

class DocumentPainter extends CustomPainter {
  DocumentPainter({
    required this.controller,
    required this.engine,
    required this.paths,
    this.zoom = 1,
    this.view,
  }) : super(
         repaint: Listenable.merge([
           controller.inkChanges,
           controller.playback,
         ]),
       );
  final StudioController controller;
  final BrushEngine engine;
  final Map<InkStroke, ui.Path> paths;
  final double zoom;

  /// Where the canvas sits in the workspace, to skip tiles out of sight.
  final CanvasView? view;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // Page Assist: only the page being worked on.
    final document = controller.shownDocument;
    final dimensions = document.dimensions;
    canvas.scale(size.width / dimensions.width);
    final visible = view?.visibleDocumentRect(size.width / dimensions.width);
    // No background: a checkerboard shows the transparency, 10 screen
    // pixels a square at any zoom.
    if (document.backgroundHidden) {
      final cell = 10 * dimensions.width / size.width / zoom;
      canvas.drawRect(
        dimensions.rect,
        Paint()
          ..filterQuality = FilterQuality.none
          ..shader = ImageShader(
            _checker,
            TileMode.repeated,
            TileMode.repeated,
            (Matrix4.identity()..scaleByDouble(cell, cell, 1, 1)).storage,
          ),
      );
    }
    final overrides = controller.nativeOverrides;
    final transformLayer = controller.transformLayerId;
    final onion = controller.onionView;
    // Flattened layers only when nothing but the active layer is live.
    final composite =
        onion == null &&
            controller.flattenLayers &&
            overrides.keys.every((id) => id == document.activeLayerId) &&
            (transformLayer == null || transformLayer == document.activeLayerId)
        ? controller.compositor.frame(document, controller.rasters.images)
        : null;
    if (composite != null) {
      paintComposited(
        canvas,
        document,
        engine,
        composite,
        pending: controller.pendingStrokes,
        cache: paths,
        rasterImages: controller.rasters.images,
        transform: controller.transformDraft,
        transformSelection: controller.transformSelection,
        overrides: overrides,
        visible: visible,
      );
    } else if (onion != null) {
      // Onion skins: paper, background frame, tinted neighbours, then the
      // frame being drawn (live strokes included) and the foreground.
      final images = controller.rasters.images;
      if (!document.backgroundHidden) {
        canvas.drawRect(
          dimensions.rect,
          Paint()..color = Color(document.background),
        );
      }
      if (onion.under case final under?) {
        paintDocument(canvas, under, engine, rasterImages: images);
      }
      for (final (frame, tint, opacity) in onion.onions) {
        canvas.saveLayer(
          dimensions.rect,
          Paint()
            ..color = Color.fromRGBO(0, 0, 0, opacity)
            ..colorFilter = ColorFilter.mode(Color(tint), BlendMode.srcIn),
        );
        paintDocument(canvas, frame, engine, rasterImages: images);
        canvas.restore();
      }
      if (onion.blendPrimary) {
        canvas.saveLayer(
          dimensions.rect,
          Paint()..color = const Color.fromRGBO(0, 0, 0, .6),
        );
      }
      paintDocument(
        canvas,
        onion.top,
        engine,
        pending: controller.pendingStrokes,
        cache: paths,
        rasterImages: images,
        transform: controller.transformDraft,
        transformLayerId: transformLayer,
        transformSelection: controller.transformSelection,
        overrides: overrides,
        visible: visible,
      );
      if (onion.blendPrimary) canvas.restore();
    } else {
      paintDocument(
        canvas,
        document,
        engine,
        pending: controller.pendingStrokes,
        cache: paths,
        rasterImages: controller.rasters.images,
        transform: controller.transformDraft,
        transformLayerId: transformLayer,
        transformSelection: controller.transformSelection,
        overrides: overrides,
        visible: visible,
      );
    }
    _paintGuides(canvas, dimensions, dimensions.width / size.width / zoom);
    _paintQuickShape(canvas, dimensions.width / size.width / zoom);
    if (controller.snapGuides.isNotEmpty) {
      final guide = Paint()
        ..color = const Color(0xffff9500)
        ..strokeWidth = 1.5 * dimensions.width / size.width / zoom;
      for (final (a, b) in controller.snapGuides) {
        canvas.drawLine(a, b, guide);
      }
    }
    _paintCloneDisc(canvas, dimensions.width / size.width / zoom);
    _paintCrop(canvas, dimensions, dimensions.width / size.width / zoom);
    _paintAdjustmentCentre(
      canvas,
      dimensions,
      dimensions.width / size.width / zoom,
    );
    final draft = controller.transformDraft;
    if (draft == null) {
      ui.Path? selectionPath = controller.selection?.path;
      if (controller.selectionDrawing) {
        final shape = controller.selectionDraftShape;
        final draft = ui.Path()..addPolygon(shape, shape.length >= 3);
        final current = selectionPath;
        // Adding or removing previews the selection it will make.
        selectionPath =
            current == null ||
                controller.selectionMode == SelectionMode.replace ||
                shape.length < 3
            ? draft
            : ui.Path.combine(
                controller.selectionMode == SelectionMode.add
                    ? ui.PathOperation.union
                    : ui.PathOperation.difference,
                current,
                draft,
              );
      }
      if (selectionPath != null) {
        final pixel = dimensions.width / size.width;
        final outside = ui.Path.combine(
          ui.PathOperation.difference,
          ui.Path()..addRect(dimensions.rect),
          selectionPath,
        );
        if (controller.selectionMask > 0) {
          canvas.drawPath(
            outside,
            Paint()..color = Color.fromRGBO(0, 0, 0, controller.selectionMask),
          );
        }
        canvas.drawPath(
          selectionPath,
          Paint()
            ..color = const Color(0xff111111)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * pixel,
        );
        final dash = ui.Path();
        for (final metric in selectionPath.computeMetrics()) {
          for (var d = 0.0; d < metric.length; d += 10 * pixel) {
            dash.addPath(
              metric.extractPath(d, math.min(d + 5 * pixel, metric.length)),
              Offset.zero,
            );
          }
        }
        canvas.drawPath(
          dash,
          Paint()
            ..color = const Color(0xffffffff)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 * pixel,
        );
      }
    }
    if (draft != null) {
      final pixel = dimensions.width / size.width / zoom;
      final line = Paint()
        ..color = const Color(0xff388ef6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * pixel;
      final warp = draft.mesh?.length == 16;
      if (warp) {
        // The mesh's thirds, as curves.
        for (var k = 0; k <= 3; k++) {
          final across = ui.Path(), down = ui.Path();
          for (var i = 0; i <= 24; i++) {
            final a = draft.surface(i / 24, k / 3);
            final b = draft.surface(k / 3, i / 24);
            i == 0 ? across.moveTo(a.dx, a.dy) : across.lineTo(a.dx, a.dy);
            i == 0 ? down.moveTo(b.dx, b.dy) : down.lineTo(b.dx, b.dy);
          }
          canvas.drawPath(across, line);
          canvas.drawPath(down, line);
        }
      } else {
        canvas.drawPath(ui.Path()..addPolygon(draft.corners, true), line);
      }
      final mode = controller.transformMode;
      final handles = [
        if (warp)
          for (var j = 0; j <= 3; j++)
            for (var i = 0; i <= 3; i++) draft.surface(i / 3, j / 3)
        else ...[
          ...draft.corners,
          if (draft.mesh != null || mode == TransformMode.freeform)
            ...draft.sides,
        ],
      ];
      for (final point in handles) {
        canvas.drawCircle(
          point,
          5 * pixel,
          Paint()..color = const Color(0xffffffff),
        );
        canvas.drawCircle(point, 5 * pixel, line);
      }
    }

    // An open freehand polygon: a ring on every corner; the first, which
    // closes it, larger and filled.
    if (controller.selectionPolygonOpen) {
      final shape = controller.selectionDraftShape;
      final pixel = dimensions.width / size.width / zoom;
      final ring = Paint()
        ..color = const Color(0xff388ef6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * pixel;
      for (final (i, corner) in shape.indexed) {
        final first = i == 0;
        canvas.drawCircle(
          corner,
          (first ? 10 : 6) * pixel,
          Paint()
            ..color = first ? const Color(0xff388ef6) : const Color(0xffffffff),
        );
        canvas.drawCircle(corner, (first ? 10 : 6) * pixel, ring);
        if (first) {
          canvas.drawCircle(
            corner,
            4 * pixel,
            Paint()..color = const Color(0xffffffff),
          );
        }
      }
    }
    final pick = controller.pickPoint;
    if (pick != null) {
      _paintLoupe(canvas, pick, dimensions.width / size.width);
    }
    if (controller.editedText case final text?) {
      final pixel = dimensions.width / size.width / zoom;
      final box = textBounds(text);
      final blue = Paint()
        ..color = const Color(0xff388ef6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * pixel;
      canvas.drawRect(box, blue);
      if (!text.vertical) {
        final handle = Offset(box.right, box.center.dy);
        canvas.drawCircle(handle, 8 * pixel, Paint()..color = Colors.white);
        canvas.drawCircle(handle, 8 * pixel, blue);
      }
    }
    final cursor = controller.cursor;
    if (cursor != null && controller.brushCursor && pick == null) {
      final pixel = dimensions.width / size.width / zoom;
      final radius = math.max(controller.size / 2, 2 * pixel);
      canvas.drawCircle(
        cursor,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * pixel
          ..color = const Color(0x66000000),
      );
      canvas.drawCircle(
        cursor,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 * pixel
          ..color = const Color(0xddffffff),
      );
    }
    canvas.restore();
  }

  /// Procreate-style ring: upper half the colour under the pen, lower half
  /// the current colour, sized in screen pixels whatever the zoom.
  void _paintLoupe(Canvas canvas, Offset center, double pixel) {
    final unit = pixel / zoom;
    final rect = Rect.fromCircle(center: center, radius: 44 * unit);
    final picked = Color(controller.pickColor ?? controller.color);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16 * unit;
    canvas.drawArc(rect, math.pi, math.pi, false, ring..color = picked);
    canvas.drawArc(
      rect,
      0,
      math.pi,
      false,
      ring..color = Color(controller.color),
    );
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * unit;
    for (final (radius, color) in [
      (52.0, const Color(0xffffffff)),
      (36.0, const Color(0xffffffff)),
      (53.5, const Color(0x55000000)),
      (34.5, const Color(0x55000000)),
    ]) {
      canvas.drawCircle(center, radius * unit, edge..color = color);
    }
  }

  /// The drawing guide over the canvas, never in the drawing: grid lines
  /// and the symmetry axes, one screen pixel wide at any zoom.
  /// Crop & Resize: what goes is darkened; the crop has a border and
  /// handles.
  void _paintCrop(Canvas canvas, CanvasSize dimensions, double pixel) {
    final crop = controller.canvasCrop;
    if (crop == null || crop.resample) return;
    final r = crop.rect;
    final outside = ui.Path()
      ..fillType = ui.PathFillType.evenOdd
      ..addRect(dimensions.rect.expandToInclude(r).inflate(2))
      ..addRect(r);
    canvas.drawPath(outside, Paint()..color = const Color(0x99000000));
    canvas.drawRect(
      r,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * pixel,
    );
    for (final handle in cropHandles(r)) {
      canvas.drawCircle(handle, 7 * pixel, Paint()..color = Colors.white);
      canvas.drawCircle(
        handle,
        7 * pixel,
        Paint()
          ..color = const Color(0xff388ef6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * pixel,
      );
    }
  }

  /// Clone's source: a ring with a cross, following the pen while it
  /// paints.
  void _paintCloneDisc(Canvas canvas, double pixel) {
    final session = controller.clone;
    if (session == null) return;
    final at = session.shownDisc;
    final r = 18 * pixel;
    final dark = Paint()
      ..color = const Color(0xaa000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * pixel;
    final light = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * pixel;
    for (final paint in [dark, light]) {
      canvas.drawCircle(at, r, paint);
      canvas.drawLine(at - Offset(r * .5, 0), at + Offset(r * .5, 0), paint);
      canvas.drawLine(at - Offset(0, r * .5), at + Offset(0, r * .5), paint);
    }
    // Locked, the disc stays: a small cross shows where pixels come from.
    final sampling = session.sampling;
    if (!session.locked || sampling == null) return;
    final c = 7 * pixel;
    for (final paint in [dark, light]) {
      canvas.drawLine(sampling - Offset(c, c), sampling + Offset(c, c), paint);
      canvas.drawLine(
        sampling - Offset(c, -c),
        sampling + Offset(c, -c),
        paint,
      );
    }
  }

  /// A held QuickShape, or the shape being edited with its nodes.
  void _paintQuickShape(Canvas canvas, double pixel) {
    final edit = controller.shapeEdit;
    final shape = edit ?? controller.quickShape?.current;
    if (shape == null) return;
    final points = shape.outline(spacing: 3 * pixel);
    final eraser = controller.tool == StudioTool.eraser;
    canvas.drawPath(
      ui.Path()..addPolygon(points, false),
      Paint()
        ..color = eraser
            ? const Color(0x99888888)
            : Color(controller.color).withValues(alpha: controller.opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(controller.size, pixel)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (edit == null) return;
    final ring = Paint()
      ..color = const Color(0xff388ef6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * pixel;
    for (final node in edit.nodes) {
      canvas.drawCircle(node, 7 * pixel, Paint()..color = Colors.white);
      canvas.drawCircle(node, 7 * pixel, ring);
    }
  }

  /// Perspective Blur's disc, with an arrow when it is directional.
  void _paintAdjustmentCentre(
    Canvas canvas,
    CanvasSize dimensions,
    double pixel,
  ) {
    final session = controller.adjustment;
    if (session == null ||
        session.pencil ||
        session.showOriginal ||
        !session.adjustment.centred) {
      return;
    }
    final a = session.adjustment;
    final centre = Offset(
      a['x'] * dimensions.width,
      a['y'] * dimensions.height,
    );
    final radius = 22 * pixel;
    canvas.drawCircle(centre, radius, Paint()..color = const Color(0x55000000));
    final ring = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * pixel;
    canvas.drawCircle(centre, radius, ring);
    canvas.drawCircle(centre, 4 * pixel, Paint()..color = Colors.white);
    if (a.kind == AdjustmentKind.perspectiveBlur && a['directional'] > .5) {
      final angle = a['angle'] * 2 * math.pi;
      final tip =
          centre + Offset(math.cos(angle), math.sin(angle)) * radius * 2;
      canvas.drawLine(centre, tip, ring);
      final back = Offset(math.cos(angle), math.sin(angle)) * 9 * pixel;
      final side = Offset(-back.dy, back.dx);
      canvas.drawPath(
        ui.Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo((tip - back + side).dx, (tip - back + side).dy)
          ..lineTo((tip - back - side).dx, (tip - back - side).dy)
          ..close(),
        Paint()..color = Colors.white,
      );
    }
  }

  void _paintGuides(Canvas canvas, CanvasSize dimensions, double pixel) {
    final size = dimensions.size;
    final guide = controller.guide;
    canvas.save();
    canvas.clipRect(dimensions.rect);
    final lines = guideLines(guide, size);
    if (lines.isNotEmpty) {
      final path = ui.Path();
      for (final (a, b) in lines) {
        path
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Color(guide.color).withValues(alpha: guide.opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = guide.thickness * pixel,
      );
    }
    final centre = guide.symmetryCentreOn(size);
    final axes = symmetryAxes(controller.symmetry, size, centre: centre);
    final axis = Paint()
      ..color = const Color(0xcc2f80ed)
      ..strokeWidth = 1.5 * pixel;
    for (final (from, to) in axes) {
      canvas.drawLine(from, to, axis);
    }
    canvas.restore();
    // Edit Drawing Guide: its points as handles.
    if (!controller.guideEditing) return;
    final ring = Paint()
      ..color = const Color(0xff388ef6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * pixel;
    final handles = [
      if (guide.kind == GuideKind.perspective) ...guide.vanishingOn(size),
      if (controller.symmetry != SymmetryKind.off) centre,
    ];
    for (final p in handles) {
      canvas.drawCircle(p, 10 * pixel, Paint()..color = Colors.white);
      canvas.drawCircle(p, 10 * pixel, ring);
      canvas.drawCircle(p, 3 * pixel, Paint()..color = const Color(0xff388ef6));
    }
  }

  @override
  bool shouldRepaint(covariant DocumentPainter oldDelegate) => true;
}

/// The canvas inside the workspace's [InteractiveViewer]: the viewport, the
/// canvas centred in it, and the pan/zoom applied on top.
class CanvasView {
  const CanvasView(this.transformation, this.viewport, this.canvas);
  final TransformationController transformation;
  final Size viewport, canvas;

  /// The part of the drawing on screen, in document pixels, with a margin.
  Rect visibleDocumentRect(double scale) {
    final inChild = MatrixUtils.inverseTransformRect(
      transformation.value,
      Offset.zero & viewport,
    );
    final offset = Offset(
      (viewport.width - canvas.width) / 2,
      (viewport.height - canvas.height) / 2,
    );
    final local = inChild.shift(-offset);
    return Rect.fromLTRB(
      local.left / scale,
      local.top / scale,
      local.right / scale,
      local.bottom / scale,
    ).inflate(TiledRaster.size / 2);
  }
}

enum _GrabKind { corner, side, warp }

/// What a one-finger transform drag holds.
class _Grab {
  _Grab.corner(this.index, this.offset) : kind = _GrabKind.corner, u = 0, v = 0;
  _Grab.side(this.index, this.offset) : kind = _GrabKind.side, u = 0, v = 0;
  _Grab.warp(this.u, this.v)
    : kind = _GrabKind.warp,
      index = 0,
      offset = Offset.zero;

  final _GrabKind kind;
  final int index;

  /// From the handle to the finger, kept as it moves.
  final Offset offset;

  /// Warp: the source position held.
  final double u, v;
}
