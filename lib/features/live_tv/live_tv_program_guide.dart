import 'package:flutter/material.dart';
import 'package:potv/ui/branding/potv_animated_assets.dart';

import '../../domain/models/epg_program.dart';
import '../../domain/models/live_channel.dart';
import '../../domain/services/live_tv_organizer.dart';

/// POTV now/next parrilla, based on verified programs for all TV sources.
class LiveTvProgramGuideRow extends StatelessWidget {
  final LiveChannel channel;
  final LiveTvCategory category;
  final EpgProgram? current;
  final EpgProgram? next;
  final DateTime now;
  final bool compact;
  final bool favorite;
  final bool opening;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;

  const LiveTvProgramGuideRow({
    super.key,
    required this.channel,
    required this.category,
    required this.current,
    required this.next,
    required this.now,
    required this.compact,
    required this.favorite,
    required this.opening,
    required this.onOpen,
    required this.onFavorite,
  });

  String _clock(DateTime value) =>
      value.hour.toString().padLeft(2, '0') + ':' +
      value.minute.toString().padLeft(2, '0');

  Widget _program(EpgProgram? program, String fallback, bool onAir) {
    if (program == null) {
      return Text(fallback,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white54, fontSize: 12));
    }
    final progress = (now.difference(program.startsAt).inMilliseconds /
        program.endsAt.difference(program.startsAt).inMilliseconds)
        .clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_clock(program.startsAt) + '–' + _clock(program.endsAt) +
            ' · ' + program.title,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12,
              fontWeight: onAir ? FontWeight.w700 : FontWeight.w400)),
        if (onAir) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(value: progress, minHeight: 3),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final details = Row(
      children: [
        if (channel.logo != null)
          Image.network(channel.logo.toString(), width: 32, height: 32,
            errorBuilder: (_, error, stack) =>
                const Icon(Icons.live_tv_rounded, size: 28))
        else
          const Icon(Icons.live_tv_rounded, size: 28),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(category.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white60)),
          ],
        )),
        IconButton(
          key: ValueKey('live-tv-guide-star-' + channel.id),
          tooltip: favorite ? 'Quitar de favoritos' : 'Guardar favorito',
          icon: Icon(favorite ? Icons.star_rounded : Icons.star_border_rounded),
          onPressed: onFavorite,
        ),
      ],
    );
    return Card(
      child: InkWell(
        key: ValueKey('live-tv-guide-channel-' + channel.id),
        onTap: opening ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  details,
                  const SizedBox(height: 7),
                  _program(current, 'Sin datos de programación', true),
                  const SizedBox(height: 7),
                  _program(next, 'Próximo programa no disponible', false),
                  if (opening) const PotvLoadingFlag(width: 44),
                ],
              )
            : Row(
                children: [
                  SizedBox(width: 240, child: details),
                  const SizedBox(width: 14),
                  Expanded(flex: 5, child: _program(
                      current, 'Sin datos de programación', true)),
                  const SizedBox(width: 18),
                  Expanded(flex: 4, child: _program(
                      next, 'Próximo programa no disponible', false)),
                  const SizedBox(width: 8),
                  if (opening)
                    const SizedBox(width: 20, height: 20,
                        child: PotvLoadingFlag(width: 20))
                  else
                    const Icon(Icons.play_arrow_rounded, size: 22),
                ],
              ),
        ),
      ),
    );
  }
}
