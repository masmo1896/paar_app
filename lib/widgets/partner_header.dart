import 'package:cached_network_image/cached_network_image.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/chat_media_screen.dart';
import '../services/couple_service.dart';
import '../services/push_service.dart';
import '../theme.dart';
import 'who.dart';
import '../utils/shared_stream.dart';
import '../services/app_logger.dart';

/// Rundes Profilbild; ohne Bild wird der erste Buchstabe des Namens gezeigt.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.name,
    required this.photoUrl,
    this.radius = 20,
  });

  final String name;
  final String? photoUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = photoUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.secondaryContainer,
      // Profilbild nur in Anzeigegrösse dekodieren.
      foregroundImage: url == null
          ? null
          : ResizeImage(
              CachedNetworkImageProvider(url),
              width: (radius * 2 * MediaQuery.devicePixelRatioOf(context))
                  .round(),
            ),
      child: Text(
        name.isEmpty ? '♥' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: scheme.onSecondaryContainer,
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Profilbild deines Schatzes oben in der Chat-Kopfzeile (ohne Namen, damit der
/// Header ruhig bleibt), mit hellem Papier-Ring. Antippen zeigt das Bild gross.
class PartnerPhoto extends StatelessWidget {
  const PartnerPhoto({super.key, required this.coupleId});

  final String coupleId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: CoupleService.instance.partnerStream(coupleId),
      builder: (context, snap) {
        final partner = snap.data;
        if (partner == null) return const SizedBox.shrink();
        final name = (partner['name'] as String?)?.trim();
        final displayName = name == null || name.isEmpty ? 'Dein Schatz' : name;
        final photoUrl = partner['photoUrl'] as String?;

        return Semantics(
          label: 'Profilbild von $displayName',
          button: photoUrl != null,
          child: GestureDetector(
            onTap: photoUrl == null
                ? null
                : () => _showPhoto(context, displayName, photoUrl),
            child: Container(
              width: HeaderCircle.size,
              height: HeaderCircle.size,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Kitsune.paper,
                boxShadow: [
                  BoxShadow(
                    color: Kitsune.deep.withValues(alpha: 0.6),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Avatar(
                name: displayName,
                photoUrl: photoUrl,
                radius: HeaderCircle.size / 2 - 2,
              ),
            ),
          ),
        );
      },
    );
  }

  void _showPhoto(BuildContext context, String name, String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Image.network(
                url,
                fit: BoxFit.cover,
                semanticLabel: 'Profilbild von $name',
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(name, style: Theme.of(context).textTheme.titleMedium),
            ),
          ],
        ),
      ),
    );
  }
}

/// "schreibt…" unten im Chat, solange die andere Person tippt: drei kleine
/// helle Punkte, die sanft nacheinander aufleuchten und sich leicht heben.
/// Ein Tipp-Signal gilt 8 Sekunden; ein Timer prüft das regelmässig nach,
/// damit die Blase auch verschwindet, wenn kein "fertig"-Signal mehr kommt.
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key, required this.coupleId});

  final String coupleId;

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble> {
  static const _validFor = Duration(seconds: 8);
  StreamSubscription<Map<String, dynamic>?>? _partnerSub;
  StreamSubscription<DateTime?>? _typingSub;
  String? _partnerUid;
  DateTime? _since;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _partnerSub = CoupleService.instance.partnerStream(widget.coupleId).listen((
      partner,
    ) {
      final uid = partner?['uid'] as String?;
      if (uid == _partnerUid) return;
      _partnerUid = uid;
      _typingSub?.cancel();
      _typingSub = uid == null
          ? null
          : CoupleService.instance.typingSince(widget.coupleId, uid).listen((
              since,
            ) {
              setState(() => _since = since);
              _updateTick();
            });
    });
  }

  // Akku: Der Prüf-Timer läuft nur, solange gerade jemand tippt – nicht dauernd.
  void _updateTick() {
    if (_since == null) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(const Duration(seconds: 2), (_) {
        if (!mounted) return;
        final since = _since;
        if (since == null || DateTime.now().difference(since) >= _validFor) {
          _tick?.cancel();
          _tick = null;
        }
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _partnerSub?.cancel();
    _typingSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final since = _since;
    final typing =
        since != null && DateTime.now().difference(since) < _validFor;
    // Sanft ein- und ausblenden, statt die Nachrichten ruckartig zu verschieben.
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: Alignment.bottomLeft,
      child: !typing
          ? const SizedBox(width: double.infinity)
          // Ganz dezent: nur drei helle Punkte, kein Text, keine Blase.
          : Padding(
              padding: const EdgeInsets.fromLTRB(22, 2, 12, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  liveRegion: true,
                  label: 'schreibt gerade',
                  child: const RepaintBoundary(child: _BouncingDots()),
                ),
              ),
            ),
    );
  }
}

