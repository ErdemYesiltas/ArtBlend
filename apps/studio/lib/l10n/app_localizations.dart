import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('tr'),
  ];

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @actions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actions;

  /// No description provided for @brush.
  ///
  /// In en, this message translates to:
  /// **'Brush'**
  String get brush;

  /// No description provided for @eraser.
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get eraser;

  /// No description provided for @pan.
  ///
  /// In en, this message translates to:
  /// **'Move canvas'**
  String get pan;

  /// No description provided for @layers.
  ///
  /// In en, this message translates to:
  /// **'Layers'**
  String get layers;

  /// No description provided for @colors.
  ///
  /// In en, this message translates to:
  /// **'Colors'**
  String get colors;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get settings;

  /// No description provided for @connections.
  ///
  /// In en, this message translates to:
  /// **'Local AI'**
  String get connections;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @size.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get size;

  /// No description provided for @opacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get opacity;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved on device'**
  String get saved;

  /// No description provided for @unsaved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get unsaved;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed · Retry'**
  String get saveFailed;

  /// No description provided for @newDocument.
  ///
  /// In en, this message translates to:
  /// **'New drawing'**
  String get newDocument;

  /// No description provided for @openDocument.
  ///
  /// In en, this message translates to:
  /// **'Open drawing'**
  String get openDocument;

  /// No description provided for @saveDocument.
  ///
  /// In en, this message translates to:
  /// **'Save now'**
  String get saveDocument;

  /// No description provided for @exportDocument.
  ///
  /// In en, this message translates to:
  /// **'Export drawing file'**
  String get exportDocument;

  /// No description provided for @exportPng.
  ///
  /// In en, this message translates to:
  /// **'Export PNG'**
  String get exportPng;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @newDocumentMessage.
  ///
  /// In en, this message translates to:
  /// **'The current drawing is saved before starting a new one. Export a drawing file to keep a separate copy.'**
  String get newDocumentMessage;

  /// No description provided for @untitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled drawing'**
  String get untitled;

  /// No description provided for @brushLibrary.
  ///
  /// In en, this message translates to:
  /// **'Brush library'**
  String get brushLibrary;

  /// No description provided for @importBrush.
  ///
  /// In en, this message translates to:
  /// **'Import brush presets'**
  String get importBrush;

  /// No description provided for @importPalette.
  ///
  /// In en, this message translates to:
  /// **'Import palette'**
  String get importPalette;

  /// No description provided for @brushImportHint.
  ///
  /// In en, this message translates to:
  /// **'ArtBlend JSON presets · MyPaint v3 (.myb) · ABR and PNG tip brushes are planned for a later milestone.'**
  String get brushImportHint;

  /// No description provided for @paletteImportHint.
  ///
  /// In en, this message translates to:
  /// **'HEX · GPL · RGB ASE · RGB/HSB ACO · SWATCHES v1'**
  String get paletteImportHint;

  /// No description provided for @ink.
  ///
  /// In en, this message translates to:
  /// **'Studio ink'**
  String get ink;

  /// No description provided for @pencil.
  ///
  /// In en, this message translates to:
  /// **'Sketch pencil'**
  String get pencil;

  /// No description provided for @marker.
  ///
  /// In en, this message translates to:
  /// **'Flat marker'**
  String get marker;

  /// No description provided for @coast.
  ///
  /// In en, this message translates to:
  /// **'Coastal study'**
  String get coast;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get custom;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get theme;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @rightSidebar.
  ///
  /// In en, this message translates to:
  /// **'Controls on the right'**
  String get rightSidebar;

  /// No description provided for @fingerDrawing.
  ///
  /// In en, this message translates to:
  /// **'Draw with a finger'**
  String get fingerDrawing;

  /// No description provided for @themeHint.
  ///
  /// In en, this message translates to:
  /// **'Appearance never changes artwork or palette colors.'**
  String get themeHint;

  /// No description provided for @palmHint.
  ///
  /// In en, this message translates to:
  /// **'Disable finger drawing when using a stylus for reliable separation from touch gestures.'**
  String get palmHint;

  /// No description provided for @addLayer.
  ///
  /// In en, this message translates to:
  /// **'Add layer'**
  String get addLayer;

  /// No description provided for @layerName.
  ///
  /// In en, this message translates to:
  /// **'Layer {index}'**
  String layerName(int index);

  /// No description provided for @deleteLayer.
  ///
  /// In en, this message translates to:
  /// **'Delete layer'**
  String get deleteLayer;

  /// No description provided for @hideLayer.
  ///
  /// In en, this message translates to:
  /// **'Show / hide layer'**
  String get hideLayer;

  /// No description provided for @lockLayer.
  ///
  /// In en, this message translates to:
  /// **'Lock / unlock layer'**
  String get lockLayer;

  /// No description provided for @moveUp.
  ///
  /// In en, this message translates to:
  /// **'Move layer up'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In en, this message translates to:
  /// **'Move layer down'**
  String get moveDown;

  /// No description provided for @colorHex.
  ///
  /// In en, this message translates to:
  /// **'Hex color'**
  String get colorHex;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @invalidHex.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 6- or 8-digit hex color.'**
  String get invalidHex;

  /// No description provided for @zoomReset.
  ///
  /// In en, this message translates to:
  /// **'Fit canvas'**
  String get zoomReset;

  /// No description provided for @serverUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get serverUrl;

  /// No description provided for @checking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get checking;

  /// No description provided for @startupError.
  ///
  /// In en, this message translates to:
  /// **'Your saved drawing could not be opened. The existing files have been preserved.'**
  String get startupError;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @importSuccess.
  ///
  /// In en, this message translates to:
  /// **'Imported: {name}'**
  String importSuccess(String name);

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not complete the operation: {detail}'**
  String operationFailed(String detail);

  /// No description provided for @exportSuccess.
  ///
  /// In en, this message translates to:
  /// **'File exported'**
  String get exportSuccess;

  /// No description provided for @activeLayer.
  ///
  /// In en, this message translates to:
  /// **'Active layer'**
  String get activeLayer;

  /// No description provided for @prototype.
  ///
  /// In en, this message translates to:
  /// **'Development build · Freehand engine'**
  String get prototype;

  /// No description provided for @drawingAssistant.
  ///
  /// In en, this message translates to:
  /// **'Drawing assistant'**
  String get drawingAssistant;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @askAssistant.
  ///
  /// In en, this message translates to:
  /// **'Ask about color, composition or your next idea…'**
  String get askAssistant;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @chatPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Only the text you enter is sent to the selected local server.'**
  String get chatPrivacy;

  /// No description provided for @fingerprint.
  ///
  /// In en, this message translates to:
  /// **'Certificate fingerprint'**
  String get fingerprint;

  /// No description provided for @pairingCode.
  ///
  /// In en, this message translates to:
  /// **'Pairing code'**
  String get pairingCode;

  /// No description provided for @deviceName.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get deviceName;

  /// No description provided for @pairDevice.
  ///
  /// In en, this message translates to:
  /// **'Pair device'**
  String get pairDevice;

  /// No description provided for @removePairing.
  ///
  /// In en, this message translates to:
  /// **'Revoke this device'**
  String get removePairing;

  /// No description provided for @mcpTools.
  ///
  /// In en, this message translates to:
  /// **'MCP tools'**
  String get mcpTools;

  /// No description provided for @noMcpServers.
  ///
  /// In en, this message translates to:
  /// **'No MCP server is allowed for this device. Allow one in LocalHub on the Mac (Devices).'**
  String get noMcpServers;

  /// No description provided for @runTool.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get runTool;

  /// No description provided for @generationComplete.
  ///
  /// In en, this message translates to:
  /// **'Completed · Choose an image to preview'**
  String get generationComplete;

  /// No description provided for @importImage.
  ///
  /// In en, this message translates to:
  /// **'Import image'**
  String get importImage;

  /// No description provided for @addImageLayer.
  ///
  /// In en, this message translates to:
  /// **'Add as new layer'**
  String get addImageLayer;

  /// No description provided for @transformLayer.
  ///
  /// In en, this message translates to:
  /// **'Transform layer'**
  String get transformLayer;

  /// No description provided for @transformHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to move, drag a corner to scale, or pinch to scale and rotate. Apply commits the preview and crops pixels outside the canvas; switching tools cancels.'**
  String get transformHint;

  /// No description provided for @transformUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Choose a visible, unlocked layer with artwork.'**
  String get transformUnavailable;

  /// No description provided for @scale.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get scale;

  /// No description provided for @rotation.
  ///
  /// In en, this message translates to:
  /// **'Rotation'**
  String get rotation;

  /// No description provided for @resetTransform.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetTransform;

  /// No description provided for @blendMode.
  ///
  /// In en, this message translates to:
  /// **'Blend mode'**
  String get blendMode;

  /// No description provided for @blendNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get blendNormal;

  /// No description provided for @blendMultiply.
  ///
  /// In en, this message translates to:
  /// **'Multiply'**
  String get blendMultiply;

  /// No description provided for @blendScreen.
  ///
  /// In en, this message translates to:
  /// **'Screen'**
  String get blendScreen;

  /// No description provided for @selection.
  ///
  /// In en, this message translates to:
  /// **'Selection'**
  String get selection;

  /// No description provided for @selectionHint.
  ///
  /// In en, this message translates to:
  /// **'Draw a region. Done keeps it active for painting. A layer mask hides pixels without deleting them.'**
  String get selectionHint;

  /// No description provided for @rectangleSelection.
  ///
  /// In en, this message translates to:
  /// **'Rectangle'**
  String get rectangleSelection;

  /// No description provided for @freehandSelection.
  ///
  /// In en, this message translates to:
  /// **'Freehand'**
  String get freehandSelection;

  /// No description provided for @invertSelection.
  ///
  /// In en, this message translates to:
  /// **'Invert'**
  String get invertSelection;

  /// No description provided for @deselect.
  ///
  /// In en, this message translates to:
  /// **'Deselect'**
  String get deselect;

  /// No description provided for @exportSelectionMask.
  ///
  /// In en, this message translates to:
  /// **'Export mask'**
  String get exportSelectionMask;

  /// No description provided for @layerMask.
  ///
  /// In en, this message translates to:
  /// **'Layer mask'**
  String get layerMask;

  /// No description provided for @removeLayerMask.
  ///
  /// In en, this message translates to:
  /// **'Remove layer mask'**
  String get removeLayerMask;

  /// No description provided for @deleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Erase selected'**
  String get deleteSelected;

  /// No description provided for @selectionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get selectionDone;

  /// No description provided for @transformMaskHint.
  ///
  /// In en, this message translates to:
  /// **'Applying a transform merges the current layer mask into its pixels. Undo restores the editable mask.'**
  String get transformMaskHint;

  /// No description provided for @transformSelection.
  ///
  /// In en, this message translates to:
  /// **'Transform selection'**
  String get transformSelection;

  /// No description provided for @inpaintPrompt.
  ///
  /// In en, this message translates to:
  /// **'Describe what should appear here'**
  String get inpaintPrompt;

  /// No description provided for @generationSettings.
  ///
  /// In en, this message translates to:
  /// **'Generation settings'**
  String get generationSettings;

  /// No description provided for @negativePrompt.
  ///
  /// In en, this message translates to:
  /// **'Negative prompt'**
  String get negativePrompt;

  /// No description provided for @seed.
  ///
  /// In en, this message translates to:
  /// **'Seed'**
  String get seed;

  /// No description provided for @steps.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get steps;

  /// No description provided for @denoise.
  ///
  /// In en, this message translates to:
  /// **'Change strength'**
  String get denoise;

  /// No description provided for @inpaintNeedsSelection.
  ///
  /// In en, this message translates to:
  /// **'Select a region on the canvas before running inpaint.'**
  String get inpaintNeedsSelection;

  /// No description provided for @charcoal.
  ///
  /// In en, this message translates to:
  /// **'Charcoal'**
  String get charcoal;

  /// No description provided for @modelling.
  ///
  /// In en, this message translates to:
  /// **'Modelling'**
  String get modelling;

  /// No description provided for @mypaintBrush.
  ///
  /// In en, this message translates to:
  /// **'MyPaint'**
  String get mypaintBrush;

  /// No description provided for @galleryUnreadable.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 drawing file could not be read and is not listed. It is left untouched on disk.} other{{count} drawing files could not be read and are not listed. They are left untouched on disk.}}'**
  String galleryUnreadable(int count);

  /// No description provided for @libraryUnreadable.
  ///
  /// In en, this message translates to:
  /// **'The brush and palette library could not be read. Built-in brushes are available; the library file is not overwritten and importing is disabled until it is repaired.'**
  String get libraryUnreadable;

  /// No description provided for @scanPairingQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanPairingQr;

  /// No description provided for @scanPairingQrHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the QR code LocalHub shows on your Mac (Devices → Pair a device).'**
  String get scanPairingQrHint;

  /// No description provided for @invalidPairingQr.
  ///
  /// In en, this message translates to:
  /// **'This QR code is not a LocalHub pairing code. Create a new one on the Mac if it has expired.'**
  String get invalidPairingQr;

  /// No description provided for @cameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The camera is unavailable: {error}. You can type the address, fingerprint and code instead.'**
  String cameraUnavailable(String error);

  /// No description provided for @eyedropper.
  ///
  /// In en, this message translates to:
  /// **'Eyedropper'**
  String get eyedropper;

  /// No description provided for @stabilization.
  ///
  /// In en, this message translates to:
  /// **'Stabilization'**
  String get stabilization;

  /// No description provided for @streamLine.
  ///
  /// In en, this message translates to:
  /// **'StreamLine'**
  String get streamLine;

  /// No description provided for @streamLineHint.
  ///
  /// In en, this message translates to:
  /// **'Per brush. Irons out bumps and shakiness: the line trails the pen slightly and catches up when you lift it. Hold Option/Alt with a brush to pick a colour.'**
  String get streamLineHint;

  /// No description provided for @pressureAndSmoothing.
  ///
  /// In en, this message translates to:
  /// **'Pressure and smoothing'**
  String get pressureAndSmoothing;

  /// No description provided for @motionFiltering.
  ///
  /// In en, this message translates to:
  /// **'Motion filtering'**
  String get motionFiltering;

  /// No description provided for @motionExpression.
  ///
  /// In en, this message translates to:
  /// **'Motion filtering expression'**
  String get motionExpression;

  /// No description provided for @smoothingHint.
  ///
  /// In en, this message translates to:
  /// **'Apply to every brush, on top of its StreamLine. Stabilization averages your movement and grows stronger the faster you draw; slow lines stay precise. Motion filtering removes the extremes of wobble at any speed, and Expression brings some natural variation back.'**
  String get smoothingHint;

  /// No description provided for @unsupportedFile.
  ///
  /// In en, this message translates to:
  /// **'{name} is not a supported file for this action.'**
  String unsupportedFile(String name);

  /// No description provided for @canvasSize.
  ///
  /// In en, this message translates to:
  /// **'Canvas size'**
  String get canvasSize;

  /// No description provided for @squareCanvas.
  ///
  /// In en, this message translates to:
  /// **'Square · {size}'**
  String squareCanvas(String size);

  /// No description provided for @screenCanvas.
  ///
  /// In en, this message translates to:
  /// **'Screen · {size}'**
  String screenCanvas(String size);

  /// No description provided for @customCanvas.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customCanvas;

  /// No description provided for @canvasWidth.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get canvasWidth;

  /// No description provided for @canvasHeight.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get canvasHeight;

  /// No description provided for @canvasSizeHint.
  ///
  /// In en, this message translates to:
  /// **'{min}–{max} pixels per side. The size stays fixed; large canvases use more memory.'**
  String canvasSizeHint(int min, int max);

  /// No description provided for @localHub.
  ///
  /// In en, this message translates to:
  /// **'LocalHub'**
  String get localHub;

  /// No description provided for @hubHint.
  ///
  /// In en, this message translates to:
  /// **'Open LocalHub on your Mac, choose Devices → Pair a device, then scan its QR code or enter the address, SHA-256 fingerprint and code it shows.'**
  String get hubHint;

  /// No description provided for @companionRetired.
  ///
  /// In en, this message translates to:
  /// **'This is a pairing code from the retired ArtBlend Companion. Install LocalHub on your Mac and pair with the code it shows.'**
  String get companionRetired;

  /// No description provided for @hubPaired.
  ///
  /// In en, this message translates to:
  /// **'Paired with {name}'**
  String hubPaired(String name);

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @hubNoWorkflow.
  ///
  /// In en, this message translates to:
  /// **'Allowed, but LocalHub has no model or workflow for this yet. Add one on the Mac.'**
  String get hubNoWorkflow;

  /// No description provided for @hubPermissionMissing.
  ///
  /// In en, this message translates to:
  /// **'This device is not allowed to use this. Allow it in LocalHub on the Mac (Devices).'**
  String get hubPermissionMissing;

  /// No description provided for @editSelection.
  ///
  /// In en, this message translates to:
  /// **'Repaint selection'**
  String get editSelection;

  /// No description provided for @createImage.
  ///
  /// In en, this message translates to:
  /// **'New image'**
  String get createImage;

  /// No description provided for @hubDefaultModel.
  ///
  /// In en, this message translates to:
  /// **'Hub default'**
  String get hubDefaultModel;

  /// No description provided for @imagePrompt.
  ///
  /// In en, this message translates to:
  /// **'Describe the image'**
  String get imagePrompt;

  /// No description provided for @generate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get generate;

  /// No description provided for @jobQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting on the Mac…'**
  String get jobQueued;

  /// No description provided for @jobRunning.
  ///
  /// In en, this message translates to:
  /// **'Generating on the Mac…'**
  String get jobRunning;

  /// No description provided for @jobCancelled.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get jobCancelled;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @hubFiles.
  ///
  /// In en, this message translates to:
  /// **'Files on the hub'**
  String get hubFiles;

  /// No description provided for @uploadFile.
  ///
  /// In en, this message translates to:
  /// **'Upload image'**
  String get uploadFile;

  /// No description provided for @uploadDrawing.
  ///
  /// In en, this message translates to:
  /// **'Upload drawing'**
  String get uploadDrawing;

  /// No description provided for @noHubFiles.
  ///
  /// In en, this message translates to:
  /// **'No files yet. Uploads and generated images appear here.'**
  String get noHubFiles;

  /// No description provided for @addToCanvas.
  ///
  /// In en, this message translates to:
  /// **'Add to canvas'**
  String get addToCanvas;

  /// No description provided for @deleteFile.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteFile;

  /// No description provided for @mcpServer.
  ///
  /// In en, this message translates to:
  /// **'MCP server'**
  String get mcpServer;

  /// No description provided for @mcpTool.
  ///
  /// In en, this message translates to:
  /// **'Tool'**
  String get mcpTool;

  /// No description provided for @mcpArguments.
  ///
  /// In en, this message translates to:
  /// **'Arguments (JSON)'**
  String get mcpArguments;

  /// No description provided for @jobsAhead.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 job ahead} other{{count} jobs ahead}}'**
  String jobsAhead(int count);

  /// No description provided for @aboutMinutes.
  ///
  /// In en, this message translates to:
  /// **'about {minutes} min'**
  String aboutMinutes(int minutes);

  /// No description provided for @generativeFill.
  ///
  /// In en, this message translates to:
  /// **'Generative fill'**
  String get generativeFill;

  /// No description provided for @fillPromptHint.
  ///
  /// In en, this message translates to:
  /// **'What to add? Leave empty to match the surroundings'**
  String get fillPromptHint;

  /// No description provided for @previousVariation.
  ///
  /// In en, this message translates to:
  /// **'Previous variation'**
  String get previousVariation;

  /// No description provided for @nextVariation.
  ///
  /// In en, this message translates to:
  /// **'Next variation'**
  String get nextVariation;

  /// No description provided for @newVariation.
  ///
  /// In en, this message translates to:
  /// **'New variation'**
  String get newVariation;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @assistantTab.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get assistantTab;

  /// No description provided for @filesTab.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get filesTab;

  /// No description provided for @hubNoImageWorkflow.
  ///
  /// In en, this message translates to:
  /// **'LocalHub has no image workflow this device may use yet.'**
  String get hubNoImageWorkflow;

  /// No description provided for @hubIntegrationsDown.
  ///
  /// In en, this message translates to:
  /// **'Not running: {names}'**
  String hubIntegrationsDown(String names);

  /// No description provided for @writePrompt.
  ///
  /// In en, this message translates to:
  /// **'Write a detailed prompt from these keywords'**
  String get writePrompt;

  /// No description provided for @graphiteBrush.
  ///
  /// In en, this message translates to:
  /// **'Graphite'**
  String get graphiteBrush;

  /// No description provided for @pastelBrush.
  ///
  /// In en, this message translates to:
  /// **'Soft pastel'**
  String get pastelBrush;

  /// No description provided for @dryBrush.
  ///
  /// In en, this message translates to:
  /// **'Dry brush'**
  String get dryBrush;

  /// No description provided for @gouacheBrush.
  ///
  /// In en, this message translates to:
  /// **'Gouache'**
  String get gouacheBrush;

  /// No description provided for @splatterBrush.
  ///
  /// In en, this message translates to:
  /// **'Splatter'**
  String get splatterBrush;

  /// No description provided for @stampBrush.
  ///
  /// In en, this message translates to:
  /// **'Texture'**
  String get stampBrush;

  /// No description provided for @blendDarken.
  ///
  /// In en, this message translates to:
  /// **'Darken'**
  String get blendDarken;

  /// No description provided for @blendColorBurn.
  ///
  /// In en, this message translates to:
  /// **'Color burn'**
  String get blendColorBurn;

  /// No description provided for @blendLighten.
  ///
  /// In en, this message translates to:
  /// **'Lighten'**
  String get blendLighten;

  /// No description provided for @blendColorDodge.
  ///
  /// In en, this message translates to:
  /// **'Color dodge'**
  String get blendColorDodge;

  /// No description provided for @blendAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get blendAdd;

  /// No description provided for @blendOverlay.
  ///
  /// In en, this message translates to:
  /// **'Overlay'**
  String get blendOverlay;

  /// No description provided for @blendSoftLight.
  ///
  /// In en, this message translates to:
  /// **'Soft light'**
  String get blendSoftLight;

  /// No description provided for @blendHardLight.
  ///
  /// In en, this message translates to:
  /// **'Hard light'**
  String get blendHardLight;

  /// No description provided for @blendDifference.
  ///
  /// In en, this message translates to:
  /// **'Difference'**
  String get blendDifference;

  /// No description provided for @renameLayer.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameLayer;

  /// No description provided for @duplicateLayer.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicateLayer;

  /// No description provided for @mergeDown.
  ///
  /// In en, this message translates to:
  /// **'Merge down'**
  String get mergeDown;

  /// No description provided for @clearLayer.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearLayer;

  /// No description provided for @unlockLayer.
  ///
  /// In en, this message translates to:
  /// **'Unlock layer'**
  String get unlockLayer;

  /// No description provided for @layerCopy.
  ///
  /// In en, this message translates to:
  /// **'{name} copy'**
  String layerCopy(String name);

  /// No description provided for @layerCount.
  ///
  /// In en, this message translates to:
  /// **'{count} of {max} layers'**
  String layerCount(int count, int max);

  /// No description provided for @layersHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the selected layer for options · swipe right to choose more · pinch two layers to merge them · hold and drag to reorder · the letter sets blend mode and opacity'**
  String get layersHint;

  /// No description provided for @ellipseSelection.
  ///
  /// In en, this message translates to:
  /// **'Ellipse'**
  String get ellipseSelection;

  /// No description provided for @selectionNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get selectionNew;

  /// No description provided for @selectionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get selectionAdd;

  /// No description provided for @selectionSubtract.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get selectionSubtract;

  /// No description provided for @featherSelection.
  ///
  /// In en, this message translates to:
  /// **'Soft edge'**
  String get featherSelection;

  /// No description provided for @featherAmount.
  ///
  /// In en, this message translates to:
  /// **'Soft edge {pixels} px'**
  String featherAmount(int pixels);

  /// No description provided for @featherHint.
  ///
  /// In en, this message translates to:
  /// **'Fades the selection\'s edge over this many canvas pixels: strokes, masks, deleting and generative fill blend in instead of stopping at a hard line.'**
  String get featherHint;

  /// No description provided for @drawingGuide.
  ///
  /// In en, this message translates to:
  /// **'Drawing guide'**
  String get drawingGuide;

  /// No description provided for @symmetry.
  ///
  /// In en, this message translates to:
  /// **'Symmetry'**
  String get symmetry;

  /// No description provided for @symmetryOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get symmetryOff;

  /// No description provided for @symmetryVertical.
  ///
  /// In en, this message translates to:
  /// **'Vertical'**
  String get symmetryVertical;

  /// No description provided for @symmetryHorizontal.
  ///
  /// In en, this message translates to:
  /// **'Horizontal'**
  String get symmetryHorizontal;

  /// No description provided for @symmetryQuadrant.
  ///
  /// In en, this message translates to:
  /// **'Quadrant'**
  String get symmetryQuadrant;

  /// No description provided for @symmetryRadial.
  ///
  /// In en, this message translates to:
  /// **'Radial'**
  String get symmetryRadial;

  /// No description provided for @gridGuide.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get gridGuide;

  /// No description provided for @turnView.
  ///
  /// In en, this message translates to:
  /// **'Turn the view'**
  String get turnView;

  /// No description provided for @turnLeft.
  ///
  /// In en, this message translates to:
  /// **'Turn left 90°'**
  String get turnLeft;

  /// No description provided for @turnRight.
  ///
  /// In en, this message translates to:
  /// **'Turn right 90°'**
  String get turnRight;

  /// No description provided for @colorDisc.
  ///
  /// In en, this message translates to:
  /// **'Disc'**
  String get colorDisc;

  /// No description provided for @colorValues.
  ///
  /// In en, this message translates to:
  /// **'Values'**
  String get colorValues;

  /// No description provided for @recentColors.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recentColors;

  /// No description provided for @exitFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Show the interface'**
  String get exitFullScreen;

  /// No description provided for @fullScreen.
  ///
  /// In en, this message translates to:
  /// **'Full screen'**
  String get fullScreen;

  /// No description provided for @swapColor.
  ///
  /// In en, this message translates to:
  /// **'Previous colour'**
  String get swapColor;

  /// No description provided for @undone.
  ///
  /// In en, this message translates to:
  /// **'Undo: {action}'**
  String undone(String action);

  /// No description provided for @redone.
  ///
  /// In en, this message translates to:
  /// **'Redo: {action}'**
  String redone(String action);

  /// No description provided for @historyPaint.
  ///
  /// In en, this message translates to:
  /// **'Paint'**
  String get historyPaint;

  /// No description provided for @historyAddLayer.
  ///
  /// In en, this message translates to:
  /// **'New layer'**
  String get historyAddLayer;

  /// No description provided for @historyDeleteLayer.
  ///
  /// In en, this message translates to:
  /// **'Delete layer'**
  String get historyDeleteLayer;

  /// No description provided for @historyMergeLayers.
  ///
  /// In en, this message translates to:
  /// **'Merge layers'**
  String get historyMergeLayers;

  /// No description provided for @historyMoveLayer.
  ///
  /// In en, this message translates to:
  /// **'Move layer'**
  String get historyMoveLayer;

  /// No description provided for @historyLayerMask.
  ///
  /// In en, this message translates to:
  /// **'Layer mask'**
  String get historyLayerMask;

  /// No description provided for @historyLayerSettings.
  ///
  /// In en, this message translates to:
  /// **'Layer settings'**
  String get historyLayerSettings;

  /// No description provided for @historyRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get historyRename;

  /// No description provided for @historyCanvas.
  ///
  /// In en, this message translates to:
  /// **'Canvas'**
  String get historyCanvas;

  /// No description provided for @historyEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get historyEdit;

  /// No description provided for @cut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get cut;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get copyAll;

  /// No description provided for @cutAndPaste.
  ///
  /// In en, this message translates to:
  /// **'Cut & paste'**
  String get cutAndPaste;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @fromSelection.
  ///
  /// In en, this message translates to:
  /// **'From selection'**
  String get fromSelection;

  /// No description provided for @pastedLayer.
  ///
  /// In en, this message translates to:
  /// **'Pasted'**
  String get pastedLayer;

  /// No description provided for @smudge.
  ///
  /// In en, this message translates to:
  /// **'Smudge'**
  String get smudge;

  /// No description provided for @referenceLayer.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get referenceLayer;

  /// No description provided for @colorDrop.
  ///
  /// In en, this message translates to:
  /// **'ColorDrop'**
  String get colorDrop;

  /// No description provided for @fillThreshold.
  ///
  /// In en, this message translates to:
  /// **'Threshold'**
  String get fillThreshold;

  /// No description provided for @fillHint.
  ///
  /// In en, this message translates to:
  /// **'Tap more areas to fill them; the threshold redoes the last fill.'**
  String get fillHint;

  /// No description provided for @alphaLock.
  ///
  /// In en, this message translates to:
  /// **'Alpha lock'**
  String get alphaLock;

  /// No description provided for @clippingMask.
  ///
  /// In en, this message translates to:
  /// **'Clipping mask'**
  String get clippingMask;

  /// No description provided for @fillLayer.
  ///
  /// In en, this message translates to:
  /// **'Fill layer'**
  String get fillLayer;

  /// No description provided for @invertLayer.
  ///
  /// In en, this message translates to:
  /// **'Invert'**
  String get invertLayer;

  /// No description provided for @backgroundColor.
  ///
  /// In en, this message translates to:
  /// **'Background color'**
  String get backgroundColor;

  /// No description provided for @adjustments.
  ///
  /// In en, this message translates to:
  /// **'Adjustments'**
  String get adjustments;

  /// No description provided for @adjustColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get adjustColor;

  /// No description provided for @adjustBlur.
  ///
  /// In en, this message translates to:
  /// **'Blur'**
  String get adjustBlur;

  /// No description provided for @hueSaturationBrightness.
  ///
  /// In en, this message translates to:
  /// **'Hue, Saturation, Brightness'**
  String get hueSaturationBrightness;

  /// No description provided for @gaussianBlur.
  ///
  /// In en, this message translates to:
  /// **'Gaussian Blur'**
  String get gaussianBlur;

  /// No description provided for @adjustHue.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get adjustHue;

  /// No description provided for @adjustSaturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get adjustSaturation;

  /// No description provided for @adjustBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get adjustBrightness;

  /// No description provided for @adjustAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get adjustAmount;

  /// No description provided for @adjustLayer.
  ///
  /// In en, this message translates to:
  /// **'Layer'**
  String get adjustLayer;

  /// No description provided for @adjustPencil.
  ///
  /// In en, this message translates to:
  /// **'Pencil'**
  String get adjustPencil;

  /// No description provided for @adjustPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get adjustPreview;

  /// No description provided for @adjustReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get adjustReset;

  /// No description provided for @adjustSwipeHint.
  ///
  /// In en, this message translates to:
  /// **'Slide left or right on the canvas to change the amount.'**
  String get adjustSwipeHint;

  /// No description provided for @adjustPencilHint.
  ///
  /// In en, this message translates to:
  /// **'Paint where the adjustment should apply; the eraser takes it back.'**
  String get adjustPencilHint;

  /// No description provided for @adjustUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The layer is locked or hidden.'**
  String get adjustUnavailable;

  /// No description provided for @colorBalance.
  ///
  /// In en, this message translates to:
  /// **'Color Balance'**
  String get colorBalance;

  /// No description provided for @curves.
  ///
  /// In en, this message translates to:
  /// **'Curves'**
  String get curves;

  /// No description provided for @gradientMap.
  ///
  /// In en, this message translates to:
  /// **'Gradient Map'**
  String get gradientMap;

  /// No description provided for @toneShadows.
  ///
  /// In en, this message translates to:
  /// **'Shadows'**
  String get toneShadows;

  /// No description provided for @toneMidtones.
  ///
  /// In en, this message translates to:
  /// **'Midtones'**
  String get toneMidtones;

  /// No description provided for @toneHighlights.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get toneHighlights;

  /// No description provided for @cyanRed.
  ///
  /// In en, this message translates to:
  /// **'Cyan – Red'**
  String get cyanRed;

  /// No description provided for @magentaGreen.
  ///
  /// In en, this message translates to:
  /// **'Magenta – Green'**
  String get magentaGreen;

  /// No description provided for @yellowBlue.
  ///
  /// In en, this message translates to:
  /// **'Yellow – Blue'**
  String get yellowBlue;

  /// No description provided for @curveGamma.
  ///
  /// In en, this message translates to:
  /// **'Gamma'**
  String get curveGamma;

  /// No description provided for @curveRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get curveRed;

  /// No description provided for @curveGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get curveGreen;

  /// No description provided for @curveBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get curveBlue;

  /// No description provided for @curvesHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to add or move a point; double-tap a point to remove it.'**
  String get curvesHint;

  /// No description provided for @gradientHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the bar to add a color, tap a color to change it, hold it to remove it.'**
  String get gradientHint;

  /// No description provided for @gradientNoir.
  ///
  /// In en, this message translates to:
  /// **'Noir'**
  String get gradientNoir;

  /// No description provided for @gradientSepia.
  ///
  /// In en, this message translates to:
  /// **'Sepia'**
  String get gradientSepia;

  /// No description provided for @gradientSunset.
  ///
  /// In en, this message translates to:
  /// **'Sunset'**
  String get gradientSunset;

  /// No description provided for @gradientOcean.
  ///
  /// In en, this message translates to:
  /// **'Ocean'**
  String get gradientOcean;

  /// No description provided for @gradientNeon.
  ///
  /// In en, this message translates to:
  /// **'Neon'**
  String get gradientNeon;

  /// No description provided for @gradientGold.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get gradientGold;

  /// No description provided for @motionBlur.
  ///
  /// In en, this message translates to:
  /// **'Motion Blur'**
  String get motionBlur;

  /// No description provided for @perspectiveBlur.
  ///
  /// In en, this message translates to:
  /// **'Perspective Blur'**
  String get perspectiveBlur;

  /// No description provided for @adjustAngle.
  ///
  /// In en, this message translates to:
  /// **'Angle'**
  String get adjustAngle;

  /// No description provided for @perspectivePositional.
  ///
  /// In en, this message translates to:
  /// **'Positional'**
  String get perspectivePositional;

  /// No description provided for @perspectiveDirectional.
  ///
  /// In en, this message translates to:
  /// **'Directional'**
  String get perspectiveDirectional;

  /// No description provided for @motionHint.
  ///
  /// In en, this message translates to:
  /// **'Slide on the canvas in the direction of the blur; a longer slide blurs more.'**
  String get motionHint;

  /// No description provided for @perspectiveHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the disc to move the centre; slide elsewhere to change the amount.'**
  String get perspectiveHint;

  /// No description provided for @transformFreeform.
  ///
  /// In en, this message translates to:
  /// **'Freeform'**
  String get transformFreeform;

  /// No description provided for @transformUniform.
  ///
  /// In en, this message translates to:
  /// **'Uniform'**
  String get transformUniform;

  /// No description provided for @transformDistort.
  ///
  /// In en, this message translates to:
  /// **'Distort'**
  String get transformDistort;

  /// No description provided for @transformWarp.
  ///
  /// In en, this message translates to:
  /// **'Warp'**
  String get transformWarp;

  /// No description provided for @flipHorizontal.
  ///
  /// In en, this message translates to:
  /// **'Flip horizontal'**
  String get flipHorizontal;

  /// No description provided for @flipVertical.
  ///
  /// In en, this message translates to:
  /// **'Flip vertical'**
  String get flipVertical;

  /// No description provided for @rotate45.
  ///
  /// In en, this message translates to:
  /// **'Rotate 45°'**
  String get rotate45;

  /// No description provided for @fitToScreen.
  ///
  /// In en, this message translates to:
  /// **'Fit to screen'**
  String get fitToScreen;

  /// No description provided for @interpolation.
  ///
  /// In en, this message translates to:
  /// **'Interpolation'**
  String get interpolation;

  /// No description provided for @interpolationNearest.
  ///
  /// In en, this message translates to:
  /// **'Nearest neighbor'**
  String get interpolationNearest;

  /// No description provided for @interpolationBilinear.
  ///
  /// In en, this message translates to:
  /// **'Bilinear'**
  String get interpolationBilinear;

  /// No description provided for @interpolationBicubic.
  ///
  /// In en, this message translates to:
  /// **'Bicubic'**
  String get interpolationBicubic;

  /// No description provided for @transformFreeformHint.
  ///
  /// In en, this message translates to:
  /// **'Drag a corner or side to stretch, the middle to move; pinch to rotate.'**
  String get transformFreeformHint;

  /// No description provided for @transformDistortHint.
  ///
  /// In en, this message translates to:
  /// **'Drag a corner for perspective, a side to skew, the middle to move.'**
  String get transformDistortHint;

  /// No description provided for @transformWarpHint.
  ///
  /// In en, this message translates to:
  /// **'Drag anywhere on the mesh to bend it; drag outside it to move.'**
  String get transformWarpHint;

  /// No description provided for @enterValue.
  ///
  /// In en, this message translates to:
  /// **'Enter a value'**
  String get enterValue;

  /// No description provided for @editShape.
  ///
  /// In en, this message translates to:
  /// **'Edit Shape'**
  String get editShape;

  /// No description provided for @perfectShape.
  ///
  /// In en, this message translates to:
  /// **'Perfect'**
  String get perfectShape;

  /// No description provided for @groupLayers.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get groupLayers;

  /// No description provided for @ungroup.
  ///
  /// In en, this message translates to:
  /// **'Ungroup'**
  String get ungroup;

  /// No description provided for @leaveGroup.
  ///
  /// In en, this message translates to:
  /// **'Remove from group'**
  String get leaveGroup;

  /// No description provided for @flattenGroup.
  ///
  /// In en, this message translates to:
  /// **'Flatten group'**
  String get flattenGroup;

  /// No description provided for @deleteGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get deleteGroup;

  /// No description provided for @renameGroup.
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get renameGroup;

  /// No description provided for @mergeChosen.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get mergeChosen;

  /// No description provided for @deleteChosen.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteChosen;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group {index}'**
  String groupName(int index);

  /// No description provided for @chosenLayers.
  ///
  /// In en, this message translates to:
  /// **'{count} layers chosen'**
  String chosenLayers(int count);

  /// No description provided for @blendLinearBurn.
  ///
  /// In en, this message translates to:
  /// **'Linear Burn'**
  String get blendLinearBurn;

  /// No description provided for @blendDarkerColor.
  ///
  /// In en, this message translates to:
  /// **'Darker Color'**
  String get blendDarkerColor;

  /// No description provided for @blendLighterColor.
  ///
  /// In en, this message translates to:
  /// **'Lighter Color'**
  String get blendLighterColor;

  /// No description provided for @blendVividLight.
  ///
  /// In en, this message translates to:
  /// **'Vivid Light'**
  String get blendVividLight;

  /// No description provided for @blendLinearLight.
  ///
  /// In en, this message translates to:
  /// **'Linear Light'**
  String get blendLinearLight;

  /// No description provided for @blendPinLight.
  ///
  /// In en, this message translates to:
  /// **'Pin Light'**
  String get blendPinLight;

  /// No description provided for @blendHardMix.
  ///
  /// In en, this message translates to:
  /// **'Hard Mix'**
  String get blendHardMix;

  /// No description provided for @blendExclusion.
  ///
  /// In en, this message translates to:
  /// **'Exclusion'**
  String get blendExclusion;

  /// No description provided for @blendSubtract.
  ///
  /// In en, this message translates to:
  /// **'Subtract'**
  String get blendSubtract;

  /// No description provided for @blendDivide.
  ///
  /// In en, this message translates to:
  /// **'Divide'**
  String get blendDivide;

  /// No description provided for @blendHue.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get blendHue;

  /// No description provided for @blendSaturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get blendSaturation;

  /// No description provided for @blendColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get blendColor;

  /// No description provided for @blendLuminosity.
  ///
  /// In en, this message translates to:
  /// **'Luminosity'**
  String get blendLuminosity;

  /// No description provided for @liquify.
  ///
  /// In en, this message translates to:
  /// **'Liquify'**
  String get liquify;

  /// No description provided for @liquifyPush.
  ///
  /// In en, this message translates to:
  /// **'Push'**
  String get liquifyPush;

  /// No description provided for @liquifyTwirlRight.
  ///
  /// In en, this message translates to:
  /// **'Twirl right'**
  String get liquifyTwirlRight;

  /// No description provided for @liquifyTwirlLeft.
  ///
  /// In en, this message translates to:
  /// **'Twirl left'**
  String get liquifyTwirlLeft;

  /// No description provided for @liquifyPinch.
  ///
  /// In en, this message translates to:
  /// **'Pinch'**
  String get liquifyPinch;

  /// No description provided for @liquifyExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get liquifyExpand;

  /// No description provided for @liquifyCrystals.
  ///
  /// In en, this message translates to:
  /// **'Crystals'**
  String get liquifyCrystals;

  /// No description provided for @liquifyEdge.
  ///
  /// In en, this message translates to:
  /// **'Edge'**
  String get liquifyEdge;

  /// No description provided for @liquifyReconstruct.
  ///
  /// In en, this message translates to:
  /// **'Reconstruct'**
  String get liquifyReconstruct;

  /// No description provided for @liquifySize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get liquifySize;

  /// No description provided for @liquifyPressure.
  ///
  /// In en, this message translates to:
  /// **'Pressure'**
  String get liquifyPressure;

  /// No description provided for @liquifyDistortion.
  ///
  /// In en, this message translates to:
  /// **'Distortion'**
  String get liquifyDistortion;

  /// No description provided for @liquifyMomentum.
  ///
  /// In en, this message translates to:
  /// **'Momentum'**
  String get liquifyMomentum;

  /// No description provided for @liquifyHalfBack.
  ///
  /// In en, this message translates to:
  /// **'Reconstruct ½'**
  String get liquifyHalfBack;

  /// No description provided for @liquifyHint.
  ///
  /// In en, this message translates to:
  /// **'Drag on the canvas; Twirl, Pinch, Expand and Crystals keep working while you hold still.'**
  String get liquifyHint;

  /// No description provided for @clone.
  ///
  /// In en, this message translates to:
  /// **'Clone'**
  String get clone;

  /// No description provided for @cloneLock.
  ///
  /// In en, this message translates to:
  /// **'Lock source'**
  String get cloneLock;

  /// No description provided for @cloneHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the disc onto what to copy, then paint: the disc follows your brush. Locked, the disc stays put and every stroke starts copying from it (the ✕ shows where pixels come from).'**
  String get cloneHint;

  /// No description provided for @adjustFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get adjustFilters;

  /// No description provided for @sharpen.
  ///
  /// In en, this message translates to:
  /// **'Sharpen'**
  String get sharpen;

  /// No description provided for @noise.
  ///
  /// In en, this message translates to:
  /// **'Noise'**
  String get noise;

  /// No description provided for @bloom.
  ///
  /// In en, this message translates to:
  /// **'Bloom'**
  String get bloom;

  /// No description provided for @glitch.
  ///
  /// In en, this message translates to:
  /// **'Glitch'**
  String get glitch;

  /// No description provided for @halftone.
  ///
  /// In en, this message translates to:
  /// **'Halftone'**
  String get halftone;

  /// No description provided for @chromaticAberration.
  ///
  /// In en, this message translates to:
  /// **'Chromatic Aberration'**
  String get chromaticAberration;

  /// No description provided for @noiseClouds.
  ///
  /// In en, this message translates to:
  /// **'Clouds'**
  String get noiseClouds;

  /// No description provided for @noiseBillows.
  ///
  /// In en, this message translates to:
  /// **'Billows'**
  String get noiseBillows;

  /// No description provided for @noiseRidges.
  ///
  /// In en, this message translates to:
  /// **'Ridges'**
  String get noiseRidges;

  /// No description provided for @noiseScale.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get noiseScale;

  /// No description provided for @noiseOctaves.
  ///
  /// In en, this message translates to:
  /// **'Octaves'**
  String get noiseOctaves;

  /// No description provided for @noiseTurbulence.
  ///
  /// In en, this message translates to:
  /// **'Turbulence'**
  String get noiseTurbulence;

  /// No description provided for @bloomTransition.
  ///
  /// In en, this message translates to:
  /// **'Transition'**
  String get bloomTransition;

  /// No description provided for @filterSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get filterSize;

  /// No description provided for @bloomBurn.
  ///
  /// In en, this message translates to:
  /// **'Burn'**
  String get bloomBurn;

  /// No description provided for @glitchArtifact.
  ///
  /// In en, this message translates to:
  /// **'Artifact'**
  String get glitchArtifact;

  /// No description provided for @glitchWave.
  ///
  /// In en, this message translates to:
  /// **'Wave'**
  String get glitchWave;

  /// No description provided for @glitchSignal.
  ///
  /// In en, this message translates to:
  /// **'Signal'**
  String get glitchSignal;

  /// No description provided for @glitchDiverge.
  ///
  /// In en, this message translates to:
  /// **'Diverge'**
  String get glitchDiverge;

  /// No description provided for @glitchBlock.
  ///
  /// In en, this message translates to:
  /// **'Block size'**
  String get glitchBlock;

  /// No description provided for @glitchZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get glitchZoom;

  /// No description provided for @halftoneFullColor.
  ///
  /// In en, this message translates to:
  /// **'Full color'**
  String get halftoneFullColor;

  /// No description provided for @halftoneScreenPrint.
  ///
  /// In en, this message translates to:
  /// **'Screen print'**
  String get halftoneScreenPrint;

  /// No description provided for @halftoneNewspaper.
  ///
  /// In en, this message translates to:
  /// **'Newspaper'**
  String get halftoneNewspaper;

  /// No description provided for @chromaticPerspective.
  ///
  /// In en, this message translates to:
  /// **'Perspective'**
  String get chromaticPerspective;

  /// No description provided for @chromaticDisplace.
  ///
  /// In en, this message translates to:
  /// **'Displace'**
  String get chromaticDisplace;

  /// No description provided for @chromaticFalloff.
  ///
  /// In en, this message translates to:
  /// **'Falloff'**
  String get chromaticFalloff;

  /// No description provided for @automaticSelection.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get automaticSelection;

  /// No description provided for @selectionThreshold.
  ///
  /// In en, this message translates to:
  /// **'Threshold'**
  String get selectionThreshold;

  /// No description provided for @selectLayerContents.
  ///
  /// In en, this message translates to:
  /// **'Select contents'**
  String get selectLayerContents;

  /// No description provided for @automaticSelectionHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a colour area; keep the finger down and slide left or right to change the threshold.'**
  String get automaticSelectionHint;

  /// No description provided for @freehandSelectionHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to draw the outline.'**
  String get freehandSelectionHint;

  /// No description provided for @closePolygon.
  ///
  /// In en, this message translates to:
  /// **'Close polygon'**
  String get closePolygon;

  /// No description provided for @polygonSelection.
  ///
  /// In en, this message translates to:
  /// **'Polygon'**
  String get polygonSelection;

  /// No description provided for @polygonSelectionHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to place corners; drag a corner to move it; tap the first corner (or Close polygon) to finish.'**
  String get polygonSelectionHint;

  /// No description provided for @savedSelections.
  ///
  /// In en, this message translates to:
  /// **'Save & load'**
  String get savedSelections;

  /// No description provided for @saveSelection.
  ///
  /// In en, this message translates to:
  /// **'Save selection'**
  String get saveSelection;

  /// No description provided for @previousSelection.
  ///
  /// In en, this message translates to:
  /// **'Previous selection'**
  String get previousSelection;

  /// No description provided for @colorFill.
  ///
  /// In en, this message translates to:
  /// **'Color fill'**
  String get colorFill;

  /// No description provided for @copyPasteSelection.
  ///
  /// In en, this message translates to:
  /// **'Copy & paste'**
  String get copyPasteSelection;

  /// No description provided for @savedSelectionName.
  ///
  /// In en, this message translates to:
  /// **'Selection {index}'**
  String savedSelectionName(int index);

  /// No description provided for @snapping.
  ///
  /// In en, this message translates to:
  /// **'Snapping'**
  String get snapping;

  /// No description provided for @magnetics.
  ///
  /// In en, this message translates to:
  /// **'Magnetics'**
  String get magnetics;

  /// No description provided for @snapSettings.
  ///
  /// In en, this message translates to:
  /// **'Snapping settings'**
  String get snapSettings;

  /// No description provided for @snapDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get snapDistance;

  /// No description provided for @snapVelocity.
  ///
  /// In en, this message translates to:
  /// **'Velocity'**
  String get snapVelocity;

  /// No description provided for @cropResize.
  ///
  /// In en, this message translates to:
  /// **'Crop & Resize'**
  String get cropResize;

  /// No description provided for @cropResample.
  ///
  /// In en, this message translates to:
  /// **'Resample (scale the drawing)'**
  String get cropResample;

  /// No description provided for @rotateCanvasLeft.
  ///
  /// In en, this message translates to:
  /// **'Rotate canvas left'**
  String get rotateCanvasLeft;

  /// No description provided for @rotateCanvasRight.
  ///
  /// In en, this message translates to:
  /// **'Rotate canvas right'**
  String get rotateCanvasRight;

  /// No description provided for @flipCanvasHorizontal.
  ///
  /// In en, this message translates to:
  /// **'Flip canvas horizontally'**
  String get flipCanvasHorizontal;

  /// No description provided for @flipCanvasVertical.
  ///
  /// In en, this message translates to:
  /// **'Flip canvas vertically'**
  String get flipCanvasVertical;

  /// No description provided for @cropHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the handles to crop; past the canvas edge it grows. With Resample on, a new size scales the drawing.'**
  String get cropHint;

  /// No description provided for @canvasInfo.
  ///
  /// In en, this message translates to:
  /// **'Canvas info'**
  String get canvasInfo;

  /// No description provided for @infoSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get infoSize;

  /// No description provided for @infoPrint.
  ///
  /// In en, this message translates to:
  /// **'Print size'**
  String get infoPrint;

  /// No description provided for @infoLayers.
  ///
  /// In en, this message translates to:
  /// **'Layers'**
  String get infoLayers;

  /// No description provided for @infoGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get infoGroups;

  /// No description provided for @infoStrokes.
  ///
  /// In en, this message translates to:
  /// **'Vector strokes'**
  String get infoStrokes;

  /// No description provided for @infoSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved selections'**
  String get infoSaved;

  /// No description provided for @infoMemory.
  ///
  /// In en, this message translates to:
  /// **'Pixel data'**
  String get infoMemory;

  /// No description provided for @infoEdits.
  ///
  /// In en, this message translates to:
  /// **'Edits'**
  String get infoEdits;

  /// No description provided for @editGuide.
  ///
  /// In en, this message translates to:
  /// **'Edit drawing guide'**
  String get editGuide;

  /// No description provided for @guideNone.
  ///
  /// In en, this message translates to:
  /// **'No guide'**
  String get guideNone;

  /// No description provided for @guideGrid.
  ///
  /// In en, this message translates to:
  /// **'2D grid'**
  String get guideGrid;

  /// No description provided for @guideIsometric.
  ///
  /// In en, this message translates to:
  /// **'Isometric'**
  String get guideIsometric;

  /// No description provided for @guidePerspective.
  ///
  /// In en, this message translates to:
  /// **'Perspective'**
  String get guidePerspective;

  /// No description provided for @guideRotational.
  ///
  /// In en, this message translates to:
  /// **'Rotational symmetry'**
  String get guideRotational;

  /// No description provided for @guideRemovePoint.
  ///
  /// In en, this message translates to:
  /// **'Remove last vanishing point'**
  String get guideRemovePoint;

  /// No description provided for @guideColor.
  ///
  /// In en, this message translates to:
  /// **'Guide colour'**
  String get guideColor;

  /// No description provided for @guideThickness.
  ///
  /// In en, this message translates to:
  /// **'Thickness'**
  String get guideThickness;

  /// No description provided for @guideHint.
  ///
  /// In en, this message translates to:
  /// **'Perspective: tap the canvas to add a vanishing point (up to three) and drag points to move them. Drag the symmetry centre to move the axes.'**
  String get guideHint;

  /// No description provided for @drawingAssist.
  ///
  /// In en, this message translates to:
  /// **'Drawing assist'**
  String get drawingAssist;

  /// No description provided for @colorClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get colorClassic;

  /// No description provided for @colorHarmony.
  ///
  /// In en, this message translates to:
  /// **'Harmony'**
  String get colorHarmony;

  /// No description provided for @harmonyComplementary.
  ///
  /// In en, this message translates to:
  /// **'Complementary'**
  String get harmonyComplementary;

  /// No description provided for @harmonySplit.
  ///
  /// In en, this message translates to:
  /// **'Split complementary'**
  String get harmonySplit;

  /// No description provided for @harmonyAnalogous.
  ///
  /// In en, this message translates to:
  /// **'Analogous'**
  String get harmonyAnalogous;

  /// No description provided for @harmonyTriadic.
  ///
  /// In en, this message translates to:
  /// **'Triadic'**
  String get harmonyTriadic;

  /// No description provided for @harmonyTetradic.
  ///
  /// In en, this message translates to:
  /// **'Tetradic'**
  String get harmonyTetradic;

  /// No description provided for @colorBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get colorBrightness;

  /// No description provided for @palettes.
  ///
  /// In en, this message translates to:
  /// **'Palettes'**
  String get palettes;

  /// No description provided for @newPalette.
  ///
  /// In en, this message translates to:
  /// **'New palette'**
  String get newPalette;

  /// No description provided for @paletteName.
  ///
  /// In en, this message translates to:
  /// **'Palette'**
  String get paletteName;

  /// No description provided for @setDefaultPalette.
  ///
  /// In en, this message translates to:
  /// **'Set as default'**
  String get setDefaultPalette;

  /// No description provided for @unsetDefaultPalette.
  ///
  /// In en, this message translates to:
  /// **'Not default'**
  String get unsetDefaultPalette;

  /// No description provided for @addCurrentColor.
  ///
  /// In en, this message translates to:
  /// **'Add the current colour'**
  String get addCurrentColor;

  /// No description provided for @replaceSwatch.
  ///
  /// In en, this message translates to:
  /// **'Replace with the current colour'**
  String get replaceSwatch;

  /// No description provided for @paletteCards.
  ///
  /// In en, this message translates to:
  /// **'Card view'**
  String get paletteCards;

  /// No description provided for @paletteCopy.
  ///
  /// In en, this message translates to:
  /// **'{name} copy'**
  String paletteCopy(String name);

  /// No description provided for @brushStudio.
  ///
  /// In en, this message translates to:
  /// **'Brush Studio'**
  String get brushStudio;

  /// No description provided for @drawingPad.
  ///
  /// In en, this message translates to:
  /// **'Drawing pad: draw here to try the brush'**
  String get drawingPad;

  /// No description provided for @studioStrokePath.
  ///
  /// In en, this message translates to:
  /// **'Stroke path'**
  String get studioStrokePath;

  /// No description provided for @studioShape.
  ///
  /// In en, this message translates to:
  /// **'Shape'**
  String get studioShape;

  /// No description provided for @studioGrain.
  ///
  /// In en, this message translates to:
  /// **'Grain'**
  String get studioGrain;

  /// No description provided for @studioRendering.
  ///
  /// In en, this message translates to:
  /// **'Rendering'**
  String get studioRendering;

  /// No description provided for @studioPencil.
  ///
  /// In en, this message translates to:
  /// **'Pencil'**
  String get studioPencil;

  /// No description provided for @studioProperties.
  ///
  /// In en, this message translates to:
  /// **'Properties'**
  String get studioProperties;

  /// No description provided for @studioAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get studioAbout;

  /// No description provided for @studioTaper.
  ///
  /// In en, this message translates to:
  /// **'Taper'**
  String get studioTaper;

  /// No description provided for @brushSpacing.
  ///
  /// In en, this message translates to:
  /// **'Spacing'**
  String get brushSpacing;

  /// No description provided for @brushScatter.
  ///
  /// In en, this message translates to:
  /// **'Jitter'**
  String get brushScatter;

  /// No description provided for @brushRotation.
  ///
  /// In en, this message translates to:
  /// **'Rotation'**
  String get brushRotation;

  /// No description provided for @brushRotationJitter.
  ///
  /// In en, this message translates to:
  /// **'Rotation jitter'**
  String get brushRotationJitter;

  /// No description provided for @brushFollowStroke.
  ///
  /// In en, this message translates to:
  /// **'Follow the stroke'**
  String get brushFollowStroke;

  /// No description provided for @brushSizeJitter.
  ///
  /// In en, this message translates to:
  /// **'Size jitter'**
  String get brushSizeJitter;

  /// No description provided for @brushOpacityJitter.
  ///
  /// In en, this message translates to:
  /// **'Opacity jitter'**
  String get brushOpacityJitter;

  /// No description provided for @brushFlow.
  ///
  /// In en, this message translates to:
  /// **'Flow'**
  String get brushFlow;

  /// No description provided for @brushGrainDepth.
  ///
  /// In en, this message translates to:
  /// **'Depth'**
  String get brushGrainDepth;

  /// No description provided for @brushGrainScale.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get brushGrainScale;

  /// No description provided for @brushPressureSize.
  ///
  /// In en, this message translates to:
  /// **'Pressure → size'**
  String get brushPressureSize;

  /// No description provided for @brushPressureOpacity.
  ///
  /// In en, this message translates to:
  /// **'Pressure → opacity'**
  String get brushPressureOpacity;

  /// No description provided for @brushDefaultSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get brushDefaultSize;

  /// No description provided for @brushName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get brushName;

  /// No description provided for @brushSmoothing.
  ///
  /// In en, this message translates to:
  /// **'Smoothing'**
  String get brushSmoothing;

  /// No description provided for @brushThinning.
  ///
  /// In en, this message translates to:
  /// **'Pressure thinning'**
  String get brushThinning;

  /// No description provided for @brushTip.
  ///
  /// In en, this message translates to:
  /// **'Tip'**
  String get brushTip;

  /// No description provided for @brushNoGrain.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get brushNoGrain;

  /// No description provided for @brushCustomImage.
  ///
  /// In en, this message translates to:
  /// **'Imported image'**
  String get brushCustomImage;

  /// No description provided for @brushEngine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get brushEngine;

  /// No description provided for @brushMypaintNote.
  ///
  /// In en, this message translates to:
  /// **'MyPaint brushes keep their own settings (JSON); only name and size change here.'**
  String get brushMypaintNote;

  /// No description provided for @brushReset.
  ///
  /// In en, this message translates to:
  /// **'Reset brush'**
  String get brushReset;

  /// No description provided for @brushEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit in Brush Studio'**
  String get brushEdit;

  /// No description provided for @brushSearch.
  ///
  /// In en, this message translates to:
  /// **'Search brushes'**
  String get brushSearch;

  /// No description provided for @recentBrushes.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recentBrushes;

  /// No description provided for @clearPad.
  ///
  /// In en, this message translates to:
  /// **'Clear pad'**
  String get clearPad;

  /// No description provided for @brushCopy.
  ///
  /// In en, this message translates to:
  /// **'{name} copy'**
  String brushCopy(String name);

  /// No description provided for @pressureCurve.
  ///
  /// In en, this message translates to:
  /// **'Pressure curve'**
  String get pressureCurve;

  /// No description provided for @pressureCurveHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the curve to change how pen pressure maps to stroke width and opacity. Tap to add a point, double-tap a point to remove it.'**
  String get pressureCurveHint;

  /// No description provided for @brushCursor.
  ///
  /// In en, this message translates to:
  /// **'Show brush outline'**
  String get brushCursor;

  /// No description provided for @resetCurve.
  ///
  /// In en, this message translates to:
  /// **'Reset curve'**
  String get resetCurve;

  /// No description provided for @addText.
  ///
  /// In en, this message translates to:
  /// **'Add text'**
  String get addText;

  /// No description provided for @textDefault.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get textDefault;

  /// No description provided for @typeText.
  ///
  /// In en, this message translates to:
  /// **'Type the text'**
  String get typeText;

  /// No description provided for @font.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get font;

  /// No description provided for @defaultFont.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultFont;

  /// No description provided for @importFont.
  ///
  /// In en, this message translates to:
  /// **'Import font…'**
  String get importFont;

  /// No description provided for @bold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get bold;

  /// No description provided for @italic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get italic;

  /// No description provided for @underline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get underline;

  /// No description provided for @outlineText.
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get outlineText;

  /// No description provided for @alignment.
  ///
  /// In en, this message translates to:
  /// **'Alignment'**
  String get alignment;

  /// No description provided for @allCaps.
  ///
  /// In en, this message translates to:
  /// **'All caps'**
  String get allCaps;

  /// No description provided for @verticalText.
  ///
  /// In en, this message translates to:
  /// **'Vertical'**
  String get verticalText;

  /// No description provided for @textStyle.
  ///
  /// In en, this message translates to:
  /// **'Text style'**
  String get textStyle;

  /// No description provided for @textSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get textSize;

  /// No description provided for @fontWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get fontWeight;

  /// No description provided for @letterSpacing.
  ///
  /// In en, this message translates to:
  /// **'Letter spacing'**
  String get letterSpacing;

  /// No description provided for @lineSpacing.
  ///
  /// In en, this message translates to:
  /// **'Line spacing'**
  String get lineSpacing;

  /// No description provided for @baselineShift.
  ///
  /// In en, this message translates to:
  /// **'Baseline'**
  String get baselineShift;

  /// No description provided for @rasterize.
  ///
  /// In en, this message translates to:
  /// **'Rasterize'**
  String get rasterize;

  /// No description provided for @editText.
  ///
  /// In en, this message translates to:
  /// **'Edit text'**
  String get editText;

  /// No description provided for @rasterizeAsk.
  ///
  /// In en, this message translates to:
  /// **'This is a text layer. Rasterize it to paint on it?'**
  String get rasterizeAsk;

  /// No description provided for @textHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the box to move it and its right handle to widen it. Picking a colour colours the text. Tap outside the box to finish.'**
  String get textHint;

  /// No description provided for @gallerySelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get gallerySelect;

  /// No description provided for @galleryStack.
  ///
  /// In en, this message translates to:
  /// **'Stack'**
  String get galleryStack;

  /// No description provided for @galleryDefaultStack.
  ///
  /// In en, this message translates to:
  /// **'Stack'**
  String get galleryDefaultStack;

  /// No description provided for @galleryUnstack.
  ///
  /// In en, this message translates to:
  /// **'Unstack'**
  String get galleryUnstack;

  /// No description provided for @galleryRemoveFromStack.
  ///
  /// In en, this message translates to:
  /// **'Remove from stack'**
  String get galleryRemoveFromStack;

  /// No description provided for @galleryDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get galleryDuplicate;

  /// No description provided for @galleryDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get galleryDelete;

  /// No description provided for @galleryPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get galleryPreview;

  /// No description provided for @galleryBack.
  ///
  /// In en, this message translates to:
  /// **'Back to gallery'**
  String get galleryBack;

  /// No description provided for @galleryHint.
  ///
  /// In en, this message translates to:
  /// **'Long-press a drawing and drag it onto another to move it there, or onto a stack to put it in. Select several to stack, copy or delete them.'**
  String get galleryHint;

  /// No description provided for @gallerySelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String gallerySelected(int count);

  /// No description provided for @galleryDeleteAsk.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete this drawing? This cannot be undone.} other{Delete {count} drawings? This cannot be undone.}}'**
  String galleryDeleteAsk(int count);

  /// No description provided for @presetScreen.
  ///
  /// In en, this message translates to:
  /// **'Screen size'**
  String get presetScreen;

  /// No description provided for @presetSquare.
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get presetSquare;

  /// No description provided for @preset4k.
  ///
  /// In en, this message translates to:
  /// **'4K'**
  String get preset4k;

  /// No description provided for @presetA4.
  ///
  /// In en, this message translates to:
  /// **'A4'**
  String get presetA4;

  /// No description provided for @presetPhoto.
  ///
  /// In en, this message translates to:
  /// **'4 × 6 photo'**
  String get presetPhoto;

  /// No description provided for @presetLetter.
  ///
  /// In en, this message translates to:
  /// **'US Letter'**
  String get presetLetter;

  /// No description provided for @canvasUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get canvasUnit;

  /// No description provided for @canvasDpi.
  ///
  /// In en, this message translates to:
  /// **'DPI'**
  String get canvasDpi;

  /// No description provided for @swapSides.
  ///
  /// In en, this message translates to:
  /// **'Swap width and height'**
  String get swapSides;

  /// No description provided for @savePreset.
  ///
  /// In en, this message translates to:
  /// **'Save as preset'**
  String get savePreset;

  /// No description provided for @updatePreset.
  ///
  /// In en, this message translates to:
  /// **'Update preset'**
  String get updatePreset;

  /// No description provided for @presetName.
  ///
  /// In en, this message translates to:
  /// **'Preset name'**
  String get presetName;

  /// No description provided for @editPreset.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editPreset;

  /// No description provided for @deletePreset.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deletePreset;

  /// No description provided for @myPresets.
  ///
  /// In en, this message translates to:
  /// **'My presets'**
  String get myPresets;

  /// No description provided for @canvasTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Too large: {width} × {height} px. A side may be {min}–{max} px; lower the size or the DPI.'**
  String canvasTooLarge(int width, int height, int min, int max);

  /// No description provided for @canvasPixels.
  ///
  /// In en, this message translates to:
  /// **'{width} × {height} px'**
  String canvasPixels(int width, int height);

  /// No description provided for @exportImage.
  ///
  /// In en, this message translates to:
  /// **'Export image…'**
  String get exportImage;

  /// No description provided for @exportFormatPsd.
  ///
  /// In en, this message translates to:
  /// **'PSD · layers, groups, blend modes'**
  String get exportFormatPsd;

  /// No description provided for @exportFormatPng.
  ///
  /// In en, this message translates to:
  /// **'PNG · transparency'**
  String get exportFormatPng;

  /// No description provided for @exportFormatJpeg.
  ///
  /// In en, this message translates to:
  /// **'JPEG · smallest'**
  String get exportFormatJpeg;

  /// No description provided for @exportFormatTiff.
  ///
  /// In en, this message translates to:
  /// **'TIFF · transparency'**
  String get exportFormatTiff;

  /// No description provided for @exportFormatPdf.
  ///
  /// In en, this message translates to:
  /// **'PDF · print size at the drawing\'s DPI'**
  String get exportFormatPdf;

  /// No description provided for @exportLayersPng.
  ///
  /// In en, this message translates to:
  /// **'Layers as PNG files (ZIP)'**
  String get exportLayersPng;

  /// No description provided for @exportLayersPdf.
  ///
  /// In en, this message translates to:
  /// **'Layers as PDF pages'**
  String get exportLayersPdf;

  /// No description provided for @exportLayer.
  ///
  /// In en, this message translates to:
  /// **'Export layer as PNG'**
  String get exportLayer;

  /// No description provided for @importScaled.
  ///
  /// In en, this message translates to:
  /// **'The file was larger than {max} pixels a side and was made smaller to fit.'**
  String importScaled(int max);

  /// No description provided for @importPartial.
  ///
  /// In en, this message translates to:
  /// **'Procreate\'s layers can\'t be read yet: its preview came in as one layer.'**
  String get importPartial;

  /// No description provided for @importTooManyLayers.
  ///
  /// In en, this message translates to:
  /// **'Only the top {max} layers were kept.'**
  String importTooManyLayers(int max);

  /// No description provided for @quickMenu.
  ///
  /// In en, this message translates to:
  /// **'QuickMenu'**
  String get quickMenu;

  /// No description provided for @quickMenuTrigger.
  ///
  /// In en, this message translates to:
  /// **'Open QuickMenu with'**
  String get quickMenuTrigger;

  /// No description provided for @quickMenuTriggerNone.
  ///
  /// In en, this message translates to:
  /// **'Right click only'**
  String get quickMenuTriggerNone;

  /// No description provided for @quickMenuTriggerHold.
  ///
  /// In en, this message translates to:
  /// **'Touch and hold'**
  String get quickMenuTriggerHold;

  /// No description provided for @quickMenuTriggerFour.
  ///
  /// In en, this message translates to:
  /// **'Four-finger tap'**
  String get quickMenuTriggerFour;

  /// No description provided for @quickMenuHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a button, or keep your finger down and slide onto one. Long-press a button to change what it does; tap the middle to switch profile, long-press it to manage profiles.'**
  String get quickMenuHint;

  /// No description provided for @quickMenuAssign.
  ///
  /// In en, this message translates to:
  /// **'Button action'**
  String get quickMenuAssign;

  /// No description provided for @quickMenuProfiles.
  ///
  /// In en, this message translates to:
  /// **'QuickMenu profiles'**
  String get quickMenuProfiles;

  /// No description provided for @quickMenuNewProfile.
  ///
  /// In en, this message translates to:
  /// **'New profile'**
  String get quickMenuNewProfile;

  /// No description provided for @quickMenuProfileName.
  ///
  /// In en, this message translates to:
  /// **'Profile {number}'**
  String quickMenuProfileName(int number);

  /// No description provided for @moveSidebar.
  ///
  /// In en, this message translates to:
  /// **'Drag to move the sidebar'**
  String get moveSidebar;

  /// No description provided for @gestureControls.
  ///
  /// In en, this message translates to:
  /// **'Gesture controls'**
  String get gestureControls;

  /// No description provided for @fingerTool.
  ///
  /// In en, this message translates to:
  /// **'A finger paints with'**
  String get fingerTool;

  /// No description provided for @fingerToolSame.
  ///
  /// In en, this message translates to:
  /// **'The current tool'**
  String get fingerToolSame;

  /// No description provided for @fingerToolSmudge.
  ///
  /// In en, this message translates to:
  /// **'Smudge'**
  String get fingerToolSmudge;

  /// No description provided for @fingerToolEraser.
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get fingerToolEraser;

  /// No description provided for @eyedropperHold.
  ///
  /// In en, this message translates to:
  /// **'Touch and hold picks a colour'**
  String get eyedropperHold;

  /// No description provided for @quickShapeDelay.
  ///
  /// In en, this message translates to:
  /// **'QuickShape hold'**
  String get quickShapeDelay;

  /// No description provided for @quickShapeOff.
  ///
  /// In en, this message translates to:
  /// **'off'**
  String get quickShapeOff;

  /// No description provided for @undoDelay.
  ///
  /// In en, this message translates to:
  /// **'Two-finger undo repeat after'**
  String get undoDelay;

  /// No description provided for @touchGestures.
  ///
  /// In en, this message translates to:
  /// **'Multi-finger taps (undo, redo, full screen…)'**
  String get touchGestures;

  /// No description provided for @selectionMaskVisibility.
  ///
  /// In en, this message translates to:
  /// **'Selection mask'**
  String get selectionMaskVisibility;

  /// No description provided for @autoHideInterface.
  ///
  /// In en, this message translates to:
  /// **'Fade the bars while drawing'**
  String get autoHideInterface;

  /// No description provided for @gestureHint.
  ///
  /// In en, this message translates to:
  /// **'Touch and hold opens either the eyedropper or the QuickMenu: turning one on moves the other.'**
  String get gestureHint;

  /// No description provided for @exportProcreateBrush.
  ///
  /// In en, this message translates to:
  /// **'Export as Procreate brush'**
  String get exportProcreateBrush;

  /// No description provided for @exportBrushset.
  ///
  /// In en, this message translates to:
  /// **'Export stamp brushes as .brushset'**
  String get exportBrushset;

  /// No description provided for @brushImportFormats.
  ///
  /// In en, this message translates to:
  /// **'Also: Procreate .brush and .brushset, Photoshop .abr (sampled tips).'**
  String get brushImportFormats;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @brushDeleteAsk.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete this brush? This cannot be undone.} other{Delete {count} brushes? This cannot be undone.}}'**
  String brushDeleteAsk(int count);

  /// No description provided for @studioDual.
  ///
  /// In en, this message translates to:
  /// **'Dual brush'**
  String get studioDual;

  /// No description provided for @dualBrush.
  ///
  /// In en, this message translates to:
  /// **'Combine with a second tip'**
  String get dualBrush;

  /// No description provided for @dualTip.
  ///
  /// In en, this message translates to:
  /// **'Second tip'**
  String get dualTip;

  /// No description provided for @dualBlend.
  ///
  /// In en, this message translates to:
  /// **'Combine mode'**
  String get dualBlend;

  /// No description provided for @dualSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get dualSize;

  /// No description provided for @dualHint.
  ///
  /// In en, this message translates to:
  /// **'The second tip is stamped along the same stroke and combined with the first: Multiply paints only where both do (a texture inside the stroke), Screen or Add where either does, Subtract cuts the second out.'**
  String get dualHint;

  /// No description provided for @recolor.
  ///
  /// In en, this message translates to:
  /// **'Recolor'**
  String get recolor;

  /// No description provided for @recolorFlood.
  ///
  /// In en, this message translates to:
  /// **'Flood'**
  String get recolorFlood;

  /// No description provided for @recolorGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global'**
  String get recolorGlobal;

  /// No description provided for @recolorColor.
  ///
  /// In en, this message translates to:
  /// **'New colour'**
  String get recolorColor;

  /// No description provided for @recolorThreshold.
  ///
  /// In en, this message translates to:
  /// **'Threshold'**
  String get recolorThreshold;

  /// No description provided for @recolorHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the crosshair onto a colour: it and the colours near it take the new colour, keeping their shading. Flood changes only the connected area, Global every match; slide sideways to change the threshold.'**
  String get recolorHint;

  /// No description provided for @reference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get reference;

  /// No description provided for @referenceCanvas.
  ///
  /// In en, this message translates to:
  /// **'Show the canvas'**
  String get referenceCanvas;

  /// No description provided for @referenceImage.
  ///
  /// In en, this message translates to:
  /// **'Show a picture…'**
  String get referenceImage;

  /// No description provided for @paletteFromImage.
  ///
  /// In en, this message translates to:
  /// **'Palette from a picture'**
  String get paletteFromImage;

  /// No description provided for @paletteFromFile.
  ///
  /// In en, this message translates to:
  /// **'From a file…'**
  String get paletteFromFile;

  /// No description provided for @paletteFromCanvas.
  ///
  /// In en, this message translates to:
  /// **'From the canvas'**
  String get paletteFromCanvas;

  /// No description provided for @paletteColors.
  ///
  /// In en, this message translates to:
  /// **'Colours'**
  String get paletteColors;

  /// No description provided for @paletteCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get paletteCreate;

  /// No description provided for @exportPalette.
  ///
  /// In en, this message translates to:
  /// **'Export as .{format}'**
  String exportPalette(String format);

  /// No description provided for @pageAssist.
  ///
  /// In en, this message translates to:
  /// **'Page Assist'**
  String get pageAssist;

  /// No description provided for @pagePrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get pagePrevious;

  /// No description provided for @pageNext.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get pageNext;

  /// No description provided for @exportPagesPdf.
  ///
  /// In en, this message translates to:
  /// **'Pages as PDF (Page Assist)'**
  String get exportPagesPdf;

  /// No description provided for @exportFormatGif.
  ///
  /// In en, this message translates to:
  /// **'Animated GIF · 256 colours, plays everywhere'**
  String get exportFormatGif;

  /// No description provided for @exportFormatApng.
  ///
  /// In en, this message translates to:
  /// **'Animated PNG · full colour, transparency'**
  String get exportFormatApng;

  /// No description provided for @exportFormatMp4.
  ///
  /// In en, this message translates to:
  /// **'MP4 · video'**
  String get exportFormatMp4;

  /// No description provided for @exportFormatHevc.
  ///
  /// In en, this message translates to:
  /// **'HEVC · video with transparency'**
  String get exportFormatHevc;

  /// No description provided for @exportAnimationSize.
  ///
  /// In en, this message translates to:
  /// **'Animation size'**
  String get exportAnimationSize;

  /// No description provided for @exportSizeFull.
  ///
  /// In en, this message translates to:
  /// **'Max resolution (up to {pixels} px)'**
  String exportSizeFull(int pixels);

  /// No description provided for @exportSizeWeb.
  ///
  /// In en, this message translates to:
  /// **'Web-ready (800 px, smaller file)'**
  String get exportSizeWeb;

  /// No description provided for @privateLayer.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get privateLayer;

  /// No description provided for @privateHint.
  ///
  /// In en, this message translates to:
  /// **'Private layers stay out of the time-lapse recording.'**
  String get privateHint;

  /// No description provided for @insertPrivatePhoto.
  ///
  /// In en, this message translates to:
  /// **'Insert a private photo'**
  String get insertPrivatePhoto;

  /// No description provided for @pastePrivately.
  ///
  /// In en, this message translates to:
  /// **'Paste privately'**
  String get pastePrivately;

  /// No description provided for @videoSection.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get videoSection;

  /// No description provided for @timelapseRecording.
  ///
  /// In en, this message translates to:
  /// **'Time-lapse recording'**
  String get timelapseRecording;

  /// No description provided for @timelapseReplay.
  ///
  /// In en, this message translates to:
  /// **'Time-lapse replay'**
  String get timelapseReplay;

  /// No description provided for @timelapseExport.
  ///
  /// In en, this message translates to:
  /// **'Export time-lapse'**
  String get timelapseExport;

  /// No description provided for @timelapseFull.
  ///
  /// In en, this message translates to:
  /// **'Full length'**
  String get timelapseFull;

  /// No description provided for @timelapse30.
  ///
  /// In en, this message translates to:
  /// **'30 seconds'**
  String get timelapse30;

  /// No description provided for @timelapseClear.
  ///
  /// In en, this message translates to:
  /// **'Delete the time-lapse'**
  String get timelapseClear;

  /// No description provided for @timelapseClearAsk.
  ///
  /// In en, this message translates to:
  /// **'Delete this drawing\'s time-lapse? It records again from the next change.'**
  String get timelapseClearAsk;

  /// No description provided for @timelapseEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded yet: draw something.'**
  String get timelapseEmpty;

  /// No description provided for @timelapsePlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get timelapsePlay;

  /// No description provided for @timelapsePause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get timelapsePause;

  /// No description provided for @timelapseUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Video export is not available on this device.'**
  String get timelapseUnsupported;

  /// No description provided for @timelapseFrames.
  ///
  /// In en, this message translates to:
  /// **'{count} frames'**
  String timelapseFrames(int count);

  /// No description provided for @studioWetMix.
  ///
  /// In en, this message translates to:
  /// **'Wet mix'**
  String get studioWetMix;

  /// No description provided for @wetDilution.
  ///
  /// In en, this message translates to:
  /// **'Dilution'**
  String get wetDilution;

  /// No description provided for @wetCharge.
  ///
  /// In en, this message translates to:
  /// **'Charge'**
  String get wetCharge;

  /// No description provided for @wetPull.
  ///
  /// In en, this message translates to:
  /// **'Pull'**
  String get wetPull;

  /// No description provided for @wetHint.
  ///
  /// In en, this message translates to:
  /// **'Pull takes up the colour under the brush and carries it on, mixing it with the paint. Charge is how far a load of paint lasts (100% never runs out). Dilution thins the paint and lets it take up more.'**
  String get wetHint;

  /// No description provided for @colorProfile.
  ///
  /// In en, this message translates to:
  /// **'Colour profile'**
  String get colorProfile;

  /// No description provided for @profileSrgb.
  ///
  /// In en, this message translates to:
  /// **'sRGB'**
  String get profileSrgb;

  /// No description provided for @profileP3.
  ///
  /// In en, this message translates to:
  /// **'Display P3'**
  String get profileP3;

  /// No description provided for @profileCmyk.
  ///
  /// In en, this message translates to:
  /// **'CMYK'**
  String get profileCmyk;

  /// No description provided for @profileHint.
  ///
  /// In en, this message translates to:
  /// **'The screen shows sRGB colours: Display P3 drawings look their fullest in their exports, which carry the profile. CMYK exports (PSD, TIFF) separate the colours with a plain ink model, not a press profile; their other files are sRGB. Changing it relabels the drawing, it does not convert it.'**
  String get profileHint;

  /// No description provided for @colorBlack.
  ///
  /// In en, this message translates to:
  /// **'black'**
  String get colorBlack;

  /// No description provided for @colorWhite.
  ///
  /// In en, this message translates to:
  /// **'white'**
  String get colorWhite;

  /// No description provided for @colorGrey.
  ///
  /// In en, this message translates to:
  /// **'grey'**
  String get colorGrey;

  /// No description provided for @colorDark.
  ///
  /// In en, this message translates to:
  /// **'dark'**
  String get colorDark;

  /// No description provided for @colorLight.
  ///
  /// In en, this message translates to:
  /// **'light'**
  String get colorLight;

  /// No description provided for @colorGreyish.
  ///
  /// In en, this message translates to:
  /// **'greyish'**
  String get colorGreyish;

  /// No description provided for @colorBrown.
  ///
  /// In en, this message translates to:
  /// **'brown'**
  String get colorBrown;

  /// No description provided for @colorRed.
  ///
  /// In en, this message translates to:
  /// **'red'**
  String get colorRed;

  /// No description provided for @colorOrange.
  ///
  /// In en, this message translates to:
  /// **'orange'**
  String get colorOrange;

  /// No description provided for @colorYellow.
  ///
  /// In en, this message translates to:
  /// **'yellow'**
  String get colorYellow;

  /// No description provided for @colorLime.
  ///
  /// In en, this message translates to:
  /// **'lime'**
  String get colorLime;

  /// No description provided for @colorGreen.
  ///
  /// In en, this message translates to:
  /// **'green'**
  String get colorGreen;

  /// No description provided for @colorTurquoise.
  ///
  /// In en, this message translates to:
  /// **'turquoise'**
  String get colorTurquoise;

  /// No description provided for @colorBlue.
  ///
  /// In en, this message translates to:
  /// **'blue'**
  String get colorBlue;

  /// No description provided for @colorPurple.
  ///
  /// In en, this message translates to:
  /// **'purple'**
  String get colorPurple;

  /// No description provided for @colorMagenta.
  ///
  /// In en, this message translates to:
  /// **'magenta'**
  String get colorMagenta;

  /// No description provided for @colorPink.
  ///
  /// In en, this message translates to:
  /// **'pink'**
  String get colorPink;

  /// No description provided for @accessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get accessibility;

  /// No description provided for @largeText.
  ///
  /// In en, this message translates to:
  /// **'Interface text size'**
  String get largeText;

  /// No description provided for @colorNames.
  ///
  /// In en, this message translates to:
  /// **'Say the colour\'s name when it is picked'**
  String get colorNames;

  /// No description provided for @feedbackSounds.
  ///
  /// In en, this message translates to:
  /// **'Feedback sounds'**
  String get feedbackSounds;

  /// No description provided for @singleTouch.
  ///
  /// In en, this message translates to:
  /// **'Single-touch gestures'**
  String get singleTouch;

  /// No description provided for @singleTouchHint.
  ///
  /// In en, this message translates to:
  /// **'A floating pad: undo, redo, fit, and move, zoom or turn the canvas with one finger (tap a mode, drag on the canvas, tap it again to draw).'**
  String get singleTouchHint;

  /// No description provided for @touchMove.
  ///
  /// In en, this message translates to:
  /// **'Move the canvas'**
  String get touchMove;

  /// No description provided for @touchZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom the canvas'**
  String get touchZoom;

  /// No description provided for @touchRotate.
  ///
  /// In en, this message translates to:
  /// **'Turn the canvas'**
  String get touchRotate;

  /// No description provided for @fitCanvas.
  ///
  /// In en, this message translates to:
  /// **'Fit the canvas'**
  String get fitCanvas;

  /// No description provided for @animationAssist.
  ///
  /// In en, this message translates to:
  /// **'Animation Assist'**
  String get animationAssist;

  /// No description provided for @addFrame.
  ///
  /// In en, this message translates to:
  /// **'Add frame'**
  String get addFrame;

  /// No description provided for @frameOptions.
  ///
  /// In en, this message translates to:
  /// **'Frame options'**
  String get frameOptions;

  /// No description provided for @frameHold.
  ///
  /// In en, this message translates to:
  /// **'Hold'**
  String get frameHold;

  /// No description provided for @frameBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get frameBackground;

  /// No description provided for @frameForeground.
  ///
  /// In en, this message translates to:
  /// **'Foreground'**
  String get frameForeground;

  /// No description provided for @frameName.
  ///
  /// In en, this message translates to:
  /// **'Frame {number}'**
  String frameName(int number);

  /// No description provided for @frameHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a frame to show it; tap the shown frame for its options (hold, split, clear, copy, delete). + adds a frame right after the shown one. Select several to copy, clear, reverse, time or delete them at once. The first frame can be a background under every frame, the last a foreground over them.'**
  String get frameHint;

  /// No description provided for @animationSettings.
  ///
  /// In en, this message translates to:
  /// **'Animation settings'**
  String get animationSettings;

  /// No description provided for @playbackLoop.
  ///
  /// In en, this message translates to:
  /// **'Loop'**
  String get playbackLoop;

  /// No description provided for @playbackPingPong.
  ///
  /// In en, this message translates to:
  /// **'Ping-Pong'**
  String get playbackPingPong;

  /// No description provided for @playbackOneShot.
  ///
  /// In en, this message translates to:
  /// **'One shot'**
  String get playbackOneShot;

  /// No description provided for @framesPerSecond.
  ///
  /// In en, this message translates to:
  /// **'Frames per second'**
  String get framesPerSecond;

  /// No description provided for @onionFrames.
  ///
  /// In en, this message translates to:
  /// **'Onion skin frames'**
  String get onionFrames;

  /// No description provided for @onionOpacity.
  ///
  /// In en, this message translates to:
  /// **'Onion skin opacity'**
  String get onionOpacity;

  /// No description provided for @blendPrimary.
  ///
  /// In en, this message translates to:
  /// **'Blend primary frame'**
  String get blendPrimary;

  /// No description provided for @onionBehind.
  ///
  /// In en, this message translates to:
  /// **'Frames before'**
  String get onionBehind;

  /// No description provided for @onionAhead.
  ///
  /// In en, this message translates to:
  /// **'Frames after'**
  String get onionAhead;

  /// No description provided for @galleryDrawings.
  ///
  /// In en, this message translates to:
  /// **'Drawings'**
  String get galleryDrawings;

  /// No description provided for @theater.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get theater;

  /// No description provided for @newMovie.
  ///
  /// In en, this message translates to:
  /// **'New movie'**
  String get newMovie;

  /// No description provided for @untitledMovie.
  ///
  /// In en, this message translates to:
  /// **'Untitled movie'**
  String get untitledMovie;

  /// No description provided for @theaterEmpty.
  ///
  /// In en, this message translates to:
  /// **'No movies yet. A movie is a timeline of drawings, Flipbooks, media and text.'**
  String get theaterEmpty;

  /// No description provided for @theaterFolder.
  ///
  /// In en, this message translates to:
  /// **'Put in a folder'**
  String get theaterFolder;

  /// No description provided for @theaterDefaultFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get theaterDefaultFolder;

  /// No description provided for @theaterUnfolder.
  ///
  /// In en, this message translates to:
  /// **'Empty the folder'**
  String get theaterUnfolder;

  /// No description provided for @theaterRemoveFromFolder.
  ///
  /// In en, this message translates to:
  /// **'Take out of the folder'**
  String get theaterRemoveFromFolder;

  /// No description provided for @theaterBack.
  ///
  /// In en, this message translates to:
  /// **'Back to the Theater'**
  String get theaterBack;

  /// No description provided for @theaterDeleteAsk.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete this movie? This can\'t be undone.} other{Delete {count} movies? This can\'t be undone.}}'**
  String theaterDeleteAsk(int count);

  /// No description provided for @theaterUnreadable.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 movie file could not be read; it was left on disk as it is.} other{{count} movie files could not be read; they were left on disk as they are.}}'**
  String theaterUnreadable(int count);

  /// No description provided for @movieSettings.
  ///
  /// In en, this message translates to:
  /// **'Movie settings'**
  String get movieSettings;

  /// No description provided for @movieStart.
  ///
  /// In en, this message translates to:
  /// **'Start with'**
  String get movieStart;

  /// No description provided for @movieStartFlipbook.
  ///
  /// In en, this message translates to:
  /// **'Flipbook'**
  String get movieStartFlipbook;

  /// No description provided for @movieStartBlank.
  ///
  /// In en, this message translates to:
  /// **'Blank'**
  String get movieStartBlank;

  /// No description provided for @movieAspect.
  ///
  /// In en, this message translates to:
  /// **'Aspect ratio'**
  String get movieAspect;

  /// No description provided for @movieAspectWide.
  ///
  /// In en, this message translates to:
  /// **'16:9 widescreen'**
  String get movieAspectWide;

  /// No description provided for @movieAspectCinema.
  ///
  /// In en, this message translates to:
  /// **'21:9 cinema'**
  String get movieAspectCinema;

  /// No description provided for @movieAspectPortrait.
  ///
  /// In en, this message translates to:
  /// **'9:16 portrait'**
  String get movieAspectPortrait;

  /// No description provided for @movieAspectSquare.
  ///
  /// In en, this message translates to:
  /// **'1:1 square'**
  String get movieAspectSquare;

  /// No description provided for @movieAspectScreen.
  ///
  /// In en, this message translates to:
  /// **'This screen'**
  String get movieAspectScreen;

  /// No description provided for @movieResolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get movieResolution;

  /// No description provided for @movieCustomSize.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get movieCustomSize;

  /// No description provided for @movieWidth.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get movieWidth;

  /// No description provided for @movieHeight.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get movieHeight;

  /// No description provided for @movieFps.
  ///
  /// In en, this message translates to:
  /// **'Frame rate'**
  String get movieFps;

  /// No description provided for @movieFpsCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom fps'**
  String get movieFpsCustom;

  /// No description provided for @movieDuration.
  ///
  /// In en, this message translates to:
  /// **'Length (seconds)'**
  String get movieDuration;

  /// No description provided for @movieBackground.
  ///
  /// In en, this message translates to:
  /// **'Stage colour'**
  String get movieBackground;

  /// No description provided for @movieTransparent.
  ///
  /// In en, this message translates to:
  /// **'Transparent stage'**
  String get movieTransparent;

  /// No description provided for @movieOffstage.
  ///
  /// In en, this message translates to:
  /// **'Offstage'**
  String get movieOffstage;

  /// No description provided for @movieCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get movieCreate;

  /// No description provided for @movieTracks.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get movieTracks;

  /// No description provided for @movieNoTracks.
  ///
  /// In en, this message translates to:
  /// **'No tracks yet'**
  String get movieNoTracks;

  /// No description provided for @movieTimelineNext.
  ///
  /// In en, this message translates to:
  /// **'The timeline comes next: tracks, contents and the playhead.'**
  String get movieTimelineNext;

  /// No description provided for @timelineAddTrack.
  ///
  /// In en, this message translates to:
  /// **'Add track'**
  String get timelineAddTrack;

  /// No description provided for @trackDrawing.
  ///
  /// In en, this message translates to:
  /// **'Drawing'**
  String get trackDrawing;

  /// No description provided for @trackDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete track'**
  String get trackDelete;

  /// No description provided for @timelineZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in on time'**
  String get timelineZoomIn;

  /// No description provided for @timelineZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out of time'**
  String get timelineZoomOut;

  /// No description provided for @timelinePlayFromStart.
  ///
  /// In en, this message translates to:
  /// **'Play from the start'**
  String get timelinePlayFromStart;

  /// No description provided for @timelineHint.
  ///
  /// In en, this message translates to:
  /// **'Tap or drag the ruler to move the playhead; fling it left to play from the start. Pinch sideways to zoom time, up and down for track height (Ctrl/⌘ + scroll zooms time). Drag the bar above to give the timeline more room. Space plays, arrows step a frame.'**
  String get timelineHint;

  /// No description provided for @composeReset.
  ///
  /// In en, this message translates to:
  /// **'Reset position, size and turn'**
  String get composeReset;

  /// No description provided for @fullscreenPreview.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen preview'**
  String get fullscreenPreview;

  /// No description provided for @composeHint.
  ///
  /// In en, this message translates to:
  /// **'Tap something on the stage to choose it, then drag it, its corners (size), sides (stretch), the round handle (turn) or the cross (anchor). Put a second finger down, or hold Shift, to snap.'**
  String get composeHint;

  /// No description provided for @contentDraw.
  ///
  /// In en, this message translates to:
  /// **'Draw in it'**
  String get contentDraw;

  /// No description provided for @backToMovie.
  ///
  /// In en, this message translates to:
  /// **'Back to the movie'**
  String get backToMovie;

  /// No description provided for @framesSelect.
  ///
  /// In en, this message translates to:
  /// **'Select frames'**
  String get framesSelect;

  /// No description provided for @flipbookMini.
  ///
  /// In en, this message translates to:
  /// **'Mini Flipbook (floats over the canvas)'**
  String get flipbookMini;

  /// No description provided for @frameClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get frameClear;

  /// No description provided for @framesReverse.
  ///
  /// In en, this message translates to:
  /// **'Reverse their order'**
  String get framesReverse;

  /// No description provided for @framesDuration.
  ///
  /// In en, this message translates to:
  /// **'How long each stays'**
  String get framesDuration;

  /// No description provided for @framesTicks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 frame (on ones)} =2{2 frames (on twos)} other{{count} frames}}'**
  String framesTicks(int count);

  /// No description provided for @frameSplit.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get frameSplit;

  /// No description provided for @flipbookDock.
  ///
  /// In en, this message translates to:
  /// **'Back to the timeline'**
  String get flipbookDock;

  /// No description provided for @miniFlipbookHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the handle to move it: it locks to the left or right edge upright, to the top edge lying down; drop it at the bottom (or double-tap the handle) to put the timeline back. Drag along the frames to scrub through them.'**
  String get miniFlipbookHint;

  /// No description provided for @timelineChoose.
  ///
  /// In en, this message translates to:
  /// **'Select several (tap, or drag a lasso over the tracks)'**
  String get timelineChoose;

  /// No description provided for @timelineFreeTrim.
  ///
  /// In en, this message translates to:
  /// **'Free Trim: trimming an end moves what follows'**
  String get timelineFreeTrim;

  /// No description provided for @timelinePaste.
  ///
  /// In en, this message translates to:
  /// **'Paste at the playhead'**
  String get timelinePaste;

  /// No description provided for @contentSplit.
  ///
  /// In en, this message translates to:
  /// **'Split at the playhead'**
  String get contentSplit;

  /// No description provided for @contentFill.
  ///
  /// In en, this message translates to:
  /// **'Fill duration'**
  String get contentFill;

  /// No description provided for @contentDuplicateAfter.
  ///
  /// In en, this message translates to:
  /// **'Duplicate right after'**
  String get contentDuplicateAfter;

  /// No description provided for @contentHide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get contentHide;

  /// No description provided for @contentShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get contentShow;

  /// No description provided for @contentColor.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get contentColor;

  /// No description provided for @contentColorDefault.
  ///
  /// In en, this message translates to:
  /// **'Its usual colour'**
  String get contentColorDefault;

  /// No description provided for @contentReverse.
  ///
  /// In en, this message translates to:
  /// **'Reverse their order'**
  String get contentReverse;

  /// No description provided for @contentRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get contentRename;

  /// No description provided for @trackVisibility.
  ///
  /// In en, this message translates to:
  /// **'Show or hide on the stage'**
  String get trackVisibility;

  /// No description provided for @trackDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate track'**
  String get trackDuplicate;

  /// No description provided for @trackUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get trackUp;

  /// No description provided for @trackDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get trackDown;

  /// No description provided for @trackGroup.
  ///
  /// In en, this message translates to:
  /// **'Group with the track below'**
  String get trackGroup;

  /// No description provided for @trackCloseGaps.
  ///
  /// In en, this message translates to:
  /// **'Close the gaps'**
  String get trackCloseGaps;

  /// No description provided for @groupDefault.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get groupDefault;

  /// No description provided for @groupFold.
  ///
  /// In en, this message translates to:
  /// **'Fold or unfold'**
  String get groupFold;

  /// No description provided for @contentHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a content to choose it, then drag it along or to another track, or drag its ends to trim (Free Trim moves what follows). Double-tap to draw in it; hold or right-click for more.'**
  String get contentHint;

  /// No description provided for @keyframeMode.
  ///
  /// In en, this message translates to:
  /// **'Keyframes: stage changes key the chosen content at the playhead'**
  String get keyframeMode;

  /// No description provided for @keyframeActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get keyframeActions;

  /// No description provided for @keyAddMove.
  ///
  /// In en, this message translates to:
  /// **'Add a Move & Scale keyframe here'**
  String get keyAddMove;

  /// No description provided for @keyAddStart.
  ///
  /// In en, this message translates to:
  /// **'Add a keyframe at its start'**
  String get keyAddStart;

  /// No description provided for @keyAllEasings.
  ///
  /// In en, this message translates to:
  /// **'All easings'**
  String get keyAllEasings;

  /// No description provided for @keyReverse.
  ///
  /// In en, this message translates to:
  /// **'Reverse keyframes'**
  String get keyReverse;

  /// No description provided for @keyCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy keyframes'**
  String get keyCopy;

  /// No description provided for @keyPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste keyframes here'**
  String get keyPaste;

  /// No description provided for @keyClear.
  ///
  /// In en, this message translates to:
  /// **'Clear keyframes'**
  String get keyClear;

  /// No description provided for @keyDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete keyframe'**
  String get keyDelete;

  /// No description provided for @keyEasing.
  ///
  /// In en, this message translates to:
  /// **'Easing to the next'**
  String get keyEasing;

  /// No description provided for @keyExpand.
  ///
  /// In en, this message translates to:
  /// **'Show each parameter'**
  String get keyExpand;

  /// No description provided for @keyCollapse.
  ///
  /// In en, this message translates to:
  /// **'Show them together'**
  String get keyCollapse;

  /// No description provided for @easingLinear.
  ///
  /// In en, this message translates to:
  /// **'Linear'**
  String get easingLinear;

  /// No description provided for @easingIn.
  ///
  /// In en, this message translates to:
  /// **'Ease in'**
  String get easingIn;

  /// No description provided for @easingOut.
  ///
  /// In en, this message translates to:
  /// **'Ease out'**
  String get easingOut;

  /// No description provided for @easingInOut.
  ///
  /// In en, this message translates to:
  /// **'Ease in and out'**
  String get easingInOut;

  /// No description provided for @paramX.
  ///
  /// In en, this message translates to:
  /// **'X'**
  String get paramX;

  /// No description provided for @paramY.
  ///
  /// In en, this message translates to:
  /// **'Y'**
  String get paramY;

  /// No description provided for @paramScale.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get paramScale;

  /// No description provided for @paramRotation.
  ///
  /// In en, this message translates to:
  /// **'Turn'**
  String get paramRotation;

  /// No description provided for @keyframeHint.
  ///
  /// In en, this message translates to:
  /// **'In keyframe mode, moving, sizing or turning the chosen content on the stage keys it at the playhead. Diamonds mark keyframes: tap one to go there, drag it to retime, hold or right-click for easing, delete or expand. Values hold before the first keyframe and after the last.'**
  String get keyframeHint;

  /// No description provided for @filterOpacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get filterOpacity;

  /// No description provided for @filterGaussianBlur.
  ///
  /// In en, this message translates to:
  /// **'Gaussian blur'**
  String get filterGaussianBlur;

  /// No description provided for @filterSharpen.
  ///
  /// In en, this message translates to:
  /// **'Sharpen'**
  String get filterSharpen;

  /// No description provided for @filterHsb.
  ///
  /// In en, this message translates to:
  /// **'Hue, saturation, brightness'**
  String get filterHsb;

  /// No description provided for @filterNoise.
  ///
  /// In en, this message translates to:
  /// **'Noise'**
  String get filterNoise;

  /// No description provided for @filterLensBlur.
  ///
  /// In en, this message translates to:
  /// **'Lens blur'**
  String get filterLensBlur;

  /// No description provided for @filterAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get filterAmount;

  /// No description provided for @filterHue.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get filterHue;

  /// No description provided for @filterSaturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get filterSaturation;

  /// No description provided for @filterBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get filterBrightness;

  /// No description provided for @filterNoiseType.
  ///
  /// In en, this message translates to:
  /// **'Clouds · billows · ridges'**
  String get filterNoiseType;

  /// No description provided for @filterScale.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get filterScale;

  /// No description provided for @filterOctaves.
  ///
  /// In en, this message translates to:
  /// **'Octaves'**
  String get filterOctaves;

  /// No description provided for @filterTurbulence.
  ///
  /// In en, this message translates to:
  /// **'Turbulence'**
  String get filterTurbulence;

  /// No description provided for @filterOffsetX.
  ///
  /// In en, this message translates to:
  /// **'Offset X'**
  String get filterOffsetX;

  /// No description provided for @filterOffsetY.
  ///
  /// In en, this message translates to:
  /// **'Offset Y'**
  String get filterOffsetY;

  /// No description provided for @filterTravelX.
  ///
  /// In en, this message translates to:
  /// **'Drift X (per second)'**
  String get filterTravelX;

  /// No description provided for @filterTravelY.
  ///
  /// In en, this message translates to:
  /// **'Drift Y (per second)'**
  String get filterTravelY;

  /// No description provided for @filterRadius.
  ///
  /// In en, this message translates to:
  /// **'Radius'**
  String get filterRadius;

  /// No description provided for @filterContrast.
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get filterContrast;

  /// No description provided for @liveFilters.
  ///
  /// In en, this message translates to:
  /// **'Live filters'**
  String get liveFilters;

  /// No description provided for @addFilter.
  ///
  /// In en, this message translates to:
  /// **'Add a filter'**
  String get addFilter;

  /// No description provided for @removeFilter.
  ///
  /// In en, this message translates to:
  /// **'Remove the filter'**
  String get removeFilter;

  /// No description provided for @filtersHint.
  ///
  /// In en, this message translates to:
  /// **'Filters change how the content looks without touching its drawing. In keyframe mode each change keys it at the playhead; otherwise a setting stays the same all along.'**
  String get filtersHint;

  /// No description provided for @composeMove.
  ///
  /// In en, this message translates to:
  /// **'Move & Scale'**
  String get composeMove;

  /// No description provided for @distort.
  ///
  /// In en, this message translates to:
  /// **'Distort'**
  String get distort;

  /// No description provided for @warp.
  ///
  /// In en, this message translates to:
  /// **'Warp'**
  String get warp;

  /// No description provided for @warpAddColumn.
  ///
  /// In en, this message translates to:
  /// **'More nodes across (starts the warp over)'**
  String get warpAddColumn;

  /// No description provided for @warpAddRow.
  ///
  /// In en, this message translates to:
  /// **'More nodes down (starts the warp over)'**
  String get warpAddRow;

  /// No description provided for @meshReset.
  ///
  /// In en, this message translates to:
  /// **'Straighten'**
  String get meshReset;

  /// No description provided for @performMode.
  ///
  /// In en, this message translates to:
  /// **'Perform: drag on the stage to record motion while the movie plays'**
  String get performMode;

  /// No description provided for @motionFilter.
  ///
  /// In en, this message translates to:
  /// **'Motion filter (smooths a performance)'**
  String get motionFilter;

  /// No description provided for @performHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a content, then drag it (or its corner, turn handle, Distort corner, Warp node or a filter slider): the movie plays and a keyframe is written every frame. Lift to pause. Recording the same thing again writes over it; different things layer. A performance past the content\'s end makes it longer where there is room.'**
  String get performHint;

  /// No description provided for @contentLook.
  ///
  /// In en, this message translates to:
  /// **'Opacity, blend and mask'**
  String get contentLook;

  /// No description provided for @maskOver.
  ///
  /// In en, this message translates to:
  /// **'Mask over the content beneath'**
  String get maskOver;

  /// No description provided for @maskNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get maskNone;

  /// No description provided for @maskClip.
  ///
  /// In en, this message translates to:
  /// **'Clip'**
  String get maskClip;

  /// No description provided for @maskAlpha.
  ///
  /// In en, this message translates to:
  /// **'Alpha'**
  String get maskAlpha;

  /// No description provided for @maskLuma.
  ///
  /// In en, this message translates to:
  /// **'Luminance'**
  String get maskLuma;

  /// No description provided for @maskInvert.
  ///
  /// In en, this message translates to:
  /// **'Invert the mask'**
  String get maskInvert;

  /// No description provided for @passthrough.
  ///
  /// In en, this message translates to:
  /// **'Passthrough (its tracks mix with what is outside)'**
  String get passthrough;

  /// No description provided for @toDrawings.
  ///
  /// In en, this message translates to:
  /// **'Make into drawings'**
  String get toDrawings;

  /// No description provided for @toFlipbook.
  ///
  /// In en, this message translates to:
  /// **'Make into a Flipbook'**
  String get toFlipbook;

  /// No description provided for @cannotFlipbook.
  ///
  /// In en, this message translates to:
  /// **'Only drawings that don\'t overlap in time can become a Flipbook.'**
  String get cannotFlipbook;

  /// No description provided for @timelineImport.
  ///
  /// In en, this message translates to:
  /// **'Bring in a picture, GIF, video or sound'**
  String get timelineImport;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'That file could not be brought in.'**
  String get importFailed;

  /// No description provided for @separateAudio.
  ///
  /// In en, this message translates to:
  /// **'Separate audio and video'**
  String get separateAudio;

  /// No description provided for @trackSound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get trackSound;

  /// No description provided for @volume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volume;

  /// No description provided for @trackText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get trackText;

  /// No description provided for @textEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit the text'**
  String get textEdit;

  /// No description provided for @textPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get textPlaceholder;

  /// No description provided for @textWords.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get textWords;

  /// No description provided for @textFont.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get textFont;

  /// No description provided for @textDefaultFont.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get textDefaultFont;

  /// No description provided for @exportMovie.
  ///
  /// In en, this message translates to:
  /// **'Export the movie'**
  String get exportMovie;

  /// No description provided for @exportMp4.
  ///
  /// In en, this message translates to:
  /// **'MP4 video (H.264, with sound)'**
  String get exportMp4;

  /// No description provided for @exportHevc.
  ///
  /// In en, this message translates to:
  /// **'HEVC video with transparency (.mov, with sound)'**
  String get exportHevc;

  /// No description provided for @exportGif.
  ///
  /// In en, this message translates to:
  /// **'Animated GIF'**
  String get exportGif;

  /// No description provided for @exportPngFrames.
  ///
  /// In en, this message translates to:
  /// **'PNG frames (zip)'**
  String get exportPngFrames;

  /// No description provided for @exportJpegFrames.
  ///
  /// In en, this message translates to:
  /// **'JPEG frames (zip)'**
  String get exportJpegFrames;

  /// No description provided for @exportTiffFrames.
  ///
  /// In en, this message translates to:
  /// **'TIFF frames (zip)'**
  String get exportTiffFrames;

  /// No description provided for @exportTgaFrames.
  ///
  /// In en, this message translates to:
  /// **'TGA frames (zip)'**
  String get exportTgaFrames;

  /// No description provided for @exportBmpFrames.
  ///
  /// In en, this message translates to:
  /// **'BMP frames (zip)'**
  String get exportBmpFrames;

  /// No description provided for @exportFrame.
  ///
  /// In en, this message translates to:
  /// **'This frame (PNG)'**
  String get exportFrame;

  /// No description provided for @exportProject.
  ///
  /// In en, this message translates to:
  /// **'Project file (.artmovie)'**
  String get exportProject;

  /// No description provided for @exportPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview: half size'**
  String get exportPreview;

  /// No description provided for @exportColors.
  ///
  /// In en, this message translates to:
  /// **'Colours'**
  String get exportColors;

  /// No description provided for @exportDither.
  ///
  /// In en, this message translates to:
  /// **'Dither'**
  String get exportDither;

  /// No description provided for @exportAlphaThreshold.
  ///
  /// In en, this message translates to:
  /// **'Alpha threshold'**
  String get exportAlphaThreshold;

  /// No description provided for @exportGo.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportGo;

  /// No description provided for @exportWorking.
  ///
  /// In en, this message translates to:
  /// **'Exporting…'**
  String get exportWorking;

  /// No description provided for @importProject.
  ///
  /// In en, this message translates to:
  /// **'Bring in a project file (.artmovie)'**
  String get importProject;

  /// No description provided for @actionPlay.
  ///
  /// In en, this message translates to:
  /// **'Play or stop'**
  String get actionPlay;

  /// No description provided for @actionStepBack.
  ///
  /// In en, this message translates to:
  /// **'One frame back'**
  String get actionStepBack;

  /// No description provided for @actionStepForward.
  ///
  /// In en, this message translates to:
  /// **'One frame on'**
  String get actionStepForward;

  /// No description provided for @moviePrefs.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get moviePrefs;

  /// No description provided for @prefsUndoButtons.
  ///
  /// In en, this message translates to:
  /// **'Undo and redo buttons on the stage'**
  String get prefsUndoButtons;

  /// No description provided for @prefsQuickUndo.
  ///
  /// In en, this message translates to:
  /// **'Held undo repeats after'**
  String get prefsQuickUndo;

  /// No description provided for @prefsUndoDepth.
  ///
  /// In en, this message translates to:
  /// **'Undo steps kept'**
  String get prefsUndoDepth;

  /// No description provided for @prefsTwoFingerUndo.
  ///
  /// In en, this message translates to:
  /// **'Two-finger tap undoes'**
  String get prefsTwoFingerUndo;

  /// No description provided for @prefsThreeFingerRedo.
  ///
  /// In en, this message translates to:
  /// **'Three-finger tap redoes'**
  String get prefsThreeFingerRedo;

  /// No description provided for @prefsShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get prefsShortcuts;

  /// No description provided for @prefsRecovery.
  ///
  /// In en, this message translates to:
  /// **'Recovery points'**
  String get prefsRecovery;

  /// No description provided for @prefsPressKeys.
  ///
  /// In en, this message translates to:
  /// **'Press the keys…'**
  String get prefsPressKeys;

  /// No description provided for @prefsDefaults.
  ///
  /// In en, this message translates to:
  /// **'Defaults'**
  String get prefsDefaults;

  /// No description provided for @recoveryNone.
  ///
  /// In en, this message translates to:
  /// **'No recovery points yet: one is kept at most every five minutes while you work.'**
  String get recoveryNone;

  /// No description provided for @mcpTitle.
  ///
  /// In en, this message translates to:
  /// **'AI agents (MCP)'**
  String get mcpTitle;

  /// No description provided for @mcpLan.
  ///
  /// In en, this message translates to:
  /// **'Reachable on the local network'**
  String get mcpLan;

  /// No description provided for @mcpAdd.
  ///
  /// In en, this message translates to:
  /// **'Add ArtBlend to Claude Code (Terminal):'**
  String get mcpAdd;

  /// No description provided for @mcpNewKey.
  ///
  /// In en, this message translates to:
  /// **'New key'**
  String get mcpNewKey;

  /// No description provided for @mcpHint.
  ///
  /// In en, this message translates to:
  /// **'Lets Claude Code, Claude Desktop and other MCP clients draw, edit layers, apply adjustments and build movies in ArtBlend, live and undoable. Whoever has the key can control the app: keep it to yourself, and renew it to shut agents out.'**
  String get mcpHint;

  /// No description provided for @mcpError.
  ///
  /// In en, this message translates to:
  /// **'Could not start: {message}'**
  String mcpError(String message);

  /// No description provided for @mcpWorking.
  ///
  /// In en, this message translates to:
  /// **'AI at work: {tool}'**
  String mcpWorking(String tool);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
