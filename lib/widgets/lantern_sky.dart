import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/couple_service.dart';
import '../services/lantern_service.dart';
import '../theme.dart';
import 'who.dart';
import 'motion.dart';

/// Unser Laternenhimmel: Jede Laterne heisst "Ich denk an dich" und bleibt für
/// immer am Himmel – deine rot, die deines Schatzes aqua.
///
/// - Antippen des Knopfs lässt eine Laterne aufsteigen.
/// - Kommen neue Laternen deines Schatzes an, bringt sie ein kleiner Fuchs-Bote.
/// - Habt ihr innerhalb von 5 Minuten beide eine geschickt: Feuerwerk.
class LanternSky extends StatefulWidget {
  const LanternSky({super.key, required this.couple, required this.active});

  final Couple couple;

  /// Ist die Home-Seite gerade zu sehen? Nur dann läuft der Fuchs-Bote los.
  final bool active;

  @override
  State<LanternSky> createState() => _LanternSkyState();
}

class _LanternSkyState extends State<LanternSky> with TickerProviderStateMixin {
  static const _skyHeight = 168.0;

  final _service = LanternService.instance;
  StreamSubscription<List<Lantern>>? _lanternSub;
  StreamSubscription<Map<String, dynamic>?>? _profileSub;
  var _lanterns = <Lantern>[];
  bool _lanternsLoaded = false;
  bool _profileLoaded = false;
  DateTime? _seenAt;

