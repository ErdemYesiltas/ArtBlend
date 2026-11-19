import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import 'quick_menu.dart';
import 'studio_controller.dart';

(String, IconData) quickActionLook(
  AppLocalizations l,
  QuickAction a,
) => switch (a) {
  QuickAction.newLayer => (l.addLayer, Icons.add_box_outlined),
  QuickAction.duplicateLayer => (l.duplicateLayer, Icons.copy_outlined),
  QuickAction.mergeDown => (l.mergeDown, Icons.merge_type),
  QuickAction.clearLayer => (l.clearLayer, Icons.layers_clear_outlined),
  QuickAction.hideLayer => (l.hideLayer, Icons.visibility_off_outlined),
  QuickAction.alphaLock => (l.alphaLock, Icons.lock_outline),
  QuickAction.clippingMask => (l.clippingMask, Icons.subdirectory_arrow_right),
  QuickAction.fillLayer => (l.fillLayer, Icons.format_color_fill),
  QuickAction.invertLayer => (l.invertLayer, Icons.invert_colors),
  QuickAction.undo => (l.undo, Icons.undo),
  QuickAction.redo => (l.redo, Icons.redo),
  QuickAction.brush => (l.brush, Icons.brush_outlined),
  QuickAction.smudge => (l.smudge, Icons.back_hand_outlined),
  QuickAction.eraser => (l.eraser, Icons.auto_fix_normal_outlined),
  QuickAction.eyedropper => (l.eyedropper, Icons.colorize_outlined),
  QuickAction.selection => (l.selection, Icons.highlight_alt),
  QuickAction.transform => (l.transformLayer, Icons.open_with),
  QuickAction.deselect => (l.deselect, Icons.deselect),
  QuickAction.invertSelection => (l.invertSelection, Icons.flip_to_back),
  QuickAction.cut => (l.cut, Icons.content_cut),
  QuickAction.copy => (l.copy, Icons.content_copy),
  QuickAction.paste => (l.paste, Icons.content_paste),
  QuickAction.flipHorizontal => (l.flipCanvasHorizontal, Icons.flip),
  QuickAction.flipVertical => (
    l.flipCanvasVertical,
    Icons.flip_camera_android_outlined,
  ),
  QuickAction.swapColor => (l.swapColor, Icons.swap_horiz),
  QuickAction.addText => (l.addText, Icons.title),
  QuickAction.liquify => (l.liquify, Icons.water_drop_outlined),
  QuickAction.fullScreen => (l.fullScreen, Icons.fullscreen),
  QuickAction.layers => (l.layers, Icons.layers_outlined),
  QuickAction.colors => (l.colors, Icons.palette_outlined),
  QuickAction.brushes => (l.brushLibrary, Icons.brush),
  QuickAction.adjustments => (l.adjustments, Icons.tune),
  QuickAction.reference => (l.reference, Icons.picture_in_picture_alt_outlined),
};

Future<void> _assign(
  BuildContext context,
  StudioController controller,
  int slot, {
  QuickMenuProfile? profile,
}) async {
  final l = AppLocalizations.of(context);
  final target = profile ?? controller.quickMenu;
  final action = await showDialog<QuickAction>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l.quickMenuAssign),
      children: [
        for (final a in QuickAction.values)
          SimpleDialogOption(
            key: ValueKey('quick-assign-${a.name}'),
            onPressed: () => Navigator.pop(context, a),
            child: Row(
              children: [
                Icon(quickActionLook(l, a).$2, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(quickActionLook(l, a).$1)),
                if (target.slots[slot] == a) const Icon(Icons.check, size: 18),
              ],
            ),
          ),
      ],
    ),
  );
  if (action != null) {
    controller.assignQuickAction(slot, action, profileId: target.id);
  }
}

