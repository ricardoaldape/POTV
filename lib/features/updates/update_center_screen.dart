import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:potv/ui/branding/potv_animated_assets.dart';
import 'package:intl/intl.dart';

import '../../data/updates/potv_update_catalog.dart';
import '../../data/updates/potv_update_center.dart';

/// App binary updates are intentionally separate from POTV's live content
/// refresh. Android will request user permission before installing an APK.
class UpdateCenterScreen extends StatefulWidget {
  final PotvUpdateCenter? updater;

  const UpdateCenterScreen({super.key, this.updater});

  @override
  State<UpdateCenterScreen> createState() => _UpdateCenterScreenState();
}

class _UpdateCenterScreenState extends State<UpdateCenterScreen> {
  late final PotvUpdateCenter _updater;
  PotvInstalledVersion? _installed;
  PotvUpdateChannel _channel = PotvUpdateChannel.stable;
  PotvUpdateRelease? _available;
  File? _downloaded;
  CancelToken? _cancel;
  int _received = 0;
  int _total = 0;
  bool _checking = false;
  bool _downloading = false;
  String? _message;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _updater = widget.updater ?? PotvUpdateCenter(
      Dio(BaseOptions(connectTimeout: const Duration(seconds: 8))),
    );
    _initialize();
  }

  @override
  void dispose() {
    _cancel?.cancel('El usuario salió de Update Center.');
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final channel = await _updater.selectedChannel();
      final installed = await _updater.installedVersion();
      if (!mounted) return;
      setState(() {
        _channel = channel;
        _installed = installed;
      });
      await _check();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _message = 'No fue posible iniciar Update Center: $error';
      });
    }
  }

  Future<void> _check() async {
    if (_checking || _downloading) return;
    setState(() {
      _checking = true;
      _failed = false;
      _message = null;
      _available = null;
      _downloaded = null;
    });
    try {
      final installed = _installed ?? await _updater.installedVersion();
      final update = await _updater.check(
        channel: _channel,
        installed: installed,
      );
      File? cached;
      if (update != null) {
        cached = await _updater.cachedVerifiedDownload(update);
      } else {
        await _updater.clearDownloadedUpdate();
      }
      if (!mounted) return;
      setState(() {
        _installed = installed;
        _available = update;
        _downloaded = cached;
        _message = update == null
            ? 'POTV está actualizado. No hay una versión más reciente publicada.'
            : cached != null
                ? 'La actualización ya está descargada y verificada.'
                : 'Hay una versión nueva disponible.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _message = 'No se pudo consultar GitHub. Revisa tu conexión e inténtalo de nuevo.';
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _setChannel(PotvUpdateChannel value) async {
    if (_downloading || value == _channel) return;
    await _updater.changeChannel(value);
    if (!mounted) return;
    setState(() => _channel = value);
    await _check();
  }

  Future<void> _download() async {
    final release = _available;
    if (release == null || _downloading) return;
    // Avoid unexpectedly using mobile data for a large binary.
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descargar actualización'),
        content: Text(
          'Se descargarán ${(release.size / (1024 * 1024)).toStringAsFixed(1)} MB '
          'desde las publicaciones oficiales de POTV. '
          'Se verificará SHA-256 antes de solicitar la instalación. '
          'Si usas datos móviles, pueden generarse cargos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descargar'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final token = CancelToken();
    _cancel = token;
    setState(() {
      _downloading = true;
      _downloaded = null;
      _received = 0;
      _total = release.size;
      _failed = false;
      _message = 'Descargando actualización verificada…';
    });
    try {
      final apk = await _updater.downloadAndVerify(
        release,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _downloaded = apk;
        _message = 'APK verificada con SHA-256. Lista para instalar.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = !token.isCancelled;
        _message = token.isCancelled
            ? 'Descarga cancelada.'
            : 'La descarga o su verificación falló. No se instalará ninguna APK.';
      });
    } finally {
      _cancel = null;
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _install() async {
    final apk = _downloaded;
    final release = _available;
    if (apk == null || release == null || !mounted) return;
    try {
      if (!await verifyPotvApk(apk, release)) {
        await _updater.clearDownloadedUpdate();
        if (!mounted) return;
        setState(() {
          _downloaded = null;
          _failed = true;
          _message = 'La APK cambió después de descargarse o está dañada. '
              'POTV la eliminó; vuelve a descargarla.';
        });
        return;
      }
      final validation = await _updater.validateAndroidInstall(apk);
      if (!mounted) return;
      if (!validation.ok) {
        setState(() {
          _failed = true;
          _message = switch (validation.code) {
            'SIGNATURE_MISMATCH' =>
              'Esta APK usa un certificado distinto al de la instalación actual. '
                  'POTV no la instalará para evitar perder datos o romper futuras OTA.',
            'VERSION_NOT_NEWER' =>
              'La APK descargada no es más reciente que la versión instalada.',
            'PACKAGE_MISMATCH' =>
              'La APK descargada no pertenece a POTV.',
            _ => validation.message,
          };
        });
        return;
      }
      if (!await _updater.canInstallApk()) {
        await _updater.openInstallPermissionSettings();
        if (!mounted) return;
        setState(() {
          _message = 'APK, versión y firma verificadas. Autoriza a POTV en '
              'los ajustes de Android y pulsa «Instalar actualización» otra vez.';
        });
        return;
      }
      await _updater.requestAndroidInstall(apk);
      if (!mounted) return;
      setState(() {
        _failed = false;
        _message = 'APK, versión y firma verificadas. Android abrió su '
            'instalador; confirma la actualización.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _message = 'Android no pudo abrir el instalador. POTV no modificó '
            'la instalación actual.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = _available;
    final progress = _total > 0
        ? (_received / _total).clamp(0.0, 1.0).toDouble()
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('POTV Update Center')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Icon(Icons.system_update_alt_rounded, size: 52),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'Actualizaciones de POTV',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Mantén la aplicación al día sin perder tus perfiles, '
            'favoritos ni listas M3U.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.smartphone_rounded),
                  title: const Text('Versión instalada'),
                  subtitle: Text(_installed == null
                      ? 'Consultando…'
                      : '${_installed!.name} · código ${_installed!.code}'),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.security_rounded),
                  title: Text('Actualizaciones verificadas'),
                  subtitle: Text(
                    'Sólo publicaciones oficiales de POTV. '
                    'Se comprueban SHA-256, paquete, versión y certificado '
                    'Android antes de abrir el instalador.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('Canal de actualización',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 9),
          SegmentedButton<PotvUpdateChannel>(
            key: const ValueKey('ota-channel-selector'),
            segments: const [
              ButtonSegment(
                value: PotvUpdateChannel.stable,
                label: Text('Estable'),
                icon: Icon(Icons.verified_rounded),
              ),
              ButtonSegment(
                value: PotvUpdateChannel.beta,
                label: Text('Beta'),
                icon: Icon(Icons.science_rounded),
              ),
            ],
            selected: {_channel},
            onSelectionChanged: _downloading
                ? null
                : (values) => _setChannel(values.first),
          ),
          const SizedBox(height: 9),
          Text(
            _channel == PotvUpdateChannel.stable
                ? 'Sólo versiones estables recomendadas.'
                : 'Incluye versiones de prueba, que podrían tener errores.',
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _checking || _downloading ? null : _check,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Buscar actualizaciones'),
          ),
          if (_checking) ...[
            const SizedBox(height: 14),
            const PotvLoadingFlag(width: 72),
          ],
          if (_message != null) ...[
            const SizedBox(height: 15),
            Text(
              _message!,
              key: const ValueKey('ota-status'),
              style: TextStyle(
                color: _failed ? Colors.orangeAccent : null,
              ),
            ),
          ],
          if (update != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'POTV ${update.versionName}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${update.prerelease ? "Beta" : "Estable"} · '
                      'código ${update.versionCode}' +
                      (update.publishedAt == null
                          ? ''
                          : ' · ${DateFormat.yMMMd().format(update.publishedAt!)}'),
                    ),
                    if (update.notes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Novedades',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      SelectableText(
                        update.notes.length > 3000
                            ? '${update.notes.substring(0, 3000)}…'
                            : update.notes,
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (_downloading) ...[
                      LinearProgressIndicator(value: progress),
                      const SizedBox(height: 6),
                      Text(progress == null
                          ? 'Descargando…'
                          : '${(progress * 100).toStringAsFixed(0)} %'),
                      TextButton.icon(
                        onPressed: () => _cancel?.cancel(),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Cancelar descarga'),
                      ),
                    ] else if (_downloaded != null)
                      FilledButton.icon(
                        key: const ValueKey('ota-install'),
                        onPressed: _install,
                        icon: const Icon(Icons.install_mobile_rounded),
                        label: const Text('Instalar actualización'),
                      )
                    else
                      FilledButton.icon(
                        key: const ValueKey('ota-download'),
                        onPressed: _download,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Descargar APK verificada'),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          const ListTile(
            leading: Icon(Icons.live_tv_rounded),
            title: Text('Contenido siempre actualizado'),
            subtitle: Text(
              'El catálogo, las listas y los servidores autorizados '
              'se actualizan aparte de la APK, cuando existe conexión.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('Instalación segura en Android'),
            subtitle: Text(
              'Android controla el permiso para instalar APK. '
              'Para actualizar sin perder datos, la nueva versión debe '
              'tener el mismo identificador y certificado que la instalada.',
            ),
          ),
        ],
      ),
    );
  }
}
