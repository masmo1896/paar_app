import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import 'widgets/motion.dart';

// Design "Kitsune Moon": Nachtblau mit Seigaiha-Wellenmuster, cremefarbene Papierkarten
// mit feinem Innenrahmen, Laternen-Rot als Akzent, Aqua für kleine Beschriftungen.
// Überschriften in Shippori Mincho, Fliesstext in Zen Kaku Gothic New.
// Es gibt nur diese eine (dunkle) Gestaltung – hell und dunkel sehen gleich aus.
class Kitsune {
  static const night = Color(0xFF0E1F4D); // Hintergrund
  static const deep = Color(
    0xFF0A1838,
  ); // Kopfzeilen, Navigation, Eingabefelder
  static const deeper = Color(0xFF071230);
  static const indigo = Color(0xFF133174); // eigene Sprechblasen
  static const paper = Color(
    0xFFF3EBD3,
  ); // Creme: Karten und Text auf Nachtblau
  static const lantern = Color(0xFFE73162); // Akzent-Rot
  static const plum = Color(0xFF712557);
  static const aqua = Color(0xFFA6ECF2);
  static const sky = Color(0xFF5186E3);
  static const mist = Color(0xFFC8CEDF); // leiser Text auf Nachtblau
  static const dim = Color(0xFF8E9AC0); // inaktive Navigation
  static const inkSoft = Color(0xFF3A4A70); // leiser Text auf Papier
  static const hairline = Color(0x4D133174); // Innenrahmen der Papierkarten
}

