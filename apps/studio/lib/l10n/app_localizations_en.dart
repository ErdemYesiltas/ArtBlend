// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get gallery => 'Gallery';

  @override
  String get actions => 'Actions';

  @override
  String get brush => 'Brush';

  @override
  String get eraser => 'Eraser';

  @override
  String get pan => 'Move canvas';

  @override
  String get layers => 'Layers';

  @override
  String get colors => 'Colors';

  @override
  String get settings => 'Preferences';

  @override
  String get connections => 'Local AI';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get size => 'Size';

  @override
  String get opacity => 'Opacity';

  @override
  String get saved => 'Saved on device';

  @override
  String get unsaved => 'Unsaved changes';

  @override
  String get saving => 'Saving…';

  @override
  String get saveFailed => 'Save failed · Retry';

  @override
  String get newDocument => 'New drawing';

  @override
  String get openDocument => 'Open drawing';

  @override
  String get saveDocument => 'Save now';

  @override
  String get exportDocument => 'Export drawing file';

  @override
  String get exportPng => 'Export PNG';

  @override
  String get rename => 'Rename';

  @override
  String get name => 'Name';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get close => 'Close';

  @override
  String get newDocumentMessage =>
      'The current drawing is saved before starting a new one. Export a drawing file to keep a separate copy.';

  @override
  String get untitled => 'Untitled drawing';

  @override
  String get brushLibrary => 'Brush library';

  @override
  String get importBrush => 'Import brush presets';

  @override
  String get importPalette => 'Import palette';

  @override
  String get brushImportHint =>
      'ArtBlend JSON presets · MyPaint v3 (.myb) · ABR and PNG tip brushes are planned for a later milestone.';

  @override
  String get paletteImportHint =>
      'HEX · GPL · RGB ASE · RGB/HSB ACO · SWATCHES v1';

  @override
  String get ink => 'Studio ink';

  @override
  String get pencil => 'Sketch pencil';

  @override
  String get marker => 'Flat marker';

  @override
  String get coast => 'Coastal study';

  @override
  String get custom => 'Imported';

  @override
  String get language => 'Language';

  @override
  String get system => 'System';

  @override
  String get theme => 'Appearance';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get rightSidebar => 'Controls on the right';

  @override
  String get fingerDrawing => 'Draw with a finger';

  @override
  String get themeHint => 'Appearance never changes artwork or palette colors.';

  @override
  String get palmHint =>
      'Disable finger drawing when using a stylus for reliable separation from touch gestures.';

  @override
  String get addLayer => 'Add layer';

  @override
  String layerName(int index) {
    return 'Layer $index';
  }

  @override
  String get deleteLayer => 'Delete layer';

  @override
  String get hideLayer => 'Show / hide layer';

  @override
  String get lockLayer => 'Lock / unlock layer';

  @override
  String get moveUp => 'Move layer up';

  @override
  String get moveDown => 'Move layer down';

  @override
  String get colorHex => 'Hex color';

  @override
  String get apply => 'Apply';

  @override
  String get invalidHex => 'Enter a valid 6- or 8-digit hex color.';

  @override
  String get zoomReset => 'Fit canvas';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get checking => 'Checking…';

  @override
  String get startupError =>
      'Your saved drawing could not be opened. The existing files have been preserved.';

  @override
  String get retry => 'Retry';

  @override
  String importSuccess(String name) {
    return 'Imported: $name';
  }

  @override
  String operationFailed(String detail) {
    return 'Could not complete the operation: $detail';
  }

  @override
  String get exportSuccess => 'File exported';

  @override
  String get activeLayer => 'Active layer';

  @override
  String get prototype => 'Development build · Freehand engine';

  @override
  String get drawingAssistant => 'Drawing assistant';

  @override
  String get model => 'Model';

  @override
  String get askAssistant => 'Ask about color, composition or your next idea…';

  @override
  String get send => 'Send';

  @override
  String get chatPrivacy =>
      'Only the text you enter is sent to the selected local server.';

  @override
  String get fingerprint => 'Certificate fingerprint';

  @override
  String get pairingCode => 'Pairing code';

  @override
  String get deviceName => 'Device name';

  @override
  String get pairDevice => 'Pair device';

  @override
  String get removePairing => 'Revoke this device';

  @override
  String get mcpTools => 'MCP tools';

  @override
  String get noMcpServers =>
      'No MCP server is allowed for this device. Allow one in LocalHub on the Mac (Devices).';

  @override
  String get runTool => 'Run';

  @override
  String get generationComplete => 'Completed · Choose an image to preview';

  @override
  String get importImage => 'Import image';

  @override
  String get addImageLayer => 'Add as new layer';

  @override
  String get transformLayer => 'Transform layer';

  @override
  String get transformHint =>
      'Drag to move, drag a corner to scale, or pinch to scale and rotate. Apply commits the preview and crops pixels outside the canvas; switching tools cancels.';

  @override
  String get transformUnavailable =>
      'Choose a visible, unlocked layer with artwork.';

  @override
  String get scale => 'Scale';

  @override
  String get rotation => 'Rotation';

  @override
  String get resetTransform => 'Reset';

  @override
  String get blendMode => 'Blend mode';

  @override
  String get blendNormal => 'Normal';

  @override
  String get blendMultiply => 'Multiply';

  @override
  String get blendScreen => 'Screen';

  @override
  String get selection => 'Selection';

  @override
  String get selectionHint =>
      'Draw a region. Done keeps it active for painting. A layer mask hides pixels without deleting them.';

  @override
  String get rectangleSelection => 'Rectangle';

  @override
  String get freehandSelection => 'Freehand';

  @override
  String get invertSelection => 'Invert';

  @override
  String get deselect => 'Deselect';

  @override
  String get exportSelectionMask => 'Export mask';

  @override
  String get layerMask => 'Layer mask';

  @override
  String get removeLayerMask => 'Remove layer mask';

  @override
  String get deleteSelected => 'Erase selected';

  @override
  String get selectionDone => 'Done';

  @override
  String get transformMaskHint =>
      'Applying a transform merges the current layer mask into its pixels. Undo restores the editable mask.';

  @override
  String get transformSelection => 'Transform selection';

  @override
  String get inpaintPrompt => 'Describe what should appear here';

  @override
  String get generationSettings => 'Generation settings';

  @override
  String get negativePrompt => 'Negative prompt';

  @override
  String get seed => 'Seed';

  @override
  String get steps => 'Steps';

  @override
  String get denoise => 'Change strength';

  @override
  String get inpaintNeedsSelection =>
      'Select a region on the canvas before running inpaint.';

  @override
  String get charcoal => 'Charcoal';

  @override
  String get modelling => 'Modelling';

  @override
  String get mypaintBrush => 'MyPaint';

  @override
  String galleryUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count drawing files could not be read and are not listed. They are left untouched on disk.',
      one: '1 drawing file could not be read and is not listed. It is left untouched on disk.',
    );
    return '$_temp0';
  }

  @override
  String get libraryUnreadable =>
      'The brush and palette library could not be read. Built-in brushes are available; the library file is not overwritten and importing is disabled until it is repaired.';

  @override
  String get scanPairingQr => 'Scan QR code';

  @override
  String get scanPairingQrHint =>
      'Point the camera at the QR code LocalHub shows on your Mac (Devices → Pair a device).';

  @override
  String get invalidPairingQr =>
      'This QR code is not a LocalHub pairing code. Create a new one on the Mac if it has expired.';

  @override
  String cameraUnavailable(String error) {
    return 'The camera is unavailable: $error. You can type the address, fingerprint and code instead.';
  }

  @override
  String get eyedropper => 'Eyedropper';

  @override
  String get stabilization => 'Stabilization';

  @override
  String get streamLine => 'StreamLine';

  @override
  String get streamLineHint =>
      'Per brush. Irons out bumps and shakiness: the line trails the pen slightly and catches up when you lift it. Hold Option/Alt with a brush to pick a colour.';

  @override
  String get pressureAndSmoothing => 'Pressure and smoothing';

  @override
  String get motionFiltering => 'Motion filtering';

  @override
  String get motionExpression => 'Motion filtering expression';

  @override
  String get smoothingHint =>
      'Apply to every brush, on top of its StreamLine. Stabilization averages your movement and grows stronger the faster you draw; slow lines stay precise. Motion filtering removes the extremes of wobble at any speed, and Expression brings some natural variation back.';

  @override
  String unsupportedFile(String name) {
    return '$name is not a supported file for this action.';
  }

  @override
  String get canvasSize => 'Canvas size';

  @override
  String squareCanvas(String size) {
    return 'Square · $size';
  }

  @override
  String screenCanvas(String size) {
    return 'Screen · $size';
  }

  @override
  String get customCanvas => 'Custom';

  @override
  String get canvasWidth => 'Width';

  @override
  String get canvasHeight => 'Height';

  @override
  String canvasSizeHint(int min, int max) {
    return '$min–$max pixels per side. The size stays fixed; large canvases use more memory.';
  }

  @override
  String get localHub => 'LocalHub';

  @override
  String get hubHint =>
      'Open LocalHub on your Mac, choose Devices → Pair a device, then scan its QR code or enter the address, SHA-256 fingerprint and code it shows.';

  @override
  String get companionRetired =>
      'This is a pairing code from the retired ArtBlend Companion. Install LocalHub on your Mac and pair with the code it shows.';

  @override
  String hubPaired(String name) {
    return 'Paired with $name';
  }

  @override
  String get refresh => 'Refresh';

  @override
  String get hubNoWorkflow =>
      'Allowed, but LocalHub has no model or workflow for this yet. Add one on the Mac.';

  @override
  String get hubPermissionMissing =>
      'This device is not allowed to use this. Allow it in LocalHub on the Mac (Devices).';

  @override
  String get editSelection => 'Repaint selection';

  @override
  String get createImage => 'New image';

  @override
  String get hubDefaultModel => 'Hub default';

  @override
  String get imagePrompt => 'Describe the image';

  @override
  String get generate => 'Generate';

  @override
  String get jobQueued => 'Waiting on the Mac…';

  @override
  String get jobRunning => 'Generating on the Mac…';

  @override
  String get jobCancelled => 'Stopped';

  @override
  String get stop => 'Stop';

  @override
  String get clear => 'Clear';

  @override
  String get hubFiles => 'Files on the hub';

  @override
  String get uploadFile => 'Upload image';

  @override
  String get uploadDrawing => 'Upload drawing';

  @override
  String get noHubFiles =>
      'No files yet. Uploads and generated images appear here.';

  @override
  String get addToCanvas => 'Add to canvas';

  @override
  String get deleteFile => 'Delete';

  @override
  String get mcpServer => 'MCP server';

  @override
  String get mcpTool => 'Tool';

  @override
  String get mcpArguments => 'Arguments (JSON)';

  @override
  String jobsAhead(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jobs ahead',
      one: '1 job ahead',
    );
    return '$_temp0';
  }

  @override
  String aboutMinutes(int minutes) {
    return 'about $minutes min';
  }

  @override
  String get generativeFill => 'Generative fill';

  @override
  String get fillPromptHint =>
      'What to add? Leave empty to match the surroundings';

  @override
  String get previousVariation => 'Previous variation';

  @override
  String get nextVariation => 'Next variation';

  @override
  String get newVariation => 'New variation';

  @override
  String get discard => 'Discard';

  @override
  String get done => 'Done';

  @override
  String get assistantTab => 'Assistant';

  @override
  String get filesTab => 'Files';

  @override
  String get hubNoImageWorkflow =>
      'LocalHub has no image workflow this device may use yet.';

  @override
  String hubIntegrationsDown(String names) {
    return 'Not running: $names';
  }

  @override
  String get writePrompt => 'Write a detailed prompt from these keywords';

  @override
  String get graphiteBrush => 'Graphite';

  @override
  String get pastelBrush => 'Soft pastel';

  @override
  String get dryBrush => 'Dry brush';

  @override
  String get gouacheBrush => 'Gouache';

  @override
  String get splatterBrush => 'Splatter';

  @override
  String get stampBrush => 'Texture';

  @override
  String get blendDarken => 'Darken';

  @override
  String get blendColorBurn => 'Color burn';

  @override
  String get blendLighten => 'Lighten';

  @override
  String get blendColorDodge => 'Color dodge';

  @override
  String get blendAdd => 'Add';

  @override
  String get blendOverlay => 'Overlay';

  @override
  String get blendSoftLight => 'Soft light';

  @override
  String get blendHardLight => 'Hard light';

  @override
  String get blendDifference => 'Difference';

  @override
  String get renameLayer => 'Rename';

  @override
  String get duplicateLayer => 'Duplicate';

  @override
  String get mergeDown => 'Merge down';

  @override
  String get clearLayer => 'Clear';

  @override
  String get unlockLayer => 'Unlock layer';

  @override
  String layerCopy(String name) {
    return '$name copy';
  }

  @override
  String layerCount(int count, int max) {
    return '$count of $max layers';
  }

  @override
  String get layersHint =>
      'Tap the selected layer for options · swipe right to choose more · pinch two layers to merge them · hold and drag to reorder · the letter sets blend mode and opacity';

  @override
  String get ellipseSelection => 'Ellipse';

  @override
  String get selectionNew => 'New';

  @override
  String get selectionAdd => 'Add';

  @override
  String get selectionSubtract => 'Remove';

  @override
  String get featherSelection => 'Soft edge';

  @override
  String featherAmount(int pixels) {
    return 'Soft edge $pixels px';
  }

  @override
  String get featherHint =>
      'Fades the selection\'s edge over this many canvas pixels: strokes, masks, deleting and generative fill blend in instead of stopping at a hard line.';

  @override
  String get drawingGuide => 'Drawing guide';

  @override
  String get symmetry => 'Symmetry';

  @override
  String get symmetryOff => 'Off';

  @override
  String get symmetryVertical => 'Vertical';

  @override
  String get symmetryHorizontal => 'Horizontal';

  @override
  String get symmetryQuadrant => 'Quadrant';

  @override
  String get symmetryRadial => 'Radial';

  @override
  String get gridGuide => 'Grid';

  @override
  String get turnView => 'Turn the view';

  @override
  String get turnLeft => 'Turn left 90°';

  @override
  String get turnRight => 'Turn right 90°';

  @override
  String get colorDisc => 'Disc';

  @override
  String get colorValues => 'Values';

  @override
  String get recentColors => 'Recent';

  @override
  String get exitFullScreen => 'Show the interface';

  @override
  String get fullScreen => 'Full screen';

  @override
  String get swapColor => 'Previous colour';

  @override
  String undone(String action) {
    return 'Undo: $action';
  }

  @override
  String redone(String action) {
    return 'Redo: $action';
  }

  @override
  String get historyPaint => 'Paint';

  @override
  String get historyAddLayer => 'New layer';

  @override
  String get historyDeleteLayer => 'Delete layer';

  @override
  String get historyMergeLayers => 'Merge layers';

  @override
  String get historyMoveLayer => 'Move layer';

  @override
  String get historyLayerMask => 'Layer mask';

  @override
  String get historyLayerSettings => 'Layer settings';

  @override
  String get historyRename => 'Rename';

  @override
  String get historyCanvas => 'Canvas';

  @override
  String get historyEdit => 'Edit';

  @override
  String get cut => 'Cut';

  @override
  String get copy => 'Copy';

  @override
  String get copyAll => 'Copy all';

  @override
  String get cutAndPaste => 'Cut & paste';

  @override
  String get paste => 'Paste';

  @override
  String get fromSelection => 'From selection';

  @override
  String get pastedLayer => 'Pasted';

  @override
  String get smudge => 'Smudge';

  @override
  String get referenceLayer => 'Reference';

  @override
  String get colorDrop => 'ColorDrop';

  @override
  String get fillThreshold => 'Threshold';

  @override
  String get fillHint =>
      'Tap more areas to fill them; the threshold redoes the last fill.';

  @override
  String get alphaLock => 'Alpha lock';

  @override
  String get clippingMask => 'Clipping mask';

  @override
  String get fillLayer => 'Fill layer';

  @override
  String get invertLayer => 'Invert';

  @override
  String get backgroundColor => 'Background color';

  @override
  String get adjustments => 'Adjustments';

  @override
  String get adjustColor => 'Color';

  @override
  String get adjustBlur => 'Blur';

  @override
  String get hueSaturationBrightness => 'Hue, Saturation, Brightness';

  @override
  String get gaussianBlur => 'Gaussian Blur';

  @override
  String get adjustHue => 'Hue';

  @override
  String get adjustSaturation => 'Saturation';

  @override
  String get adjustBrightness => 'Brightness';

  @override
  String get adjustAmount => 'Amount';

  @override
  String get adjustLayer => 'Layer';

  @override
  String get adjustPencil => 'Pencil';

  @override
  String get adjustPreview => 'Preview';

  @override
  String get adjustReset => 'Reset';

  @override
  String get adjustSwipeHint =>
      'Slide left or right on the canvas to change the amount.';

  @override
  String get adjustPencilHint =>
      'Paint where the adjustment should apply; the eraser takes it back.';

  @override
  String get adjustUnavailable => 'The layer is locked or hidden.';

  @override
  String get colorBalance => 'Color Balance';

  @override
  String get curves => 'Curves';

  @override
  String get gradientMap => 'Gradient Map';

  @override
  String get toneShadows => 'Shadows';

  @override
  String get toneMidtones => 'Midtones';

  @override
  String get toneHighlights => 'Highlights';

  @override
  String get cyanRed => 'Cyan – Red';

  @override
  String get magentaGreen => 'Magenta – Green';

  @override
  String get yellowBlue => 'Yellow – Blue';

  @override
  String get curveGamma => 'Gamma';

  @override
  String get curveRed => 'Red';

  @override
  String get curveGreen => 'Green';

  @override
  String get curveBlue => 'Blue';

  @override
  String get curvesHint =>
      'Drag to add or move a point; double-tap a point to remove it.';

  @override
  String get gradientHint =>
      'Tap the bar to add a color, tap a color to change it, hold it to remove it.';

  @override
  String get gradientNoir => 'Noir';

  @override
  String get gradientSepia => 'Sepia';

  @override
  String get gradientSunset => 'Sunset';

  @override
  String get gradientOcean => 'Ocean';

  @override
  String get gradientNeon => 'Neon';

  @override
  String get gradientGold => 'Gold';

  @override
  String get motionBlur => 'Motion Blur';

  @override
  String get perspectiveBlur => 'Perspective Blur';

  @override
  String get adjustAngle => 'Angle';

  @override
  String get perspectivePositional => 'Positional';

  @override
  String get perspectiveDirectional => 'Directional';

  @override
  String get motionHint =>
      'Slide on the canvas in the direction of the blur; a longer slide blurs more.';

  @override
  String get perspectiveHint =>
      'Drag the disc to move the centre; slide elsewhere to change the amount.';

  @override
  String get transformFreeform => 'Freeform';

  @override
  String get transformUniform => 'Uniform';

  @override
  String get transformDistort => 'Distort';

  @override
  String get transformWarp => 'Warp';

  @override
  String get flipHorizontal => 'Flip horizontal';

  @override
  String get flipVertical => 'Flip vertical';

  @override
  String get rotate45 => 'Rotate 45°';

  @override
  String get fitToScreen => 'Fit to screen';

  @override
  String get interpolation => 'Interpolation';

  @override
  String get interpolationNearest => 'Nearest neighbor';

  @override
  String get interpolationBilinear => 'Bilinear';

  @override
  String get interpolationBicubic => 'Bicubic';

  @override
  String get transformFreeformHint =>
      'Drag a corner or side to stretch, the middle to move; pinch to rotate.';

  @override
  String get transformDistortHint =>
      'Drag a corner for perspective, a side to skew, the middle to move.';

  @override
  String get transformWarpHint =>
      'Drag anywhere on the mesh to bend it; drag outside it to move.';

  @override
  String get enterValue => 'Enter a value';

  @override
  String get editShape => 'Edit Shape';

  @override
  String get perfectShape => 'Perfect';

  @override
  String get groupLayers => 'Group';

  @override
  String get ungroup => 'Ungroup';

  @override
  String get leaveGroup => 'Remove from group';

  @override
  String get flattenGroup => 'Flatten group';

  @override
  String get deleteGroup => 'Delete group';

  @override
  String get renameGroup => 'Rename group';

  @override
  String get mergeChosen => 'Merge';

  @override
  String get deleteChosen => 'Delete';

  @override
  String groupName(int index) {
    return 'Group $index';
  }

  @override
  String chosenLayers(int count) {
    return '$count layers chosen';
  }

  @override
  String get blendLinearBurn => 'Linear Burn';

  @override
  String get blendDarkerColor => 'Darker Color';

  @override
  String get blendLighterColor => 'Lighter Color';

  @override
  String get blendVividLight => 'Vivid Light';

  @override
  String get blendLinearLight => 'Linear Light';

  @override
  String get blendPinLight => 'Pin Light';

  @override
  String get blendHardMix => 'Hard Mix';

  @override
  String get blendExclusion => 'Exclusion';

  @override
  String get blendSubtract => 'Subtract';

  @override
  String get blendDivide => 'Divide';

  @override
  String get blendHue => 'Hue';

  @override
  String get blendSaturation => 'Saturation';

  @override
  String get blendColor => 'Color';

  @override
  String get blendLuminosity => 'Luminosity';

  @override
  String get liquify => 'Liquify';

  @override
  String get liquifyPush => 'Push';

  @override
  String get liquifyTwirlRight => 'Twirl right';

  @override
  String get liquifyTwirlLeft => 'Twirl left';

  @override
  String get liquifyPinch => 'Pinch';

  @override
  String get liquifyExpand => 'Expand';

  @override
  String get liquifyCrystals => 'Crystals';

  @override
  String get liquifyEdge => 'Edge';

  @override
  String get liquifyReconstruct => 'Reconstruct';

  @override
  String get liquifySize => 'Size';

  @override
  String get liquifyPressure => 'Pressure';

  @override
  String get liquifyDistortion => 'Distortion';

  @override
  String get liquifyMomentum => 'Momentum';

  @override
  String get liquifyHalfBack => 'Reconstruct ½';

  @override
  String get liquifyHint =>
      'Drag on the canvas; Twirl, Pinch, Expand and Crystals keep working while you hold still.';

  @override
  String get clone => 'Clone';

  @override
  String get cloneLock => 'Lock source';

  @override
  String get cloneHint =>
      'Drag the disc onto what to copy, then paint: the disc follows your brush. Locked, the disc stays put and every stroke starts copying from it (the ✕ shows where pixels come from).';

  @override
  String get adjustFilters => 'Filters';

  @override
  String get sharpen => 'Sharpen';

  @override
  String get noise => 'Noise';

  @override
  String get bloom => 'Bloom';

  @override
  String get glitch => 'Glitch';

  @override
  String get halftone => 'Halftone';

  @override
  String get chromaticAberration => 'Chromatic Aberration';

  @override
  String get noiseClouds => 'Clouds';

  @override
  String get noiseBillows => 'Billows';

  @override
  String get noiseRidges => 'Ridges';

  @override
  String get noiseScale => 'Scale';

  @override
  String get noiseOctaves => 'Octaves';

  @override
  String get noiseTurbulence => 'Turbulence';

  @override
  String get bloomTransition => 'Transition';

  @override
  String get filterSize => 'Size';

  @override
  String get bloomBurn => 'Burn';

  @override
  String get glitchArtifact => 'Artifact';

  @override
  String get glitchWave => 'Wave';

  @override
  String get glitchSignal => 'Signal';

  @override
  String get glitchDiverge => 'Diverge';

  @override
  String get glitchBlock => 'Block size';

  @override
  String get glitchZoom => 'Zoom';

  @override
  String get halftoneFullColor => 'Full color';

  @override
  String get halftoneScreenPrint => 'Screen print';

  @override
  String get halftoneNewspaper => 'Newspaper';

  @override
  String get chromaticPerspective => 'Perspective';

  @override
  String get chromaticDisplace => 'Displace';

  @override
  String get chromaticFalloff => 'Falloff';

  @override
  String get automaticSelection => 'Automatic';

  @override
  String get selectionThreshold => 'Threshold';

  @override
  String get selectLayerContents => 'Select contents';

  @override
  String get automaticSelectionHint =>
      'Tap a colour area; keep the finger down and slide left or right to change the threshold.';

  @override
  String get freehandSelectionHint => 'Drag to draw the outline.';

  @override
  String get closePolygon => 'Close polygon';

  @override
  String get polygonSelection => 'Polygon';

  @override
  String get polygonSelectionHint =>
      'Tap to place corners; drag a corner to move it; tap the first corner (or Close polygon) to finish.';

  @override
  String get savedSelections => 'Save & load';

  @override
  String get saveSelection => 'Save selection';

  @override
  String get previousSelection => 'Previous selection';

  @override
  String get colorFill => 'Color fill';

  @override
  String get copyPasteSelection => 'Copy & paste';

  @override
  String savedSelectionName(int index) {
    return 'Selection $index';
  }

  @override
  String get snapping => 'Snapping';

  @override
  String get magnetics => 'Magnetics';

  @override
  String get snapSettings => 'Snapping settings';

  @override
  String get snapDistance => 'Distance';

  @override
  String get snapVelocity => 'Velocity';

  @override
  String get cropResize => 'Crop & Resize';

  @override
  String get cropResample => 'Resample (scale the drawing)';

  @override
  String get rotateCanvasLeft => 'Rotate canvas left';

  @override
  String get rotateCanvasRight => 'Rotate canvas right';

  @override
  String get flipCanvasHorizontal => 'Flip canvas horizontally';

  @override
  String get flipCanvasVertical => 'Flip canvas vertically';

  @override
  String get cropHint =>
      'Drag the handles to crop; past the canvas edge it grows. With Resample on, a new size scales the drawing.';

  @override
  String get canvasInfo => 'Canvas info';

  @override
  String get infoSize => 'Size';

  @override
  String get infoPrint => 'Print size';

  @override
  String get infoLayers => 'Layers';

  @override
  String get infoGroups => 'Groups';

  @override
  String get infoStrokes => 'Vector strokes';

  @override
  String get infoSaved => 'Saved selections';

  @override
  String get infoMemory => 'Pixel data';

  @override
  String get infoEdits => 'Edits';

  @override
  String get editGuide => 'Edit drawing guide';

  @override
  String get guideNone => 'No guide';

  @override
  String get guideGrid => '2D grid';

  @override
  String get guideIsometric => 'Isometric';

  @override
  String get guidePerspective => 'Perspective';

  @override
  String get guideRotational => 'Rotational symmetry';

  @override
  String get guideRemovePoint => 'Remove last vanishing point';

  @override
  String get guideColor => 'Guide colour';

  @override
  String get guideThickness => 'Thickness';

  @override
  String get guideHint =>
      'Perspective: tap the canvas to add a vanishing point (up to three) and drag points to move them. Drag the symmetry centre to move the axes.';

  @override
  String get drawingAssist => 'Drawing assist';

  @override
  String get colorClassic => 'Classic';

  @override
  String get colorHarmony => 'Harmony';

  @override
  String get harmonyComplementary => 'Complementary';

  @override
  String get harmonySplit => 'Split complementary';

  @override
  String get harmonyAnalogous => 'Analogous';

  @override
  String get harmonyTriadic => 'Triadic';

  @override
  String get harmonyTetradic => 'Tetradic';

  @override
  String get colorBrightness => 'Brightness';

  @override
  String get palettes => 'Palettes';

  @override
  String get newPalette => 'New palette';

  @override
  String get paletteName => 'Palette';

  @override
  String get setDefaultPalette => 'Set as default';

  @override
  String get unsetDefaultPalette => 'Not default';

  @override
  String get addCurrentColor => 'Add the current colour';

  @override
  String get replaceSwatch => 'Replace with the current colour';

  @override
  String get paletteCards => 'Card view';

  @override
  String paletteCopy(String name) {
    return '$name copy';
  }

  @override
  String get brushStudio => 'Brush Studio';

  @override
  String get drawingPad => 'Drawing pad: draw here to try the brush';

  @override
  String get studioStrokePath => 'Stroke path';

  @override
  String get studioShape => 'Shape';

  @override
  String get studioGrain => 'Grain';

  @override
  String get studioRendering => 'Rendering';

  @override
  String get studioPencil => 'Pencil';

  @override
  String get studioProperties => 'Properties';

  @override
  String get studioAbout => 'About';

  @override
  String get studioTaper => 'Taper';

  @override
  String get brushSpacing => 'Spacing';

  @override
  String get brushScatter => 'Jitter';

  @override
  String get brushRotation => 'Rotation';

  @override
  String get brushRotationJitter => 'Rotation jitter';

  @override
  String get brushFollowStroke => 'Follow the stroke';

  @override
  String get brushSizeJitter => 'Size jitter';

  @override
  String get brushOpacityJitter => 'Opacity jitter';

  @override
  String get brushFlow => 'Flow';

  @override
  String get brushGrainDepth => 'Depth';

  @override
  String get brushGrainScale => 'Scale';

  @override
  String get brushPressureSize => 'Pressure → size';

  @override
  String get brushPressureOpacity => 'Pressure → opacity';

  @override
  String get brushDefaultSize => 'Size';

  @override
  String get brushName => 'Name';

  @override
  String get brushSmoothing => 'Smoothing';

  @override
  String get brushThinning => 'Pressure thinning';

  @override
  String get brushTip => 'Tip';

  @override
  String get brushNoGrain => 'None';

  @override
  String get brushCustomImage => 'Imported image';

  @override
  String get brushEngine => 'Engine';

  @override
  String get brushMypaintNote =>
      'MyPaint brushes keep their own settings (JSON); only name and size change here.';

  @override
  String get brushReset => 'Reset brush';

  @override
  String get brushEdit => 'Edit in Brush Studio';

  @override
  String get brushSearch => 'Search brushes';

  @override
  String get recentBrushes => 'Recent';

  @override
  String get clearPad => 'Clear pad';

  @override
  String brushCopy(String name) {
    return '$name copy';
  }

  @override
  String get pressureCurve => 'Pressure curve';

  @override
  String get pressureCurveHint =>
      'Drag the curve to change how pen pressure maps to stroke width and opacity. Tap to add a point, double-tap a point to remove it.';

  @override
  String get brushCursor => 'Show brush outline';

  @override
  String get resetCurve => 'Reset curve';

  @override
  String get addText => 'Add text';

  @override
  String get textDefault => 'Text';

  @override
  String get typeText => 'Type the text';

  @override
  String get font => 'Font';

  @override
  String get defaultFont => 'Default';

  @override
  String get importFont => 'Import font…';

  @override
  String get bold => 'Bold';

  @override
  String get italic => 'Italic';

  @override
  String get underline => 'Underline';

  @override
  String get outlineText => 'Outline';

  @override
  String get alignment => 'Alignment';

  @override
  String get allCaps => 'All caps';

  @override
  String get verticalText => 'Vertical';

  @override
  String get textStyle => 'Text style';

  @override
  String get textSize => 'Size';

  @override
  String get fontWeight => 'Weight';

  @override
  String get letterSpacing => 'Letter spacing';

  @override
  String get lineSpacing => 'Line spacing';

  @override
  String get baselineShift => 'Baseline';

  @override
  String get rasterize => 'Rasterize';

  @override
  String get editText => 'Edit text';

  @override
  String get rasterizeAsk =>
      'This is a text layer. Rasterize it to paint on it?';

  @override
  String get textHint =>
      'Drag the box to move it and its right handle to widen it. Picking a colour colours the text. Tap outside the box to finish.';

  @override
  String get gallerySelect => 'Select';

  @override
  String get galleryStack => 'Stack';

  @override
  String get galleryDefaultStack => 'Stack';

  @override
  String get galleryUnstack => 'Unstack';

  @override
  String get galleryRemoveFromStack => 'Remove from stack';

  @override
  String get galleryDuplicate => 'Duplicate';

  @override
  String get galleryDelete => 'Delete';

  @override
  String get galleryPreview => 'Preview';

  @override
  String get galleryBack => 'Back to gallery';

  @override
  String get galleryHint =>
      'Long-press a drawing and drag it onto another to move it there, or onto a stack to put it in. Select several to stack, copy or delete them.';

  @override
  String gallerySelected(int count) {
    return '$count selected';
  }

  @override
  String galleryDeleteAsk(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count drawings? This cannot be undone.',
      one: 'Delete this drawing? This cannot be undone.',
    );
    return '$_temp0';
  }

  @override
  String get presetScreen => 'Screen size';

  @override
  String get presetSquare => 'Square';

  @override
  String get preset4k => '4K';

  @override
  String get presetA4 => 'A4';

  @override
  String get presetPhoto => '4 × 6 photo';

  @override
  String get presetLetter => 'US Letter';

  @override
  String get canvasUnit => 'Unit';

  @override
  String get canvasDpi => 'DPI';

  @override
  String get swapSides => 'Swap width and height';

  @override
  String get savePreset => 'Save as preset';

  @override
  String get updatePreset => 'Update preset';

  @override
  String get presetName => 'Preset name';

  @override
  String get editPreset => 'Edit';

  @override
  String get deletePreset => 'Delete';

  @override
  String get myPresets => 'My presets';

  @override
  String canvasTooLarge(int width, int height, int min, int max) {
    return 'Too large: $width × $height px. A side may be $min–$max px; lower the size or the DPI.';
  }

  @override
  String canvasPixels(int width, int height) {
    return '$width × $height px';
  }

  @override
  String get exportImage => 'Export image…';

  @override
  String get exportFormatPsd => 'PSD · layers, groups, blend modes';

  @override
  String get exportFormatPng => 'PNG · transparency';

  @override
  String get exportFormatJpeg => 'JPEG · smallest';

  @override
  String get exportFormatTiff => 'TIFF · transparency';

  @override
  String get exportFormatPdf => 'PDF · print size at the drawing\'s DPI';

  @override
  String get exportLayersPng => 'Layers as PNG files (ZIP)';

  @override
  String get exportLayersPdf => 'Layers as PDF pages';

  @override
  String get exportLayer => 'Export layer as PNG';

  @override
  String importScaled(int max) {
    return 'The file was larger than $max pixels a side and was made smaller to fit.';
  }

  @override
  String get importPartial =>
      'Procreate\'s layers can\'t be read yet: its preview came in as one layer.';

  @override
  String importTooManyLayers(int max) {
    return 'Only the top $max layers were kept.';
  }

  @override
  String get quickMenu => 'QuickMenu';

  @override
  String get quickMenuTrigger => 'Open QuickMenu with';

  @override
  String get quickMenuTriggerNone => 'Right click only';

  @override
  String get quickMenuTriggerHold => 'Touch and hold';

  @override
  String get quickMenuTriggerFour => 'Four-finger tap';

  @override
  String get quickMenuHint =>
      'Tap a button, or keep your finger down and slide onto one. Long-press a button to change what it does; tap the middle to switch profile, long-press it to manage profiles.';

  @override
  String get quickMenuAssign => 'Button action';

  @override
  String get quickMenuProfiles => 'QuickMenu profiles';

  @override
  String get quickMenuNewProfile => 'New profile';

  @override
  String quickMenuProfileName(int number) {
    return 'Profile $number';
  }

  @override
  String get moveSidebar => 'Drag to move the sidebar';

  @override
  String get gestureControls => 'Gesture controls';

  @override
  String get fingerTool => 'A finger paints with';

  @override
  String get fingerToolSame => 'The current tool';

  @override
  String get fingerToolSmudge => 'Smudge';

  @override
  String get fingerToolEraser => 'Eraser';

  @override
  String get eyedropperHold => 'Touch and hold picks a colour';

  @override
  String get quickShapeDelay => 'QuickShape hold';

  @override
  String get quickShapeOff => 'off';

  @override
  String get undoDelay => 'Two-finger undo repeat after';

  @override
  String get touchGestures => 'Multi-finger taps (undo, redo, full screen…)';

  @override
  String get selectionMaskVisibility => 'Selection mask';

  @override
  String get autoHideInterface => 'Fade the bars while drawing';

  @override
  String get gestureHint =>
      'Touch and hold opens either the eyedropper or the QuickMenu: turning one on moves the other.';

  @override
  String get exportProcreateBrush => 'Export as Procreate brush';

  @override
  String get exportBrushset => 'Export stamp brushes as .brushset';

  @override
  String get brushImportFormats =>
      'Also: Procreate .brush and .brushset, Photoshop .abr (sampled tips).';

  @override
  String get selectAll => 'Select all';

  @override
  String brushDeleteAsk(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count brushes? This cannot be undone.',
      one: 'Delete this brush? This cannot be undone.',
    );
    return '$_temp0';
  }

  @override
  String get studioDual => 'Dual brush';

  @override
  String get dualBrush => 'Combine with a second tip';

  @override
  String get dualTip => 'Second tip';

  @override
  String get dualBlend => 'Combine mode';

  @override
  String get dualSize => 'Size';

  @override
  String get dualHint =>
      'The second tip is stamped along the same stroke and combined with the first: Multiply paints only where both do (a texture inside the stroke), Screen or Add where either does, Subtract cuts the second out.';

  @override
  String get recolor => 'Recolor';

  @override
  String get recolorFlood => 'Flood';

  @override
  String get recolorGlobal => 'Global';

  @override
  String get recolorColor => 'New colour';

  @override
  String get recolorThreshold => 'Threshold';

  @override
  String get recolorHint =>
      'Drag the crosshair onto a colour: it and the colours near it take the new colour, keeping their shading. Flood changes only the connected area, Global every match; slide sideways to change the threshold.';

  @override
  String get reference => 'Reference';

  @override
  String get referenceCanvas => 'Show the canvas';

  @override
  String get referenceImage => 'Show a picture…';

  @override
  String get paletteFromImage => 'Palette from a picture';

  @override
  String get paletteFromFile => 'From a file…';

  @override
  String get paletteFromCanvas => 'From the canvas';

  @override
  String get paletteColors => 'Colours';

  @override
  String get paletteCreate => 'Create';

  @override
  String exportPalette(String format) {
    return 'Export as .$format';
  }

  @override
  String get pageAssist => 'Page Assist';

  @override
  String get pagePrevious => 'Previous page';

  @override
  String get pageNext => 'Next page';

  @override
  String get exportPagesPdf => 'Pages as PDF (Page Assist)';

  @override
  String get exportFormatGif => 'Animated GIF · 256 colours, plays everywhere';

  @override
  String get exportFormatApng => 'Animated PNG · full colour, transparency';

  @override
  String get exportFormatMp4 => 'MP4 · video';

  @override
  String get exportFormatHevc => 'HEVC · video with transparency';

  @override
  String get exportAnimationSize => 'Animation size';

  @override
  String exportSizeFull(int pixels) {
    return 'Max resolution (up to $pixels px)';
  }

  @override
  String get exportSizeWeb => 'Web-ready (800 px, smaller file)';

  @override
  String get privateLayer => 'Private';

  @override
  String get privateHint =>
      'Private layers stay out of the time-lapse recording.';

  @override
  String get insertPrivatePhoto => 'Insert a private photo';

  @override
  String get pastePrivately => 'Paste privately';

  @override
  String get videoSection => 'Video';

  @override
  String get timelapseRecording => 'Time-lapse recording';

  @override
  String get timelapseReplay => 'Time-lapse replay';

  @override
  String get timelapseExport => 'Export time-lapse';

  @override
  String get timelapseFull => 'Full length';

  @override
  String get timelapse30 => '30 seconds';

  @override
  String get timelapseClear => 'Delete the time-lapse';

  @override
  String get timelapseClearAsk =>
      'Delete this drawing\'s time-lapse? It records again from the next change.';

  @override
  String get timelapseEmpty => 'Nothing recorded yet: draw something.';

  @override
  String get timelapsePlay => 'Play';

  @override
  String get timelapsePause => 'Pause';

  @override
  String get timelapseUnsupported =>
      'Video export is not available on this device.';

  @override
  String timelapseFrames(int count) {
    return '$count frames';
  }

  @override
  String get studioWetMix => 'Wet mix';

  @override
  String get wetDilution => 'Dilution';

  @override
  String get wetCharge => 'Charge';

  @override
  String get wetPull => 'Pull';

  @override
  String get wetHint =>
      'Pull takes up the colour under the brush and carries it on, mixing it with the paint. Charge is how far a load of paint lasts (100% never runs out). Dilution thins the paint and lets it take up more.';

  @override
  String get colorProfile => 'Colour profile';

  @override
  String get profileSrgb => 'sRGB';

  @override
  String get profileP3 => 'Display P3';

  @override
  String get profileCmyk => 'CMYK';

  @override
  String get profileHint =>
      'The screen shows sRGB colours: Display P3 drawings look their fullest in their exports, which carry the profile. CMYK exports (PSD, TIFF) separate the colours with a plain ink model, not a press profile; their other files are sRGB. Changing it relabels the drawing, it does not convert it.';

  @override
  String get colorBlack => 'black';

  @override
  String get colorWhite => 'white';

  @override
  String get colorGrey => 'grey';

  @override
  String get colorDark => 'dark';

  @override
  String get colorLight => 'light';

  @override
  String get colorGreyish => 'greyish';

  @override
  String get colorBrown => 'brown';

  @override
  String get colorRed => 'red';

  @override
  String get colorOrange => 'orange';

  @override
  String get colorYellow => 'yellow';

  @override
  String get colorLime => 'lime';

  @override
  String get colorGreen => 'green';

  @override
  String get colorTurquoise => 'turquoise';

  @override
  String get colorBlue => 'blue';

  @override
  String get colorPurple => 'purple';

  @override
  String get colorMagenta => 'magenta';

  @override
  String get colorPink => 'pink';

  @override
  String get accessibility => 'Accessibility';

  @override
  String get largeText => 'Interface text size';

  @override
  String get colorNames => 'Say the colour\'s name when it is picked';

  @override
  String get feedbackSounds => 'Feedback sounds';

  @override
  String get singleTouch => 'Single-touch gestures';

  @override
  String get singleTouchHint =>
      'A floating pad: undo, redo, fit, and move, zoom or turn the canvas with one finger (tap a mode, drag on the canvas, tap it again to draw).';

  @override
  String get touchMove => 'Move the canvas';

  @override
  String get touchZoom => 'Zoom the canvas';

  @override
  String get touchRotate => 'Turn the canvas';

  @override
  String get fitCanvas => 'Fit the canvas';

  @override
  String get animationAssist => 'Animation Assist';

  @override
  String get addFrame => 'Add frame';

  @override
  String get frameOptions => 'Frame options';

  @override
  String get frameHold => 'Hold';

  @override
  String get frameBackground => 'Background';

  @override
  String get frameForeground => 'Foreground';

  @override
  String frameName(int number) {
    return 'Frame $number';
  }

  @override
  String get frameHint =>
      'Tap a frame to show it; tap the shown frame for its options (hold, split, clear, copy, delete). + adds a frame right after the shown one. Select several to copy, clear, reverse, time or delete them at once. The first frame can be a background under every frame, the last a foreground over them.';

  @override
  String get animationSettings => 'Animation settings';

  @override
  String get playbackLoop => 'Loop';

  @override
  String get playbackPingPong => 'Ping-Pong';

  @override
  String get playbackOneShot => 'One shot';

  @override
  String get framesPerSecond => 'Frames per second';

  @override
  String get onionFrames => 'Onion skin frames';

  @override
  String get onionOpacity => 'Onion skin opacity';

  @override
  String get blendPrimary => 'Blend primary frame';

  @override
  String get onionBehind => 'Frames before';

  @override
  String get onionAhead => 'Frames after';

  @override
  String get galleryDrawings => 'Drawings';

  @override
  String get theater => 'Movies';

  @override
  String get newMovie => 'New movie';

  @override
  String get untitledMovie => 'Untitled movie';

  @override
  String get theaterEmpty =>
      'No movies yet. A movie is a timeline of drawings, Flipbooks, media and text.';

  @override
  String get theaterFolder => 'Put in a folder';

  @override
  String get theaterDefaultFolder => 'Folder';

  @override
  String get theaterUnfolder => 'Empty the folder';

  @override
  String get theaterRemoveFromFolder => 'Take out of the folder';

  @override
  String get theaterBack => 'Back to the Theater';

  @override
  String theaterDeleteAsk(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count movies? This can\'t be undone.',
      one: 'Delete this movie? This can\'t be undone.',
    );
    return '$_temp0';
  }

  @override
  String theaterUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count movie files could not be read; they were left on disk as they are.',
      one: '1 movie file could not be read; it was left on disk as it is.',
    );
    return '$_temp0';
  }

  @override
  String get movieSettings => 'Movie settings';

  @override
  String get movieStart => 'Start with';

  @override
  String get movieStartFlipbook => 'Flipbook';

  @override
  String get movieStartBlank => 'Blank';

  @override
  String get movieAspect => 'Aspect ratio';

  @override
  String get movieAspectWide => '16:9 widescreen';

  @override
  String get movieAspectCinema => '21:9 cinema';

  @override
  String get movieAspectPortrait => '9:16 portrait';

  @override
  String get movieAspectSquare => '1:1 square';

  @override
  String get movieAspectScreen => 'This screen';

  @override
  String get movieResolution => 'Resolution';

  @override
  String get movieCustomSize => 'Custom';

  @override
  String get movieWidth => 'Width';

  @override
  String get movieHeight => 'Height';

  @override
  String get movieFps => 'Frame rate';

  @override
  String get movieFpsCustom => 'Custom fps';

  @override
  String get movieDuration => 'Length (seconds)';

  @override
  String get movieBackground => 'Stage colour';

  @override
  String get movieTransparent => 'Transparent stage';

  @override
  String get movieOffstage => 'Offstage';

  @override
  String get movieCreate => 'Create';

  @override
  String get movieTracks => 'Tracks';

  @override
  String get movieNoTracks => 'No tracks yet';

  @override
  String get movieTimelineNext =>
      'The timeline comes next: tracks, contents and the playhead.';

  @override
  String get timelineAddTrack => 'Add track';

  @override
  String get trackDrawing => 'Drawing';

  @override
  String get trackDelete => 'Delete track';

  @override
  String get timelineZoomIn => 'Zoom in on time';

  @override
  String get timelineZoomOut => 'Zoom out of time';

  @override
  String get timelinePlayFromStart => 'Play from the start';

  @override
  String get timelineHint =>
      'Tap or drag the ruler to move the playhead; fling it left to play from the start. Pinch sideways to zoom time, up and down for track height (Ctrl/⌘ + scroll zooms time). Drag the bar above to give the timeline more room. Space plays, arrows step a frame.';

  @override
  String get composeReset => 'Reset position, size and turn';

  @override
  String get fullscreenPreview => 'Fullscreen preview';

  @override
  String get composeHint =>
      'Tap something on the stage to choose it, then drag it, its corners (size), sides (stretch), the round handle (turn) or the cross (anchor). Put a second finger down, or hold Shift, to snap.';

  @override
  String get contentDraw => 'Draw in it';

  @override
  String get backToMovie => 'Back to the movie';

  @override
  String get framesSelect => 'Select frames';

  @override
  String get flipbookMini => 'Mini Flipbook (floats over the canvas)';

  @override
  String get frameClear => 'Clear';

  @override
  String get framesReverse => 'Reverse their order';

  @override
  String get framesDuration => 'How long each stays';

  @override
  String framesTicks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count frames',
      two: '2 frames (on twos)',
      one: '1 frame (on ones)',
    );
    return '$_temp0';
  }

  @override
  String get frameSplit => 'Split';

  @override
  String get flipbookDock => 'Back to the timeline';

  @override
  String get miniFlipbookHint =>
      'Drag the handle to move it: it locks to the left or right edge upright, to the top edge lying down; drop it at the bottom (or double-tap the handle) to put the timeline back. Drag along the frames to scrub through them.';

  @override
  String get timelineChoose =>
      'Select several (tap, or drag a lasso over the tracks)';

  @override
  String get timelineFreeTrim =>
      'Free Trim: trimming an end moves what follows';

  @override
  String get timelinePaste => 'Paste at the playhead';

  @override
  String get contentSplit => 'Split at the playhead';

  @override
  String get contentFill => 'Fill duration';

  @override
  String get contentDuplicateAfter => 'Duplicate right after';

  @override
  String get contentHide => 'Hide';

  @override
  String get contentShow => 'Show';

  @override
  String get contentColor => 'Colour';

  @override
  String get contentColorDefault => 'Its usual colour';

  @override
  String get contentReverse => 'Reverse their order';

  @override
  String get contentRename => 'Rename';

  @override
  String get trackVisibility => 'Show or hide on the stage';

  @override
  String get trackDuplicate => 'Duplicate track';

  @override
  String get trackUp => 'Move up';

  @override
  String get trackDown => 'Move down';

  @override
  String get trackGroup => 'Group with the track below';

  @override
  String get trackCloseGaps => 'Close the gaps';

  @override
  String get groupDefault => 'Group';

  @override
  String get groupFold => 'Fold or unfold';

  @override
  String get contentHint =>
      'Tap a content to choose it, then drag it along or to another track, or drag its ends to trim (Free Trim moves what follows). Double-tap to draw in it; hold or right-click for more.';

  @override
  String get keyframeMode =>
      'Keyframes: stage changes key the chosen content at the playhead';

  @override
  String get keyframeActions => 'Actions';

  @override
  String get keyAddMove => 'Add a Move & Scale keyframe here';

  @override
  String get keyAddStart => 'Add a keyframe at its start';

  @override
  String get keyAllEasings => 'All easings';

  @override
  String get keyReverse => 'Reverse keyframes';

  @override
  String get keyCopy => 'Copy keyframes';

  @override
  String get keyPaste => 'Paste keyframes here';

  @override
  String get keyClear => 'Clear keyframes';

  @override
  String get keyDelete => 'Delete keyframe';

  @override
  String get keyEasing => 'Easing to the next';

  @override
  String get keyExpand => 'Show each parameter';

  @override
  String get keyCollapse => 'Show them together';

  @override
  String get easingLinear => 'Linear';

  @override
  String get easingIn => 'Ease in';

  @override
  String get easingOut => 'Ease out';

  @override
  String get easingInOut => 'Ease in and out';

  @override
  String get paramX => 'X';

  @override
  String get paramY => 'Y';

  @override
  String get paramScale => 'Scale';

  @override
  String get paramRotation => 'Turn';

  @override
  String get keyframeHint =>
      'In keyframe mode, moving, sizing or turning the chosen content on the stage keys it at the playhead. Diamonds mark keyframes: tap one to go there, drag it to retime, hold or right-click for easing, delete or expand. Values hold before the first keyframe and after the last.';

  @override
  String get filterOpacity => 'Opacity';

  @override
  String get filterGaussianBlur => 'Gaussian blur';

  @override
  String get filterSharpen => 'Sharpen';

  @override
  String get filterHsb => 'Hue, saturation, brightness';

  @override
  String get filterNoise => 'Noise';

  @override
  String get filterLensBlur => 'Lens blur';

  @override
  String get filterAmount => 'Amount';

  @override
  String get filterHue => 'Hue';

  @override
  String get filterSaturation => 'Saturation';

  @override
  String get filterBrightness => 'Brightness';

  @override
  String get filterNoiseType => 'Clouds · billows · ridges';

  @override
  String get filterScale => 'Scale';

  @override
  String get filterOctaves => 'Octaves';

  @override
  String get filterTurbulence => 'Turbulence';

  @override
  String get filterOffsetX => 'Offset X';

  @override
  String get filterOffsetY => 'Offset Y';

  @override
  String get filterTravelX => 'Drift X (per second)';

  @override
  String get filterTravelY => 'Drift Y (per second)';

  @override
  String get filterRadius => 'Radius';

  @override
  String get filterContrast => 'Contrast';

  @override
  String get liveFilters => 'Live filters';

  @override
  String get addFilter => 'Add a filter';

  @override
  String get removeFilter => 'Remove the filter';

  @override
  String get filtersHint =>
      'Filters change how the content looks without touching its drawing. In keyframe mode each change keys it at the playhead; otherwise a setting stays the same all along.';

  @override
  String get composeMove => 'Move & Scale';

  @override
  String get distort => 'Distort';

  @override
  String get warp => 'Warp';

  @override
  String get warpAddColumn => 'More nodes across (starts the warp over)';

  @override
  String get warpAddRow => 'More nodes down (starts the warp over)';

  @override
  String get meshReset => 'Straighten';

  @override
  String get performMode =>
      'Perform: drag on the stage to record motion while the movie plays';

  @override
  String get motionFilter => 'Motion filter (smooths a performance)';

  @override
  String get performHint =>
      'Choose a content, then drag it (or its corner, turn handle, Distort corner, Warp node or a filter slider): the movie plays and a keyframe is written every frame. Lift to pause. Recording the same thing again writes over it; different things layer. A performance past the content\'s end makes it longer where there is room.';

  @override
  String get contentLook => 'Opacity, blend and mask';

  @override
  String get maskOver => 'Mask over the content beneath';

  @override
  String get maskNone => 'None';

  @override
  String get maskClip => 'Clip';

  @override
  String get maskAlpha => 'Alpha';

  @override
  String get maskLuma => 'Luminance';

  @override
  String get maskInvert => 'Invert the mask';

  @override
  String get passthrough => 'Passthrough (its tracks mix with what is outside)';

  @override
  String get toDrawings => 'Make into drawings';

  @override
  String get toFlipbook => 'Make into a Flipbook';

  @override
  String get cannotFlipbook =>
      'Only drawings that don\'t overlap in time can become a Flipbook.';

  @override
  String get timelineImport => 'Bring in a picture, GIF, video or sound';

  @override
  String get importFailed => 'That file could not be brought in.';

  @override
  String get separateAudio => 'Separate audio and video';

  @override
  String get trackSound => 'Sound';

  @override
  String get volume => 'Volume';

  @override
  String get trackText => 'Text';

  @override
  String get textEdit => 'Edit the text';

  @override
  String get textPlaceholder => 'Title';

  @override
  String get textWords => 'Words';

  @override
  String get textFont => 'Font';

  @override
  String get textDefaultFont => 'Default';

  @override
  String get exportMovie => 'Export the movie';

  @override
  String get exportMp4 => 'MP4 video (H.264, with sound)';

  @override
  String get exportHevc => 'HEVC video with transparency (.mov, with sound)';

  @override
  String get exportGif => 'Animated GIF';

  @override
  String get exportPngFrames => 'PNG frames (zip)';

  @override
  String get exportJpegFrames => 'JPEG frames (zip)';

  @override
  String get exportTiffFrames => 'TIFF frames (zip)';

  @override
  String get exportTgaFrames => 'TGA frames (zip)';

  @override
  String get exportBmpFrames => 'BMP frames (zip)';

  @override
  String get exportFrame => 'This frame (PNG)';

  @override
  String get exportProject => 'Project file (.artmovie)';

  @override
  String get exportPreview => 'Preview: half size';

  @override
  String get exportColors => 'Colours';

  @override
  String get exportDither => 'Dither';

  @override
  String get exportAlphaThreshold => 'Alpha threshold';

  @override
  String get exportGo => 'Export';

  @override
  String get exportWorking => 'Exporting…';

  @override
  String get importProject => 'Bring in a project file (.artmovie)';

  @override
  String get actionPlay => 'Play or stop';

  @override
  String get actionStepBack => 'One frame back';

  @override
  String get actionStepForward => 'One frame on';

  @override
  String get moviePrefs => 'Preferences';

  @override
  String get prefsUndoButtons => 'Undo and redo buttons on the stage';

  @override
  String get prefsQuickUndo => 'Held undo repeats after';

  @override
  String get prefsUndoDepth => 'Undo steps kept';

  @override
  String get prefsTwoFingerUndo => 'Two-finger tap undoes';

  @override
  String get prefsThreeFingerRedo => 'Three-finger tap redoes';

  @override
  String get prefsShortcuts => 'Keyboard shortcuts';

  @override
  String get prefsRecovery => 'Recovery points';

  @override
  String get prefsPressKeys => 'Press the keys…';

  @override
  String get prefsDefaults => 'Defaults';

  @override
  String get recoveryNone =>
      'No recovery points yet: one is kept at most every five minutes while you work.';

  @override
  String get mcpTitle => 'AI agents (MCP)';

  @override
  String get mcpLan => 'Reachable on the local network';

  @override
  String get mcpAdd => 'Add ArtBlend to Claude Code (Terminal):';

  @override
  String get mcpNewKey => 'New key';

  @override
  String get mcpHint =>
      'Lets Claude Code, Claude Desktop and other MCP clients draw, edit layers, apply adjustments and build movies in ArtBlend, live and undoable. Whoever has the key can control the app: keep it to yourself, and renew it to shut agents out.';

  @override
  String mcpError(String message) {
    return 'Could not start: $message';
  }

  @override
  String mcpWorking(String tool) {
    return 'AI at work: $tool';
  }
}
