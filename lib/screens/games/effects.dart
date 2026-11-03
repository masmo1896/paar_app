import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';

// Kleines Partikelsystem für die Spiele: Feuerball, Explosion, Wasserfontäne,
// Fuchsfeuer, Feuerwerk und Regen. Wird von einem Ticker weitergezählt
// (EffectLayer.tick) und mit EffectPainter gezeichnet.

class _Particle {
  _Particle({
    required this.pos,
    required this.vel,
    required this.color,
    required this.life,
    required this.size,
    this.gravity = 0,
    this.drag = 0.98,
    this.glow = false,
    this.rise = 0,
    this.streak = false,
  });

  Offset pos;
  Offset vel;
  final Color color;
  final double life; // Sekunden
  final double size;
  final double gravity;
  final double drag;
  final bool glow;
  final double rise; // Auftrieb (Flammen)
  final bool streak; // als Strich zeichnen (Regen, Funken)
  double age = 0;

  double get t => (age / life).clamp(0, 1);
  bool get dead => age >= life;
}

class _Ring {
  _Ring(this.center, this.color, this.maxRadius, this.life, {this.width = 2});
  final Offset center;
  final Color color;
  final double maxRadius;
  final double life;
  final double width;
  double age = 0;
}

class _Flash {
  _Flash(this.center, this.radius, this.color, this.life);
  final Offset center;
  final double radius;
  final Color color;
  final double life;
  double age = 0;
}

/// Ein fliegender Feuerball von [from] nach [to] auf einem Bogen.
class _Projectile {
  _Projectile(this.from, this.to, this.duration, this.onArrive, this.color);
  final Offset from;
  final Offset to;
  final double duration;
  final VoidCallback onArrive;
  final Color color;
  double age = 0;
  bool arrived = false;

  Offset at(double t) {
    final mid = Offset(
      (from.dx + to.dx) / 2,
      math.min(from.dy, to.dy) - (from - to).distance * 0.45,
    );
    final a = Offset.lerp(from, mid, t)!, b = Offset.lerp(mid, to, t)!;
    return Offset.lerp(a, b, t)!;
  }
}

/// Hält alle laufenden Effekte. Positionen in Pixeln des Spielfelds.
class EffectLayer extends ChangeNotifier {
  final _rnd = math.Random();
  final _particles = <_Particle>[];
  final _rings = <_Ring>[];
  final _flashes = <_Flash>[];
  final _projectiles = <_Projectile>[];

  /// Bildschirm-Wackeln (0 = ruhig).
  double shake = 0;

  bool get busy =>
      _particles.isNotEmpty ||
      _rings.isNotEmpty ||
      _flashes.isNotEmpty ||
      _projectiles.isNotEmpty ||
      shake > 0.01;

  Offset get shakeOffset => shake <= 0.01
      ? Offset.zero
      : Offset(
          (_rnd.nextDouble() - 0.5) * shake * 10,
          (_rnd.nextDouble() - 0.5) * shake * 10,
        );

  void tick(double dt) {
    if (!busy) return;
    for (final p in _particles) {
      p.age += dt;
      if (p.age < 0) continue; // startet verzögert
      p.vel = Offset(p.vel.dx * p.drag, p.vel.dy * p.drag + p.gravity * dt);
      p.pos += p.vel * dt + Offset(0, -p.rise * dt);
    }
    _particles.removeWhere((p) => p.dead);
    for (final r in _rings) {
      r.age += dt;
    }
    _rings.removeWhere((r) => r.age >= r.life);
    for (final f in _flashes) {
      f.age += dt;
    }
    _flashes.removeWhere((f) => f.age >= f.life);
    for (final pr in [..._projectiles]) {
      pr.age += dt;
      final t = (pr.age / pr.duration).clamp(0.0, 1.0);
      // Funkenschweif
      final pos = pr.at(t);
      for (var i = 0; i < 2; i++) {
        _particles.add(
          _Particle(
            pos: pos,
            vel: Offset(
              (_rnd.nextDouble() - 0.5) * 30,
              (_rnd.nextDouble() - 0.5) * 30,
            ),
            color: Color.lerp(
              pr.color,
              Kitsune.paper,
              _rnd.nextDouble() * 0.5,
            )!,
            life: 0.35 + _rnd.nextDouble() * 0.2,
            size: 2 + _rnd.nextDouble() * 2.5,
            glow: true,
          ),
        );
      }
      if (t >= 1 && !pr.arrived) {
        pr.arrived = true;
        _projectiles.remove(pr);
        pr.onArrive();
      }
    }
    shake *= math.pow(0.02, dt).toDouble();
    notifyListeners();
  }

