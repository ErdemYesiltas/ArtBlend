import 'dart:math' as math;
import 'dart:ui';

/// What a QuickMenu button can do.
enum QuickAction {
  newLayer,
  duplicateLayer,
  mergeDown,
  clearLayer,
  hideLayer,
  alphaLock,
  clippingMask,
  fillLayer,
  invertLayer,
  undo,
  redo,
  brush,
  smudge,
  eraser,
  eyedropper,
  selection,
  transform,
  deselect,
  invertSelection,
  cut,
  copy,
  paste,
  flipHorizontal,
  flipVertical,
  swapColor,
  addText,
  liquify,
  fullScreen,
  layers,
  colors,
  brushes,
  adjustments,
  reference,
}

/// When the QuickMenu opens.
enum QuickMenuTrigger {
  /// Only from the mouse's right button (and the keyboard).
  none,

  /// A finger held still on the canvas.
  touchHold,

  /// Four fingers tapped (in place of full screen).
  fourFingerTap,
}

/// Six buttons, named.
class QuickMenuProfile {
  const QuickMenuProfile({
    required this.id,
    required this.name,
    required this.slots,
  });
  final String id, name;
  final List<QuickAction> slots;

  static const size = 6;

  QuickMenuProfile copyWith({String? name, List<QuickAction>? slots}) =>
      QuickMenuProfile(
        id: id,
        name: name ?? this.name,
        slots: slots ?? this.slots,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'slots': [for (final a in slots) a.name],
  };

  /// Null when damaged; unknown actions become [QuickAction.undo].
  static QuickMenuProfile? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String || json['name'] is! String) {
      return null;
    }
    final slots = json['slots'];
    if (slots is! List) return null;
    final actions = QuickAction.values.asNameMap();
    return QuickMenuProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      slots: [
        for (var i = 0; i < size; i++)
          (i < slots.length ? actions[slots[i]] : null) ?? QuickAction.undo,
      ],
    );
  }

  /// Procreate's starting buttons.
  static const initial = QuickMenuProfile(
    id: 'default',
    name: 'Default',
    slots: [
      QuickAction.newLayer,
      QuickAction.flipHorizontal,
      QuickAction.flipVertical,
      QuickAction.clearLayer,
      QuickAction.mergeDown,
      QuickAction.eyedropper,
    ],
  );
}

/// The ring's radius and how near its middle a touch is "the middle".
const quickMenuRadius = 96.0, quickMenuHub = 36.0;

/// Where button [slot] sits around [centre]: the first at the top, then
/// clockwise.
Offset quickMenuSlot(Offset centre, int slot) =>
    centre +
    Offset.fromDirection(
      -math.pi / 2 + slot * 2 * math.pi / QuickMenuProfile.size,
      quickMenuRadius,
    );

/// The button under [point] for a menu at [centre], if any.
int? quickMenuSlotAt(Offset centre, Offset point) {
  final d = point - centre;
  if (d.distance < quickMenuHub || d.distance > quickMenuRadius + 48) {
    return null;
  }
  final step = 2 * math.pi / QuickMenuProfile.size;
  final angle = (d.direction + math.pi / 2) % (2 * math.pi);
  return ((angle + step / 2) / step).floor() % QuickMenuProfile.size;
}