  // Sanftes Schweben aller Laternen.
  late final _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();
  // Eigene Laterne steigt auf.
  late final _fly = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  // Fuchs-Bote läuft durchs Bild.
  late final _fox = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );
  // Gleichzeitig-Feuerwerk.
  late final _party = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4200),
  );

  String? _flyingId; // eigene Laterne, die gerade aufsteigt
  String? _foxLanternId; // Laterne, die der Fuchs bringt
  int _foxCount = 0;

  String get _coupleId => widget.couple.coupleId;
  String get _me => widget.couple.myUid;

  @override
  void initState() {
    super.initState();
    _lanternSub = _service.lanterns(_coupleId).listen(
      (list) {
        setState(() {
          _lanterns = list;
          _lanternsLoaded = true;
        });
        _maybeSendFox();
      },
      // Z. B. keine Berechtigung: Himmel bleibt einfach leer.
      onError: (Object e) => debugPrint('Laternen nicht lesbar: $e'),
    );
    _profileSub = CoupleService.instance.myProfileStream().listen((me) {
      // Nur übernehmen, wenn es neuer ist (lokal setzen wir es schon vorher).
      final at = (me?['lanternsSeenAt'] as Timestamp?)?.toDate();
      if (at != null && (_seenAt == null || at.isAfter(_seenAt!))) {
        _seenAt = at;
      }
      _profileLoaded = true;
      _maybeSendFox();
    });
  }

  // "Bewegung reduzieren" am Handy: Laternen schweben nicht.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _float.stop();
    } else if (!_float.isAnimating) {
      _float.repeat();
    }
  }

  @override
  void didUpdateWidget(LanternSky old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _maybeSendFox();
  }

  @override
  void dispose() {
    _lanternSub?.cancel();
    _profileSub?.cancel();
    _float.dispose();
    _fly.dispose();
    _fox.dispose();
    _party.dispose();
    super.dispose();
  }

  /// Neue Laternen deines Schatzes, die du noch nicht gesehen hast.
  List<Lantern> get _unseen => [
    for (final l in _lanterns)
      if (l.from != _me && (_seenAt == null || l.at.isAfter(_seenAt!))) l,
  ];

  void _maybeSendFox() {
    if (!mounted ||
        !widget.active ||
        !_lanternsLoaded ||
        !_profileLoaded ||
        _fox.isAnimating) {
      return;
    }
    final unseen = _unseen;
    if (unseen.isEmpty) return;
    final sync = unseen.any((l) => LanternService.isSync(l, _lanterns));
    setState(() {
      _foxLanternId = unseen.first.id;
      _foxCount = unseen.length;
    });
    // Sofort als gesehen merken, damit der Fuchs nicht zweimal kommt.
    _seenAt = DateTime.now();
    _service.markSeen();
    _fox.forward(from: 0).then((_) {
      if (!mounted) return;
      setState(() => _foxLanternId = null);
      if (sync) _celebrate();
    });
  }

  Future<void> _send() async {
    if (_fly.isAnimating) return;
    HapticFeedback.mediumImpact();
    final id = _service.newId(_coupleId);
    final partnerJustSent = _lanterns.any(
      (l) =>
          l.from != _me &&
          DateTime.now().difference(l.at) <= LanternService.syncWindow,
    );
    setState(() => _flyingId = id);
    final saving = _service.send(_coupleId, id);
    await _fly.forward(from: 0);
    if (!mounted) return;
    setState(() => _flyingId = null);
    if (partnerJustSent) _celebrate();
    try {
      await saving;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Nicht gesendet: $e')));
      }
    }
  }

  void _celebrate() {
    HapticFeedback.heavyImpact();
    _party.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.couple.partnerUid == null) return const SizedBox.shrink();
    final partner = widget.couple.partnerLabel;
    final syncCount = _syncMoments(_lanterns);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Kitsune.paper.withValues(alpha: 0.18)),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Kitsune.deeper, Kitsune.night],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _skyHeight,
            child: LayoutBuilder(
              builder: (context, box) {
                final size = Size(box.maxWidth, _skyHeight);
                final hidden = {?_flyingId, ?_foxLanternId};
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Sterne und Mond: einmal gemalt, bleiben stehen.
                    const Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(painter: _StarsPainter()),
                      ),
                    ),
                    // Laternen in 3 Gruppen. Jede Gruppe wird nur neu gemalt,
                    // wenn sich Laternen ändern; das Schweben verschiebt nur
                    // die fertige Ebene (kostet fast nichts).
                    for (var g = 0; g < _SkyPainter.groups; g++)
                      Positioned.fill(
                        child: AnimatedBuilder(
                          animation: _float,
                          builder: (context, child) => Transform.translate(
                            offset: Offset(
                              0,
                              math.sin(
                                    (_float.value + g / _SkyPainter.groups) *
                                        2 *
                                        math.pi,
                                  ) *
                                  2.2,
                            ),
                            child: child,
                          ),
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _SkyPainter(
                                lanterns: _lanterns,
                                me: _me,
                                hidden: hidden,
                                group: g,
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Titel oben links.
                    Positioned(
                      left: 14,
                      top: 10,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'とうろう',
                            style: AppTheme.serif(
                              size: 10,
                              weight: FontWeight.w600,
                              color: Kitsune.aqua,
                            ).copyWith(letterSpacing: 3),
                          ),
                          Text(
                            'Unser Laternenhimmel',
                            style: AppTheme.serif(size: 17).copyWith(
                              shadows: const [
                                Shadow(color: Kitsune.deeper, blurRadius: 8),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Aufsteigende Laterne, Fuchs-Bote, Feuerwerk: nur diese
                    // Ebene läuft mit, und nur solange etwas passiert.
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_fly, _fox, _party]),
                          builder: (context, _) => Stack(
                            clipBehavior: Clip.none,
                            children: [
                              if (_flyingId case final id?)
                                _flyingLantern(size, id),
                              if (_foxLanternId case final id?)
                                ..._foxRun(size, id),
                              if (_party.isAnimating)
                                ..._fireworks(size, partner),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _lanterns.isEmpty
                            ? 'Lass die erste Laterne steigen'
                            : '${_lanterns.length} '
                                  '${_lanterns.length == 1 ? 'Laterne' : 'Laternen'}'
                                  '${syncCount > 0 ? ' · $syncCount× gleichzeitig ✨' : ''}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Kitsune.paper,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const _Dot(color: Kitsune.lantern),
                          const Text(
                            ' du   ',
                            style: TextStyle(fontSize: 11, color: Kitsune.mist),
                          ),
                          const _Dot(color: Kitsune.aqua),
                          Flexible(
                            child: Text(
                              ' $partner',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Kitsune.mist,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PressScale(
                  child: _SendButton(
                    onTap: _send,
                    label: 'Laterne für $partner steigen lassen',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Wie viele Gleichzeitig-Momente gab es? (Jedes Paar nur einmal gezählt.)
  int _syncMoments(List<Lantern> all) {
    final sorted = [...all]..sort((a, b) => a.at.compareTo(b.at));
    var count = 0;
    DateTime? lastMoment;
    for (var i = 1; i < sorted.length; i++) {
      final a = sorted[i - 1], b = sorted[i];
      if (a.from != b.from &&
          b.at.difference(a.at) <= LanternService.syncWindow &&
          (lastMoment == null ||
              a.at.difference(lastMoment) > LanternService.syncWindow)) {
        count++;
        lastMoment = b.at;
      }
    }
    return count;
  }

  /// Eigene Laterne steigt vom Knopf unten rechts zu ihrem Platz am Himmel.
  Widget _flyingLantern(Size size, String id) {
    final t = Curves.easeInOutCubic.transform(_fly.value);
    final target = _SkyPainter.positionOf(id, size);
    final start = Offset(size.width - 36, size.height + 30);
    // Leicht geschwungene Bahn: seitliches Pendeln beim Aufsteigen.
    final sway = math.sin(_fly.value * math.pi * 3) * 10 * (1 - _fly.value);
    final pos = Offset.lerp(start, target, t)! + Offset(sway, 0);
    final scale = 1.8 - 0.8 * t;
    return Positioned(
      left: pos.dx - 12 * scale,
      top: pos.dy - 16 * scale,
      child: _LanternIcon(color: Kitsune.lantern, scale: scale, glow: 1),
    );
  }

  /// Fuchs-Bote: rennt mit der Laterne herein, lässt sie steigen, rennt weiter.
  List<Widget> _foxRun(Size size, String id) {
    final v = _fox.value;
    const foxW = 72.0, foxH = 47.0;
    final ground = size.height - foxH - 6;
    final mid = size.width / 2 - foxW / 2;
    // 0–0.3 herein, 0.3–0.6 stehen bleiben, 0.6–1 hinaus.
    double x;
    bool running;
    if (v < 0.3) {
      x = -foxW + (mid + foxW) * Curves.easeOut.transform(v / 0.3);
      running = true;
    } else if (v < 0.6) {
      x = mid;
      running = false;
    } else {
      x =
          mid +
          (size.width + foxW - mid) * Curves.easeIn.transform((v - 0.6) / 0.4);
      running = true;
    }
    final hop = running ? -(math.sin(v * math.pi * 14)).abs() * 5 : 0.0;
    final foxTop = ground + hop;
    // Maul des Fuchses (in Grafik-Koordinaten ca. 72 / 28 von 80 × 52).
    final mouth = Offset(x + foxW * 0.9, foxTop + foxH * 0.56);

    // Laterne: bis 0.38 im Maul, dann steigt sie bis 0.85 zu ihrem Platz.
    final target = _SkyPainter.positionOf(id, size);
    final lift = ((v - 0.38) / 0.47).clamp(0.0, 1.0);
    final lt = Curves.easeInOut.transform(lift);
    final lanternPos = lift == 0
        ? mouth + const Offset(0, 6)
        : Offset.lerp(mouth, target, lt)! +
              Offset(math.sin(lift * math.pi * 3) * 8 * (1 - lift), 0);
    final lanternScale = 1.1 - 0.1 * lt;

    final textOpacity = v < 0.08
        ? v / 0.08
        : v > 0.88
        ? (1 - v) / 0.12
        : 1.0;
    final who = widget.couple.partnerLabel;
    return [
      Positioned(
        left: x,
        top: foxTop,
        child: SvgPicture.asset(
          'assets/kitsune/foxrunner.svg',
          width: foxW,
          height: foxH,
          semanticsLabel: 'Ein Fuchs bringt eine Laterne von $who',
        ),
      ),
      Positioned(
        left: lanternPos.dx - 12 * lanternScale,
        top: lanternPos.dy - 16 * lanternScale,
        child: _LanternIcon(
          color: Kitsune.aqua,
          scale: lanternScale,
          glow: lift,
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: 54,
        child: Opacity(
          opacity: textOpacity.clamp(0.0, 1.0),
          child: Center(
            child: _Bubble(
              text: _foxCount > 1
                  ? '$who hat $_foxCount× an dich gedacht 🏮'
                  : '$who hat an dich gedacht 🏮',
            ),
          ),
        ),
      ),
    ];
  }

  /// Feuerwerk über den ganzen Himmel plus Text.
  List<Widget> _fireworks(Size size, String partner) {
    final v = _party.value;
    final textOpacity = v < 0.1
        ? v / 0.1
        : v > 0.85
        ? (1 - v) / 0.15
        : 1.0;
    return [
      Positioned.fill(
        child: IgnorePointer(child: CustomPaint(painter: _FireworkPainter(v))),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: 54,
        child: Opacity(
          opacity: textOpacity.clamp(0.0, 1.0),
          child: const Center(
            child: _Bubble(text: '✨ Ihr habt gleichzeitig aneinander gedacht'),
          ),
        ),
      ),
    ];
  }
}

/// Runder roter Knopf mit Laterne – Antippen lässt eine Laterne steigen.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      button: true,
      label: label,
      child: Material(
        color: Kitsune.lantern,
        shape: const CircleBorder(
          side: BorderSide(color: Kitsune.paper, width: 2),
        ),
        elevation: 6,
        shadowColor: Colors.black54,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Center(
              child: _LanternIcon(color: Kitsune.paper, scale: 1, glow: 0),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Kleine Papierlaterne (24 × 32 bei scale 1), optional mit Leuchten.
class _LanternIcon extends StatelessWidget {
  const _LanternIcon({
    required this.color,
    required this.scale,
    required this.glow,
  });

  final Color color;
  final double scale;
  final double glow; // 0 = kein Schein, 1 = voller Schein

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(24 * scale, 32 * scale),
    painter: _LanternIconPainter(color, glow),
  );
}

class _LanternIconPainter extends CustomPainter {
  _LanternIconPainter(this.color, this.glow);

  final Color color;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.save();
    canvas.scale(s);
    _paintLantern(canvas, const Offset(12, 17), color, 1, glow);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LanternIconPainter old) =>
      old.color != color || old.glow != glow;
}

/// Zeichnet eine Laterne mit Mittelpunkt [c]; Grundgrösse ca. 14 × 18 bei [size] 1.
void _paintLantern(
  Canvas canvas,
  Offset c,
  Color color,
  double size,
  double glow,
) {
  if (glow > 0) {
    canvas.drawCircle(
      c,
      16 * size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.45 * glow),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: 16 * size)),
    );
  }
  final body = RRect.fromRectAndRadius(
    Rect.fromCenter(center: c, width: 14 * size, height: 16 * size),
    Radius.circular(6 * size),
  );
  canvas.drawRRect(body, Paint()..color = color);
  // Rippen der Papierlaterne.
  final rib = Paint()
    ..color = Kitsune.deeper.withValues(alpha: 0.25)
    ..strokeWidth = 0.8 * size;
  for (final dy in [-3.5, 0.0, 3.5]) {
    canvas.drawLine(
      c + Offset(-6 * size, dy * size),
      c + Offset(6 * size, dy * size),
      rib,
    );
  }
  // Deckel oben und unten.
  final cap = Paint()..color = Kitsune.deeper;
  canvas.drawRect(
    Rect.fromCenter(
      center: c + Offset(0, -8.5 * size),
      width: 8 * size,
      height: 2.4 * size,
    ),
    cap,
  );
  canvas.drawRect(
    Rect.fromCenter(
      center: c + Offset(0, 8.5 * size),
      width: 8 * size,
      height: 2.4 * size,
    ),
    cap,
  );
}

/// Sterne und Mondsichel – ändern sich nie, werden nur einmal gemalt.
class _StarsPainter extends CustomPainter {
  const _StarsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final star = Paint();
    for (var i = 0; i < 40; i++) {
      final p = Offset(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
      );
      final r = 0.6 + rnd.nextDouble() * 0.8;
      canvas.drawCircle(
        p,
        r,
        star
          ..color = Kitsune.paper.withValues(
            alpha: 0.25 + 0.35 * rnd.nextDouble(),
          ),
      );
    }
    final moon = Offset(size.width - 34, 28);
    canvas.drawCircle(moon, 13, Paint()..color = Kitsune.paper);
    canvas.drawCircle(
      moon + const Offset(-6, -4),
      12,
      Paint()..color = Kitsune.deeper,
    );
  }

  @override
  bool shouldRepaint(_StarsPainter old) => false;
}

/// Eine von [groups] Laternen-Gruppen (Laterne Nr. i gehört zu Gruppe i % groups).
/// Wird nur neu gemalt, wenn sich die Laternen oder die versteckten ändern.
class _SkyPainter extends CustomPainter {
  _SkyPainter({
    required this.lanterns,
    required this.me,
    required this.hidden,
    required this.group,
  });

  final List<Lantern> lanterns;
  final String me;
  final Set<String> hidden;
  final int group;

  static const groups = 3;

  /// Höchstens so viele Laternen zeichnen (die neuesten).
  static const _maxDrawn = 120;

  /// Fester Platz am Himmel für eine Laterne, aus ihrer ID berechnet –
  /// so steht jede Laterne bei euch beiden an derselben Stelle.
  static Offset positionOf(String id, Size size) {
    var h = 0;
    for (final c in id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    final rx = (h % 1000) / 1000;
    final ry = ((h ~/ 1000) % 1000) / 1000;
    // Oben links ist der Titel, unten bleibt Platz für Fuchs und Knopf.
    final x = 16 + rx * (size.width - 32);
    var y = 18 + ry * (size.height * 0.62);
    if (x < 190 && y < 52) y += 40;
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Älteste zuerst, damit neue obenauf liegen; neuere etwas grösser und heller.
    final drawn = lanterns.take(_maxDrawn).toList().reversed.toList();
    for (var i = 0; i < drawn.length; i++) {
      final l = drawn[i];
      if (i % groups != group || hidden.contains(l.id)) continue;
      final fresh = (i + 1) / drawn.length;
      _paintLantern(
        canvas,
        positionOf(l.id, size),
        l.from == me ? Kitsune.lantern : Kitsune.aqua,
        0.55 + 0.25 * fresh,
        0.5 + 0.5 * fresh,
      );
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) =>
      !identical(old.lanterns, lanterns) ||
      old.me != me ||
      old.group != group ||
      old.hidden.length != hidden.length ||
      !old.hidden.containsAll(hidden);
}

/// Drei Feuerwerks-Blüten nacheinander in Laternenrot, Aqua und Papier.
class _FireworkPainter extends CustomPainter {
  _FireworkPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const bursts = [
      (0.25, 0.35, 0.0, Kitsune.lantern),
      (0.72, 0.30, 0.18, Kitsune.aqua),
      (0.50, 0.55, 0.36, Kitsune.paper),
      (0.15, 0.62, 0.50, Kitsune.aqua),
      (0.85, 0.60, 0.58, Kitsune.lantern),
    ];
    for (final (bx, by, start, color) in bursts) {
      final local = ((t - start) / 0.45).clamp(0.0, 1.0);
      if (local == 0 || local == 1) continue;
      final center = Offset(bx * size.width, by * size.height);
      final radius = Curves.easeOutCubic.transform(local) * 58;
      final fade = local < 0.6 ? 1.0 : 1 - (local - 0.6) / 0.4;
      // Leuchtender Kern am Anfang.
      if (local < 0.35) {
        final flash = 1 - local / 0.35;
        canvas.drawCircle(
          center,
          22 * flash + 4,
          Paint()
            ..shader = RadialGradient(
              colors: [
                Kitsune.paper.withValues(alpha: flash),
                color.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromCircle(center: center, radius: 26)),
        );
      }
      final ray = Paint()
        ..color = color.withValues(alpha: fade)
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round;
      final spark = Paint()..color = Kitsune.paper.withValues(alpha: fade);
      for (var k = 0; k < 18; k++) {
        final a = k / 18 * 2 * math.pi + start * 7;
        final dir = Offset(math.cos(a), math.sin(a));
        // Funken sinken am Ende leicht nach unten.
        final sag = Offset(0, local * local * 14);
        canvas.drawLine(
          center + dir * radius * 0.62 + sag,
          center + dir * radius + sag,
          ray,
        );
        canvas.drawCircle(center + dir * (radius + 5) + sag, 1.8, spark);
      }
    }
  }

  @override
  bool shouldRepaint(_FireworkPainter old) => old.t != t;
}

/// Kleine Papier-Sprechblase für Hinweise im Himmel.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Kitsune.paper,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Kitsune.deep, width: 1.5),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Kitsune.night, fontSize: 13),
    ),
  );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
