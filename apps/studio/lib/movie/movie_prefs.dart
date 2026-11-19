import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../editor/value_slider.dart';
import '../l10n/app_localizations.dart';

/// What a movie keyboard shortcut does.
enum MovieAction {
  play,
  stepBack,
  stepForward,
  undo,
  redo,
  copy,
  cut,
  paste,
  duplicate,
  delete,
  keyframes,
  perform,
  fullscreen,
}

/// Movie preferences (Dreams' Prefs), kept on the device: on-stage undo
/// buttons and how fast a held one repeats, undo depth, tap gestures,
/// keyboard shortcuts.
class MoviePrefs extends ChangeNotifier {
  MoviePrefs(this._prefs) {
    final p = _prefs;
    undoButtons = p?.getBool('movie.undoButtons') ?? true;
    quickUndoMs = p?.getInt('movie.quickUndoMs') ?? 400;
    undoDepth = p?.getInt('movie.undoDepth') ?? 100;
    twoFingerUndo = p?.getBool('movie.twoFingerUndo') ?? true;
    threeFingerRedo = p?.getBool('movie.threeFingerRedo') ?? true;
    shortcuts = {...defaults()};
    try {
      final saved = jsonDecode(p?.getString('movie.shortcuts') ?? '{}');
      if (saved is Map) {
        for (final MapEntry(:key, :value) in saved.entries) {
          final action = MovieAction.values.asNameMap()[key];
          final activator = _fromJson(value);
          if (action != null && activator != null) {
            shortcuts[action] = activator;
          }
        }
      }
    } catch (_) {
      // Damaged: the defaults stand.
    }
  }

  final SharedPreferences? _prefs;
  late bool undoButtons, twoFingerUndo, threeFingerRedo;

  /// How long the on-stage undo is held before it repeats (0: never).
  late int quickUndoMs;
  late int undoDepth;
  late Map<MovieAction, SingleActivator> shortcuts;

  static const minDepth = 10, maxDepth = 500;

  static Map<MovieAction, SingleActivator> defaults() {
    final mac = Platform.isMacOS;
    SingleActivator command(LogicalKeyboardKey key, {bool shift = false}) =>
        SingleActivator(key, meta: mac, control: !mac, shift: shift);
    return {
      MovieAction.play: const SingleActivator(LogicalKeyboardKey.space),
      MovieAction.stepBack: const SingleActivator(LogicalKeyboardKey.arrowLeft),
      MovieAction.stepForward: const SingleActivator(
        LogicalKeyboardKey.arrowRight,
      ),
      MovieAction.undo: command(LogicalKeyboardKey.keyZ),
      MovieAction.redo: command(LogicalKeyboardKey.keyZ, shift: true),
      MovieAction.copy: command(LogicalKeyboardKey.keyC),
      MovieAction.cut: command(LogicalKeyboardKey.keyX),
      MovieAction.paste: command(LogicalKeyboardKey.keyV),
      MovieAction.duplicate: command(LogicalKeyboardKey.keyD),
      MovieAction.delete: const SingleActivator(LogicalKeyboardKey.backspace),
      MovieAction.keyframes: const SingleActivator(LogicalKeyboardKey.keyK),
      MovieAction.perform: const SingleActivator(LogicalKeyboardKey.keyR),
      MovieAction.fullscreen: const SingleActivator(LogicalKeyboardKey.keyF),
    };
  }

  static Map<String, dynamic> _toJson(SingleActivator a) => {
    'key': a.trigger.keyId,
    if (a.control) 'control': true,
    if (a.meta) 'meta': true,
    if (a.shift) 'shift': true,
    if (a.alt) 'alt': true,
  };

  static SingleActivator? _fromJson(Object? json) {
    if (json is! Map || json['key'] is! int) return null;
    final key = LogicalKeyboardKey.findKeyByKeyId(json['key'] as int);
    if (key == null) return null;
    return SingleActivator(
      key,
      control: json['control'] == true,
      meta: json['meta'] == true,
      shift: json['shift'] == true,
      alt: json['alt'] == true,
    );
  }

  /// A shortcut's name as keys: "⌘⇧Z", "Ctrl+C", "Space".
  static String describe(SingleActivator a) {
    final mac = Platform.isMacOS;
    final parts = [
      if (a.control) mac ? '⌃' : 'Ctrl+',
      if (a.alt) mac ? '⌥' : 'Alt+',
      if (a.shift) mac ? '⇧' : 'Shift+',
      if (a.meta) mac ? '⌘' : 'Meta+',
      a.trigger.keyLabel.isEmpty
          ? a.trigger.debugName ?? '?'
          : a.trigger.keyLabel,
    ];
    return parts.join();
  }

  void update(void Function(MoviePrefs p) change) {
    change(this);
    undoDepth = undoDepth.clamp(minDepth, maxDepth);
    final p = _prefs;
    p?.setBool('movie.undoButtons', undoButtons);
    p?.setInt('movie.quickUndoMs', quickUndoMs);
    p?.setInt('movie.undoDepth', undoDepth);
    p?.setBool('movie.twoFingerUndo', twoFingerUndo);
    p?.setBool('movie.threeFingerRedo', threeFingerRedo);
    p?.setString(
      'movie.shortcuts',
      jsonEncode({
        for (final MapEntry(:key, :value) in shortcuts.entries)
          key.name: _toJson(value),
      }),
    );
    notifyListeners();
  }
}

