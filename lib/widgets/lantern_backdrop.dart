import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

// Gemeinsamer Hintergrund von Home und Kreuzworträtsel.

/// Grosse Laternen-Illustration im Hintergrund: oben kräftig, nach unten weich
/// ausgeblendet (läuft subtil hinter die Karten). Beim Scrollen wandert sie nur
/// mit 45 % der Geschwindigkeit mit – das gibt Tiefe. Eigene Ebene, damit das
/// Verschieben nichts neu malen muss.
class LanternBackdrop extends StatelessWidget {
  const LanternBackdrop({super.key, required this.scroll});

  final ScrollController scroll;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: scroll,
    builder: (context, child) {
      final offset = scroll.hasClients ? math.max(0.0, scroll.offset) : 0.0;
      return Transform.translate(
        offset: Offset(0, -offset * 0.45),
        child: child,
      );
    },
    child: RepaintBoundary(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            Colors.white,
            Color(0x66FFFFFF),
            Colors.transparent,
          ],
          stops: [0, 0.5, 0.78, 1],
        ).createShader(rect),
        child: SvgPicture.asset(
          KitsuneArt.lanterns.asset,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
        ),
      ),
    ),
  );
}