class AppTheme {
  // Für die hervorgehobene Countdown-Karte: Laternen-Rot zu Pflaume.
  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Kitsune.lantern, Kitsune.plum],
  );

  static const _night = ColorScheme(
    brightness: Brightness.dark,
    primary: Kitsune.lantern,
    onPrimary: Kitsune.paper,
    primaryContainer: Kitsune.indigo, // eigene Sprechblasen, gewählte Chips
    onPrimaryContainer: Kitsune.paper,
    secondary: Kitsune.aqua,
    onSecondary: Kitsune.night,
    secondaryContainer: Kitsune.plum,
    onSecondaryContainer: Kitsune.paper,
    tertiary: Kitsune.paper, // runde Knöpfe: Creme mit nachtblauem Symbol
    onTertiary: Kitsune.deep,
    error: Color(0xFFFF8FA8),
    onError: Kitsune.deeper,
    surface: Kitsune.deep, // Blätter, Dialoge, Eingabefelder
    onSurface: Kitsune.paper,
    onSurfaceVariant: Kitsune.mist,
    surfaceContainerHighest: Color(0xFF1A2C60),
    outline: Color(0x59F3EBD3),
  );

  // Die "Papier"-Variante für cremefarbene Karten: dunkle Schrift auf Creme.
  static const _paper = ColorScheme(
    brightness: Brightness.light,
    primary: Kitsune.lantern,
    onPrimary: Kitsune.paper,
    primaryContainer: Kitsune.indigo,
    onPrimaryContainer: Kitsune.paper,
    secondary: Kitsune.plum,
    onSecondary: Kitsune.paper,
    secondaryContainer: Color(0xFFE6DCBF),
    onSecondaryContainer: Kitsune.night,
    tertiary: Kitsune.night,
    onTertiary: Kitsune.paper,
    error: Color(0xFFB0204D),
    onError: Kitsune.paper,
    surface: Kitsune.paper,
    onSurface: Kitsune.night,
    onSurfaceVariant: Kitsune.inkSoft,
    surfaceContainerHighest: Color(0xFFE6DCBF),
    outline: Kitsune.hairline,
  );

  // Nur EINMAL berechnen: jede Papierkarte fragt nach AppTheme.paper –
  // früher wurde das Theme dabei jedes Mal komplett neu gebaut.
  static final light = _build(_night);
  static final dark = light;
  static final paper = _build(_paper);

  /// Überschriften-Schrift (Shippori Mincho) für Titel und grosse Zahlen.
  static TextStyle serif({
    double size = 24,
    FontWeight weight = FontWeight.w800,
    Color? color,
    double? height,
  }) => GoogleFonts.shipporiMincho(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
  );

  /// Kleine, gesperrte Beschriftung wie "NOCH" oder "ALS NÄCHSTES".
  static TextStyle label({Color color = Kitsune.aqua, double size = 11}) =>
      GoogleFonts.zenKakuGothicNew(
        fontSize: size,
        fontWeight: FontWeight.w700,
        letterSpacing: size * 0.14,
        color: color,
      );

  static ThemeData _build(ColorScheme scheme) {
    final onPaper = scheme.brightness == Brightness.light;
    final base = ThemeData(brightness: scheme.brightness);
    final body = GoogleFonts.zenKakuGothicNewTextTheme(base.textTheme)
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    final textTheme = body.copyWith(
      headlineLarge: serif(size: 32, color: scheme.onSurface),
      headlineMedium: serif(size: 28, color: scheme.onSurface),
      headlineSmall: serif(size: 24, color: scheme.onSurface),
      titleLarge: serif(size: 21, color: scheme.onSurface),
      titleMedium: serif(size: 16, color: scheme.onSurface),
    );
    final small = BorderRadius.circular(4);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Weiche Seitenübergänge (Android); iPhone behält das gewohnte Wischen.
      // Jede weitere Seite bekommt ihr eigenes Wellenmuster als Grund, sonst
      // scheint beim Gleiten die Seite darunter durch.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: OpaquePageTransitionsBuilder(
            SoftPageTransitionsBuilder(),
          ),
          TargetPlatform.iOS: OpaquePageTransitionsBuilder(
            CupertinoPageTransitionsBuilder(),
          ),
        },
      ),
      textTheme: textTheme,
      // Das Wellenmuster wird hinter allen Bildschirmen gemalt (siehe AppBackground).
      scaffoldBackgroundColor: onPaper ? scheme.surface : Colors.transparent,
      canvasColor: scheme.surface,
      iconTheme: IconThemeData(color: scheme.onSurface),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: serif(size: 24, color: scheme.onSurface),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),
      // Papierkarte: Creme, kleine Ecken, feiner nachtblauer Innenrahmen.
      cardTheme: CardThemeData(
        color: Kitsune.paper,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: small,
          side: const BorderSide(color: Kitsune.hairline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: onPaper ? Colors.white.withValues(alpha: 0.5) : Kitsune.deep,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        labelStyle: TextStyle(color: onPaper ? Kitsune.inkSoft : Kitsune.aqua),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide(
            color: onPaper ? Kitsune.indigo : Kitsune.aqua,
            width: 1.5,
          ),
        ),
      ),
      // Hauptknopf wie "Anmelden": Creme mit Mincho-Schrift.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: onPaper ? Kitsune.night : Kitsune.paper,
          foregroundColor: onPaper ? Kitsune.paper : Kitsune.deep,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: small),
          textStyle: serif(size: 17).copyWith(letterSpacing: 1.6),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: small),
          side: BorderSide(color: scheme.outline),
          foregroundColor: scheme.onSurface,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: onPaper ? Kitsune.plum : Kitsune.aqua,
        ),
      ),
      // Runder Plus-Knopf: Laternen-Rot mit cremefarbenem Rand.
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Kitsune.lantern,
        foregroundColor: Kitsune.deep,
        elevation: 6,
        shape: CircleBorder(side: BorderSide(color: Kitsune.paper, width: 2)),
        extendedPadding: EdgeInsets.symmetric(horizontal: 22),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: onPaper ? Kitsune.paper : Kitsune.deep,
        selectedColor: onPaper ? Kitsune.night : Kitsune.paper,
        secondarySelectedColor: onPaper ? Kitsune.night : Kitsune.paper,
        checkmarkColor: onPaper ? Kitsune.paper : Kitsune.deep,
        // Gewählt: Creme mit nachtblauer Schrift (wie die Filter bei den To-dos).
        labelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(
            fontWeight: FontWeight.w700,
            color: states.contains(WidgetState.selected)
                ? (onPaper ? Kitsune.paper : Kitsune.deep)
                : scheme.onSurface,
          ),
        ),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          selectedBackgroundColor: onPaper ? Kitsune.night : Kitsune.paper,
          selectedForegroundColor: onPaper ? Kitsune.paper : Kitsune.deep,
          side: BorderSide(color: scheme.outline),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Kitsune.lantern : null,
        ),
        checkColor: const WidgetStatePropertyAll(Kitsune.paper),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Kitsune.paper : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Kitsune.lantern : null,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Kitsune.aqua,
      ),
      // Navigation unten: Nachtblau, aktive Seite in Creme, sonst gedämpftes Blau.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Kitsune.deep,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Kitsune.indigo,
        elevation: 0,
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? Kitsune.paper
                : Kitsune.dim,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => GoogleFonts.zenKakuGothicNew(
            fontSize: 11,
            letterSpacing: 0.6,
            fontWeight: FontWeight.w500,
            color: s.contains(WidgetState.selected)
                ? Kitsune.paper
                : Kitsune.dim,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Kitsune.deep,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: Kitsune.deep,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          side: BorderSide(color: Color(0x40F3EBD3)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Kitsune.deep,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: serif(size: 20, color: Kitsune.paper),
        shape: RoundedRectangleBorder(
          borderRadius: small,
          side: const BorderSide(color: Color(0x59F3EBD3)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Kitsune.deep,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: small,
          side: const BorderSide(color: Color(0x59F3EBD3)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Kitsune.paper,
        contentTextStyle: GoogleFonts.zenKakuGothicNew(color: Kitsune.night),
        actionTextColor: Kitsune.plum,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: small),
      ),
      dividerTheme: DividerThemeData(color: scheme.outline),
    );
  }
}