  /// Feuerball fliegt los; [onArrive] wenn er ankommt.
  void fireball(Offset from, Offset to, {VoidCallback? onArrive}) {
    _projectiles.add(
      _Projectile(from, to, 0.55, onArrive ?? () {}, const Color(0xFFFF9A3C)),
    );
    notifyListeners();
  }

  /// Treffer: Blitz, Funken, Rauch und Druckwelle.
  void explosion(Offset at, double cell, {bool big = false}) {
    final n = big ? 70 : 42;
    _flashes.add(
      _Flash(at, cell * (big ? 2.2 : 1.4), const Color(0xFFFFD27A), 0.25),
    );
    _rings.add(
      _Ring(
        at,
        const Color(0xFFFFB25C),
        cell * (big ? 2.6 : 1.7),
        0.5,
        width: 3,
      ),
    );
    for (var i = 0; i < n; i++) {
      final a = _rnd.nextDouble() * 2 * math.pi;
      final speed = cell * (2 + _rnd.nextDouble() * (big ? 7 : 5));
      _particles.add(
        _Particle(
          pos: at,
          vel: Offset(math.cos(a), math.sin(a)) * speed,
          color: [
            const Color(0xFFFFE08A),
            const Color(0xFFFF9A3C),
            Kitsune.lantern,
            const Color(0xFFFF5A3C),
          ][_rnd.nextInt(4)],
          life: 0.5 + _rnd.nextDouble() * 0.6,
          size: 1.5 + _rnd.nextDouble() * 3,
          gravity: cell * 6,
          drag: 0.93,
          glow: true,
          streak: _rnd.nextBool(),
        ),
      );
    }
    for (var i = 0; i < 10; i++) {
      _particles.add(
        _Particle(
          pos: at + Offset((_rnd.nextDouble() - 0.5) * cell, 0),
          vel: Offset((_rnd.nextDouble() - 0.5) * cell, -cell * 0.5),
          color: const Color(0x99404A66),
          life: 1.2 + _rnd.nextDouble() * 0.6,
          size: cell * (0.25 + _rnd.nextDouble() * 0.25),
          rise: cell * 0.8,
          drag: 0.97,
        ),
      );
    }
    shake = math.max(shake, big ? 1.6 : 1);
    notifyListeners();
  }

  /// Wasser: Fontäne mit Tropfen und Ringwellen.
  void splash(Offset at, double cell) {
    for (var i = 0; i < 3; i++) {
      _rings.add(
        _Ring(
          at,
          Kitsune.aqua,
          cell * (0.8 + i * 0.45),
          0.7 + i * 0.25,
          width: 1.5,
        ),
      );
    }
    for (var i = 0; i < 30; i++) {
      final a = -math.pi / 2 + (_rnd.nextDouble() - 0.5) * 1.1;
      final speed = cell * (2.5 + _rnd.nextDouble() * 3.5);
      _particles.add(
        _Particle(
          pos: at,
          vel: Offset(math.cos(a), math.sin(a)) * speed,
          color: _rnd.nextBool() ? Kitsune.aqua : Kitsune.paper,
          life: 0.6 + _rnd.nextDouble() * 0.4,
          size: 1.5 + _rnd.nextDouble() * 2,
          gravity: cell * 14,
          drag: 0.99,
        ),
      );
    }
    shake = math.max(shake, 0.25);
    notifyListeners();
  }