String movieActionName(AppLocalizations l, MovieAction a) => switch (a) {
  MovieAction.play => l.actionPlay,
  MovieAction.stepBack => l.actionStepBack,
  MovieAction.stepForward => l.actionStepForward,
  MovieAction.undo => l.undo,
  MovieAction.redo => l.redo,
  MovieAction.copy => l.copy,
  MovieAction.cut => l.cut,
  MovieAction.paste => l.paste,
  MovieAction.duplicate => l.contentDuplicateAfter,
  MovieAction.delete => l.galleryDelete,
  MovieAction.keyframes => l.keyframeMode,
  MovieAction.perform => l.performMode,
  MovieAction.fullscreen => l.fullscreenPreview,
};

/// The preferences, with ways to the shortcut editor and recovery points.
class MoviePrefsDialog extends StatelessWidget {
  const MoviePrefsDialog({
    super.key,
    required this.prefs,
    required this.onRecovery,
  });
  final MoviePrefs prefs;
  final VoidCallback onRecovery;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => AlertDialog(
        key: const ValueKey('movie-prefs'),
        title: Text(l.moviePrefs),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile.adaptive(
                  key: const ValueKey('prefs-undo-buttons'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.prefsUndoButtons),
                  value: prefs.undoButtons,
                  onChanged: (v) => prefs.update((p) => p.undoButtons = v),
                ),
                ValueSlider(
                  id: 'prefs-quick-undo',
                  label: l.prefsQuickUndo,
                  labelWidth: 140,
                  value: prefs.quickUndoMs.toDouble(),
                  max: 1500,
                  toNumber: (v) => v,
                  fromNumber: (n) => n,
                  unit: 'ms',
                  onChanged: (v) =>
                      prefs.update((p) => p.quickUndoMs = v.round()),
                ),
                ValueSlider(
                  id: 'prefs-undo-depth',
                  label: l.prefsUndoDepth,
                  labelWidth: 140,
                  value: prefs.undoDepth.toDouble(),
                  min: MoviePrefs.minDepth.toDouble(),
                  max: MoviePrefs.maxDepth.toDouble(),
                  toNumber: (v) => v,
                  fromNumber: (n) => n,
                  unit: '',
                  onChanged: (v) =>
                      prefs.update((p) => p.undoDepth = v.round()),
                ),
                SwitchListTile.adaptive(
                  key: const ValueKey('prefs-two-finger'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.prefsTwoFingerUndo),
                  value: prefs.twoFingerUndo,
                  onChanged: (v) => prefs.update((p) => p.twoFingerUndo = v),
                ),
                SwitchListTile.adaptive(
                  key: const ValueKey('prefs-three-finger'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.prefsThreeFingerRedo),
                  value: prefs.threeFingerRedo,
                  onChanged: (v) => prefs.update((p) => p.threeFingerRedo = v),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('prefs-shortcuts'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ShortcutsDialog(prefs: prefs),
                  ),
                  icon: const Icon(Icons.keyboard_outlined),
                  label: Text(l.prefsShortcuts),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('prefs-recovery'),
                  onPressed: onRecovery,
                  icon: const Icon(Icons.history_rounded),
                  label: Text(l.prefsRecovery),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.done),
          ),
        ],
      ),
    );
  }
}

/// Every shortcut, each changed by pressing the new keys; back to the
/// defaults at once.
class ShortcutsDialog extends StatefulWidget {
  const ShortcutsDialog({super.key, required this.prefs});
  final MoviePrefs prefs;

  @override
  State<ShortcutsDialog> createState() => _ShortcutsDialogState();
}

class _ShortcutsDialogState extends State<ShortcutsDialog> {
  MovieAction? listening;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    final action = listening;
    if (action == null || e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final modifiers = {
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
    };
    if (modifiers.contains(k)) return KeyEventResult.handled;
    final keys = HardwareKeyboard.instance;
    widget.prefs.update(
      (p) => p.shortcuts[action] = SingleActivator(
        k,
        control: keys.isControlPressed,
        meta: keys.isMetaPressed,
        shift: keys.isShiftPressed,
        alt: keys.isAltPressed,
      ),
    );
    setState(() => listening = null);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final prefs = widget.prefs;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _key,
      child: AlertDialog(
        key: const ValueKey('shortcuts-dialog'),
        title: Text(l.prefsShortcuts),
        content: SizedBox(
          width: 380,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final a in MovieAction.values)
                ListTile(
                  key: ValueKey('shortcut-${a.name}'),
                  dense: true,
                  title: Text(movieActionName(l, a)),
                  trailing: Text(
                    listening == a
                        ? l.prefsPressKeys
                        : MoviePrefs.describe(prefs.shortcuts[a]!),
                  ),
                  onTap: () {
                    setState(() => listening = a);
                    _focus.requestFocus();
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              prefs.update((p) => p.shortcuts = {...MoviePrefs.defaults()});
              setState(() => listening = null);
            },
            child: Text(l.prefsDefaults),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.done),
          ),
        ],
      ),
    );
  }
}
