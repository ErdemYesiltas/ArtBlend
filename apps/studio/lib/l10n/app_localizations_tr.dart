// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get gallery => 'Galeri';

  @override
  String get actions => 'İşlemler';

  @override
  String get brush => 'Fırça';

  @override
  String get eraser => 'Silgi';

  @override
  String get pan => 'Tuvali taşı';

  @override
  String get layers => 'Katmanlar';

  @override
  String get colors => 'Renkler';

  @override
  String get settings => 'Tercihler';

  @override
  String get connections => 'Yerel AI';

  @override
  String get undo => 'Geri al';

  @override
  String get redo => 'Yinele';

  @override
  String get size => 'Boyut';

  @override
  String get opacity => 'Opaklık';

  @override
  String get saved => 'Cihazda kayıtlı';

  @override
  String get unsaved => 'Kaydedilmemiş değişiklikler';

  @override
  String get saving => 'Kaydediliyor…';

  @override
  String get saveFailed => 'Kayıt başarısız · Yeniden dene';

  @override
  String get newDocument => 'Yeni çizim';

  @override
  String get openDocument => 'Çizim aç';

  @override
  String get saveDocument => 'Şimdi kaydet';

  @override
  String get exportDocument => 'Çizim dosyasını dışa aktar';

  @override
  String get exportPng => 'PNG dışa aktar';

  @override
  String get rename => 'Yeniden adlandır';

  @override
  String get name => 'Ad';

  @override
  String get cancel => 'İptal';

  @override
  String get confirm => 'Onayla';

  @override
  String get close => 'Kapat';

  @override
  String get newDocumentMessage =>
      'Yeni çizime geçmeden önce mevcut çizim kaydedilir. Ayrı bir kopyayı korumak için çizim dosyasını dışa aktar.';

  @override
  String get untitled => 'Adsız çizim';

  @override
  String get brushLibrary => 'Fırça kitaplığı';

  @override
  String get importBrush => 'Fırça ayarlarını içe aktar';

  @override
  String get importPalette => 'Palet içe aktar';

  @override
  String get brushImportHint =>
      'ArtBlend JSON ayarları · MyPaint v3 (.myb) · ABR ve PNG uçlu fırçalar sonraki geliştirme aşamasında.';

  @override
  String get paletteImportHint =>
      'HEX · GPL · RGB ASE · RGB/HSB ACO · SWATCHES v1';

  @override
  String get ink => 'Stüdyo mürekkebi';

  @override
  String get pencil => 'Eskiz kalemi';

  @override
  String get marker => 'Düz marker';

  @override
  String get coast => 'Kıyı çalışması';

  @override
  String get custom => 'İçe aktarılan';

  @override
  String get language => 'Dil';

  @override
  String get system => 'Sistem';

  @override
  String get theme => 'Görünüm';

  @override
  String get light => 'Açık';

  @override
  String get dark => 'Koyu';

  @override
  String get rightSidebar => 'Kontroller sağ kenarda';

  @override
  String get fingerDrawing => 'Parmakla çizim';

  @override
  String get themeHint =>
      'Görünüm, çizimin ve paletlerin renklerini değiştirmez.';

  @override
  String get palmHint =>
      'Kalem kullanırken parmakla çizimi kapatarak dokunma hareketlerini çizimden ayırabilirsin.';

  @override
  String get addLayer => 'Katman ekle';

  @override
  String layerName(int index) {
    return 'Katman $index';
  }

  @override
  String get deleteLayer => 'Katmanı sil';

  @override
  String get hideLayer => 'Katmanı göster / gizle';

  @override
  String get lockLayer => 'Katmanı kilitle / aç';

  @override
  String get moveUp => 'Katmanı yukarı taşı';

  @override
  String get moveDown => 'Katmanı aşağı taşı';

  @override
  String get colorHex => 'Hex renk';

  @override
  String get apply => 'Uygula';

  @override
  String get invalidHex => 'Geçerli, 6 veya 8 haneli bir hex renk gir.';

  @override
  String get zoomReset => 'Tuvali sığdır';

  @override
  String get serverUrl => 'Sunucu adresi';

  @override
  String get checking => 'Kontrol ediliyor…';

  @override
  String get startupError =>
      'Kayıtlı çizimin açılamadı. Mevcut dosyalar korundu.';

  @override
  String get retry => 'Yeniden dene';

  @override
  String importSuccess(String name) {
    return 'İçe aktarıldı: $name';
  }

  @override
  String operationFailed(String detail) {
    return 'İşlem tamamlanamadı: $detail';
  }

  @override
  String get exportSuccess => 'Dosya dışa aktarıldı';

  @override
  String get activeLayer => 'Etkin katman';

  @override
  String get prototype => 'Geliştirme sürümü · Freehand motoru';

  @override
  String get drawingAssistant => 'Çizim asistanı';

  @override
  String get model => 'Model';

  @override
  String get askAssistant =>
      'Renk, kompozisyon veya yeni bir fikir hakkında sor…';

  @override
  String get send => 'Gönder';

  @override
  String get chatPrivacy =>
      'Yalnızca girdiğin metin, seçtiğin yerel sunucuya gönderilir.';

  @override
  String get fingerprint => 'Sertifika parmak izi';

  @override
  String get pairingCode => 'Eşleştirme kodu';

  @override
  String get deviceName => 'Cihaz adı';

  @override
  String get pairDevice => 'Cihazı eşleştir';

  @override
  String get removePairing => 'Bu cihazın yetkisini kaldır';

  @override
  String get mcpTools => 'MCP araçları';

  @override
  String get noMcpServers =>
      'Bu cihaza izin verilmiş bir MCP sunucusu yok. Mac\'te LocalHub\'dan (Cihazlar) izin ver.';

  @override
  String get runTool => 'Çalıştır';

  @override
  String get generationComplete => 'Tamamlandı · Önizlemek için bir görsel seç';

  @override
  String get importImage => 'Görsel yükle';

  @override
  String get addImageLayer => 'Yeni katman olarak ekle';

  @override
  String get transformLayer => 'Katmanı dönüştür';

  @override
  String get transformHint =>
      'Sürükleyerek taşı; köşeden ölçekle veya iki parmakla ölçekleyip döndür. Uygula, tuval dışında kalan kısmı kırpar; araç değiştirmek önizlemeyi iptal eder.';

  @override
  String get transformUnavailable =>
      'Çizim içeren, görünür ve kilitsiz bir katman seç.';

  @override
  String get scale => 'Ölçek';

  @override
  String get rotation => 'Açı';

  @override
  String get resetTransform => 'Sıfırla';

  @override
  String get blendMode => 'Harmanlama modu';

  @override
  String get blendNormal => 'Normal';

  @override
  String get blendMultiply => 'Çarpma';

  @override
  String get blendScreen => 'Ekran';

  @override
  String get selection => 'Seçim';

  @override
  String get selectionHint =>
      'Bir alan çiz. Bitti, seçimi çizim için etkin tutar. Katman maskesi pikselleri silmeden gizler.';

  @override
  String get rectangleSelection => 'Dikdörtgen';

  @override
  String get freehandSelection => 'Serbest';

  @override
  String get invertSelection => 'Tersini seç';

  @override
  String get deselect => 'Seçimi kaldır';

  @override
  String get exportSelectionMask => 'Maskeyi aktar';

  @override
  String get layerMask => 'Katman maskesi';

  @override
  String get removeLayerMask => 'Katman maskesini kaldır';

  @override
  String get deleteSelected => 'Seçileni sil';

  @override
  String get selectionDone => 'Bitti';

  @override
  String get transformMaskHint =>
      'Dönüşümü uygulamak katman maskesini piksellerle birleştirir. Geri al, düzenlenebilir maskeyi geri getirir.';

  @override
  String get transformSelection => 'Seçimi dönüştür';

  @override
  String get inpaintPrompt => 'Bu alana ne çizilsin?';

  @override
  String get generationSettings => 'Üretim ayarları';

  @override
  String get negativePrompt => 'İstenmeyenler';

  @override
  String get seed => 'Seed';

  @override
  String get steps => 'Adım';

  @override
  String get denoise => 'Değişim gücü';

  @override
  String get inpaintNeedsSelection => 'Inpaint için önce tuvalde bir alan seç.';

  @override
  String get charcoal => 'Kömür';

  @override
  String get modelling => 'Modelaj';

  @override
  String get mypaintBrush => 'MyPaint';

  @override
  String galleryUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count çizim dosyası okunamadı ve listelenmedi. Diskte olduğu gibi bırakıldı.',
      one: '1 çizim dosyası okunamadı ve listelenmedi. Diskte olduğu gibi bırakıldı.',
    );
    return '$_temp0';
  }

  @override
  String get libraryUnreadable =>
      'Fırça ve palet kitaplığı okunamadı. Yerleşik fırçalar kullanılabilir; kitaplık dosyasının üzerine yazılmaz ve onarılana kadar içe aktarma kapalıdır.';

  @override
  String get scanPairingQr => 'QR kodu tara';

  @override
  String get scanPairingQrHint =>
      'Kamerayı, LocalHub\'ın Mac\'te gösterdiği QR koda tut (Cihazlar → Cihaz eşleştir).';

  @override
  String get invalidPairingQr =>
      'Bu QR kod bir LocalHub eşleştirme kodu değil. Süresi dolduysa Mac\'te yenisini oluştur.';

  @override
  String cameraUnavailable(String error) {
    return 'Kamera kullanılamıyor: $error. Adresi, parmak izini ve kodu elle de girebilirsin.';
  }

  @override
  String get eyedropper => 'Damlalık';

  @override
  String get stabilization => 'Stabilizasyon';

  @override
  String get streamLine => 'StreamLine';

  @override
  String get streamLineHint =>
      'Fırça başına. Tümsekleri ve titremeyi ütüler: çizgi kalemi hafifçe geriden izler, kalemi kaldırınca yetişir. Fırçadayken Option/Alt basılı tutarak renk seçebilirsin.';

  @override
  String get pressureAndSmoothing => 'Basınç ve yumuşatma';

  @override
  String get motionFiltering => 'Hareket filtresi';

  @override
  String get motionExpression => 'Hareket filtresi ifadesi';

  @override
  String get smoothingHint =>
      'Fırçanın StreamLine ayarının üstüne bütün fırçalara uygulanır. Stabilizasyon hareketin ortalamasını alır ve hızlı çizdikçe güçlenir; yavaş çizgiler hassas kalır. Hareket filtresi hızdan bağımsız olarak titremenin uç sapmalarını keser; ifade doğal çeşitliliğin bir kısmını geri getirir.';

  @override
  String unsupportedFile(String name) {
    return '$name bu işlem için desteklenen bir dosya değil.';
  }

  @override
  String get canvasSize => 'Tuval boyutu';

  @override
  String squareCanvas(String size) {
    return 'Kare · $size';
  }

  @override
  String screenCanvas(String size) {
    return 'Ekran · $size';
  }

  @override
  String get customCanvas => 'Özel';

  @override
  String get canvasWidth => 'Genişlik';

  @override
  String get canvasHeight => 'Yükseklik';

  @override
  String canvasSizeHint(int min, int max) {
    return 'Kenar başına $min–$max piksel. Boyut sonradan değişmez; büyük tuval daha çok bellek kullanır.';
  }

  @override
  String get localHub => 'LocalHub';

  @override
  String get hubHint =>
      'Mac\'inde LocalHub\'ı aç, Cihazlar → Cihaz eşleştir\'i seç; sonra QR kodu tara ya da gösterdiği adresi, SHA-256 parmak izini ve kodu gir.';

  @override
  String get companionRetired =>
      'Bu, artık kullanılmayan ArtBlend Companion\'ın eşleştirme kodu. Mac\'ine LocalHub\'ı kur ve onun gösterdiği kodla eşleştir.';

  @override
  String hubPaired(String name) {
    return '$name ile eşleşti';
  }

  @override
  String get refresh => 'Yenile';

  @override
  String get hubNoWorkflow =>
      'İzin var ama LocalHub\'da bunun için henüz model ya da workflow yok. Mac\'te bir tane ekle.';

  @override
  String get hubPermissionMissing =>
      'Bu cihazın buna izni yok. Mac\'te LocalHub\'dan (Cihazlar) izin ver.';

  @override
  String get editSelection => 'Seçimi yeniden boya';

  @override
  String get createImage => 'Yeni görsel';

  @override
  String get hubDefaultModel => 'Hub varsayılanı';

  @override
  String get imagePrompt => 'Görseli tarif et';

  @override
  String get generate => 'Üret';

  @override
  String get jobQueued => 'Mac\'te sırada…';

  @override
  String get jobRunning => 'Mac\'te üretiliyor…';

  @override
  String get jobCancelled => 'Durduruldu';

  @override
  String get stop => 'Durdur';

  @override
  String get clear => 'Temizle';

  @override
  String get hubFiles => 'Hub\'daki dosyalar';

  @override
  String get uploadFile => 'Görsel yükle';

  @override
  String get uploadDrawing => 'Çizimi yükle';

  @override
  String get noHubFiles =>
      'Henüz dosya yok. Yüklediklerin ve üretilen görseller burada görünür.';

  @override
  String get addToCanvas => 'Tuvale ekle';

  @override
  String get deleteFile => 'Sil';

  @override
  String get mcpServer => 'MCP sunucusu';

  @override
  String get mcpTool => 'Araç';

  @override
  String get mcpArguments => 'Argümanlar (JSON)';

  @override
  String jobsAhead(int count) {
    return '$count iş önde';
  }

  @override
  String aboutMinutes(int minutes) {
    return 'yaklaşık $minutes dk';
  }

  @override
  String get generativeFill => 'Üretken dolgu';

  @override
  String get fillPromptHint => 'Ne eklensin? Boş bırakırsan çevreye uydurur';

  @override
  String get previousVariation => 'Önceki varyasyon';

  @override
  String get nextVariation => 'Sonraki varyasyon';

  @override
  String get newVariation => 'Yeni varyasyon';

  @override
  String get discard => 'Vazgeç';

  @override
  String get done => 'Bitti';

  @override
  String get assistantTab => 'Asistan';

  @override
  String get filesTab => 'Dosyalar';

  @override
  String get hubNoImageWorkflow =>
      'LocalHub\'da bu cihazın kullanabileceği bir görsel workflow\'u henüz yok.';

  @override
  String hubIntegrationsDown(String names) {
    return 'Çalışmıyor: $names';
  }

  @override
  String get writePrompt => 'Bu anahtar kelimelerden detaylı prompt yaz';

  @override
  String get graphiteBrush => 'Grafit';

  @override
  String get pastelBrush => 'Yumuşak pastel';

  @override
  String get dryBrush => 'Kuru fırça';

  @override
  String get gouacheBrush => 'Guaj';

  @override
  String get splatterBrush => 'Sıçratma';

  @override
  String get stampBrush => 'Doku';

  @override
  String get blendDarken => 'Koyulaştır';

  @override
  String get blendColorBurn => 'Renk yanması';

  @override
  String get blendLighten => 'Açıklaştır';

  @override
  String get blendColorDodge => 'Renk soldurma';

  @override
  String get blendAdd => 'Ekle';

  @override
  String get blendOverlay => 'Bindirme';

  @override
  String get blendSoftLight => 'Yumuşak ışık';

  @override
  String get blendHardLight => 'Sert ışık';

  @override
  String get blendDifference => 'Fark';

  @override
  String get renameLayer => 'Yeniden adlandır';

  @override
  String get duplicateLayer => 'Çoğalt';

  @override
  String get mergeDown => 'Aşağı birleştir';

  @override
  String get clearLayer => 'Temizle';

  @override
  String get unlockLayer => 'Kilidi aç';

  @override
  String layerCopy(String name) {
    return '$name kopya';
  }

  @override
  String layerCount(int count, int max) {
    return '$count / $max katman';
  }

  @override
  String get layersHint =>
      'Seçili katmana dokun: seçenekler · sağa kaydır: daha fazla seç · iki katmanı sıkıştır: birleştir · basılı tutup sürükle: sırala · harf: karışım modu ve opaklık';

  @override
  String get ellipseSelection => 'Elips';

  @override
  String get selectionNew => 'Yeni';

  @override
  String get selectionAdd => 'Ekle';

  @override
  String get selectionSubtract => 'Çıkar';

  @override
  String get featherSelection => 'Yumuşak kenar';

  @override
  String featherAmount(int pixels) {
    return 'Yumuşak kenar $pixels px';
  }

  @override
  String get featherHint =>
      'Seçimin kenarını bu kadar tuval pikseli boyunca yumuşatır: fırça, maske, silme ve üretken dolgu sert bir çizgide durmak yerine yavaşça karışır.';

  @override
  String get drawingGuide => 'Çizim kılavuzu';

  @override
  String get symmetry => 'Simetri';

  @override
  String get symmetryOff => 'Kapalı';

  @override
  String get symmetryVertical => 'Dikey';

  @override
  String get symmetryHorizontal => 'Yatay';

  @override
  String get symmetryQuadrant => 'Dörtlü';

  @override
  String get symmetryRadial => 'Radyal';

  @override
  String get gridGuide => 'Izgara';

  @override
  String get turnView => 'Görünümü döndür';

  @override
  String get turnLeft => '90° sola döndür';

  @override
  String get turnRight => '90° sağa döndür';

  @override
  String get colorDisc => 'Disk';

  @override
  String get colorValues => 'Değerler';

  @override
  String get recentColors => 'Son kullanılanlar';

  @override
  String get exitFullScreen => 'Arayüzü göster';

  @override
  String get fullScreen => 'Tam ekran';

  @override
  String get swapColor => 'Önceki renk';

  @override
  String undone(String action) {
    return 'Geri alındı: $action';
  }

  @override
  String redone(String action) {
    return 'Yinelendi: $action';
  }

  @override
  String get historyPaint => 'Boyama';

  @override
  String get historyAddLayer => 'Yeni katman';

  @override
  String get historyDeleteLayer => 'Katmanı sil';

  @override
  String get historyMergeLayers => 'Katmanları birleştir';

  @override
  String get historyMoveLayer => 'Katmanı taşı';

  @override
  String get historyLayerMask => 'Katman maskesi';

  @override
  String get historyLayerSettings => 'Katman ayarı';

  @override
  String get historyRename => 'Yeniden adlandır';

  @override
  String get historyCanvas => 'Tuval';

  @override
  String get historyEdit => 'Düzenleme';

  @override
  String get cut => 'Kes';

  @override
  String get copy => 'Kopyala';

  @override
  String get copyAll => 'Tümünü kopyala';

  @override
  String get cutAndPaste => 'Kes ve yapıştır';

  @override
  String get paste => 'Yapıştır';

  @override
  String get fromSelection => 'Seçimden';

  @override
  String get pastedLayer => 'Yapıştırılan';

  @override
  String get smudge => 'Karıştır';

  @override
  String get referenceLayer => 'Referans';

  @override
  String get colorDrop => 'ColorDrop';

  @override
  String get fillThreshold => 'Eşik';

  @override
  String get fillHint =>
      'Başka alanlara dokunarak onları da doldur; eşik son dolguyu yeniler.';

  @override
  String get alphaLock => 'Alfa kilidi';

  @override
  String get clippingMask => 'Kırpma maskesi';

  @override
  String get fillLayer => 'Katmanı doldur';

  @override
  String get invertLayer => 'Ters çevir';

  @override
  String get backgroundColor => 'Arka plan rengi';

  @override
  String get adjustments => 'Ayarlamalar';

  @override
  String get adjustColor => 'Renk';

  @override
  String get adjustBlur => 'Bulanıklık';

  @override
  String get hueSaturationBrightness => 'Ton, Doygunluk, Parlaklık';

  @override
  String get gaussianBlur => 'Gauss Bulanıklığı';

  @override
  String get adjustHue => 'Ton';

  @override
  String get adjustSaturation => 'Doygunluk';

  @override
  String get adjustBrightness => 'Parlaklık';

  @override
  String get adjustAmount => 'Miktar';

  @override
  String get adjustLayer => 'Katman';

  @override
  String get adjustPencil => 'Kalem';

  @override
  String get adjustPreview => 'Önizle';

  @override
  String get adjustReset => 'Sıfırla';

  @override
  String get adjustSwipeHint =>
      'Miktarı değiştirmek için tuvalde sağa ya da sola kaydır.';

  @override
  String get adjustPencilHint =>
      'Ayarlamanın uygulanacağı yerleri boya; silgi geri alır.';

  @override
  String get adjustUnavailable => 'Katman kilitli ya da gizli.';

  @override
  String get colorBalance => 'Renk Dengesi';

  @override
  String get curves => 'Eğriler';

  @override
  String get gradientMap => 'Gradyan Haritası';

  @override
  String get toneShadows => 'Gölgeler';

  @override
  String get toneMidtones => 'Orta tonlar';

  @override
  String get toneHighlights => 'Vurgular';

  @override
  String get cyanRed => 'Camgöbeği – Kırmızı';

  @override
  String get magentaGreen => 'Macenta – Yeşil';

  @override
  String get yellowBlue => 'Sarı – Mavi';

  @override
  String get curveGamma => 'Gama';

  @override
  String get curveRed => 'Kırmızı';

  @override
  String get curveGreen => 'Yeşil';

  @override
  String get curveBlue => 'Mavi';

  @override
  String get curvesHint =>
      'Nokta eklemek ya da taşımak için sürükle; silmek için noktaya çift dokun.';

  @override
  String get gradientHint =>
      'Renk eklemek için şeride, değiştirmek için renge dokun; silmek için basılı tut.';

  @override
  String get gradientNoir => 'Noir';

  @override
  String get gradientSepia => 'Sepya';

  @override
  String get gradientSunset => 'Gün batımı';

  @override
  String get gradientOcean => 'Okyanus';

  @override
  String get gradientNeon => 'Neon';

  @override
  String get gradientGold => 'Altın';

  @override
  String get motionBlur => 'Hareket Bulanıklığı';

  @override
  String get perspectiveBlur => 'Perspektif Bulanıklığı';

  @override
  String get adjustAngle => 'Açı';

  @override
  String get perspectivePositional => 'Konumsal';

  @override
  String get perspectiveDirectional => 'Yönlü';

  @override
  String get motionHint =>
      'Tuvalde bulanıklığın yönünde kaydır; kaydırma uzadıkça bulanıklık artar.';

  @override
  String get perspectiveHint =>
      'Merkezi taşımak için diski sürükle; miktar için başka bir yerde kaydır.';

  @override
  String get transformFreeform => 'Serbest';

  @override
  String get transformUniform => 'Orantılı';

  @override
  String get transformDistort => 'Bük';

  @override
  String get transformWarp => 'Çarpıt';

  @override
  String get flipHorizontal => 'Yatay çevir';

  @override
  String get flipVertical => 'Dikey çevir';

  @override
  String get rotate45 => '45° döndür';

  @override
  String get fitToScreen => 'Ekrana sığdır';

  @override
  String get interpolation => 'İnterpolasyon';

  @override
  String get interpolationNearest => 'En yakın komşu';

  @override
  String get interpolationBilinear => 'Bilinear';

  @override
  String get interpolationBicubic => 'Bicubic';

  @override
  String get transformFreeformHint =>
      'Esnetmek için köşe ya da kenarı, taşımak için ortayı sürükle; döndürmek için iki parmakla çevir.';

  @override
  String get transformDistortHint =>
      'Perspektif için köşeyi, eğmek için kenarı, taşımak için ortayı sürükle.';

  @override
  String get transformWarpHint =>
      'Bükmek için ağın üstünde herhangi bir yeri sürükle; taşımak için dışından sürükle.';

  @override
  String get enterValue => 'Değer gir';

  @override
  String get editShape => 'Şekli düzenle';

  @override
  String get perfectShape => 'Mükemmelleştir';

  @override
  String get groupLayers => 'Grupla';

  @override
  String get ungroup => 'Grubu çöz';

  @override
  String get leaveGroup => 'Gruptan çıkar';

  @override
  String get flattenGroup => 'Grubu birleştir';

  @override
  String get deleteGroup => 'Grubu sil';

  @override
  String get renameGroup => 'Grubu yeniden adlandır';

  @override
  String get mergeChosen => 'Birleştir';

  @override
  String get deleteChosen => 'Sil';

  @override
  String groupName(int index) {
    return 'Grup $index';
  }

  @override
  String chosenLayers(int count) {
    return '$count katman seçili';
  }

  @override
  String get blendLinearBurn => 'Doğrusal Yakma';

  @override
  String get blendDarkerColor => 'Daha Koyu Renk';

  @override
  String get blendLighterColor => 'Daha Açık Renk';

  @override
  String get blendVividLight => 'Canlı Işık';

  @override
  String get blendLinearLight => 'Doğrusal Işık';

  @override
  String get blendPinLight => 'Nokta Işığı';

  @override
  String get blendHardMix => 'Sert Karışım';

  @override
  String get blendExclusion => 'Dışlama';

  @override
  String get blendSubtract => 'Çıkarma';

  @override
  String get blendDivide => 'Bölme';

  @override
  String get blendHue => 'Ton';

  @override
  String get blendSaturation => 'Doygunluk';

  @override
  String get blendColor => 'Renk';

  @override
  String get blendLuminosity => 'Parlaklık';

  @override
  String get liquify => 'Sıvılaştır';

  @override
  String get liquifyPush => 'İt';

  @override
  String get liquifyTwirlRight => 'Sağa bük';

  @override
  String get liquifyTwirlLeft => 'Sola bük';

  @override
  String get liquifyPinch => 'Sıkıştır';

  @override
  String get liquifyExpand => 'Genişlet';

  @override
  String get liquifyCrystals => 'Kristal';

  @override
  String get liquifyEdge => 'Kenar';

  @override
  String get liquifyReconstruct => 'Geri getir';

  @override
  String get liquifySize => 'Boyut';

  @override
  String get liquifyPressure => 'Basınç';

  @override
  String get liquifyDistortion => 'Bozulma';

  @override
  String get liquifyMomentum => 'Momentum';

  @override
  String get liquifyHalfBack => 'Yarısını geri getir';

  @override
  String get liquifyHint =>
      'Tuvalde sürükle; Bük, Sıkıştır, Genişlet ve Kristal sabit tutarken de çalışır.';

  @override
  String get clone => 'Klonla';

  @override
  String get cloneLock => 'Kaynağı kilitle';

  @override
  String get cloneHint =>
      'Diski kopyalanacak yere sürükle, sonra boya: disk fırçanı izler. Kilitliyken disk yerinde kalır, her vuruş onun olduğu yerden kopyalamaya başlar (✕ o an kopyalanan nokta).';

  @override
  String get adjustFilters => 'Filtreler';

  @override
  String get sharpen => 'Keskinleştir';

  @override
  String get noise => 'Gürültü';

  @override
  String get bloom => 'Işıma (Bloom)';

  @override
  String get glitch => 'Glitch';

  @override
  String get halftone => 'Yarım Ton (Halftone)';

  @override
  String get chromaticAberration => 'Renk Sapması';

  @override
  String get noiseClouds => 'Bulut';

  @override
  String get noiseBillows => 'Dalga';

  @override
  String get noiseRidges => 'Sırt';

  @override
  String get noiseScale => 'Ölçek';

  @override
  String get noiseOctaves => 'Oktav';

  @override
  String get noiseTurbulence => 'Türbülans';

  @override
  String get bloomTransition => 'Geçiş';

  @override
  String get filterSize => 'Boyut';

  @override
  String get bloomBurn => 'Yanma';

  @override
  String get glitchArtifact => 'Artifact';

  @override
  String get glitchWave => 'Dalga';

  @override
  String get glitchSignal => 'Sinyal';

  @override
  String get glitchDiverge => 'Ayrışma';

  @override
  String get glitchBlock => 'Blok boyutu';

  @override
  String get glitchZoom => 'Zoom';

  @override
  String get halftoneFullColor => 'Tam renk';

  @override
  String get halftoneScreenPrint => 'Serigrafi';

  @override
  String get halftoneNewspaper => 'Gazete';

  @override
  String get chromaticPerspective => 'Perspektif';

  @override
  String get chromaticDisplace => 'Kaydırma';

  @override
  String get chromaticFalloff => 'Düşüş';

  @override
  String get automaticSelection => 'Otomatik';

  @override
  String get selectionThreshold => 'Eşik';

  @override
  String get selectLayerContents => 'İçeriği seç';

  @override
  String get automaticSelectionHint =>
      'Bir renk alanına dokun; parmağını kaldırmadan sağa/sola kaydırarak eşiği değiştir.';

  @override
  String get freehandSelectionHint => 'Sürükleyerek sınırı çiz.';

  @override
  String get closePolygon => 'Çokgeni kapat';

  @override
  String get polygonSelection => 'Çokgen';

  @override
  String get polygonSelectionHint =>
      'Dokunarak köşe koy; bir köşeyi sürükleyerek taşı; bitirmek için ilk köşeye dokun (ya da Çokgeni kapat).';

  @override
  String get savedSelections => 'Kaydet ve yükle';

  @override
  String get saveSelection => 'Seçimi kaydet';

  @override
  String get previousSelection => 'Önceki seçim';

  @override
  String get colorFill => 'Renk dolgusu';

  @override
  String get copyPasteSelection => 'Kopyala ve yapıştır';

  @override
  String savedSelectionName(int index) {
    return 'Seçim $index';
  }

  @override
  String get snapping => 'Yaslanma';

  @override
  String get magnetics => 'Manyetik';

  @override
  String get snapSettings => 'Yaslanma ayarları';

  @override
  String get snapDistance => 'Mesafe';

  @override
  String get snapVelocity => 'Hız';

  @override
  String get cropResize => 'Kırp ve yeniden boyutlandır';

  @override
  String get cropResample => 'Yeniden örnekle (çizimi ölçekle)';

  @override
  String get rotateCanvasLeft => 'Tuvali sola döndür';

  @override
  String get rotateCanvasRight => 'Tuvali sağa döndür';

  @override
  String get flipCanvasHorizontal => 'Tuvali yatay çevir';

  @override
  String get flipCanvasVertical => 'Tuvali dikey çevir';

  @override
  String get cropHint =>
      'Kırpmak için tutamaçları sürükle; tuvalin dışına çekince büyür. Yeniden örnekle açıkken yeni boyut çizimi ölçekler.';

  @override
  String get canvasInfo => 'Tuval bilgisi';

  @override
  String get infoSize => 'Boyut';

  @override
  String get infoPrint => 'Baskı boyutu';

  @override
  String get infoLayers => 'Katmanlar';

  @override
  String get infoGroups => 'Gruplar';

  @override
  String get infoStrokes => 'Vektör çizgiler';

  @override
  String get infoSaved => 'Kayıtlı seçimler';

  @override
  String get infoMemory => 'Piksel verisi';

  @override
  String get infoEdits => 'Düzenlemeler';

  @override
  String get editGuide => 'Çizim kılavuzunu düzenle';

  @override
  String get guideNone => 'Kılavuz yok';

  @override
  String get guideGrid => '2B ızgara';

  @override
  String get guideIsometric => 'İzometrik';

  @override
  String get guidePerspective => 'Perspektif';

  @override
  String get guideRotational => 'Döndürmeli simetri';

  @override
  String get guideRemovePoint => 'Son kaçış noktasını kaldır';

  @override
  String get guideColor => 'Kılavuz rengi';

  @override
  String get guideThickness => 'Kalınlık';

  @override
  String get guideHint =>
      'Perspektif: kaçış noktası eklemek için tuvale dokun (en fazla üç), taşımak için noktaları sürükle. Eksenleri taşımak için simetri merkezini sürükle.';

  @override
  String get drawingAssist => 'Çizim yardımı';

  @override
  String get colorClassic => 'Klasik';

  @override
  String get colorHarmony => 'Uyum';

  @override
  String get harmonyComplementary => 'Tamamlayıcı';

  @override
  String get harmonySplit => 'Bölünmüş tamamlayıcı';

  @override
  String get harmonyAnalogous => 'Analog';

  @override
  String get harmonyTriadic => 'Üçlü';

  @override
  String get harmonyTetradic => 'Dörtlü';

  @override
  String get colorBrightness => 'Parlaklık';

  @override
  String get palettes => 'Paletler';

  @override
  String get newPalette => 'Yeni palet';

  @override
  String get paletteName => 'Palet';

  @override
  String get setDefaultPalette => 'Varsayılan yap';

  @override
  String get unsetDefaultPalette => 'Varsayılanı kaldır';

  @override
  String get addCurrentColor => 'Mevcut rengi ekle';

  @override
  String get replaceSwatch => 'Mevcut renkle değiştir';

  @override
  String get paletteCards => 'Kart görünümü';

  @override
  String paletteCopy(String name) {
    return '$name kopya';
  }

  @override
  String get brushStudio => 'Fırça stüdyosu';

  @override
  String get drawingPad => 'Çizim pedi: fırçayı denemek için burada çiz';

  @override
  String get studioStrokePath => 'Çizgi yolu';

  @override
  String get studioShape => 'Şekil';

  @override
  String get studioGrain => 'Doku';

  @override
  String get studioRendering => 'İşleme';

  @override
  String get studioPencil => 'Kalem';

  @override
  String get studioProperties => 'Özellikler';

  @override
  String get studioAbout => 'Hakkında';

  @override
  String get studioTaper => 'İncelme';

  @override
  String get brushSpacing => 'Aralık';

  @override
  String get brushScatter => 'Titreşim';

  @override
  String get brushRotation => 'Döndürme';

  @override
  String get brushRotationJitter => 'Döndürme titreşimi';

  @override
  String get brushFollowStroke => 'Çizgiyi takip et';

  @override
  String get brushSizeJitter => 'Boyut titreşimi';

  @override
  String get brushOpacityJitter => 'Opaklık titreşimi';

  @override
  String get brushFlow => 'Akış';

  @override
  String get brushGrainDepth => 'Derinlik';

  @override
  String get brushGrainScale => 'Ölçek';

  @override
  String get brushPressureSize => 'Basınç → boyut';

  @override
  String get brushPressureOpacity => 'Basınç → opaklık';

  @override
  String get brushDefaultSize => 'Boyut';

  @override
  String get brushName => 'Ad';

  @override
  String get brushSmoothing => 'Yumuşatma';

  @override
  String get brushThinning => 'Basınçla incelme';

  @override
  String get brushTip => 'Uç';

  @override
  String get brushNoGrain => 'Yok';

  @override
  String get brushCustomImage => 'İçe aktarılan görsel';

  @override
  String get brushEngine => 'Motor';

  @override
  String get brushMypaintNote =>
      'MyPaint fırçaları kendi ayarlarını (JSON) taşır; burada yalnızca ad ve boyut değişir.';

  @override
  String get brushReset => 'Fırçayı sıfırla';

  @override
  String get brushEdit => 'Fırça stüdyosunda düzenle';

  @override
  String get brushSearch => 'Fırça ara';

  @override
  String get recentBrushes => 'Son kullanılanlar';

  @override
  String get clearPad => 'Pedi temizle';

  @override
  String brushCopy(String name) {
    return '$name kopya';
  }

  @override
  String get pressureCurve => 'Basınç eğrisi';

  @override
  String get pressureCurveHint =>
      'Kalem basıncının çizgi kalınlığına ve opaklığa nasıl yansıyacağını eğriyi sürükleyerek ayarla. Nokta eklemek için dokun, silmek için noktaya çift dokun.';

  @override
  String get brushCursor => 'Fırça çerçevesini göster';

  @override
  String get resetCurve => 'Eğriyi sıfırla';

  @override
  String get addText => 'Metin ekle';

  @override
  String get textDefault => 'Metin';

  @override
  String get typeText => 'Metni yaz';

  @override
  String get font => 'Yazı tipi';

  @override
  String get defaultFont => 'Varsayılan';

  @override
  String get importFont => 'Yazı tipi içe aktar…';

  @override
  String get bold => 'Kalın';

  @override
  String get italic => 'İtalik';

  @override
  String get underline => 'Altı çizili';

  @override
  String get outlineText => 'Dış hat';

  @override
  String get alignment => 'Hizalama';

  @override
  String get allCaps => 'Büyük harf';

  @override
  String get verticalText => 'Dikey';

  @override
  String get textStyle => 'Metin stili';

  @override
  String get textSize => 'Boyut';

  @override
  String get fontWeight => 'Kalınlık';

  @override
  String get letterSpacing => 'Harf aralığı';

  @override
  String get lineSpacing => 'Satır aralığı';

  @override
  String get baselineShift => 'Taban çizgisi';

  @override
  String get rasterize => 'Rasterleştir';

  @override
  String get editText => 'Metni düzenle';

  @override
  String get rasterizeAsk =>
      'Bu bir metin katmanı. Üzerine çizmek için rasterleştirilsin mi?';

  @override
  String get textHint =>
      'Kutuyu sürükleyerek taşı, sağdaki tutamaçla genişlet. Renk seçmek metni boyar. Bitirmek için kutunun dışına dokun.';

  @override
  String get gallerySelect => 'Seç';

  @override
  String get galleryStack => 'Yığın yap';

  @override
  String get galleryDefaultStack => 'Yığın';

  @override
  String get galleryUnstack => 'Yığını dağıt';

  @override
  String get galleryRemoveFromStack => 'Yığından çıkar';

  @override
  String get galleryDuplicate => 'Çoğalt';

  @override
  String get galleryDelete => 'Sil';

  @override
  String get galleryPreview => 'Önizle';

  @override
  String get galleryBack => 'Galeriye dön';

  @override
  String get galleryHint =>
      'Bir çizime basılı tut ve başka bir çizimin üstüne sürükleyerek oraya taşı ya da bir yığının üstüne bırakarak içine koy. Birkaçını seçip yığın yapabilir, çoğaltabilir veya silebilirsin.';

  @override
  String gallerySelected(int count) {
    return '$count seçili';
  }

  @override
  String galleryDeleteAsk(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count çizim silinsin mi? Geri alınamaz.',
      one: 'Bu çizim silinsin mi? Geri alınamaz.',
    );
    return '$_temp0';
  }

  @override
  String get presetScreen => 'Ekran boyutu';

  @override
  String get presetSquare => 'Kare';

  @override
  String get preset4k => '4K';

  @override
  String get presetA4 => 'A4';

  @override
  String get presetPhoto => '4 × 6 fotoğraf';

  @override
  String get presetLetter => 'US Letter';

  @override
  String get canvasUnit => 'Birim';

  @override
  String get canvasDpi => 'DPI';

  @override
  String get swapSides => 'En ve boyu değiştir';

  @override
  String get savePreset => 'Ön ayar olarak kaydet';

  @override
  String get updatePreset => 'Ön ayarı güncelle';

  @override
  String get presetName => 'Ön ayar adı';

  @override
  String get editPreset => 'Düzenle';

  @override
  String get deletePreset => 'Sil';

  @override
  String get myPresets => 'Ön ayarlarım';

  @override
  String canvasTooLarge(int width, int height, int min, int max) {
    return 'Çok büyük: $width × $height px. Bir kenar $min–$max px olabilir; boyutu ya da DPI\'ı düşür.';
  }

  @override
  String canvasPixels(int width, int height) {
    return '$width × $height px';
  }

  @override
  String get exportImage => 'Görüntü dışa aktar…';

  @override
  String get exportFormatPsd => 'PSD · katmanlar, gruplar, karışım modları';

  @override
  String get exportFormatPng => 'PNG · saydamlık';

  @override
  String get exportFormatJpeg => 'JPEG · en küçük';

  @override
  String get exportFormatTiff => 'TIFF · saydamlık';

  @override
  String get exportFormatPdf => 'PDF · çizimin DPI\'ında baskı boyutu';

  @override
  String get exportLayersPng => 'Katmanlar: PNG dosyaları (ZIP)';

  @override
  String get exportLayersPdf => 'Katmanlar: PDF sayfaları';

  @override
  String get exportLayer => 'Katmanı PNG olarak dışa aktar';

  @override
  String importScaled(int max) {
    return 'Dosya bir kenarda $max pikselden büyüktü; sığması için küçültüldü.';
  }

  @override
  String get importPartial =>
      'Procreate katmanları henüz okunamıyor: önizlemesi tek katman olarak geldi.';

  @override
  String importTooManyLayers(int max) {
    return 'Yalnızca en üstteki $max katman alındı.';
  }

  @override
  String get quickMenu => 'QuickMenu';

  @override
  String get quickMenuTrigger => 'QuickMenu\'yü açan';

  @override
  String get quickMenuTriggerNone => 'Yalnızca sağ tık';

  @override
  String get quickMenuTriggerHold => 'Basılı tutma';

  @override
  String get quickMenuTriggerFour => 'Dört parmakla dokunma';

  @override
  String get quickMenuHint =>
      'Bir düğmeye dokun ya da parmağını kaldırmadan bir düğmeye kaydır. Bir düğmenin işini değiştirmek için ona basılı tut; ortaya dokunmak profili değiştirir, basılı tutmak profilleri yönetir.';

  @override
  String get quickMenuAssign => 'Düğme eylemi';

  @override
  String get quickMenuProfiles => 'QuickMenu profilleri';

  @override
  String get quickMenuNewProfile => 'Yeni profil';

  @override
  String quickMenuProfileName(int number) {
    return 'Profil $number';
  }

  @override
  String get moveSidebar => 'Kenar çubuğunu taşımak için sürükle';

  @override
  String get gestureControls => 'Jest denetimleri';

  @override
  String get fingerTool => 'Parmak şununla boyar';

  @override
  String get fingerToolSame => 'Seçili araç';

  @override
  String get fingerToolSmudge => 'Karıştır';

  @override
  String get fingerToolEraser => 'Silgi';

  @override
  String get eyedropperHold => 'Basılı tutma renk alır';

  @override
  String get quickShapeDelay => 'QuickShape bekleme';

  @override
  String get quickShapeOff => 'kapalı';

  @override
  String get undoDelay => 'İki parmakla geri alma tekrarı';

  @override
  String get touchGestures =>
      'Çok parmaklı dokunuşlar (geri al, yinele, tam ekran…)';

  @override
  String get selectionMaskVisibility => 'Seçim maskesi';

  @override
  String get autoHideInterface => 'Çizerken çubukları soldur';

  @override
  String get gestureHint =>
      'Basılı tutma ya damlalığı ya da QuickMenu\'yü açar: birini açmak diğerini dört parmağa taşır.';

  @override
  String get exportProcreateBrush => 'Procreate fırçası olarak dışa aktar';

  @override
  String get exportBrushset => 'Damga fırçalarını .brushset olarak dışa aktar';

  @override
  String get brushImportFormats =>
      'Ayrıca: Procreate .brush ve .brushset, Photoshop .abr (örneklenmiş uçlar).';

  @override
  String get selectAll => 'Tümünü seç';

  @override
  String brushDeleteAsk(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fırça silinsin mi? Geri alınamaz.',
      one: 'Bu fırça silinsin mi? Geri alınamaz.',
    );
    return '$_temp0';
  }

  @override
  String get studioDual => 'Çift fırça';

  @override
  String get dualBrush => 'İkinci bir uçla birleştir';

  @override
  String get dualTip => 'İkinci uç';

  @override
  String get dualBlend => 'Birleşme modu';

  @override
  String get dualSize => 'Boyut';

  @override
  String get dualHint =>
      'İkinci uç aynı çizgi boyunca basılır ve ilkiyle birleşir: Çarp yalnızca ikisinin de boyadığı yeri boyar (çizginin içinde doku), Ekran ya da Ekle ikisinden birinin boyadığı yeri, Çıkar ikinciyi oyar.';

  @override
  String get recolor => 'Yeniden renklendir';

  @override
  String get recolorFlood => 'Bitişik';

  @override
  String get recolorGlobal => 'Tümü';

  @override
  String get recolorColor => 'Yeni renk';

  @override
  String get recolorThreshold => 'Eşik';

  @override
  String get recolorHint =>
      'Artı işaretini bir rengin üstüne sürükle: o renk ve ona yakın renkler, gölgelerini koruyarak yeni rengi alır. Bitişik yalnızca bağlı alanı, Tümü her eşleşmeyi değiştirir; eşiği değiştirmek için yana kaydır.';

  @override
  String get reference => 'Referans';

  @override
  String get referenceCanvas => 'Tuvali göster';

  @override
  String get referenceImage => 'Görsel göster…';

  @override
  String get paletteFromImage => 'Görselden palet';

  @override
  String get paletteFromFile => 'Dosyadan…';

  @override
  String get paletteFromCanvas => 'Tuvalden';

  @override
  String get paletteColors => 'Renk sayısı';

  @override
  String get paletteCreate => 'Oluştur';

  @override
  String exportPalette(String format) {
    return '.$format olarak dışa aktar';
  }

  @override
  String get pageAssist => 'Sayfa Yardımı';

  @override
  String get pagePrevious => 'Önceki sayfa';

  @override
  String get pageNext => 'Sonraki sayfa';

  @override
  String get exportPagesPdf => 'Sayfalar: PDF (Sayfa Yardımı)';

  @override
  String get exportFormatGif => 'Hareketli GIF · 256 renk, her yerde oynar';

  @override
  String get exportFormatApng => 'Hareketli PNG · tam renk, saydamlık';

  @override
  String get exportFormatMp4 => 'MP4 · video';

  @override
  String get exportFormatHevc => 'HEVC · saydam video';

  @override
  String get exportAnimationSize => 'Animasyon boyutu';

  @override
  String exportSizeFull(int pixels) {
    return 'En yüksek çözünürlük ($pixels piksele kadar)';
  }

  @override
  String get exportSizeWeb => 'Web için (800 piksel, küçük dosya)';

  @override
  String get privateLayer => 'Özel';

  @override
  String get privateHint => 'Özel katmanlar time-lapse kaydına girmez.';

  @override
  String get insertPrivatePhoto => 'Özel fotoğraf ekle';

  @override
  String get pastePrivately => 'Özel yapıştır';

  @override
  String get videoSection => 'Video';

  @override
  String get timelapseRecording => 'Time-lapse kaydı';

  @override
  String get timelapseReplay => 'Time-lapse oynat';

  @override
  String get timelapseExport => 'Time-lapse dışa aktar';

  @override
  String get timelapseFull => 'Tam uzunluk';

  @override
  String get timelapse30 => '30 saniye';

  @override
  String get timelapseClear => 'Time-lapse\'i sil';

  @override
  String get timelapseClearAsk =>
      'Bu çizimin time-lapse kaydı silinsin mi? Bir sonraki değişiklikten itibaren yeniden kaydedilir.';

  @override
  String get timelapseEmpty => 'Henüz bir şey kaydedilmedi: bir şeyler çiz.';

  @override
  String get timelapsePlay => 'Oynat';

  @override
  String get timelapsePause => 'Duraklat';

  @override
  String get timelapseUnsupported =>
      'Bu cihazda video dışa aktarma kullanılamıyor.';

  @override
  String timelapseFrames(int count) {
    return '$count kare';
  }

  @override
  String get studioWetMix => 'Islak karışım';

  @override
  String get wetDilution => 'Seyreltme';

  @override
  String get wetCharge => 'Yük';

  @override
  String get wetPull => 'Çekme';

  @override
  String get wetHint =>
      'Çekme fırçanın altındaki rengi alıp boyayla karıştırarak taşır. Yük bir fırça dolusu boyanın ne kadar gideceğidir (%100 hiç bitmez). Seyreltme boyayı inceltir ve daha çok renk almasını sağlar.';

  @override
  String get colorProfile => 'Renk profili';

  @override
  String get profileSrgb => 'sRGB';

  @override
  String get profileP3 => 'Display P3';

  @override
  String get profileCmyk => 'CMYK';

  @override
  String get profileHint =>
      'Ekran sRGB renk gösterir: Display P3 çizimler en doygun hâlini, profili taşıyan dışa aktarmalarında gösterir. CMYK dışa aktarmalar (PSD, TIFF) renkleri basit bir mürekkep modeliyle ayırır, bir baskı profiliyle değil; diğer dosyaları sRGB\'dir. Değiştirmek çizimi dönüştürmez, yalnızca etiketini değiştirir.';

  @override
  String get colorBlack => 'siyah';

  @override
  String get colorWhite => 'beyaz';

  @override
  String get colorGrey => 'gri';

  @override
  String get colorDark => 'koyu';

  @override
  String get colorLight => 'açık';

  @override
  String get colorGreyish => 'grimsi';

  @override
  String get colorBrown => 'kahverengi';

  @override
  String get colorRed => 'kırmızı';

  @override
  String get colorOrange => 'turuncu';

  @override
  String get colorYellow => 'sarı';

  @override
  String get colorLime => 'limon yeşili';

  @override
  String get colorGreen => 'yeşil';

  @override
  String get colorTurquoise => 'turkuaz';

  @override
  String get colorBlue => 'mavi';

  @override
  String get colorPurple => 'mor';

  @override
  String get colorMagenta => 'eflatun';

  @override
  String get colorPink => 'pembe';

  @override
  String get accessibility => 'Erişilebilirlik';

  @override
  String get largeText => 'Arayüz metin boyutu';

  @override
  String get colorNames => 'Seçilen rengin adını söyle';

  @override
  String get feedbackSounds => 'Geri bildirim sesleri';

  @override
  String get singleTouch => 'Tek dokunuşla jestler';

  @override
  String get singleTouchHint =>
      'Yüzen bir panel: geri al, yinele, sığdır; tuvali tek parmakla taşı, yakınlaştır ya da döndür (bir moda dokun, tuvalde sürükle, çizmek için tekrar dokun).';

  @override
  String get touchMove => 'Tuvali taşı';

  @override
  String get touchZoom => 'Tuvali yakınlaştır';

  @override
  String get touchRotate => 'Tuvali döndür';

  @override
  String get fitCanvas => 'Tuvali sığdır';

  @override
  String get animationAssist => 'Animasyon Yardımı';

  @override
  String get addFrame => 'Kare ekle';

  @override
  String get frameOptions => 'Kare seçenekleri';

  @override
  String get frameHold => 'Bekletme';

  @override
  String get frameBackground => 'Arka plan';

  @override
  String get frameForeground => 'Ön plan';

  @override
  String frameName(int number) {
    return 'Kare $number';
  }

  @override
  String get frameHint =>
      'Göstermek için kareye dokun; gösterilen kareye dokununca seçenekleri açılır (bekletme, böl, temizle, çoğalt, sil). + gösterilen karenin hemen arkasına kare ekler. Birkaçını seçip birlikte çoğaltabilir, temizleyebilir, sırasını çevirebilir, süre verebilir ya da silebilirsin. İlk kare her karenin altında arka plan, son kare üstünde ön plan olabilir.';

  @override
  String get animationSettings => 'Animasyon ayarları';

  @override
  String get playbackLoop => 'Döngü';

  @override
  String get playbackPingPong => 'Ping Pong';

  @override
  String get playbackOneShot => 'Tek sefer';

  @override
  String get framesPerSecond => 'Saniyedeki kare';

  @override
  String get onionFrames => 'Soğan kabuğu kareleri';

  @override
  String get onionOpacity => 'Soğan kabuğu opaklığı';

  @override
  String get blendPrimary => 'Birincil kareyi karıştır';

  @override
  String get onionBehind => 'Önceki kareler';

  @override
  String get onionAhead => 'Sonraki kareler';

  @override
  String get galleryDrawings => 'Çizimler';

  @override
  String get theater => 'Filmler';

  @override
  String get newMovie => 'Yeni film';

  @override
  String get untitledMovie => 'Adsız film';

  @override
  String get theaterEmpty =>
      'Henüz film yok. Film; çizimlerin, Flipbook\'ların, medyanın ve metnin zaman çizelgesidir.';

  @override
  String get theaterFolder => 'Klasöre koy';

  @override
  String get theaterDefaultFolder => 'Klasör';

  @override
  String get theaterUnfolder => 'Klasörü boşalt';

  @override
  String get theaterRemoveFromFolder => 'Klasörden çıkar';

  @override
  String get theaterBack => 'Tiyatroya dön';

  @override
  String theaterDeleteAsk(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count film silinsin mi? Geri alınamaz.',
      one: 'Bu film silinsin mi? Geri alınamaz.',
    );
    return '$_temp0';
  }

  @override
  String theaterUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count film dosyası okunamadı; diskte olduğu gibi bırakıldı.',
      one: '1 film dosyası okunamadı; diskte olduğu gibi bırakıldı.',
    );
    return '$_temp0';
  }

  @override
  String get movieSettings => 'Film ayarları';

  @override
  String get movieStart => 'Başlangıç';

  @override
  String get movieStartFlipbook => 'Flipbook';

  @override
  String get movieStartBlank => 'Boş';

  @override
  String get movieAspect => 'En-boy oranı';

  @override
  String get movieAspectWide => '16:9 geniş';

  @override
  String get movieAspectCinema => '21:9 sinema';

  @override
  String get movieAspectPortrait => '9:16 dikey';

  @override
  String get movieAspectSquare => '1:1 kare';

  @override
  String get movieAspectScreen => 'Bu ekran';

  @override
  String get movieResolution => 'Çözünürlük';

  @override
  String get movieCustomSize => 'Özel';

  @override
  String get movieWidth => 'Genişlik';

  @override
  String get movieHeight => 'Yükseklik';

  @override
  String get movieFps => 'Kare hızı';

  @override
  String get movieFpsCustom => 'Özel fps';

  @override
  String get movieDuration => 'Süre (saniye)';

  @override
  String get movieBackground => 'Sahne rengi';

  @override
  String get movieTransparent => 'Saydam sahne';

  @override
  String get movieOffstage => 'Sahne dışı';

  @override
  String get movieCreate => 'Oluştur';

  @override
  String get movieTracks => 'İzler';

  @override
  String get movieNoTracks => 'Henüz iz yok';

  @override
  String get movieTimelineNext =>
      'Sırada zaman çizelgesi var: izler, içerikler ve oynatma kafası.';

  @override
  String get timelineAddTrack => 'İz ekle';

  @override
  String get trackDrawing => 'Çizim';

  @override
  String get trackDelete => 'İzi sil';

  @override
  String get timelineZoomIn => 'Zamanı yakınlaştır';

  @override
  String get timelineZoomOut => 'Zamanı uzaklaştır';

  @override
  String get timelinePlayFromStart => 'Baştan oynat';

  @override
  String get timelineHint =>
      'Oynatma kafasını taşımak için cetvele dokun ya da sürükle; sola fırlatırsan baştan oynar. Yana doğru kıstırınca zaman, yukarı-aşağı kıstırınca iz yüksekliği yakınlaşır (Ctrl/⌘ + kaydırma da zamanı yakınlaştırır). Zaman çizelgesine yer açmak için üstteki çubuğu sürükle. Boşluk oynatır, oklar bir kare ilerletir.';

  @override
  String get composeReset => 'Konum, boyut ve dönüşü sıfırla';

  @override
  String get fullscreenPreview => 'Tam ekran önizleme';

  @override
  String get composeHint =>
      'Sahnede bir şeye dokunup seç; sonra kendisini, köşelerini (boyut), kenarlarını (esnet), yuvarlak tutamacı (döndür) ya da artıyı (çapa) sürükle. İkinci bir parmak koyarsan ya da Shift\'e basılı tutarsan yapışır.';

  @override
  String get contentDraw => 'İçinde çiz';

  @override
  String get backToMovie => 'Filme dön';

  @override
  String get framesSelect => 'Kare seç';

  @override
  String get flipbookMini => 'Mini Flipbook (tuvalin üstünde yüzer)';

  @override
  String get frameClear => 'Temizle';

  @override
  String get framesReverse => 'Sırasını çevir';

  @override
  String get framesDuration => 'Her biri ne kadar kalsın';

  @override
  String framesTicks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kare',
      two: '2 kare (ikişerli)',
      one: '1 kare (birerli)',
    );
    return '$_temp0';
  }

  @override
  String get frameSplit => 'Böl';

  @override
  String get flipbookDock => 'Zaman çizelgesine dön';

  @override
  String get miniFlipbookHint =>
      'Taşımak için tutamacı sürükle: sol ya da sağ kenarda dik, üst kenarda yatay kilitlenir; alta bırakırsan (ya da tutamaca çift dokunursan) zaman çizelgesi geri gelir. Kareler arasında gezinmek için karelerin üzerinde sürükle.';

  @override
  String get timelineChoose =>
      'Birkaçını seç (dokun ya da izlerin üstünde kement sürükle)';

  @override
  String get timelineFreeTrim =>
      'Serbest kırpma: ucu kırpınca arkasındakiler de kayar';

  @override
  String get timelinePaste => 'Oynatma kafasına yapıştır';

  @override
  String get contentSplit => 'Oynatma kafasında böl';

  @override
  String get contentFill => 'Süreyi doldur';

  @override
  String get contentDuplicateAfter => 'Hemen arkasına çoğalt';

  @override
  String get contentHide => 'Gizle';

  @override
  String get contentShow => 'Göster';

  @override
  String get contentColor => 'Renk';

  @override
  String get contentColorDefault => 'Olağan rengi';

  @override
  String get contentReverse => 'Sırasını çevir';

  @override
  String get contentRename => 'Yeniden adlandır';

  @override
  String get trackVisibility => 'Sahnede göster ya da gizle';

  @override
  String get trackDuplicate => 'İzi çoğalt';

  @override
  String get trackUp => 'Yukarı taşı';

  @override
  String get trackDown => 'Aşağı taşı';

  @override
  String get trackGroup => 'Alttaki izle grupla';

  @override
  String get trackCloseGaps => 'Boşlukları kapat';

  @override
  String get groupDefault => 'Grup';

  @override
  String get groupFold => 'Katla ya da aç';

  @override
  String get contentHint =>
      'Bir içeriğe dokunup seç; sonra boyunca ya da başka bir ize sürükle, uçlarından sürükleyerek kırp (Serbest kırpma arkasındakileri de kaydırır). İçinde çizmek için çift dokun; daha fazlası için basılı tut ya da sağ tıkla.';

  @override
  String get keyframeMode =>
      'Anahtar kareler: sahnedeki değişiklik, seçili içeriği oynatma kafasında anahtarlar';

  @override
  String get keyframeActions => 'Eylemler';

  @override
  String get keyAddMove => 'Buraya Taşı ve Ölçekle anahtar karesi ekle';

  @override
  String get keyAddStart => 'Başına anahtar kare ekle';

  @override
  String get keyAllEasings => 'Tüm yumuşatmalar';

  @override
  String get keyReverse => 'Anahtar kareleri ters çevir';

  @override
  String get keyCopy => 'Anahtar kareleri kopyala';

  @override
  String get keyPaste => 'Anahtar kareleri buraya yapıştır';

  @override
  String get keyClear => 'Anahtar kareleri temizle';

  @override
  String get keyDelete => 'Anahtar kareyi sil';

  @override
  String get keyEasing => 'Sonrakine yumuşatma';

  @override
  String get keyExpand => 'Her parametreyi ayrı göster';

  @override
  String get keyCollapse => 'Birlikte göster';

  @override
  String get easingLinear => 'Doğrusal';

  @override
  String get easingIn => 'Yavaş başla';

  @override
  String get easingOut => 'Yavaş bitir';

  @override
  String get easingInOut => 'Yavaş başla, yavaş bitir';

  @override
  String get paramX => 'X';

  @override
  String get paramY => 'Y';

  @override
  String get paramScale => 'Ölçek';

  @override
  String get paramRotation => 'Dönüş';

  @override
  String get keyframeHint =>
      'Anahtar kare modunda, seçili içeriği sahnede taşımak, boyutlamak ya da döndürmek onu oynatma kafasında anahtarlar. Elmaslar anahtar kareleri gösterir: dokununca oraya gidersin, sürükleyince zamanı değişir, basılı tut ya da sağ tıkla: yumuşatma, sil, genişlet. İlk anahtar kareden önce ve sondan sonra değer sabit kalır.';

  @override
  String get filterOpacity => 'Opaklık';

  @override
  String get filterGaussianBlur => 'Gauss bulanıklığı';

  @override
  String get filterSharpen => 'Keskinleştir';

  @override
  String get filterHsb => 'Ton, doygunluk, parlaklık';

  @override
  String get filterNoise => 'Gürültü';

  @override
  String get filterLensBlur => 'Lens bulanıklığı';

  @override
  String get filterAmount => 'Miktar';

  @override
  String get filterHue => 'Ton';

  @override
  String get filterSaturation => 'Doygunluk';

  @override
  String get filterBrightness => 'Parlaklık';

  @override
  String get filterNoiseType => 'Bulut · kabarık · sırt';

  @override
  String get filterScale => 'Ölçek';

  @override
  String get filterOctaves => 'Oktav';

  @override
  String get filterTurbulence => 'Türbülans';

  @override
  String get filterOffsetX => 'Ofset X';

  @override
  String get filterOffsetY => 'Ofset Y';

  @override
  String get filterTravelX => 'Kayma X (saniyede)';

  @override
  String get filterTravelY => 'Kayma Y (saniyede)';

  @override
  String get filterRadius => 'Yarıçap';

  @override
  String get filterContrast => 'Kontrast';

  @override
  String get liveFilters => 'Canlı filtreler';

  @override
  String get addFilter => 'Filtre ekle';

  @override
  String get removeFilter => 'Filtreyi kaldır';

  @override
  String get filtersHint =>
      'Filtreler içeriğin görünüşünü çizimine dokunmadan değiştirir. Anahtar kare modunda her değişiklik oynatma kafasında anahtarlanır; değilse ayar baştan sona aynı kalır.';

  @override
  String get composeMove => 'Taşı ve Ölçekle';

  @override
  String get distort => 'Bozulma';

  @override
  String get warp => 'Bük';

  @override
  String get warpAddColumn =>
      'Yatayda daha çok düğüm (bükmeyi baştan başlatır)';

  @override
  String get warpAddRow => 'Dikeyde daha çok düğüm (bükmeyi baştan başlatır)';

  @override
  String get meshReset => 'Düzelt';

  @override
  String get performMode =>
      'Perform: film oynarken sahnede sürükleyerek hareket kaydet';

  @override
  String get motionFilter => 'Hareket filtresi (kaydı yumuşatır)';

  @override
  String get performHint =>
      'Bir içerik seç, sonra onu (ya da köşesini, dönüş tutamacını, Bozulma köşesini, Bük düğümünü ya da bir filtre kaydırıcısını) sürükle: film oynar ve her kareye bir anahtar kare yazılır. Kaldırınca duraklar. Aynı şeyi yeniden kaydetmek üstüne yazar; farklı şeyler üst üste biner. İçeriğin sonunu geçen kayıt, yer varsa onu uzatır.';

  @override
  String get contentLook => 'Opaklık, karışım ve maske';

  @override
  String get maskOver => 'Alttaki içeriğe maske';

  @override
  String get maskNone => 'Yok';

  @override
  String get maskClip => 'Kırp';

  @override
  String get maskAlpha => 'Alfa';

  @override
  String get maskLuma => 'Parlaklık';

  @override
  String get maskInvert => 'Maskeyi ters çevir';

  @override
  String get passthrough => 'Geçirgen (izleri dışarıdakilerle karışır)';

  @override
  String get toDrawings => 'Çizimlere dönüştür';

  @override
  String get toFlipbook => 'Flipbook\'a dönüştür';

  @override
  String get cannotFlipbook =>
      'Yalnızca zamanda çakışmayan çizimler Flipbook olabilir.';

  @override
  String get timelineImport => 'Görsel, GIF, video ya da ses içe aktar';

  @override
  String get importFailed => 'Bu dosya içe aktarılamadı.';

  @override
  String get separateAudio => 'Sesi ve görüntüyü ayır';

  @override
  String get trackSound => 'Ses';

  @override
  String get volume => 'Ses düzeyi';

  @override
  String get trackText => 'Metin';

  @override
  String get textEdit => 'Metni düzenle';

  @override
  String get textPlaceholder => 'Başlık';

  @override
  String get textWords => 'Yazı';

  @override
  String get textFont => 'Yazı tipi';

  @override
  String get textDefaultFont => 'Varsayılan';

  @override
  String get exportMovie => 'Filmi dışa aktar';

  @override
  String get exportMp4 => 'MP4 video (H.264, sesli)';

  @override
  String get exportHevc => 'Saydam HEVC video (.mov, sesli)';

  @override
  String get exportGif => 'Hareketli GIF';

  @override
  String get exportPngFrames => 'PNG kareler (zip)';

  @override
  String get exportJpegFrames => 'JPEG kareler (zip)';

  @override
  String get exportTiffFrames => 'TIFF kareler (zip)';

  @override
  String get exportTgaFrames => 'TGA kareler (zip)';

  @override
  String get exportBmpFrames => 'BMP kareler (zip)';

  @override
  String get exportFrame => 'Bu kare (PNG)';

  @override
  String get exportProject => 'Proje dosyası (.artmovie)';

  @override
  String get exportPreview => 'Önizleme: yarı boyut';

  @override
  String get exportColors => 'Renk sayısı';

  @override
  String get exportDither => 'Titreşim (dithering)';

  @override
  String get exportAlphaThreshold => 'Alfa eşiği';

  @override
  String get exportGo => 'Dışa aktar';

  @override
  String get exportWorking => 'Dışa aktarılıyor…';

  @override
  String get importProject => 'Proje dosyası içe aktar (.artmovie)';

  @override
  String get actionPlay => 'Oynat ya da durdur';

  @override
  String get actionStepBack => 'Bir kare geri';

  @override
  String get actionStepForward => 'Bir kare ileri';

  @override
  String get moviePrefs => 'Tercihler';

  @override
  String get prefsUndoButtons => 'Sahnede geri al ve yinele düğmeleri';

  @override
  String get prefsQuickUndo => 'Basılı geri al şu süreden sonra tekrarlar';

  @override
  String get prefsUndoDepth => 'Tutulan geri alma adımı';

  @override
  String get prefsTwoFingerUndo => 'İki parmakla dokunmak geri alır';

  @override
  String get prefsThreeFingerRedo => 'Üç parmakla dokunmak yineler';

  @override
  String get prefsShortcuts => 'Klavye kısayolları';

  @override
  String get prefsRecovery => 'Kurtarma noktaları';

  @override
  String get prefsPressKeys => 'Tuşlara bas…';

  @override
  String get prefsDefaults => 'Varsayılanlar';

  @override
  String get recoveryNone =>
      'Henüz kurtarma noktası yok: çalışırken en fazla beş dakikada bir saklanır.';

  @override
  String get mcpTitle => 'AI ajanları (MCP)';

  @override
  String get mcpLan => 'Yerel ağdan erişilebilir';

  @override
  String get mcpAdd => 'ArtBlend\'i Claude Code\'a ekle (Terminal):';

  @override
  String get mcpNewKey => 'Yeni anahtar';

  @override
  String get mcpHint =>
      'Claude Code, Claude Desktop ve diğer MCP istemcileri ArtBlend\'de çizebilir, katmanları düzenleyebilir, ayar uygulayabilir ve film kurabilir; canlı ve geri alınabilir. Anahtarı bilen uygulamayı yönetebilir: kimseyle paylaşma, ajanları dışarıda bırakmak için yenile.';

  @override
  String mcpError(String message) {
    return 'Başlatılamadı: $message';
  }

  @override
  String mcpWorking(String tool) {
    return 'AI çalışıyor: $tool';
  }
}