/// Inhalt auf cremefarbenem Papier: Schrift und Symbole darin werden dunkel.
class Paper extends StatelessWidget {
  const Paper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.paper,
    child: DefaultTextStyle.merge(
      style: const TextStyle(color: Kitsune.night),
      child: IconTheme.merge(
        data: const IconThemeData(color: Kitsune.night),
        child: child,
      ),
    ),
  );
}

/// Nachtblau mit feinem Seigaiha-Wellenmuster hinter der ganzen App.
///
/// Schnell: Das Muster wird nur EINMAL als kleine Kachel gemalt und dann als
/// Bild wiederholt (ein Zeichenschritt statt tausender Kreise). Es liegt in
/// einer eigenen Ebene (RepaintBoundary), damit Animationen darüber es nicht
/// jedes Mal neu malen.
/// Alle Bildschirme sind durchsichtig, das Wellenmuster liegt einmal ganz
/// hinten (AppBackground um die ganze App). Eine Seite, die darüber gleitet,
/// braucht aber einen deckenden Grund – sonst sieht man beide gleichzeitig.
/// Darum bekommt jede Seite ausser der ersten ihr eigenes Muster.
class OpaquePageTransitionsBuilder extends PageTransitionsBuilder {
  const OpaquePageTransitionsBuilder(this.inner);

  final PageTransitionsBuilder inner;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => inner.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    route.isFirst || !route.opaque ? child : AppBackground(child: child),
  );
}

class AppBackground extends StatefulWidget {
  const AppBackground({super.key, required this.child});

  final Widget? child;

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground> {
  // Eine Kachel pro Bildschirmdichte für alle Hintergründe (jede Seite hat einen).
  static final _shared = <double, ui.Image>{};
  ui.Image? _tile;
  double? _tileRatio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (ratio != _tileRatio) {
      _tileRatio = ratio;
      _makeTile(ratio);
    }
  }

  Future<void> _makeTile(double ratio) async {
    final cached = _shared[ratio];
    if (cached != null) {
      _tile = cached;
      return;
    }
    final tile = await _SeigaihaTile.render(ratio);
    _shared.putIfAbsent(ratio, () => tile);
    if (!identical(_shared[ratio], tile)) tile.dispose();
    if (mounted) setState(() => _tile = _shared[ratio]);
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      RepaintBoundary(
        child: CustomPaint(painter: _SeigaihaPainter(_tile, _tileRatio ?? 1)),
      ),
      ?widget.child,
    ],
  );
}

/// Eine Kachel des Musters (40 × 20 Punkte), die sich nahtlos wiederholt.
abstract final class _SeigaihaTile {
  static const w = 40.0, h = 20.0;

  static Future<ui.Image> render(double ratio) {
    // Ganze Pixel, sonst entstehen feine Nähte zwischen den Kacheln.
    final pxW = (w * ratio).round(), pxH = (h * ratio).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(pxW / w, pxH / h)
      // Aus der Mitte eines grösseren Musters ausschneiden: dort ist es
      // vollständig und wiederholt sich exakt alle 40 × 20 Punkte.
      ..translate(-2 * w, -2 * h);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 6 * w, 6 * h),
      Paint()..color = Kitsune.night,
    );
    final line = Paint()
      ..color = Kitsune.aqua.withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final cover = Paint()..color = Kitsune.night;
    // Reihe für Reihe von oben nach unten: jede Welle überdeckt die obere Hälfte der vorigen.
    var row = 0;
    for (var y = 0.0; y < 6 * h; y += h / 2, row++) {
      final shift = row.isOdd ? w / 2 : 0.0;
      for (var x = -w + shift; x < 6 * w; x += w) {
        final c = Offset(x + w / 2, y);
        canvas.drawCircle(c, 20, cover);
        for (final r in [5.5, 10.5, 15.5]) {
          canvas.drawCircle(c, r, line);
        }
      }
    }
    return recorder.endRecording().toImage(pxW, pxH);
  }
}

class _SeigaihaPainter extends CustomPainter {
  const _SeigaihaPainter(this.tile, this.ratio);

