import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    const mypaint = 'vendor/libmypaint/';
    const json = 'vendor/json-c/';
    await CBuilder.library(
      name: input.packageName,
      assetName: '${input.packageName}_bindings_generated.dart',
      includes: ['src', mypaint, json],
      sources: [
        'src/artblend_brush_engine.c',
        for (final file in [
          'brushmodes',
          'fifo',
          'helpers',
          'mypaint-mapping',
          'mypaint',
          'mypaint-brush',
          'mypaint-brush-settings',
          'mypaint-matrix',
          'mypaint-symmetry',
          'mypaint-rectangle',
          'mypaint-surface',
          'mypaint-tiled-surface',
          'operationqueue',
          'rng-double',
          'tilemap',
        ])
          '$mypaint$file.c',
        for (final file in [
          'arraylist',
          'debug',
          'json_c_version',
          'json_object',
          'json_object_iterator',
          'json_tokener',
          'json_util',
          'json_visit',
          'linkhash',
          'printbuf',
          'random_seed',
          'strerror_override',
        ])
          '$json$file.c',
      ],
      // libmypaint uses logf/expf/powf…: Android's dynamic linker refuses the
      // library unless libm is a declared dependency (Apple folds it into
      // libSystem, which is why desktop and iOS builds did not notice).
      libraries: [if (input.config.code.targetOS != OS.windows) 'm'],
      defines: {'_GNU_SOURCE': '1'},
      flags: ['-fvisibility=hidden'],
    ).run(input: input, output: output);
  });
}
