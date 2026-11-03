import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/couple_service.dart';
import '../services/planner_service.dart';
import '../utils/daily_magic.dart';
import '../services/lantern_service.dart';
import '../theme.dart';
import 'heart_rain.dart';
import 'sky_extras.dart';
import 'who.dart';
import 'motion.dart';
import '../services/app_logger.dart';

/// Unser Laternenhimmel: Jede Laterne heisst "Ich denk an dich" und schwebt
/// bis Mitternacht am Himmel – deine rot, die deines Schatzes aqua.
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
  Timer? _midnight;
  StreamSubscription<Map<String, dynamic>?>? _profileSub;
  var _lanterns = <Lantern>[];
  bool _lanternsLoaded = false;
  bool _profileLoaded = false;
  DateTime? _seenAt;

  // Endloses Schweben: läuft auf der echten Zeit (Sekunden seit Start), damit
  // es nie an einem Loop-Ende springt. Jede Laterne rechnet daraus ihre eigene
  // Bewegung (siehe _SkyPainter.drift).
  late final Ticker _clock = createTicker(
    (elapsed) => _time.value = elapsed.inMicroseconds / 1e6,
  );
  final _time = ValueNotifier<double>(0);

  // Tägliche Überraschungen.
  StreamSubscription<List<Countdown>>? _countdownSub;
  int? _months; // heute Monatstag? Dann so viele Monate zusammen.
  final _starActive = ValueNotifier<bool>(false);
  Timer? _starTimer;
  String? _foxSays; // Sprechblase des Tagesfuchses
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
    _subscribeToday();
    // Monatstag: aus dem jährlichen ❤️/💍-Countdown (wie auf der Wir-Seite).
    _countdownSub = PlannerService.instance.countdowns(_coupleId).listen((all) {
      final yearly = all.where((c) => c.yearly).toList()
        ..sort((a, b) {
          int score(Countdown c) => ['❤️', '💍'].contains(c.emoji) ? 0 : 1;
          return score(a).compareTo(score(b));
        });
      final months = yearly.isEmpty
          ? null
          : monthiversary(yearly.first.date, DateTime.now());
      if (months != _months && mounted) setState(() => _months = months);
    });
    _checkStar();
    _starTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkStar(),
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

  // Laternen von heute; um Mitternacht beginnt der Himmel wieder leer.
  void _subscribeToday() {
    _lanternSub?.cancel();
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
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    _midnight?.cancel();
    _midnight = Timer(
      midnight.difference(now) + const Duration(seconds: 1),
      () {
        if (!mounted) return;
        setState(() => _lanterns = const []);
        _subscribeToday();
      },
    );
  }

  // "Bewegung reduzieren" am Handy: Laternen schweben nicht.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      if (_clock.isActive) _clock.stop();
    } else if (!_clock.isActive) {
      _clock.start();
    }
  }

  @override
  void didUpdateWidget(LanternSky old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _maybeSendFox();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    _countdownSub?.cancel();
    _starTimer?.cancel();
    _starActive.dispose();
    _lanternSub?.cancel();
    _profileSub?.cancel();
    _clock.dispose();
    _time.dispose();
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
    final unseenIds = {for (final l in unseen) l.id};
    final sync = LanternService.addsSyncMoment([
      for (final l in _lanterns)
        if (!unseenIds.contains(l.id)) l,
    ], unseen);
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
    final partnerJustSent = LanternService.addsSyncMoment(_lanterns, [
      Lantern(id: id, from: _me, at: DateTime.now()),
    ]);
    setState(() => _flyingId = id);
    final saving = _service.send(_coupleId, id);
    if (isGoldenLantern(id)) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '✨ Eine goldene Laterne! Das passiert nur etwa jedes 50. Mal.',
          ),
        ),
      );
    }
    await _fly.forward(from: 0);
    if (!mounted) return;
    setState(() => _flyingId = null);
    if (partnerJustSent) _celebrate();
    try {
      await saving;
    } catch (e, s) {
      AppLogger.error(e, s, where: 'Laterne senden');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Nicht gesendet: $e')));
      }
    }
  }

  // ---- Sternschnuppe: ab ihrer Tageszeit, bis jemand sie hier fängt ----

  String get _starKey => 'star_caught_${dayKey(DateTime.now())}';

  Future<void> _checkStar() async {
    final now = DateTime.now();
    var caught = false;
    try {
      caught =
          (await SharedPreferences.getInstance()).getBool(_starKey) ?? false;
    } catch (_) {}
    final active = !caught && !now.isBefore(shootingStarTime(now, _coupleId));
    if (mounted) _starActive.value = active;
  }

  Future<void> _tapSky() async {
    if (!_starActive.value || !ShootingStarPainter.flying(_time.value)) return;
    _starActive.value = false;
    HapticFeedback.heavyImpact();
    await showFormSheet<void>(
      context,
      (_) => WishSheet(
        partner: widget.couple.partnerLabel,
        onSend: (wish) async {
          // Erst jetzt gilt sie als gefangen (Fenster nur zu = sie kommt wieder).
          try {
            await (await SharedPreferences.getInstance()).setBool(
              _starKey,
              true,
            );
          } catch (_) {}
          try {
            await CoupleService.instance.sendMessage(
              _coupleId,
              wish == null
                  ? '🌠 Ich habe eine Sternschnuppe gefangen und mir '
                        'heimlich etwas für uns gewünscht ✨'
                  : '🌠 Ich habe eine Sternschnuppe gefangen und wünsche '
                        'mir: $wish',
            );
          } catch (e, s) {
            AppLogger.error(e, s, where: 'Sternschnuppe: Wunsch senden');
          }
        },
      ),
    );
    await _checkStar();
  }

  void _tapFox() {
    final outfit = foxOutfitFor(DateTime.now());
    HapticFeedback.selectionClick();
    setState(() => _foxSays = 'Heute trage ich ${outfit.label} 🦊');
    Future<void>.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _foxSays = null);
    });
  }

  void _showMoon() {
    final now = DateTime.now();
    final pct = (moonIllumination(now) * 100).round();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            isFullMoon(now)
                ? '🌕 Heute ist Vollmond – schaut beide hoch!'
                : '🌙 Heute: ${moonName(now)} ($pct % beleuchtet)',
          ),
        ),
      );
  }

  void _celebrate() {
    HapticFeedback.heavyImpact();
    _party.forward(from: 0);
    // Herzen über den ganzen Bildschirm.
    HeartRain.show(context);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.couple.partnerUid == null) return const SizedBox.shrink();
    final partner = widget.couple.partnerLabel;
    final syncCount = LanternService.syncMoments(_lanterns);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Kitsune.paper.withValues(alpha: 0.18)),
        // Am Monatstag färbt sich der Himmel rosa.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _months != null
              ? const [Color(0xFF3B1640), Color(0xFF5A2350)]
              : const [Kitsune.deeper, Kitsune.night],
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
                    // Sterne: einmal gemalt, bleiben stehen.
                    const Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(painter: _StarsPainter()),
                      ),
                    ),
                    // Der echte Mond von heute; antippen zeigt die Phase.
                    Positioned(
                      right: 14,
                      top: 8,
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: _showMoon,
                        child: CustomPaint(
                          painter: MoonPainter(
                            phase: moonPhase(DateTime.now()),
                            center: const Offset(20, 20),
                          ),
                        ),
                      ),
                    ),
                    if (_months != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(painter: PetalPainter(_time)),
                          ),
                        ),
                      ),
                    // Alle Laternen in einer Ebene; nur diese wird pro Bild
                    // neu gemalt (RepaintBoundary), der Rest bleibt ruhig.
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _SkyPainter(
                            lanterns: _lanterns,
                            me: _me,
                            hidden: hidden,
                            time: _time,
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
                    // Sternschnuppe: Antippen des Himmels, während sie fliegt.
                    // Nur aktiv, solange es heute eine gibt (sonst bleibt z. B.
                    // der Mond antippbar).
                    Positioned.fill(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _starActive,
                        builder: (context, active, child) => GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: active ? _tapSky : null,
                          child: child,
                        ),
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: ShootingStarPainter(
                              _time,
                              active: _starActive,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Fuchs des Tages lugt unten links hervor.
                    if (_foxLanternId == null)
                      Positioned(
                        left: 12,
                        bottom: -10,
                        child: GestureDetector(
                          onTap: _tapFox,
                          child: DailyFox(
                            outfit: foxOutfitFor(DateTime.now()),
                            time: _time,
                          ),
                        ),
                      ),
                    if (_foxSays case final text?)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 40,
                        child: Center(child: _Bubble(text: text)),
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
                        _months != null
                            ? '🌸 Heute: $_months Monate zusammen'
                            : _lanterns.isEmpty
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

  /// Eigene Laterne steigt vom Knopf unten rechts zu ihrem Platz am Himmel.
  Widget _flyingLantern(Size size, String id) {
    final v = _fly.value;
    // Weich los, weich an; landet genau dort, wo sie danach weiterschwebt.
    final t = _riseCurve.transform(v);
    final target =
        _SkyPainter.positionOf(id, size) + _SkyPainter.drift(id, _time.value);
    final start = Offset(size.width - 36, size.height + 30);
    // Leicht geschwungene Bahn, die zum Ende hin ausklingt.
    final sway = math.sin(v * math.pi * 2.5) * 12 * (1 - t);
    final pos = Offset.lerp(start, target, t)! + Offset(sway, 0);
    // Endgrösse = Grösse der neuesten Laterne am Himmel (kein Aufploppen).
    final scale = 1.8 - (1.8 - _SkyPainter.newestSize) * t;
    return Positioned(
      left: pos.dx - 12 * scale,
      top: pos.dy - 17 * scale,
      child: Transform.rotate(
        angle: math.cos(v * math.pi * 2.5) * 0.12 * (1 - t),
        child: _LanternIcon(
          color: isGoldenLantern(id) ? lanternGold : Kitsune.lantern,
          scale: scale,
          glow: 1,
        ),
      ),
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
    final target =
        _SkyPainter.positionOf(id, size) + _SkyPainter.drift(id, _time.value);
    final lift = ((v - 0.38) / 0.47).clamp(0.0, 1.0);
    final lt = _riseCurve.transform(lift);
    final lanternPos = lift == 0
        ? mouth + const Offset(0, 6)
        : Offset.lerp(mouth, target, lt)! +
              Offset(math.sin(lift * math.pi * 3) * 8 * (1 - lift), 0);
    final lanternScale = 1.1 - (1.1 - _SkyPainter.newestSize) * lt;

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
        top: lanternPos.dy - 17 * lanternScale,
        child: _LanternIcon(
          color: isGoldenLantern(id) ? lanternGold : Kitsune.aqua,
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

final _glowShaders = <Color, Shader>{};

Shader _glowShader(Color color) => _glowShaders.putIfAbsent(
  color,
  () => RadialGradient(
    colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0)],
  ).createShader(Rect.fromCircle(center: Offset.zero, radius: 16)),
);

/// Weich los, weich an – ohne Knick (für aufsteigende Laternen).
const _riseCurve = Cubic(0.45, 0.05, 0.2, 1.0);

/// Zeichnet eine Laterne mit Mittelpunkt [c]; Grundgrösse ca. 14 × 18 bei [size] 1.
void _paintLantern(
  Canvas canvas,
  Offset c,
  Color color,
  double size,
  double glow,
) {
  if (glow > 0) {
    // Schein: ein fertiger Verlauf je Farbe (einmal erzeugt), nur verschoben
    // und skaliert – günstig, auch bei vielen Laternen in jedem Bild.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(size);
    canvas.drawCircle(
      Offset.zero,
      16,
      Paint()
        ..shader = _glowShader(color)
        ..color = Color.fromRGBO(0, 0, 0, glow.clamp(0.0, 1.0)),
    );
    canvas.restore();
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

/// Sterne – ändern sich nie, werden nur einmal gemalt (Mond: MoonPainter).
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
  }

  @override
  bool shouldRepaint(_StarsPainter old) => false;
}

/// Alle Laternen am Himmel. Jede schwebt endlos auf ihrer eigenen Bahn:
/// ruhiges Auf und Ab, leichtes Pendeln und flackerndes Licht – mit eigenem
/// Tempo und Versatz aus ihrer ID, damit nichts im Gleichschritt läuft.
class _SkyPainter extends CustomPainter {
  _SkyPainter({
    required this.lanterns,
    required this.me,
    required this.hidden,
    required this.time,
  }) : super(repaint: time);

  final List<Lantern> lanterns;
  final String me;
  final Set<String> hidden;
  final ValueListenable<double> time;

  /// Höchstens so viele Laternen zeichnen (die neuesten).
  static const _maxDrawn = 120;

  /// Grösse der neuesten Laterne (ältere sind etwas kleiner).
  static const newestSize = 0.8;

  static int _hash(String id) {
    var h = 0;
    for (final c in id.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  // Zufallszahl 0–1 aus der ID, für Tempo und Versatz je Laterne.
  static double _r(int h, int salt) =>
      ((h ~/ (salt * 7 + 3) + salt * 977) % 1000) / 1000;

  /// Fester Platz am Himmel für eine Laterne, aus ihrer ID berechnet –
  /// so steht jede Laterne bei euch beiden an derselben Stelle.
  static Offset positionOf(String id, Size size) {
    final h = _hash(id);
    final rx = (h % 1000) / 1000;
    final ry = ((h ~/ 1000) % 1000) / 1000;
    // Oben links ist der Titel, unten bleibt Platz für Fuchs und Knopf.
    final x = 16 + rx * (size.width - 32);
    var y = 18 + ry * (size.height * 0.62);
    if (x < 190 && y < 52) y += 40;
    return Offset(x, y);
  }

  /// Schwebe-Versatz zur Zeit [t] (Sekunden): langsames Auf und Ab (5–8 s)
  /// und seitliches Treiben (8–14 s). Reiner Sinus der Zeit → nahtlos endlos.
  static Offset drift(String id, double t) {
    final h = _hash(id);
    const tau = 2 * math.pi;
    final bob = math.sin(tau * (0.12 + 0.07 * _r(h, 1)) * t + tau * _r(h, 2));
    final side = math.sin(tau * (0.07 + 0.05 * _r(h, 3)) * t + tau * _r(h, 4));
    return Offset(side * (1.5 + 1.5 * _r(h, 5)), bob * (3 + 2.5 * _r(h, 6)));
  }

  /// Leichtes Pendeln um den oberen Deckel (Bogenmass).
  static double _tilt(String id, double t) {
    final h = _hash(id);
    return math.sin(
          2 * math.pi * (0.15 + 0.1 * _r(h, 7)) * t + 2 * math.pi * _r(h, 8),
        ) *
        (0.05 + 0.04 * _r(h, 9));
  }

  /// Sanftes Flackern des Lichts (0.78–1.0), zwei überlagerte Wellen.
  static double _flicker(String id, double t) {
    final h = _hash(id);
    final a = math.sin(2 * math.pi * 0.8 * t + 6 * _r(h, 10));
    final b = math.sin(2 * math.pi * 2.1 * t + 6 * _r(h, 11));
    return 0.89 + 0.07 * a + 0.04 * b;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    // Älteste zuerst, damit neue obenauf liegen; neuere etwas grösser und heller.
    final drawn = lanterns.take(_maxDrawn).toList().reversed.toList();
    for (var i = 0; i < drawn.length; i++) {
      final l = drawn[i];
      if (hidden.contains(l.id)) continue;
      final fresh = (i + 1) / drawn.length;
      final scale = newestSize - 0.25 + 0.25 * fresh;
      final c = positionOf(l.id, size) + drift(l.id, t);
      canvas.save();
      // Drehen um den oberen Deckel, damit es wie Pendeln aussieht.
      final pivot = c + Offset(0, -8.5 * scale);
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(_tilt(l.id, t));
      canvas.translate(-pivot.dx, -pivot.dy);
      _paintLantern(
        canvas,
        c,
        isGoldenLantern(l.id)
            ? lanternGold
            : l.from == me
            ? Kitsune.lantern
            : Kitsune.aqua,
        scale,
        (0.5 + 0.5 * fresh) * _flicker(l.id, t),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) =>
      !identical(old.lanterns, lanterns) ||
      old.me != me ||
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
