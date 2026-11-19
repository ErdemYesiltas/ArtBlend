import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/document.dart';
import '../drawing/brush_engine.dart';
import '../l10n/app_localizations.dart';
import 'color_picker.dart';
import 'studio_controller.dart';
import 'value_slider.dart';

/// Procreate-style layers: thumbnails top to bottom, drag to reorder, a
/// visibility box, the blend letter opening opacity and blend mode, and the
/// active layer's options on a second tap.
/// A blend mode's name.
String layerBlendName(AppLocalizations l, LayerBlend blend) => switch (blend) {
  LayerBlend.normal => l.blendNormal,
  LayerBlend.multiply => l.blendMultiply,
  LayerBlend.darken => l.blendDarken,
  LayerBlend.colorBurn => l.blendColorBurn,
  LayerBlend.screen => l.blendScreen,
  LayerBlend.lighten => l.blendLighten,
  LayerBlend.colorDodge => l.blendColorDodge,
  LayerBlend.add => l.blendAdd,
  LayerBlend.overlay => l.blendOverlay,
  LayerBlend.softLight => l.blendSoftLight,
  LayerBlend.hardLight => l.blendHardLight,
  LayerBlend.difference => l.blendDifference,
  LayerBlend.linearBurn => l.blendLinearBurn,
  LayerBlend.darkerColor => l.blendDarkerColor,
  LayerBlend.lighterColor => l.blendLighterColor,
  LayerBlend.vividLight => l.blendVividLight,
  LayerBlend.linearLight => l.blendLinearLight,
  LayerBlend.pinLight => l.blendPinLight,
  LayerBlend.hardMix => l.blendHardMix,
  LayerBlend.exclusion => l.blendExclusion,
  LayerBlend.subtract => l.blendSubtract,
  LayerBlend.divide => l.blendDivide,
  LayerBlend.hue => l.blendHue,
  LayerBlend.saturation => l.blendSaturation,
  LayerBlend.color => l.blendColor,
  LayerBlend.luminosity => l.blendLuminosity,
};

class LayersPanel extends StatefulWidget {
  const LayersPanel({
    super.key,
    required this.controller,
    required this.run,
    required this.askName,
    this.exportLayer,
  });
  final StudioController controller;

  /// Saves a layer's pixels as a PNG file.
  final Future<void> Function(ArtLayer layer)? exportLayer;

  /// Runs an action and reports its failure, as the editor does.
  final Future<void> Function(Future<void> Function()) run;
  final Future<String?> Function(String current) askName;

  @override
  State<LayersPanel> createState() => _LayersPanelState();
}

enum _LayerAction {
  editText,
  rasterize,
  rename,
  private,
  group,
  leaveGroup,
  selectContents,
  assist,
  duplicate,
  export,
  mergeDown,
  clear,
  lock,
  reference,
  alphaLock,
  clipping,
  fill,
  invert,
  removeMask,
  delete,
}

class _LayersPanelState extends State<LayersPanel> {
  /// The layer whose opacity and blend mode are open.
  String? editing;

  StudioController get c => widget.controller;

  static String letter(LayerBlend blend) => switch (blend) {
    LayerBlend.normal => 'N',
    LayerBlend.multiply => 'M',
    LayerBlend.darken => 'Da',
    LayerBlend.colorBurn => 'Cb',
    LayerBlend.screen => 'S',
    LayerBlend.lighten => 'Li',
    LayerBlend.colorDodge => 'Cd',
    LayerBlend.add => 'A',
    LayerBlend.overlay => 'O',
    LayerBlend.softLight => 'Sl',
    LayerBlend.hardLight => 'Hl',
    LayerBlend.difference => 'Di',
    LayerBlend.linearBurn => 'Lb',
    LayerBlend.darkerColor => 'Dc',
    LayerBlend.lighterColor => 'Lc',
    LayerBlend.vividLight => 'Vl',
    LayerBlend.linearLight => 'Ll',
    LayerBlend.pinLight => 'Pl',
    LayerBlend.hardMix => 'Hm',
    LayerBlend.exclusion => 'E',
    LayerBlend.subtract => 'Su',
    LayerBlend.divide => 'Dv',
    LayerBlend.hue => 'H',
    LayerBlend.saturation => 'Sa',
    LayerBlend.color => 'C',
    LayerBlend.luminosity => 'L',
  };

