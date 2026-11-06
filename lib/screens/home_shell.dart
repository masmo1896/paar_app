import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/couple_service.dart';
import '../services/push_service.dart';
import '../theme.dart';
import '../widgets/fox_visit.dart';
import '../widgets/hidden_kanji.dart';
import '../widgets/motion.dart';
import '../widgets/who.dart';
import 'calendar_screen.dart';
import 'chat_screen.dart';
import 'home_screen.dart';
import 'todo_screen.dart';
import 'us_screen.dart';

/// Hauptbildschirm mit der Navigationsleiste unten: Home, Chat, Kalender, To-dos, Wir.
/// Countdowns erreichst du über die Home-Seite, die Alben über die Wir-Seite.
/// Alle Bereiche bleiben im Hintergrund geöffnet, so verlierst du beim Wechseln
/// weder deine Scrollposition noch einen angefangenen Text.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.coupleId});

  final String coupleId;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  int _previousTab = 0; // Home
  final _myUid = FirebaseAuth.instance.currentUser!.uid;
  final _myProfile = CoupleService.instance.myProfileStream();

  @override
  void initState() {
    super.initState();
    final push = PushService.instance;
    push.startIfEnabled();
    push.requestedTab.addListener(_openRequestedTab);
    WidgetsBinding.instance.addObserver(this);
    // Kopfzeilen-Bilder im Hintergrund vorladen (flüssige Seitenwechsel).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => KitsuneArt.precacheAll(),
    );
    // Ist die App offen, zeigen wir bewusst keinen eigenen Hinweis – Benachrichtigungen
    // erscheinen nur als normale System-Mitteilung, wenn die App im Hintergrund ist.
    // Falls die App durch eine Benachrichtigung gestartet wurde, noch bevor wir lauschten.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openRequestedTab());
  }

  // Akku: Im Hintergrund die Live-Verbindung zur Datenbank trennen. Sonst hält
  // die App die ganze Nacht Verbindungen offen. Benachrichtigungen kommen
  // trotzdem (die laufen über Google, nicht über diese Verbindung).
  // Aber erst nach einer Gnadenfrist und wenn alles Gesendete angekommen ist –
  // sonst bliebe eine Nachricht hängen, wenn man direkt danach sperrt.
  Timer? _offlineTimer;
  bool _offline = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final db = FirebaseFirestore.instance;
    if (state == AppLifecycleState.paused) {
      _offlineTimer?.cancel();
      _offlineTimer = Timer(const Duration(seconds: 20), () async {
        try {
          await db.waitForPendingWrites().timeout(const Duration(seconds: 40));
        } catch (_) {
          // Ohne Netz kommt es eh nicht an – dann bleibt es in der Warteschlange.
        }
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.paused) {
          _offline = true;
          await db.disableNetwork();
        }
      });
    } else if (state == AppLifecycleState.resumed) {
      _offlineTimer?.cancel();
      if (_offline) {
        _offline = false;
        db.enableNetwork();
      }
    }
  }

  @override
  void dispose() {
    _offlineTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    PushService.instance.requestedTab.removeListener(_openRequestedTab);
    super.dispose();
  }

  void _openRequestedTab() {
    final tab = PushService.instance.requestedTab.value;
    if (tab == null) return;
    PushService.instance.requestedTab.value = null;
    if (mounted) _open(tab);
  }

  @override
  Widget build(BuildContext context) {
    // Name und uid der anderen Person brauchen To-dos und Kalender für "Du / Name / Beide".
    return StreamBuilder<Map<String, dynamic>?>(
      stream: CoupleService.instance.partnerStream(widget.coupleId),
      builder: (context, snap) {
        final partner = snap.data;
        return StreamBuilder<Map<String, dynamic>?>(
          stream: _myProfile,
          builder: (context, me) => _scaffold(
            Couple(
              coupleId: widget.coupleId,
              myUid: _myUid,
              partnerUid: partner?['uid'] as String?,
              partnerName: partner?['name'] as String?,
              myName: me.data?['name'] as String?,
            ),
          ),
        );
      },
    );
  }

  Widget _scaffold(Couple couple) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _pages(couple)),
          // Das versteckte Kanji des Tages liegt über dem aktuellen Bereich.
          Positioned.fill(
            child: HiddenKanjiLayer(couple: couple, tab: _tab),
          ),
          // Alle 15 Minuten schaut der Fuchs vom Rand herein und schickt Küsse.
          const Positioned.fill(child: FoxVisitLayer()),
        ],
      ),
      bottomNavigationBar: _KitsuneNav(selected: _tab, onSelect: _open),
    );
  }

  Widget _pages(Couple couple) {
    return IndexedStack(
      index: _tab,
      children: [
        for (final (i, page) in [
          HomeScreen(couple: couple, onOpenTab: _open, active: _tab == 0),
          ChatScreen(
            coupleId: widget.coupleId,
            active: _tab == 1,
            onBack: () => _open(_previousTab),
          ),
          CalendarScreen(couple: couple),
          TodoScreen(couple: couple),
          UsScreen(couple: couple),
        ].indexed)
          // Versteckte Bereiche: Animationen anhalten (spart Akku und
          // verhindert Ruckeln) und in eigener Ebene halten.
          TickerMode(
            enabled: i == _tab,
            child: RepaintBoundary(
              child: _TabFade(active: i == _tab, child: page),
            ),
          ),
      ],
    );
  }

  // Merkt sich den vorherigen Bereich für den Zurück-Knopf im Chat.
  void _open(int tab) {
    if (tab == _tab) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      if (_tab != 1) _previousTab = _tab;
      _tab = tab;
    });
  }
}

