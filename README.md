# ArtBlend

macOS, iPadOS ve Android tabletler için yerel AI destekli çizim uygulaması geliştirme projesi.

**Durum:** Geliştirme başladı. Çalışan Flutter çizim temeli mevcut; tamamlanan ve bekleyen işler [geliştirme durumunda](docs/06-GELISTIRME-DURUMU.md).
**Güncelleme:** 17 Kasım 2026.
**Ürün adı:** ArtBlend. `ProCreate` mevcut çalışma klasörünün adıdır.

Ürün; Procreate'in akıcı çizim yaklaşımını, Sketchbook'un eskiz yardımcılarını ve Adobe Fresco'nun raster/vektör ile doğal boya yaklaşımını özgün bir deneyimde birleştirir. LM Studio, ComfyUI ve yerel MCP desteği üretim sürecinin parçasıdır. Çizim ve dosyalar kullanıcı cihazında kalır; AI bağlantısı isteğe bağlıdır.

## Proje belgeleri

- [Ürün kapsamı ve kullanıcı deneyimi](docs/01-URUN-PLANI.md)
- [Teknik mimari ve entegrasyon sözleşmeleri](docs/02-TEKNIK-MIMARI.md)
- [Aşamalar, iş paketleri ve kabul kriterleri](docs/03-YOL-HARITASI.md)
- [Kaynaklar, varsayımlar ve kararlar](docs/04-KAYNAKLAR-VE-KARARLAR.md)
- [Hazır kütüphaneler, dil/tema ve fırça/palet uyumluluğu](docs/05-KUTUPHANELER-VE-KISISELLESTIRME.md)
- [Çalıştırma, doğrulama ve güncel geliştirme durumu](docs/06-GELISTIRME-DURUMU.md)
- [Başka AI modeline devir: mevcut kod, kalan işler ve başlangıç talimatı](docs/07-AI-DEVIR-DOKUMANI.md)

## Çalıştırma

```sh
./scripts/flutterw pub get
./scripts/flutterw run -d macos
```

Kaynak kod `apps/studio` altında. Diğer platform/derleme komutları ve gerçek uygulama sınırları geliştirme durumu belgesindedir.

## Başlangıç kararı

Hazır kütüphaneleri önceleyen Flutter/Dart uygulaması, FFI arkasında hazır çizim motoru adayı libmypaint ve Mac üzerinde çalışan Companion servis önerilir. Procreate araç yerleşimi üç platformda esas alınır. iPad ve Android tablet bağımsız çizim/asset içe aktarma yapar; yerel AI ve stdio MCP araçlarına Mac üzerinden erişir. Çizim motorunu sıfırdan yazmak başlangıç tercihi değildir.

Çoklu dil, açık/koyu/sistem teması ve dışarıdan fırça/palet yükleme ilk sürüm gereksinimleridir. [Hazır bileşenler ve uyumluluk planı](docs/05-KUTUPHANELER-VE-KISISELLESTIRME.md), önceki özel motor önerisini günceller.

İlk teknik iş: üç platformda aynı fırça çekirdeğiyle çizim, kaydet/aç ve tablet–Mac eşleştirme prototipi. Teknik eşikler geçildikten sonra ürün kapsamı büyütülür.