  Future<void> _options(ArtLayer layer, Offset at) async {
    final l = AppLocalizations.of(context);
    final layers = c.document.layers;
    final index = layers.indexOf(layer);
    final below = index > 0 ? layers[index - 1] : null;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<_LayerAction>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        if (layer.text != null) ...[
          PopupMenuItem(
            value: _LayerAction.editText,
            enabled: !layer.locked,
            child: Text(l.editText),
          ),
          PopupMenuItem(
            value: _LayerAction.rasterize,
            enabled: !layer.locked,
            child: Text(l.rasterize),
          ),
        ],
        PopupMenuItem(value: _LayerAction.rename, child: Text(l.renameLayer)),
        PopupMenuItem(value: _LayerAction.group, child: Text(l.groupLayers)),
        PopupMenuItem(
          value: _LayerAction.selectContents,
          child: Text(l.selectLayerContents),
        ),
        CheckedPopupMenuItem(
          value: _LayerAction.private,
          checked: layer.private,
          child: Tooltip(message: l.privateHint, child: Text(l.privateLayer)),
        ),
        CheckedPopupMenuItem(
          value: _LayerAction.assist,
          checked: layer.assisted,
          child: Text(l.drawingAssist),
        ),
        if (layer.group != null)
          PopupMenuItem(
            value: _LayerAction.leaveGroup,
            child: Text(l.leaveGroup),
          ),
        PopupMenuItem(
          value: _LayerAction.duplicate,
          enabled: layers.length < StudioController.maxLayers,
          child: Text(l.duplicateLayer),
        ),
        if (widget.exportLayer != null)
          PopupMenuItem(value: _LayerAction.export, child: Text(l.exportLayer)),
        PopupMenuItem(
          value: _LayerAction.mergeDown,
          enabled: below != null && !layer.locked && !below.locked,
          child: Text(l.mergeDown),
        ),
        PopupMenuItem(
          value: _LayerAction.clear,
          enabled: !layer.locked,
          child: Text(l.clearLayer),
        ),
        PopupMenuItem(
          value: _LayerAction.lock,
          child: Text(layer.locked ? l.unlockLayer : l.lockLayer),
        ),
        CheckedPopupMenuItem(
          value: _LayerAction.alphaLock,
          checked: layer.alphaLock,
          enabled: !layer.locked,
          child: Text(l.alphaLock),
        ),
        CheckedPopupMenuItem(
          value: _LayerAction.clipping,
          checked: layer.clipping,
          enabled: !layer.locked && (index > 0 || layer.clipping),
          child: Text(l.clippingMask),
        ),
        PopupMenuItem(
          value: _LayerAction.fill,
          enabled: !layer.locked,
          child: Text(l.fillLayer),
        ),
        PopupMenuItem(
          value: _LayerAction.invert,
          enabled: !layer.locked,
          child: Text(l.invertLayer),
        ),
        CheckedPopupMenuItem(
          value: _LayerAction.reference,
          checked: layer.reference,
          child: Text(l.referenceLayer),
        ),
        if (layer.mask != null)
          PopupMenuItem(
            value: _LayerAction.removeMask,
            enabled: !layer.locked,
            child: Text(l.removeLayerMask),
          ),
        PopupMenuItem(
          value: _LayerAction.delete,
          enabled: layers.length > 1,
          child: Text(l.deleteLayer),
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _LayerAction.editText:
        c.editText(layer.id);
      case _LayerAction.rasterize:
        await widget.run(() => c.rasterizeText(layer.id));
      case _LayerAction.rename:
        await widget.run(() async {
          final name = await widget.askName(layer.name);
          if (name != null && name.trim().isNotEmpty) {
            c.updateLayer(layer.id, (l) => l.copyWith(name: name.trim()));
          }
        });
      case _LayerAction.group:
        c.groupLayers(
          l.groupName(c.document.groups.length + 1),
          ids: c.selectedLayers.isEmpty ? [layer.id] : null,
        );
      case _LayerAction.assist:
        c.toggleDrawingAssist(layer.id);
      case _LayerAction.private:
        c.togglePrivateLayer(layer.id);
      case _LayerAction.selectContents:
        await widget.run(() async {
          await c.selectLayerContents(layer.id);
          c.setPanel(null);
          c.selectTool(StudioTool.selection);
        });
      case _LayerAction.leaveGroup:
        // Out just above its group.
        final rest = [
          for (final x in c.document.layers)
            if (x.id != layer.id) x,
        ];
        c.placeLayer(
          layer.id,
          rest.lastIndexWhere((x) => x.group == layer.group) + 1,
        );
      case _LayerAction.duplicate:
        c.duplicateLayer(layer.id, l.layerCopy(layer.name));
      case _LayerAction.export:
        await widget.run(() => widget.exportLayer!(layer));
      case _LayerAction.mergeDown:
        await widget.run(() => c.mergeDown(layer.id));
      case _LayerAction.clear:
        c.clearLayer(layer.id);
      case _LayerAction.lock:
        c.updateLayer(layer.id, (l) => l.copyWith(locked: !l.locked));
      case _LayerAction.alphaLock:
        c.toggleAlphaLock(layer.id);
      case _LayerAction.clipping:
        c.toggleClipping(layer.id);
      case _LayerAction.fill:
        await widget.run(c.fillActiveLayer);
      case _LayerAction.invert:
        await widget.run(c.invertActiveLayer);
      case _LayerAction.reference:
        c.toggleReferenceLayer(layer.id);
      case _LayerAction.removeMask:
        c.updateLayer(layer.id, (l) => l.copyWith(clearMask: true));
      case _LayerAction.delete:
        c.deleteLayer(layer.id);
    }
  }

