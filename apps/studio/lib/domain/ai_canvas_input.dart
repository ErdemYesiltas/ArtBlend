import 'dart:typed_data';
import 'dart:ui';

import 'selection.dart';

/// Immutable source snapshot and mapping for a single local generation job:
/// [png] is the drawing in [area] (document pixels), sent at [width] ×
/// [height], transparent where [selection] asks for new pixels; the
/// result goes back over [area].
class AiCanvasInput {
  AiCanvasInput({
    required this.documentId,
    required this.revision,
    required this.layerId,
    required Uint8List png,
    required this.width,
    required this.height,
    required this.area,
    this.selection,
  }) : png = Uint8List.fromList(png).asUnmodifiableView();
  final String documentId, layerId;
  final int revision, width, height;
  final Rect area;
  final Uint8List png;
  final SelectionRegion? selection;
}
