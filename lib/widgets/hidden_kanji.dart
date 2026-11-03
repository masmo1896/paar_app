import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_logger.dart';
import '../services/egg_service.dart';
import '../theme.dart';
import '../utils/daily_magic.dart';
import 'heart_rain.dart';
import 'who.dart';

/// Das versteckte Kanji des Tages: ein kleines, blasses Zeichen, jeden Tag in
/// einem anderen Bereich an anderer Stelle. Habt ihr es beide gefunden,
/// regnet es Herzen. Liegt als Ebene über den Bereichen (HomeShell).
class HiddenKanjiLayer extends StatefulWidget {
  const HiddenKanjiLayer({super.key, required this.couple, required this.tab});

  final Couple couple;

  /// Der gerade sichtbare Bereich (0 Home … 4 Wir).
  final int tab;

  @override
  State<HiddenKanjiLayer> createState() => _HiddenKanjiLayerState();
}

class _HiddenKanjiLayerState extends State<HiddenKanjiLayer> {
  bool _celebrated = false;

  String get _today => dayKey(DateTime.now());

  Future<void> _maybeCelebrate(Set<String> found) async {
    final partner = widget.couple.partnerUid;
    if (_celebrated ||
        partner == null ||
        !found.contains(widget.couple.myUid) ||
        !found.contains(partner)) {
      return;
    }
    _celebrated = true;
    // Pro Tag nur einmal feiern, auch nach einem Neustart der App.
    final key = 'kanji_party_$_today';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(key) ?? false) return;
      await prefs.setBool(key, true);
    } catch (_) {}
    if (!mounted) return;
    final k = hiddenKanji(DateTime.now(), widget.couple.coupleId);
    HeartRain.show(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Ihr habt beide ${k.char} (${kanjiMeanings[k.char]}) gefunden ✨',
        ),
      ),
    );
  }

  Future<void> _tap(Set<String> found) async {
    if (found.contains(widget.couple.myUid)) return;
    HapticFeedback.mediumImpact();
    final k = hiddenKanji(DateTime.now(), widget.couple.coupleId);
    final partnerHas = found.contains(widget.couple.partnerUid);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            partnerHas
                ? 'Gefunden: ${k.char} – ${kanjiMeanings[k.char]}'
                : 'Gefunden: ${k.char} – ${kanjiMeanings[k.char]}. '
                      'Findet ${widget.couple.partnerLabel} es auch?',
          ),
        ),
      );
    try {
      await EggService.instance.markFound(widget.couple.coupleId, _today);
    } catch (e, s) {
      AppLogger.error(e, s, where: 'Verstecktes Kanji');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.couple.partnerUid == null) return const SizedBox.shrink();
    final k = hiddenKanji(DateTime.now(), widget.couple.coupleId);
    if (k.tab != widget.tab) return const SizedBox.shrink();
    return StreamBuilder<Set<String>>(
      stream: EggService.instance.found(widget.couple.coupleId, _today),
      builder: (context, snap) {
        final found = snap.data ?? const <String>{};
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _maybeCelebrate(found),
        );
        final mine = found.contains(widget.couple.myUid);
        return LayoutBuilder(
          builder: (context, box) => Stack(
            children: [
              Positioned(
                left: box.maxWidth * k.x - 22,
                top: box.maxHeight * k.y - 22,
                child: Semantics(
                  label: mine ? 'Gefundenes Zeichen' : null,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _tap(found),
                    child: SizedBox.square(
                      dimension: 44,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          child: mine
                              ? Hanko(k.char, key: const ValueKey(1), size: 22)
                              : Transform.rotate(
                                  key: const ValueKey(0),
                                  angle: -0.2,
                                  child: Text(
                                    k.char,
                                    style: AppTheme.serif(
                                      size: 15,
                                      color: Kitsune.paper.withValues(
                                        alpha: 0.22,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
