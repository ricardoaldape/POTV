import 'package:flutter/material.dart';

import '../../data/services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.update,
    this.service,
  });

  final UpdateInfo update;
  final UpdateService? service;

  static Future<void> show(
    BuildContext context,
    UpdateInfo update, {
    UpdateService? service,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !update.mandatory,
      builder: (_) => PopScope(
        canPop: !update.mandatory,
        child: UpdateDialog(update: update, service: service),
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  UpdateService get _service => widget.service ?? UpdateService();

  Future<void> _updateNow() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });

    try {
      final path = await _service.downloadApk(
        widget.update.apkUrl,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      await _service.installApk(path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo completar la actualización.';
          _downloading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_progress * 100).clamp(0, 100).round();

    return AlertDialog(
      title: const Text('Nueva versión disponible'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'POTV ${widget.update.version}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            const Text('Cambios:'),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                child: Text(widget.update.changelog),
              ),
            ),
            if (_downloading) ...[
              const SizedBox(height: 18),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('Descargando… $percent%'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!widget.update.mandatory && !_downloading)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Después'),
          ),
        FilledButton(
          onPressed: _downloading ? null : _updateNow,
          child: const Text('Actualizar ahora'),
        ),
      ],
    );
  }
}
