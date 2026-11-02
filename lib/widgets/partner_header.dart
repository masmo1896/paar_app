import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/couple_service.dart';
import '../services/push_service.dart';
import '../theme.dart';
import 'fox_bubble.dart';
import 'who.dart';

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
      foregroundImage: url == null ? null : NetworkImage(url),
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

/// Titel der Kopfzeile: Profilbild + Name der Partnerin/des Partners.
/// Antippen zeigt das Profilbild gross. Solange niemand beigetreten ist: "Wir zwei".
class PartnerTitle extends StatelessWidget {
  const PartnerTitle({super.key, required this.coupleId});

  final String coupleId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: CoupleService.instance.partnerStream(coupleId),
      builder: (context, snap) {
        final partner = snap.data;
        if (partner == null) return const Text('Wir zwei');
        final name = (partner['name'] as String?)?.trim();
        final displayName = name == null || name.isEmpty ? 'Dein Schatz' : name;
        final photoUrl = partner['photoUrl'] as String?;

        return InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: photoUrl == null
              ? null
              : () => _showPhoto(context, displayName, photoUrl),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Avatar(name: displayName, photoUrl: photoUrl),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        overflow: TextOverflow.ellipsis,
                        // Schatten, damit der Name auf der Illustration lesbar bleibt.
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          shadows: const [
                            Shadow(color: Color(0xFF0A1838), blurRadius: 10),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

/// "schreibt…"-Blase unten im Chat, solange die andere Person tippt: eine kleine
/// Papier-Sprechblase mit Fuchsohren und drei hüpfenden Punkten.
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
          : CoupleService.instance
                .typingSince(widget.coupleId, uid)
                .listen((since) => setState(() => _since = since));
    });
    _tick = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && _since != null) setState(() {});
    });
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
          : Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  liveRegion: true,
                  label: 'schreibt gerade',
                  child: FoxBubble(
                    color: Kitsune.paper,
                    isMine: false,
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(14, 9, 14, 9),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _BouncingDots(),
                          SizedBox(width: 8),
                          Text(
                            'schreibt…',
                            style: TextStyle(
                              color: Kitsune.inkSoft,
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Drei Punkte, die nacheinander hüpfen (rot, wie die Laternen).
class _BouncingDots extends StatefulWidget {
  const _BouncingDots();

  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots>
    with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
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
            if (i > 0) const SizedBox(width: 4),
            Transform.translate(
              // Jeder Punkt startet etwas später; hüpft im ersten Drittel hoch und runter.
              offset: Offset(0, -4 * _hop((_anim.value - i * 0.15) % 1.0)),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == 1 ? Kitsune.plum : Kitsune.lantern,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static double _hop(double t) =>
      t < 0.35 ? math.sin(t / 0.35 * math.pi) : 0.0;
}

/// ⋮-Menü oben rechts: eigenes Profilbild, eigener Name, Abmelden.
class ChatMenu extends StatelessWidget {
  const ChatMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Menü',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) => switch (value) {
        'photo' => _changePhoto(context),
        'name' => _changeName(context),
        'logout' => _logout(),
        _ => null,
      },
      itemBuilder: (_) => const [
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
    } catch (e) {
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