  final ui.Image? tile;
  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final tile = this.tile;
    if (tile == null) {
      canvas.drawRect(rect, Paint()..color = Kitsune.night);
      return;
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ImageShader(
          tile,
          TileMode.repeated,
          TileMode.repeated,
          // Kachel-Pixel zurück auf 40 × 20 Punkte.
          Matrix4.diagonal3Values(
            _SeigaihaTile.w / tile.width,
            _SeigaihaTile.h / tile.height,
            1,
          ).storage,
        )
        ..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_SeigaihaPainter old) =>
      old.tile != tile || old.ratio != ratio;
}

/// Bilder für die Kopfzeilen.
enum KitsuneArt {
  lanterns('assets/kitsune/lanterns.svg'),
  leaves('assets/kitsune/leaves.svg'),
  koi('assets/kitsune/koi.svg'),
  fox('assets/kitsune/fox.svg'),
  foxes('assets/kitsune/foxes.svg'),
  moonfox('assets/kitsune/moonfox.svg'),
  foxlogo('assets/kitsune/foxlogo.svg');

  const KitsuneArt(this.asset);
  final String asset;

  /// Alle Kopfzeilen-Bilder vorab laden, damit beim Öffnen einer Seite nichts
  /// erst gelesen werden muss (sonst ruckelt das erste Bild der Animation).
  static Future<void> precacheAll() async {
    for (final a in values) {
      final loader = SvgAssetLoader(a.asset);
      await svg.cache.putIfAbsent(
        loader.cacheKey(null),
        () => loader.loadBytes(null),
      );
    }
  }
}

/// Kopfzeile im Kitsune-Stil: Illustration im Hintergrund, darüber eine kleine
/// japanische Zeile in Aqua und der Titel in Mincho, links unten.
AppBar kitsuneAppBar({
  required KitsuneArt art,
  required String kana,
  Widget? title,
  String? titleText,
  List<Widget>? actions,
  Widget? leading,
  double height = 96,
  Alignment artAlignment = Alignment.topCenter,
  // true: Titel unten links im Bild, Knöpfe oben rechts (grosse Chat-Kopfzeile).
  bool titleAtBottom = false,
}) => AppBar(
  toolbarHeight: height,
  // Bei der Chat-Kopfzeile: Zurück-Knopf oben links mit dunklem runden Hintergrund.
  leading: titleAtBottom && leading != null
      ? Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Kitsune.deep.withValues(alpha: 0.75),
              ),
              child: leading,
            ),
          ),
        )
      : leading,
  actions: titleAtBottom && actions != null
      ? [
          // Dunkler runder Hintergrund, damit die Knöpfe auch vor dem Mond sichtbar sind.
          for (final a in actions)
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Kitsune.deep.withValues(alpha: 0.75),
                  ),
                  child: a,
                ),
              ),
            ),
          const SizedBox(width: 6),
        ]
      : actions,
  titleSpacing: 20,
  // Illustration oben ausgerichtet; unten weich ins Wellenmuster ausgeblendet.
  flexibleSpace: ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (rect) => const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.white, Colors.white, Colors.transparent],
      stops: [0, 0.72, 1],
    ).createShader(rect),
    child: SvgPicture.asset(
      art.asset,
      fit: BoxFit.cover,
      alignment: artAlignment,
    ),
  ),
  title: titleAtBottom && title != null
      ? SizedBox(
          height: height,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: title,
            ),
          ),
        )
      : title ??
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  kana,
                  style: AppTheme.serif(
                    size: 12,
                    weight: FontWeight.w600,
                    color: Kitsune.aqua,
                  ).copyWith(letterSpacing: 3.6),
                ),
                Text(
                  titleText ?? '',
                  style: AppTheme.serif(size: 26, color: Kitsune.paper)
                      .copyWith(
                        shadows: const [
                          Shadow(color: Kitsune.deep, blurRadius: 10),
                        ],
                      ),
                ),
              ],
            ),
);

/// Kleiner roter Stempel mit einem Schriftzeichen, leicht schräg (z. B. 済 = erledigt).
class Hanko extends StatelessWidget {
  const Hanko(this.char, {super.key, this.size = 26, this.filled = true});

  final String char;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -0.14,
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? Kitsune.lantern : null,
        borderRadius: BorderRadius.circular(filled ? 3 : size),
        border: filled ? null : Border.all(color: Kitsune.lantern, width: 1.5),
      ),
      child: Text(
        char,
        style: AppTheme.serif(
          size: size * 0.54,
          color: filled ? Kitsune.paper : Kitsune.lantern,
        ),
      ),
    ),
  );
}
