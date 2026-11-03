import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme.dart';
import '../../../utils/battleship_logic.dart';
import '../effects.dart';
import 'sea_board.dart';

/// Flotte aufstellen: Schiffe ziehen, antippen zum Drehen, oder zufällig verteilen.
class FleetSetup extends StatefulWidget {
  const FleetSetup({super.key, required this.onReady, this.initial});

  final Future<void> Function(List<Ship> ships) onReady;
  final List<Ship>? initial;

  @override
  State<FleetSetup> createState() => _FleetSetupState();
}

class _FleetSetupState extends State<FleetSetup> {
  late List<Ship> _ships = widget.initial ?? randomFleet();
  final _fx = EffectLayer();
  String? _dragId;
  int _grab = 0; // welches Feld des Schiffs der Finger hält
  bool _saving = false;

  @override
  void dispose() {
    _fx.dispose();
    super.dispose();
  }

  Ship? _shipAt(Point<int> c) {
    for (final s in _ships.reversed) {
      if (s.cells.contains(c)) return s;
    }
    return null;
  }

  // Schiff ins Feld zurückschieben, falls es übersteht.
  Ship _clamp(Ship s) {
    final maxX = s.vertical ? boardSize - 1 : boardSize - s.len;
    final maxY = s.vertical ? boardSize - s.len : boardSize - 1;
    return s.copyWith(x: s.x.clamp(0, maxX), y: s.y.clamp(0, maxY));
  }

  void _replace(Ship s) =>
      setState(() => _ships = [for (final o in _ships) o.id == s.id ? s : o]);

  void _rotate(int x, int y) {
    final s = _shipAt(Point(x, y));
    if (s == null) return;
    HapticFeedback.selectionClick();
    _replace(_clamp(s.copyWith(vertical: !s.vertical)));
  }

  @override
  Widget build(BuildContext context) {
    final invalid = invalidShips(_ships);
    final valid = isValidFleet(_ships);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('FLOTTE AUFSTELLEN', style: AppTheme.label()),
        const SizedBox(height: 4),
        const Text(
          'Ziehen zum Verschieben, antippen zum Drehen. Schiffe dürfen sich '
          'berühren, aber nicht überlappen.',
          style: TextStyle(fontSize: 13, color: Kitsune.mist),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final geo = BoardGeometry(c.maxWidth);
            return GestureDetector(
              onPanStart: (d) {
                final cell = geo.cellAt(d.localPosition);
                final s = cell == null ? null : _shipAt(cell);
                if (s == null) return;
                HapticFeedback.selectionClick();
                setState(() {
                  _dragId = s.id;
                  _grab = s.cells.indexOf(cell!);
                });
              },
              onPanUpdate: (d) {
                final id = _dragId;
                final cell = geo.cellAt(d.localPosition);
                if (id == null || cell == null) return;
                final s = _ships.firstWhere((s) => s.id == id);
                final moved = _clamp(
                  s.copyWith(
                    x: s.vertical ? cell.x : cell.x - _grab,
                    y: s.vertical ? cell.y - _grab : cell.y,
                  ),
                );
                if (moved.x != s.x || moved.y != s.y) _replace(moved);
              },
              onPanEnd: (_) => setState(() => _dragId = null),
              onPanCancel: () => setState(() => _dragId = null),
              child: BattleBoard(
                effects: _fx,
                ships: _ships,
                invalidIds: invalid,
                liftedId: _dragId,
                onTapCell: _rotate,
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        // Legende der Flotte
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final spec in fleetSpec)
              Text(
                '${spec.name} · ${spec.len}',
                style: TextStyle(
                  fontSize: 12,
                  color: invalid.contains(spec.id)
                      ? Kitsune.lantern
                      : Kitsune.mist,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        setState(() => _ships = randomFleet());
                      },
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('Zufällig'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: !valid || _saving
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        try {
                          await widget.onReady(_ships);
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
                icon: const Icon(Icons.anchor_rounded),
                label: Text(_saving ? 'Speichere …' : 'Bereit'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
