import 'package:atelier_studio/data/local_network_permission.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  test(
    'below Android 17 the permission is never requested or required',
    () async {
      var asked = 0;
      for (final sdk in [26, 31, 36]) {
        await ensureLocalNetworkAccess(
          sdkInt: () async => sdk,
          request: () async {
            asked++;
            // What permission_handler 14.1.1 reports on these versions.
            return PermissionStatus.denied;
          },
        );
      }
      expect(asked, 0);
    },
  );

  test('from Android 17 a refusal stops the connection', () async {
    await ensureLocalNetworkAccess(
      sdkInt: () async => 37,
      request: () async => PermissionStatus.granted,
    );
    await expectLater(
      ensureLocalNetworkAccess(
        sdkInt: () async => 37,
        request: () async => PermissionStatus.permanentlyDenied,
      ),
      throwsA(isA<LocalNetworkAccessDenied>()),
    );
  });
}