  /// The panel's rows top to bottom: a group's header above its layers,
  /// which a folded group hides.
  List<_Row> _rows() {
    final doc = c.document;
    final rows = <_Row>[];
    String? current;
    for (final layer in doc.layers.reversed) {
      final group = doc.groupOf(layer);
      if (group != null && group.id != current) rows.add(_Row.group(group));
      current = group?.id;
      if (group == null || !group.collapsed) rows.add(_Row.layer(layer));
    }
    return rows;
  }

  /// Where a row dropped at [to] (in [rows] as reordered) lands: the
  /// bottom-to-top index among the layers that are not moving.
  int _landing(List<_Row> rows, int to, List<ArtLayer> rest) {
    for (final row in rows.skip(to + 1)) {
      if (row.layer case final layer?) {
        final i = rest.indexWhere((x) => x.id == layer.id);
        if (i >= 0) return i + 1;
      } else {
        final i = rest.lastIndexWhere((x) => x.group == row.group!.id);
        if (i >= 0) return i + 1;
      }
    }
    return 0;
  }

  void _reorder(List<_Row> rows, int from, int to) {
    final moved = rows[from];
    final next = [...rows]..removeAt(from);
    next.insert(to, moved);
    final layers = c.document.layers;
    if (moved.group case final group?) {
      final rest = [
        for (final l in layers)
          if (l.group != group.id) l,
      ];
      final without = [
        for (final r in next)
          if (r.layer?.group != group.id) r,
      ];
      c.placeGroup(group.id, _landing(without, without.indexOf(moved), rest));
      return;
    }
    final layer = moved.layer!;
    final rest = [
      for (final l in layers)
        if (l.id != layer.id) l,
    ];
    // Under a group's header or one of its layers: into that group.
    final above = to > 0 ? next[to - 1] : null;
    final group = above?.group?.id ?? above?.layer?.group;
    c.placeLayer(layer.id, _landing(next, to, rest), group: group);
  }

  /// Pinch: two fingers on two layers coming together merge them and the
  /// layers between.
  final Map<int, (Offset, Offset)> _pinch = {};

