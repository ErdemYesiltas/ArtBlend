import 'package:material_ui/material_ui.dart';

import '../domain/document.dart';
import '../l10n/app_localizations.dart';
import 'overlay_bar.dart';
import 'studio_controller.dart';

class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.controller,
    required this.onDelete,
    required this.onMask,
    required this.onExport,
    required this.onDuplicate,
  });
  final StudioController controller;
  final VoidCallback onDelete, onExport, onMask, onDuplicate;
  @override
  Widget build(BuildContext context) {
    final c = controller, l = AppLocalizations.of(context);
    final enabled = !c.documentTransition && !c.selectionDrawing;
    final selected = enabled && c.selection != null;
    final editable =
        selected &&
        !c.document.activeLayer.locked &&
        c.document.activeLayer.visible;
    final feather = c.selection?.feather ?? 0;
    final actions = <(String, IconData, VoidCallback?, String)>[
      (
        l.invertSelection,
        Icons.flip_to_back,
        selected ? c.invertSelection : null,
        'selection-invert',
      ),
      (
        l.deselect,
        Icons.deselect,
        selected ? () => c.setSelection(null) : null,
        'selection-deselect',
      ),
      (
        feather > 0 ? l.featherAmount(feather.round()) : l.featherSelection,
        Icons.blur_on,
        selected ? () => _feather(context) : null,
        'selection-feather-open',
      ),
      (
        l.copyPasteSelection,
        Icons.copy_all_outlined,
        selected ? onDuplicate : null,
        'selection-copy-paste',
      ),
      (
        l.deleteSelected,
        Icons.delete_outline,
        editable ? onDelete : null,
        'selection-delete',
      ),
      (
        l.transformSelection,
        Icons.open_with,
        editable ? c.beginTransform : null,
        'selection-transform',
      ),
    ];
    final fill = selected && c.hub.paired;
    final hint = switch (c.selectionShape) {
      SelectionShape.automatic =>
        '${l.automaticSelectionHint}\n${l.selectionThreshold} '
            '${(c.autoThreshold * 100).round()}%',
      SelectionShape.freehand => l.freehandSelectionHint,
      SelectionShape.polygon => l.polygonSelectionHint,
      _ => l.selectionHint,
    };
    return OverlayBar(
      key: const ValueKey('selection-bar'),
      engaged: c.canvasEngaged,
      maxWidth: 960,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                barChoices<SelectionShape>(
                  keyPrefix: 'selection-shape',
                  options: {
                    SelectionShape.rectangle: (
                      l.rectangleSelection,
                      Icons.crop_square,
                    ),
                    SelectionShape.ellipse: (
                      l.ellipseSelection,
                      Icons.circle_outlined,
                    ),
                    SelectionShape.freehand: (
                      l.freehandSelection,
                      Icons.gesture,
                    ),
                    SelectionShape.polygon: (
                      l.polygonSelection,
                      Icons.pentagon_outlined,
                    ),
                    SelectionShape.automatic: (
                      l.automaticSelection,
                      Icons.auto_fix_normal,
                    ),
                  },
                  selected: c.selectionShape,
                  onSelected: enabled ? c.setSelectionShape : null,
                ),
                const SizedBox(width: 8),
                barChoices<SelectionMode>(
                  keyPrefix: 'selection-mode',
                  options: {
                    SelectionMode.replace: (l.selectionNew, Icons.crop_free),
                    SelectionMode.add: (l.selectionAdd, Icons.add_box_outlined),
                    SelectionMode.subtract: (
                      l.selectionSubtract,
                      Icons.indeterminate_check_box_outlined,
                    ),
                  },
                  selected: c.selectionMode,
                  onSelected: enabled ? c.setSelectionMode : null,
                ),
                barHint(hint),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  key: const ValueKey('selection-color-fill'),
                  tooltip: l.colorFill,
                  isSelected: c.selectionColorFill,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? c.toggleSelectionColorFill : null,
                  icon: const Icon(Icons.format_color_fill, size: 20),
                ),
                // Used less often: one menu keeps the bar a single row.
                PopupMenuButton<int>(
                  key: const ValueKey('selection-more'),
                  tooltip: l.actions,
                  enabled: enabled,
                  icon: const Icon(Icons.more_horiz, size: 20),
                  onSelected: (i) => switch (i) {
                    -1 => c.restorePreviousSelection(),
                    -2 => onExport(),
                    -3 => onMask(),
                    -4 => c.saveSelection(),
                    _ => c.loadSelection(i),
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: -1,
                      enabled: c.previousSelection != null,
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.history, size: 20),
                        title: Text(l.previousSelection),
                      ),
                    ),
                    PopupMenuItem(
                      value: -2,
                      enabled: selected,
                      child: ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.file_download_outlined,
                          size: 20,
                        ),
                        title: Text(l.exportSelectionMask),
                      ),
                    ),
                    PopupMenuItem(
                      value: -3,
                      enabled: editable,
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.vignette_outlined, size: 20),
                        title: Text(l.layerMask),
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: -4,
                      enabled:
                          selected &&
                          c.document.savedSelections.length <
                              ArtDocument.maxSavedSelections,
                      child: ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.bookmark_add_outlined,
                          size: 20,
                        ),
                        title: Text(l.saveSelection),
                      ),
                    ),
                    for (final (i, _) in c.document.savedSelections.indexed)
                      PopupMenuItem(
                        value: i,
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.bookmark_outline, size: 20),
                          title: Text(l.savedSelectionName(i + 1)),
                          trailing: IconButton(
                            tooltip: l.deleteChosen,
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              Navigator.pop(context);
                              c.deleteSavedSelection(i);
                            },
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Always in place in polygon mode, so the row never jumps.
                if (c.selectionShape == SelectionShape.polygon)
                  IconButton.filledTonal(
                    key: const ValueKey('close-polygon'),
                    tooltip: l.closePolygon,
                    visualDensity: VisualDensity.compact,
                    onPressed:
                        c.selectionPolygonOpen &&
                            c.selectionDraftShape.length >= 3
                        ? c.closeSelectionPolygon
                        : null,
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                  ),
                for (final (label, icon, run, key) in actions)
                  IconButton(
                    key: ValueKey(key),
                    tooltip: label,
                    visualDensity: VisualDensity.compact,
                    onPressed: run,
                    icon: Icon(icon, size: 20),
                  ),
                if (c.hub.paired)
                  IconButton.filledTonal(
                    key: const ValueKey('selection-generative-fill'),
                    tooltip: l.generativeFill,
                    visualDensity: VisualDensity.compact,
                    onPressed: fill ? c.hubJob.show : null,
                    icon: const Icon(Icons.auto_awesome, size: 20),
                  ),
                IconButton.filled(
                  key: const ValueKey('selection-done'),
                  tooltip: l.selectionDone,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled
                      ? () => c.selectTool(StudioTool.brush)
                      : null,
                  icon: const Icon(Icons.check, size: 20),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _feather(BuildContext context) async {
    final l = AppLocalizations.of(context);
    var value = controller.selection?.feather ?? 0;
    final result = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l.featherSelection),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.featherHint, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              Text(l.featherAmount(value.round())),
              Slider(
                key: const ValueKey('selection-feather'),
                value: value,
                max: 100,
                divisions: 100,
                onChanged: (v) => setState(() => value = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, value),
              child: Text(l.apply),
            ),
          ],
        ),
      ),
    );
    if (result != null) controller.featherSelection(result);
  }
}
