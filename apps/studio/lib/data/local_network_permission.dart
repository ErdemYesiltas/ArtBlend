import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android 17 (API 37) introduced ACCESS_LOCAL_NETWORK; earlier versions
/// allow local network access without it.
const localNetworkPermissionSdk = 37;

const _platform = MethodChannel('artblend/platform');

/// Requested only when the person starts a local network operation, never at
/// application launch. permission_handler reports the permission as denied
/// below API 37 (it finds no manifest entry to request), so it is only asked
/// for where it exists.
Future<void> ensureLocalNetworkAccess({
  Future<int?> Function()? sdkInt,
  Future<PermissionStatus> Function()? request,
}) async {
  if (!Platform.isAndroid && sdkInt == null) return;
  final sdk = await (sdkInt ?? () => _platform.invokeMethod<int>('sdkInt'))();
  if (sdk == null || sdk < localNetworkPermissionSdk) return;
  final status = await (request ?? Permission.accessLocalNetwork.request)();
  if (!status.isGranted) throw const LocalNetworkAccessDenied();
}

class LocalNetworkAccessDenied implements Exception {
  const LocalNetworkAccessDenied();
  @override
  String toString() =>
      'Local network access was denied. Enable it in the application permissions to connect to your Mac.';
}
