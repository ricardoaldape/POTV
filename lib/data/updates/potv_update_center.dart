import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'potv_update_catalog.dart';

typedef PotvDownloadProgress = void Function(int received, int total);

class PotvUpdateCenter {
  static const _channel = MethodChannel('com.potv.potv/update_center');
  static const _preference = 'potv_update_channel_v1';

  final Dio dio;
  final PotvUpdateCatalog catalog;

  PotvUpdateCenter(this.dio) : catalog = PotvUpdateCatalog(dio);

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

    if (await temp.exists()) await temp.delete();
    if (await apk.exists()) await apk.delete();
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
      final length = await temp.length();
      if (length != release.size) {
        throw StateError('El tamaño de la actualización no coincide.');
      }
      final digest = await sha256.bind(temp.openRead()).first;
      if (digest.toString().toLowerCase() != release.sha256Hex) {
        throw StateError('La verificación SHA-256 falló. No se instalará.');
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
