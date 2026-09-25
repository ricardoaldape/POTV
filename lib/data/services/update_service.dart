// TODO(main.dart): llamar a UpdateService().checkForUpdate() al arrancar
// y, si devuelve una actualización, mostrar UpdateDialog.
// TODO(pubspec.yaml): añadir package_info_plus y open_filex.
// dio y path_provider ya existen actualmente en pubspec.yaml.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.apkUrl,
    required this.changelog,
    required this.mandatory,
    required this.releasedAt,
  });

  final String version;
  final int versionCode;
  final String apkUrl;
  final String changelog;
  final bool mandatory;
  final DateTime releasedAt;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
        version: json['version'] as String,
        versionCode: json['versionCode'] as int,
        apkUrl: json['apk_url'] as String,
        changelog: json['changelog'] as String? ?? '',
        mandatory: json['mandatory'] as bool? ?? false,
        releasedAt: DateTime.parse(json['released_at'] as String).toUtc(),
      );
}

class UpdateService {
  UpdateService({
    Dio? dio,
    this.versionEndpoint = 'https://potv.fxqubit.com/version',
  }) : _dio = dio ?? Dio();

  final Dio _dio;
  final String versionEndpoint;

  Future<UpdateInfo?> checkForUpdate() async {
    final response = await _dio.get<dynamic>(versionEndpoint);
    final data = Map<String, dynamic>.from(response.data as Map);
    final latest = UpdateInfo.fromJson(data);

    final packageInfo = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(packageInfo.buildNumber) ?? 0;

    return latest.versionCode > currentCode ? latest : null;
  }

  Future<String> downloadApk(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final directory = await getExternalStorageDirectory();
    if (directory == null) {
      throw StateError('No se pudo acceder al almacenamiento externo.');
    }

    final updatesDirectory = Directory('${directory.path}/updates');
    if (!await updatesDirectory.exists()) {
      await updatesDirectory.create(recursive: true);
    }

    final filePath = '${updatesDirectory.path}/potv-update.apk';

    await _dio.download(
      url,
      filePath,
      deleteOnError: true,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress?.call(received / total);
        }
      },
      options: Options(
        followRedirects: true,
        receiveTimeout: const Duration(minutes: 5),
      ),
    );

    return filePath;
  }

  Future<void> installApk(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw ArgumentError.value(path, 'path', 'El APK descargado no existe.');
    }

    final result = await OpenFilex.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw StateError('No se pudo abrir el instalador: ${result.message}');
    }
  }
}