/// Drei helle Punkte: einer nach dem anderen wird heller und hebt sich ein wenig.
class _BouncingDots extends StatefulWidget {
  const _BouncingDots();

  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Builder(
              builder: (context) {
                // Weiche Welle: jeder Punkt etwas später (0 = ruhig, 1 = oben/hell).
                final t = (_anim.value - i * 0.18) % 1.0;
                final wave = t < 0.5 ? math.sin(t / 0.5 * math.pi) : 0.0;
                return Transform.translate(
                  offset: Offset(0, -3 * wave),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Kitsune.paper.withValues(alpha: 0.35 + 0.5 * wave),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Runder, dunkler Hintergrund für die Knöpfe in der Chat-Kopfzeile – genau so
/// gross wie das Profilbild, damit alles auf einer Linie liegt.
class HeaderCircle extends StatelessWidget {
  const HeaderCircle({super.key, required this.child});

  final Widget child;

  static const size = 40.0;

  /// Knöpfe darin ohne eigenen Innenabstand, damit sie den Kreis genau füllen.
  static final buttonStyle = IconButton.styleFrom(
    fixedSize: const Size.square(size),
    minimumSize: const Size.square(size),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Kitsune.deep.withValues(alpha: 0.75),
    ),
    child: child,
  );
}

/// ⋮-Menü oben rechts: Fotos & Videos, eigenes Profilbild, eigener Name, Abmelden.
class ChatMenu extends StatelessWidget {
  const ChatMenu({super.key, required this.coupleId});

  final String coupleId;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Menü',
      style: HeaderCircle.buttonStyle,
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert),
      onSelected: (value) => switch (value) {
        'media' => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChatMediaScreen(coupleId: coupleId),
          ),
        ),
        'photo' => _changePhoto(context),
        'name' => _changeName(context),
        'logout' => _logout(),
        _ => null,
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'media',
          child: ListTile(
            leading: Icon(Icons.photo_library_outlined),
            title: Text('Fotos & Videos'),
          ),
        ),
        PopupMenuItem(
          value: 'photo',
          child: ListTile(
            leading: Icon(Icons.account_circle_outlined),
            title: Text('Mein Profilbild ändern'),
          ),
        ),
        PopupMenuItem(
          value: 'name',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Meinen Namen ändern'),
          ),
        ),
        PopupMenuItem(
          value: 'logout',
          child: ListTile(leading: Icon(Icons.logout), title: Text('Abmelden')),
        ),
      ],
    );
  }

  // Erst dieses Gerät bei den Push-Nachrichten abmelden, dann ausloggen.
  Future<void> _logout() async {
    await PushService.instance.stop();
    SharedStreams.clear(); // alte Verbindungen schliessen
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _changePhoto(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (await CoupleService.instance.setMyPhoto()) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Profilbild gespeichert')),
        );
      }
    } catch (e, s) {
      AppLogger.error(e, s, where: 'Profilbild speichern');
      messenger.showSnackBar(
        SnackBar(
          content: Text('Profilbild konnte nicht gespeichert werden: $e'),
        ),
      );
    }
  }

  Future<void> _changeName(BuildContext context) async {
    final current = await CoupleService.instance.myProfileStream().first;
    if (!context.mounted) return;
    final name = await askText(
      context,
      title: 'Dein Name',
      initial: current?['name'] as String? ?? '',
      hint: 'So sieht dich dein Schatz',
    );
    if (name != null && name.trim().isNotEmpty) {
      await CoupleService.instance.setMyName(name.trim());
    }
  }
}
