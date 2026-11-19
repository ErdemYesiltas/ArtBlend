import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';

/// Time-lapse Replay: the frames at 30 a second, a scrubber to look at any
/// moment, pause and play.
class TimelapsePlayer extends StatefulWidget {
  const TimelapsePlayer({super.key, required this.frames});
  final List<File> frames;

  @override
  State<TimelapsePlayer> createState() => _TimelapsePlayerState();
}

class _TimelapsePlayerState extends State<TimelapsePlayer> {
  int frame = 0;
  bool playing = true;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _play();
  }

  void _play() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted) return;
      if (frame >= widget.frames.length - 1) {
        _tick?.cancel();
        setState(() => playing = false);
        return;
      }
      setState(() => frame++);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final frames = widget.frames;
    return Dialog.fullscreen(
      key: const ValueKey('timelapse-player'),
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('timelapse-close'),
                  tooltip: l.cancel,
                  color: Colors.white,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
                Expanded(
                  child: Text(
                    l.timelapseReplay,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            Expanded(
              child: frames.isEmpty
                  ? Center(
                      child: Text(
                        l.timelapseEmpty,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    )
                  : Center(
                      child: Image.file(
                        frames[frame],
                        key: const ValueKey('timelapse-frame'),
                        gaplessPlayback: true,
                        fit: BoxFit.contain,
                      ),
                    ),
            ),
            if (frames.length > 1)
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('timelapse-play'),
                    color: Colors.white,
                    tooltip: playing ? l.timelapsePause : l.timelapsePlay,
                    onPressed: () {
                      setState(() {
                        playing = !playing;
                        if (playing && frame >= frames.length - 1) frame = 0;
                      });
                      playing ? _play() : _tick?.cancel();
                    },
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  ),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('timelapse-scrub'),
                      value: frame.toDouble(),
                      max: (frames.length - 1).toDouble(),
                      onChangeStart: (_) {
                        _tick?.cancel();
                        setState(() => playing = false);
                      },
                      onChanged: (v) => setState(() => frame = v.round()),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      '${frame + 1}/${frames.length}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
