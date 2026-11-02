import 'package:flutter/material.dart';

/// Kleine, sanfte Bewegungen für die ganze App (150–350 ms, nie aufdringlich).
/// Wer am Handy "Bewegung reduzieren" eingeschaltet hat, bekommt keine.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Weiche Kurve für alles: schnell los, sanft ankommen.
const motionCurve = Curves.easeOutCubic;

/// Blendet [child] beim ersten Erscheinen ein und lässt es ein paar Punkte
/// hochgleiten. Mit [delay] erscheinen mehrere Karten nacheinander.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 12,
    this.duration = const Duration(milliseconds: 320),
  });

  final Widget child;
  final Duration delay;
  final double offset; // so viele Punkte gleitet es hoch
  final Duration duration;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.duration);
  late final _t = CurvedAnimation(parent: _c, curve: motionCurve);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (context, child) => Opacity(
      opacity: _t.value,
      child: Transform.translate(
        offset: Offset(0, widget.offset * (1 - _t.value)),
        child: child,
      ),
    ),
    child: widget.child,
  );
}

/// Liste von Karten, die beim ersten Anzeigen nacheinander erscheinen
/// (jede 60 ms nach der vorigen).
List<Widget> staggered(List<Widget> children, {int stepMs = 60}) => [
  for (final (i, child) in children.indexed)
    FadeSlideIn(
      delay: Duration(milliseconds: i * stepMs),
      child: child,
    ),
];

/// Knopf gibt beim Drücken leicht nach (verkleinert sich auf 96 %).
/// Die eigentliche Aktion bleibt beim Kind (z. B. FilledButton).
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = 0.96});

  final Widget child;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (down != _down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _down && !reduceMotion(context) ? widget.scale : 1,
      duration: const Duration(milliseconds: 130),
      curve: motionCurve,
      child: widget.child,
    ),
  );
}

/// Zahl, die beim ersten Anzeigen (und bei Änderungen) kurz hochzählt.
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 700),
  });

  final int value;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return Text('$value', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: duration,
      curve: motionCurve,
      builder: (context, v, _) => Text('${v.round()}', style: style),
    );
  }
}

/// Seitenübergang: neue Seite blendet ein und gleitet 4 % hoch (Android).
/// Auf dem iPhone bleibt das gewohnte Wischen von links.
class SoftPageTransitionsBuilder extends PageTransitionsBuilder {
  const SoftPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion(context)) return child;
    final t = CurvedAnimation(parent: animation, curve: motionCurve);
    return FadeTransition(
      opacity: t,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(t),
        child: child,
      ),
    );
  }
}
