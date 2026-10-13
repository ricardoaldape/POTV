import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'potv_update_catalog.dart';

typedef PotvDownloadProgress = void Function(int received, int total);

class PotvInstallValidation {
  final bool ok;
  final String code;
  final String message;
  final int? installedCode;
  final int? candidateCode;
  final String? candidateName;

  const PotvInstallValidation({
    required this.ok,
    required this.code,
    required this.message,
    this.installedCode,
    this.candidateCode,
    this.candidateName,
  });

  factory PotvInstallValidation.fromMap(Map<Object?, Object?> raw) {
    return PotvInstallValidation(
      ok: raw['ok'] == true,
      code: raw['code']?.toString() ?? 'INVALID_APK',
      message: raw['message']?.toString() ?? 'La APK no es compatible.',
      installedCode: raw['installedCode'] is int ? raw['installedCode'] as int : null,
      candidateCode: raw['candidateCode'] is int ? raw['candidateCode'] as int : null,
      candidateName: raw['candidateName']?.toString(),
    );
  }
}

/// Streamed SHA-256 verification: doesn't load a large APK into RAM.
Future<bool> verifyPotvApk(File file, PotvUpdateRelease release) async {
  if (!await file.exists() || await file.length() != release.size) return false;
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString().toLowerCase() == release.sha256Hex;
}


class PotvUpdateCenter {
  static const _channel = MethodChannel('com.potv.potv/update_center');
  static const _preference = 'potv_update_channel_v1';

  final Dio dio;
  final PotvUpdateCatalog catalog;

  PotvUpdateCenter(this.dio) : catalog = PotvUpdateCatalog(dio);

  Future<Directory> _updatesDirectory() async {
    final dir = await _updatesDirectory();
    return dir;
  }

  Future<File?> cachedVerifiedDownload(PotvUpdateRelease release) async {
    final dir = await _updatesDirectory();
    final apk = File('${dir.path}${Platform.pathSeparator}potv-update.apk');
    if (!await apk.exists()) return null;
    if (await verifyPotvApk(apk, release)) return apk;
    await apk.delete();
    return null;
  }

  Future<void> clearDownloadedUpdate() async {
    final dir = await _updatesDirectory();
    for (final name in const ['potv-update.part', 'potv-update.apk']) {
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      if (await file.exists()) await file.delete();
    }
  }


  Future<PotvInstalledVersion> installedVersion() async {
    final info = await _channel.invokeMapMethod<String, Object?>(
      'installedVersion',
    );
    if (info == null || info['name'] is! String || info['code'] is! int) {
      throw StateError('No fue posible leer la versión de POTV.');
    }
    return PotvInstalledVersion(
      name: info['name']! as String,
      code: info['code']! as int,
    );
  }

  Future<PotvUpdateChannel> selectedChannel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_preference) == 'beta'
        ? PotvUpdateChannel.beta
        : PotvUpdateChannel.stable;
  }

  Future<void> changeChannel(PotvUpdateChannel value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preference, value.name);
  }

  Future<PotvUpdateRelease?> check({
    required PotvUpdateChannel channel,
    required PotvInstalledVersion installed,
  }) => catalog.latest(channel: channel, installedCode: installed.code);

  Future<File> downloadAndVerify(
    PotvUpdateRelease release, {
    PotvDownloadProgress? onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = Directory(
      '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}potv-updates',
    );
    await dir.create(recursive: true);
    final temp = File('${dir.path}${Platform.pathSeparator}potv-update.part');
    final apk = File('${dir.path}${Platform.pathSeparator}potv-update.apk');

    if (await apk.exists()) {
      if (await verifyPotvApk(apk, release)) {
        onProgress?.call(release.size, release.size);
        return apk;
      }
      await apk.delete();
    }
    if (await temp.exists()) await temp.delete();
    final token = cancelToken ?? CancelToken();
    try {
      await dio.download(
        release.apkUrl.toString(),
        temp.path,
        cancelToken: token,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          maxRedirects: 5,
          receiveTimeout: const Duration(minutes: 3),
          sendTimeout: const Duration(seconds: 15),
          validateStatus: (status) => status == 200,
        ),
        onReceiveProgress: (received, total) {
          if (received > 450 * 1024 * 1024) {
            token.cancel('El archivo supera el límite permitido.');
            return;
          }
          onProgress?.call(received, release.size);
        },
      );
      if (!await verifyPotvApk(temp, release)) {
        throw StateError('El tamaño o SHA-256 de la actualización no coincide.');
      }
      await temp.rename(apk.path);
      return apk;
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  Future<bool> canInstallApk() async =>
      await _channel.invokeMethod<bool>('canInstallPackages') ?? false;

  Future<void> openInstallPermissionSettings() async =>
      _channel.invokeMethod<void>('openInstallSettings');

  Future<PotvInstallValidation> validateAndroidInstall(File apk) async {
    if (!await apk.exists()) {
      return const PotvInstallValidation(
        ok: false,
        code: 'INVALID_APK',
        message: 'No se encontró la actualización descargada.',
      );
    }
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'validateInstallPackage',
      {'path': apk.path},
    );
    if (raw == null) {
      return const PotvInstallValidation(
        ok: false,
        code: 'INVALID_APK',
        message: 'Android no pudo validar la APK.',
      );
    }
    return PotvInstallValidation.fromMap(raw);
  }

  Future<void> requestAndroidInstall(File apk) async {
    if (!await apk.exists()) {
      throw StateError('No se encontró la actualización descargada.');
    }
    await _channel.invokeMethod<void>(
      'requestInstall',
      {'path': apk.path},
    );
  }
}