/// The QuickMenu profiles: pick, rename, delete, add, and each one's six
/// buttons.
Future<void> showQuickMenuProfiles(
  BuildContext context,
  StudioController controller,
  Future<String?> Function(String current) askName,
) => showDialog<void>(
  context: context,
  builder: (context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final c = controller;
      return AlertDialog(
        title: Text(l.quickMenuProfiles),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in c.quickMenuProfiles) ...[
                ListTile(
                  key: ValueKey('quick-profile-${p.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  selected: p.id == c.quickMenu.id,
                  leading: Icon(
                    p.id == c.quickMenu.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                  ),
                  title: Text(p.name),
                  onTap: () => c.selectQuickMenu(p.id),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: l.rename,
                        iconSize: 18,
                        onPressed: () async {
                          final name = (await askName(p.name))?.trim();
                          if (name != null && name.isNotEmpty) {
                            c.renameQuickMenu(p.id, name);
                          }
                        },
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        key: ValueKey('quick-profile-delete-${p.id}'),
                        tooltip: l.deletePreset,
                        iconSize: 18,
                        onPressed: c.quickMenuProfiles.length < 2
                            ? null
                            : () => c.deleteQuickMenu(p.id),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
                // The profile's six buttons: tap one to change it.
                Padding(
                  padding: const EdgeInsets.only(left: 36, bottom: 8),
                  child: Wrap(
                    spacing: 4,
                    children: [
                      for (var i = 0; i < QuickMenuProfile.size; i++)
                        IconButton.outlined(
                          key: ValueKey('quick-profile-${p.id}-slot-$i'),
                          tooltip: quickActionLook(l, p.slots[i]).$1,
                          iconSize: 18,
                          onPressed: () =>
                              _assign(context, controller, i, profile: p),
                          icon: Icon(quickActionLook(l, p.slots[i]).$2),
                        ),
                    ],
                  ),
                ),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('quick-profile-add'),
                  onPressed: () => c.addQuickMenu(
                    l.quickMenuProfileName(c.quickMenuProfiles.length + 1),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l.quickMenuNewProfile),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.done),
          ),
        ],
      );
    },
  ),
);

/// The open QuickMenu, over everything, around [StudioController.quickMenuAt]
/// (global coordinates: it lives in the root overlay).
class QuickMenuOverlay extends StatelessWidget {
  const QuickMenuOverlay({
    super.key,
    required this.controller,
    required this.onAction,
    required this.askName,
  });
  final StudioController controller;
  final void Function(QuickAction action) onAction;
  final Future<String?> Function(String current) askName;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final at = controller.quickMenuAt;
      if (at == null) return const SizedBox.shrink();
      final l = AppLocalizations.of(context);
      final scheme = Theme.of(context).colorScheme;
      final screen = MediaQuery.sizeOf(context);
      // Kept on screen whole.
      const reach = quickMenuRadius + 40;
      final centre = Offset(
        at.dx.clamp(reach, screen.width - reach),
        at.dy.clamp(reach, screen.height - reach),
      );
      final profile = controller.quickMenu;
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('quick-menu-away'),
              behavior: HitTestBehavior.opaque,
              onTap: controller.closeQuickMenu,
            ),
          ),
          for (var i = 0; i < QuickMenuProfile.size; i++)
            Builder(
              builder: (context) {
                final p = quickMenuSlot(centre, i);
                final (name, icon) = quickActionLook(l, profile.slots[i]);
                final hot = controller.quickMenuHover == i;
                return Positioned(
                  left: p.dx - 28,
                  top: p.dy - 28,
                  child: Tooltip(
                    message: name,
                    child: Material(
                      key: ValueKey('quick-slot-$i'),
                      shape: const CircleBorder(),
                      elevation: 6,
                      color: hot ? scheme.primary : scheme.surface,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => onAction(profile.slots[i]),
                        onLongPress: () => _assign(context, controller, i),
                        child: SizedBox.square(
                          dimension: 56,
                          child: Icon(
                            icon,
                            color: hot ? scheme.onPrimary : scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          Positioned(
            left: centre.dx - quickMenuHub,
            top: centre.dy - quickMenuHub,
            child: Tooltip(
              message: l.quickMenuHint,
              child: Material(
                key: const ValueKey('quick-hub'),
                shape: const CircleBorder(),
                elevation: 6,
                color: scheme.secondaryContainer,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: controller.nextQuickMenu,
                  onLongPress: () =>
                      showQuickMenuProfiles(context, controller, askName),
                  child: SizedBox.square(
                    dimension: quickMenuHub * 2,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          profile.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