  /// The layer row each finger came down on.
  final Map<int, String> _pinchRows = {};

  void _pinchEnd() {
    if (_pinch.length != 2) {
      _pinch.clear();
      _pinchRows.clear();
      return;
    }
    final [a, b] = _pinch.keys.toList();
    final (a0, a1) = _pinch[a]!;
    final (b0, b1) = _pinch[b]!;
    final first = _pinchRows[a], second = _pinchRows[b];
    _pinch.clear();
    _pinchRows.clear();
    final before = (a0 - b0).distance, after = (a1 - b1).distance;
    if (before < 40 || after > before * .5) return;
    if (first == null || second == null || first == second) return;
    final layers = c.document.layers;
    final i = layers.indexWhere((l) => l.id == first);
    final j = layers.indexWhere((l) => l.id == second);
    final range = layers.sublist(math.min(i, j), math.max(i, j) + 1);
    unawaited(widget.run(() => c.mergeLayers(range.map((l) => l.id))));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final layers = c.document.layers;
    final rows = _rows();
    final chosen = c.chosenLayers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.layerCount(layers.length, StudioController.maxLayers),
                style: const TextStyle(fontSize: 11),
              ),
            ),
            IconButton(
              key: const ValueKey('layers-add'),
              tooltip: l.addLayer,
              onPressed: layers.length < StudioController.maxLayers
                  ? () => c.addLayer(l.layerName(layers.length + 1))
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (chosen.length > 1) _choiceBar(l, chosen),
        Listener(
          onPointerDown: (e) {
            if (e.kind == ui.PointerDeviceKind.touch) {
              _pinch[e.pointer] = (e.position, e.position);
            }
          },
          onPointerMove: (e) {
            final start = _pinch[e.pointer];
            if (start != null) _pinch[e.pointer] = (start.$1, e.position);
          },
          onPointerUp: (e) {
            if (_pinch.containsKey(e.pointer)) _pinchEnd();
          },
          onPointerCancel: (_) {
            _pinch.clear();
            _pinchRows.clear();
          },
          child: ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) => _reorder(rows, from, to),
            children: [
              for (final (i, row) in rows.indexed)
                ReorderableDelayedDragStartListener(
                  key: ValueKey(row.layer?.id ?? 'group-${row.group!.id}'),
                  index: i,
                  child: row.layer != null
                      ? _row(l, row.layer!)
                      : _groupHeader(l, row.group!),
                ),
            ],
          ),
        ),
        _background(l),
        const SizedBox(height: 6),
        Text(l.layersHint, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  /// Several layers chosen: what acts on all of them.
  Widget _choiceBar(AppLocalizations l, List<ArtLayer> chosen) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      key: const ValueKey('layer-choice-bar'),
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 0, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.chosenLayers(chosen.length),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: l.cancel,
                  visualDensity: VisualDensity.compact,
                  onPressed: c.clearLayerChoice,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
            Wrap(
              spacing: 4,
              children: [
                FilledButton.tonal(
                  key: const ValueKey('choice-group'),
                  onPressed: () =>
                      c.groupLayers(l.groupName(c.document.groups.length + 1)),
                  child: Text(l.groupLayers),
                ),
                FilledButton.tonal(
                  key: const ValueKey('choice-merge'),
                  onPressed: chosen.any((x) => x.locked)
                      ? null
                      : () => widget.run(
                          () => c.mergeLayers(chosen.map((x) => x.id)),
                        ),
                  child: Text(l.mergeChosen),
                ),
                TextButton(
                  key: const ValueKey('choice-delete'),
                  onPressed: chosen.length < c.document.layers.length
                      ? c.deleteChosenLayers
                      : null,
                  child: Text(l.deleteChosen),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _groupHeader(AppLocalizations l, LayerGroup group) {
    final scheme = Theme.of(context).colorScheme;
    final open = editing == 'group:${group.id}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        key: ValueKey('group-header-${group.id}'),
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            InkWell(
              onTapUp: (d) => _groupOptions(l, group, d.globalPosition),
              child: Row(
                children: [
                  IconButton(
                    key: ValueKey('group-fold-${group.id}'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => c.toggleGroupCollapsed(group.id),
                    icon: Icon(
                      group.collapsed ? Icons.chevron_right : Icons.expand_more,
                      size: 20,
                    ),
                  ),
                  const Icon(Icons.folder_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: group.visible ? null : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    key: ValueKey('group-blend-${group.id}'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(36, 36),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => setState(
                      () => editing = open ? null : 'group:${group.id}',
                    ),
                    child: _blendBadge(
                      group.blend,
                      group.opacity,
                      group.passThrough
                          ? scheme.onSurfaceVariant
                          : scheme.primary,
                    ),
                  ),
                  Checkbox(
                    key: ValueKey('group-visible-${group.id}'),
                    value: group.visible,
                    onChanged: (value) => c.updateGroup(
                      group.id,
                      (g) => g.copyWith(visible: value ?? true),
                    ),
                  ),
                ],
              ),
            ),
            if (open)
              _blending(
                l,
                opacity: group.opacity,
                blend: group.blend,
                onOpacity: (v) =>
                    c.updateGroup(group.id, (g) => g.copyWith(opacity: v)),
                onBlend: (b) =>
                    c.updateGroup(group.id, (g) => g.copyWith(blend: b)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _groupOptions(
    AppLocalizations l,
    LayerGroup group,
    Offset at,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final ids = [
      for (final x in c.document.layers)
        if (x.group == group.id) x.id,
    ];
    final action = await showMenu<int>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(value: 0, child: Text(l.renameGroup)),
        PopupMenuItem(value: 1, child: Text(l.ungroup)),
        PopupMenuItem(
          value: 2,
          enabled: ids.length > 1,
          child: Text(l.flattenGroup),
        ),
        PopupMenuItem(
          value: 3,
          enabled: ids.length < c.document.layers.length,
          child: Text(l.deleteGroup),
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 0:
        await widget.run(() async {
          final name = await widget.askName(group.name);
          if (name != null && name.trim().isNotEmpty) {
            c.updateGroup(group.id, (g) => g.copyWith(name: name.trim()));
          }
        });
      case 1:
        c.ungroup(group.id);
      case 2:
        await widget.run(() => c.mergeLayers(ids));
      case 3:
        c.deleteGroup(group.id);
    }
  }

  /// The background colour layer, always last: tap for its colour, the
  /// box hides it (transparent drawing and PNG).
  Widget _background(AppLocalizations l) {
    final doc = c.document;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('layer-background'),
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _pickBackground,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 0, 4),
          child: Row(
            children: [
              Container(
                width: LayerThumbnail.height,
                height: LayerThumbnail.height,
                decoration: BoxDecoration(
                  color: Color(doc.background),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: scheme.outlineVariant),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l.backgroundColor,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Checkbox(
                key: const ValueKey('layer-background-visible'),
                value: !doc.backgroundHidden,
                onChanged: (_) => c.toggleBackground(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickBackground() async {
    final l = AppLocalizations.of(context);
    var color = c.document.background;
    final chosen = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l.backgroundColor),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: ColorPicker(
                color: color,
                onColor: (value) => setState(() => color = value),
                recent: c.recentColors,
                hexField: const SizedBox.shrink(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, color),
              child: Text(l.apply),
            ),
          ],
        ),
      ),
    );
    if (chosen != null) c.setBackground(chosen);
  }

  Widget _row(AppLocalizations l, ArtLayer layer) {
    final scheme = Theme.of(context).colorScheme;
    final active = layer.id == c.document.activeLayerId;
    final chosen = c.selectedLayers.contains(layer.id);
    final open = editing == layer.id;
    return Padding(
      // A group's layers sit indented under its header.
      padding: EdgeInsets.only(bottom: 4, left: layer.group != null ? 16 : 0),
      child: Listener(
        onPointerDown: (e) => _pinchRows[e.pointer] = layer.id,
        child: Material(
          color: active
              ? scheme.primaryContainer
              : chosen
              ? scheme.secondaryContainer
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final keys = HardwareKeyboard.instance;
                  if (!active &&
                      (keys.isMetaPressed ||
                          keys.isControlPressed ||
                          keys.isShiftPressed)) {
                    c.toggleLayerChoice(layer.id);
                  } else if (active) {
                    unawaited(_options(layer, details.globalPosition));
                  } else {
                    c.selectLayer(layer.id);
                  }
                },
                // Swipe right: chosen too (Procreate's secondary selection).
                onHorizontalDragEnd: (details) {
                  if ((details.primaryVelocity ?? 0) > 150) {
                    c.toggleLayerChoice(layer.id);
                  }
                },
                child: Padding(
                  // Clipped layers sit indented under their base, as in Procreate.
                  padding: EdgeInsets.fromLTRB(layer.clipping ? 4 : 6, 4, 0, 4),
                  child: Row(
                    children: [
                      if (layer.clipping)
                        const Padding(
                          padding: EdgeInsets.only(right: 2),
                          child: Icon(Icons.subdirectory_arrow_right, size: 16),
                        ),
                      LayerThumbnail(
                        layer: layer,
                        dimensions: c.document.dimensions,
                        images: c.rasters.images,
                        active: active,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (layer.text != null)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Icon(Icons.title, size: 14),
                                  ),
                                Expanded(
                                  child: Text(
                                    layer.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: active
                                          ? FontWeight.w600
                                          : null,
                                      color: layer.visible
                                          ? null
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (layer.locked ||
                                layer.mask != null ||
                                layer.reference ||
                                layer.alphaLock ||
                                layer.assisted ||
                                layer.private)
                              Row(
                                children: [
                                  if (layer.locked)
                                    const Icon(Icons.lock_outline, size: 12),
                                  if (layer.mask != null) ...[
                                    if (layer.locked) const SizedBox(width: 4),
                                    Text(
                                      l.layerMask,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ],
                                  if (layer.alphaLock) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      l.alphaLock,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ],
                                  if (layer.assisted) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      l.drawingAssist,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ],
                                  if (layer.private) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.shield_outlined,
                                      key: ValueKey(
                                        'layer-private-${layer.id}',
                                      ),
                                      size: 12,
                                    ),
                                    Text(
                                      l.privateLayer,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ],
                                  if (layer.reference) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      l.referenceLayer,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ],
                                ],
                              ),
                          ],
                        ),
                      ),
                      TextButton(
                        key: ValueKey('layer-blend-${layer.id}'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(36, 36),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () =>
                            setState(() => editing = open ? null : layer.id),
                        child: _blendBadge(
                          layer.blend,
                          layer.opacity,
                          layer.blend == LayerBlend.normal && layer.opacity == 1
                              ? scheme.onSurfaceVariant
                              : scheme.primary,
                        ),
                      ),
                      // Press and hold: Solo (only this layer shows).
                      GestureDetector(
                        onLongPress: () => c.toggleSolo(layer.id),
                        child: Checkbox(
                          key: ValueKey('layer-visible-${layer.id}'),
                          value: layer.visible,
                          onChanged: (value) => c.updateLayer(
                            layer.id,
                            (l) => l.copyWith(visible: value ?? true),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (open)
                _blending(
                  l,
                  opacity: layer.opacity,
                  blend: layer.blend,
                  onOpacity: layer.locked
                      ? null
                      : (v) => c.updateLayer(
                          layer.id,
                          (x) => x.copyWith(opacity: v),
                        ),
                  onBlend: layer.locked
                      ? null
                      : (b) => c.updateLayer(
                          layer.id,
                          (x) => x.copyWith(blend: b),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The blend letter over the opacity, as a layer row shows them.
  Widget _blendBadge(LayerBlend blend, double opacity, Color color) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        letter(blend),
        style: TextStyle(fontWeight: FontWeight.w600, color: color),
      ),
      Text(
        '${(opacity * 100).round()}%',
        style: TextStyle(fontSize: 9, color: color),
      ),
    ],
  );

  /// Procreate's blend groups: a divider before each.
  static const _blendGroupStarts = {
    LayerBlend.darken,
    LayerBlend.lighten,
    LayerBlend.overlay,
    LayerBlend.difference,
    LayerBlend.hue,
  };

  Widget _blending(
    AppLocalizations l, {
    required double opacity,
    required LayerBlend blend,
    required ValueChanged<double>? onOpacity,
    required ValueChanged<LayerBlend>? onBlend,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Opacity(value: opacity, label: l.opacity, onCommit: onOpacity),
        Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                l.blendMode,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            Expanded(
              child: DropdownButton<LayerBlend>(
                key: const ValueKey('blend-dropdown'),
                value: blend,
                isExpanded: true,
                isDense: true,
                menuMaxHeight: 420,
                onChanged: onBlend == null ? null : (b) => onBlend(b!),
                selectedItemBuilder: (context) => [
                  for (final mode in LayerBlend.values)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        layerBlendName(l, mode),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
                items: [
                  for (final mode in LayerBlend.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Container(
                        decoration: _blendGroupStarts.contains(mode)
                            ? BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                  ),
                                ),
                              )
                            : null,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          layerBlendName(l, mode),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// A panel row: a group's header or a layer.
class _Row {
  _Row.group(LayerGroup this.group) : layer = null;
  _Row.layer(ArtLayer this.layer) : group = null;
  final LayerGroup? group;
  final ArtLayer? layer;
}

class _Opacity extends StatefulWidget {
  const _Opacity({
    required this.value,
    required this.label,
    required this.onCommit,
  });
  final double value;
  final String label;
  final ValueChanged<double>? onCommit;
  @override
  State<_Opacity> createState() => _OpacityState();
}

class _OpacityState extends State<_Opacity> {
  late double value = widget.value;

  @override
  void didUpdateWidget(covariant _Opacity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) value = widget.value;
  }

  @override
  Widget build(BuildContext context) => ValueSlider(
    label: widget.label,
    value: value,
    labelWidth: 52,
    onChanged: widget.onCommit == null
        ? null
        : (v) => setState(() => value = v),
    onChangeEnd: widget.onCommit,
  );
}

/// A small picture of one layer's own pixels on a checkerboard, rendered
/// once per layer version (layers are immutable).
class LayerThumbnail extends StatelessWidget {
  const LayerThumbnail({
    super.key,
    required this.layer,
    required this.dimensions,
    required this.images,
    this.active = false,
  });
  final ArtLayer layer;
  final CanvasSize dimensions;
  final Map<RasterAsset, ui.Image> images;
  final bool active;

  static const height = 40.0;
  static final _cache = Expando<Future<ui.Image>>();

  Size get size {
    final aspect = dimensions.width / dimensions.height;
    return Size(math.min(height * aspect, 56), height);
  }

  Future<ui.Image> _render(double ratio) async {
    final pixels = size * ratio;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..scale(
        pixels.width / dimensions.width,
        pixels.height / dimensions.height,
      );
    paintLayer(
      canvas,
      layer,
      FreehandBrushEngine(),
      dimensions,
      rasterImages: images,
      applyOpacity: false,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(pixels.width.ceil(), pixels.height.ceil());
    } finally {
      picture.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final scheme = Theme.of(context).colorScheme;
    final image = _cache[layer] ??= _render(ratio);
    return Container(
      width: size.width,
      height: size.height,
      decoration: BoxDecoration(
        border: Border.all(
          color: active ? scheme.primary : scheme.outlineVariant,
          width: active ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: CustomPaint(
          painter: _Checkerboard(),
          child: FutureBuilder(
            future: image,
            builder: (context, snapshot) => snapshot.hasData
                ? RawImage(image: snapshot.data, fit: BoxFit.fill)
                : const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _Checkerboard extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final grey = Paint()..color = const Color(0xffdedede);
    const cell = 5.0;
    for (var y = 0.0; y < size.height; y += cell) {
      for (
        var x = ((y / cell).floor().isOdd ? cell : 0.0);
        x < size.width;
        x += cell * 2
      ) {
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), grey);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
