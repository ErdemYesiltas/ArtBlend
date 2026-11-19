import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:localhub_client/localhub_client.dart';

import '../l10n/app_localizations.dart';

/// Full-screen camera that returns the first valid LocalHub invite. Codes
/// from the retired ArtBlend Companion are refused with an explanation.
class HubScannerPage extends StatefulWidget {
  const HubScannerPage({super.key});

  static Future<HubInvite?> open(BuildContext context) => Navigator.of(
    context,
  ).push<HubInvite>(MaterialPageRoute(builder: (_) => const HubScannerPage()));

  @override
  State<HubScannerPage> createState() => _HubScannerPageState();
}

class _HubScannerPageState extends State<HubScannerPage> {
  final controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool done = false, rejected = false, retired = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _detect(BarcodeCapture capture) {
    if (done) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      try {
        final invite = HubInvite.parse(raw);
        if (invite.version != 2) {
          if (!retired) setState(() => retired = true);
          continue;
        }
        done = true;
        Navigator.of(context).pop(invite);
        return;
      } on FormatException {
        if (!rejected) setState(() => rejected = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(l.scanPairingQr),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _detect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l.cameraUnavailable(
                    error.errorDetails?.message ?? error.errorCode.name,
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: const Color(0xaa000000),
              padding: const EdgeInsets.all(16),
              child: Text(
                retired
                    ? l.companionRetired
                    : rejected
                    ? l.invalidPairingQr
                    : l.scanPairingQrHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: rejected || retired
                      ? const Color(0xffffb4a8)
                      : Colors.white,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
