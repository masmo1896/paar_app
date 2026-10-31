import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/couple_service.dart';
import '../services/push_service.dart';
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
                      if (partner['uid'] case final String uid)
                        _TypingIndicator(coupleId: coupleId, partnerUid: uid),
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

/// Kleines "schreibt…" unter dem Namen, solange die andere Person tippt.
/// Ein Tipp-Signal gilt 8 Sekunden; ein Timer prüft das regelmässig nach,
/// damit die Anzeige auch verschwindet, wenn kein "fertig"-Signal mehr kommt.
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.coupleId, required this.partnerUid});

  final String coupleId;
  final String partnerUid;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> {
  static const _validFor = Duration(seconds: 8);
  late final Stream<DateTime?> _since = CoupleService.instance.typingSince(
    widget.coupleId,
    widget.partnerUid,
  );
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime?>(
      stream: _since,
      builder: (context, snap) {
        final since = snap.data;
        final typing =
            since != null && DateTime.now().difference(since) < _validFor;
        if (!typing) return const SizedBox.shrink();
        return Text(
          'schreibt…',
          style: TextStyle(
            fontSize: 13,
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }
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
