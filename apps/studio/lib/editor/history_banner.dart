import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import 'history_change.dart';

/// Names each undo and redo for a moment, as Procreate's banner does.
class HistoryBanner extends StatefulWidget {
  const HistoryBanner({super.key, required this.notice});
  final ValueListenable<(int, bool, HistoryChange)?> notice;

  @override
  State<HistoryBanner> createState() => _HistoryBannerState();
}

class _HistoryBannerState extends State<HistoryBanner> {
  Timer? _hide;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.notice.addListener(_show);
  }

  @override
  void dispose() {
    widget.notice.removeListener(_show);
    _hide?.cancel();
    super.dispose();
  }

  void _show() {
    _hide?.cancel();
    setState(() => _visible = widget.notice.value != null);
    _hide = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  static String _name(AppLocalizations l, HistoryChange change) =>
      switch (change) {
        HistoryChange.paint => l.historyPaint,
        HistoryChange.addLayer => l.historyAddLayer,
        HistoryChange.deleteLayer => l.historyDeleteLayer,
        HistoryChange.mergeLayers => l.historyMergeLayers,
        HistoryChange.moveLayer => l.historyMoveLayer,
        HistoryChange.layerMask => l.historyLayerMask,
        HistoryChange.layerSettings => l.historyLayerSettings,
        HistoryChange.rename => l.historyRename,
        HistoryChange.canvas => l.historyCanvas,
        HistoryChange.edit => l.historyEdit,
      };

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice.value;
    final l = AppLocalizations.of(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: notice == null
            ? const SizedBox.shrink()
            : Material(
                key: const ValueKey('history-banner'),
                color: Theme.of(context).colorScheme.inverseSurface,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Text(
                    (notice.$2 ? l.undone : l.redone)(_name(l, notice.$3)),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onInverseSurface,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