  /// Versenkt: blaues Fuchsfeuer steigt über allen Feldern des Schiffs auf.
  void foxfire(List<Offset> cells, double cell) {
    for (final c in cells) {
      explosion(c, cell * 0.8);
      for (var i = 0; i < 22; i++) {
        _particles.add(
          _Particle(
            pos: c + Offset((_rnd.nextDouble() - 0.5) * cell * 0.7, cell * 0.2),
            vel: Offset((_rnd.nextDouble() - 0.5) * cell * 0.6, 0),
            color: [
              const Color(0xFF7FE7FF),
              Kitsune.aqua,
              const Color(0xFF5B8CFF),
              Kitsune.paper,
            ][_rnd.nextInt(4)],
            life: 0.8 + _rnd.nextDouble() * 1.0,
            size: 2 + _rnd.nextDouble() * 4,
            rise: cell * (1.5 + _rnd.nextDouble() * 1.5),
            drag: 0.96,
            glow: true,
          ),
        );
      }
    }
    shake = math.max(shake, 1.8);
    notifyListeners();
  }

  /// Feuerwerk über der ganzen Fläche [size].
  void fireworks(Size size, {int bursts = 6}) {
    for (var b = 0; b < bursts; b++) {
      final at = Offset(
        size.width * (0.15 + _rnd.nextDouble() * 0.7),
        size.height * (0.15 + _rnd.nextDouble() * 0.5),
      );
      final color = [
        Kitsune.lantern,
        Kitsune.aqua,
        const Color(0xFFFFD27A),
        Kitsune.sky,
        Kitsune.paper,
      ][_rnd.nextInt(5)];
      final delay = b * 0.18;
      for (var i = 0; i < 46; i++) {
        final a = i / 46 * 2 * math.pi;
        final speed = size.width * (0.18 + _rnd.nextDouble() * 0.08);
        _particles.add(
          _Particle(
            pos: at,
            vel: Offset(math.cos(a), math.sin(a)) * speed,
            color: color,
            life: 1.2 + _rnd.nextDouble() * 0.4,
            size: 2 + _rnd.nextDouble() * 1.5,
            gravity: size.width * 0.12,
            drag: 0.955,
            glow: true,
            streak: true,
          )..age = -delay, // startet etwas später
        );
      }
    }
    notifyListeners();
  }

  /// Leiser Regen (verloren).
  void rain(Size size) {
    for (var i = 0; i < 120; i++) {
      _particles.add(
        _Particle(
          pos: Offset(
            size.width * _rnd.nextDouble(),
            -size.height * _rnd.nextDouble(),
          ),
          vel: Offset(-20, size.height * (0.9 + _rnd.nextDouble() * 0.4)),
          color: Kitsune.mist.withValues(alpha: 0.5),
          life: 2.2,
          size: 1.2,
          drag: 1,
          streak: true,
        ),
      );
    }
    notifyListeners();
  }
}

class EffectPainter extends CustomPainter {
  EffectPainter(this.layer) : super(repaint: layer);

  final EffectLayer layer;

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in layer._flashes) {
      final t = f.age / f.life;
      canvas.drawCircle(
        f.center,
        f.radius * (0.6 + t * 0.6),
        Paint()
          ..color = f.color.withValues(alpha: (1 - t) * 0.85)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, f.radius * 0.4),
      );
    }
    for (final r in layer._rings) {
      final t = r.age / r.life;
      canvas.drawCircle(
        r.center,
        r.maxRadius * Curves.easeOut.transform(t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r.width * (1 - t) + 0.5
          ..color = r.color.withValues(alpha: (1 - t) * 0.9),
      );
    }
    for (final p in layer._particles) {
      if (p.age < 0) continue;
      final alpha = (1 - p.t) * p.color.a;
      final paint = Paint()..color = p.color.withValues(alpha: alpha);
      if (p.glow) {
        canvas.drawCircle(
          p.pos,
          p.size * 2.2,
          Paint()
            ..color = p.color.withValues(alpha: alpha * 0.35)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 1.5),
        );
      }
      if (p.streak) {
        paint
          ..strokeWidth = p.size * 0.8
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(p.pos, p.pos - p.vel * 0.03, paint);
      } else {
        canvas.drawCircle(p.pos, p.size * (1 - p.t * 0.4), paint);
      }
    }
    for (final pr in layer._projectiles) {
      final t = (pr.age / pr.duration).clamp(0.0, 1.0);
      final pos = pr.at(t);
      canvas.drawCircle(
        pos,
        10,
        Paint()
          ..color = pr.color.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(pos, 4.5, Paint()..color = const Color(0xFFFFF1C9));
    }
  }

  @override
  bool shouldRepaint(EffectPainter old) => false;
}
