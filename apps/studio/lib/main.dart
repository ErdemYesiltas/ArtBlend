import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart'
    show LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:artblend_brush_engine/third_party_licenses.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:shared_preferences/shared_preferences.dart';

import 'data/studio_storage.dart';
import 'editor/editor_screen.dart';
import 'editor/studio_controller.dart';
import 'l10n/app_localizations.dart';
import 'mcp/artblend_tools.dart';
import 'mcp/mcp_service.dart';
import 'mcp/mcp_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'libmypaint',
      'json-c',
      'fastapprox',
    ], brushEngineThirdPartyLicenses);
  });
  try {
    final storage = await LocalStudioStorage.create();
    final preferences = await SharedPreferences.getInstance();
    final controller = StudioController(
      storage: storage,
      preferences: preferences,
    );
    await controller.initialize();
    final mcp = McpService(
      ArtBlendTools(controller).tools,
      instructions: artBlendInstructions,
      preferences: preferences,
    );
    runApp(StudioApp(controller: controller, mcp: mcp));
    unawaited(controller.hub.restore());
    unawaited(mcp.restore());
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SelectableText(
              'ArtBlend could not initialize local storage.\n$error',
            ),
          ),
        ),
      ),
    );
  }
}

class StudioApp extends StatelessWidget {
  const StudioApp({super.key, required this.controller, this.mcp});
  final StudioController controller;
  final McpService? mcp;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.appearance,
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ArtBlend',
      locale: controller.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: controller.themeMode,
      theme: _light,
      darkTheme: _dark,
      // Accessibility: the interface's text at the chosen size.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(controller.textScale)),
        child: mcp == null
            ? child!
            : Stack(
                children: [
                  child!,
                  McpBanner(activity: mcp!.server.activity),
                ],
              ),
      ),
      home: EditorScreen(controller: controller, mcp: mcp),
    ),
  );

  // ColorScheme.fromSeed is costly; build each theme once.
  static final _light = _theme(Brightness.light);
  static final _dark = _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xff388ef6),
          brightness: brightness,
        ).copyWith(
          surface: dark ? const Color(0xff292929) : const Color(0xfff7f7f7),
          primary: const Color(0xff398ef6),
        );
    return ThemeData(
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: dark
          ? const Color(0xff202020)
          : const Color(0xffe3e3e3),
      useMaterial3: true,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.all(10),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 3,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
    );
  }
}