/// Navigation wie im Mockup: feine Strich-Symbole (Torii für Home), aktive Seite in
/// Creme mit rotem Punkt darunter, die anderen in gedämpftem Blau.
class _KitsuneNav extends StatelessWidget {
  const _KitsuneNav({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  static const _items = [
    (
      'Home',
      '<path d="M2 5c6 1.5 14 1.5 20 0M4 9h16M7 6v14M17 6v14" stroke-linecap="round"/>',
    ),
    ('Chat', '<path d="M4 5h16v11H9l-5 4z" stroke-linejoin="round"/>'),
    (
      'Kalender',
      '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4M16 3v4" stroke-linecap="round"/>',
    ),
    (
      'To-dos',
      '<path d="M9 6h11M9 12h11M9 18h11M3.5 6l1.5 1.5L7.5 5M3.5 12l1.5 1.5 2.5-2.5M4 18h2" stroke-linecap="round" stroke-linejoin="round"/>',
    ),
    (
      'Wir',
      '<path d="M12 20s-7-4.6-7-10a4 4 0 017-2.6A4 4 0 0119 10c0 5.4-7 10-7 10z" stroke-linejoin="round"/>',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Kitsune.deep,
        border: Border(top: BorderSide(color: Color(0x40F3EBD3))),
      ),
      padding: EdgeInsets.fromLTRB(
        6,
        6,
        6,
        6 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: Semantics(
                selected: i == selected,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelect(i),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 4),
                        // Aktives Symbol hebt sich sanft an und wird etwas grösser.
                        AnimatedSlide(
                          offset: i == selected
                              ? const Offset(0, -0.12)
                              : Offset.zero,
                          duration: const Duration(milliseconds: 220),
                          curve: motionCurve,
                          child: AnimatedScale(
                            scale: i == selected ? 1.1 : 1,
                            duration: const Duration(milliseconds: 220),
                            curve: motionCurve,
                            child: SvgPicture.string(
                              '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
                              'fill="none" stroke="#000" stroke-width="1.8">'
                              '${_items[i].$2}</svg>',
                              width: 22,
                              height: 22,
                              colorFilter: ColorFilter.mode(
                                i == selected ? Kitsune.paper : Kitsune.dim,
                                BlendMode.srcIn,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _items[i].$1,
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 0.6,
                            color: i == selected ? Kitsune.paper : Kitsune.dim,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == selected
                                ? Kitsune.lantern
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Beim Wechsel zu einem Tab: sanft einblenden (220 ms).
class _TabFade extends StatefulWidget {
  const _TabFade({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  @override
  void didUpdateWidget(_TabFade old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !reduceMotion(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: CurvedAnimation(parent: _c, curve: motionCurve),
    child: widget.child,
  );
}
