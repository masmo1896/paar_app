import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/album_service.dart';
import '../services/couple_service.dart';
import '../services/planner_service.dart';
import '../services/push_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import '../widgets/app_lock.dart';
import '../widgets/who.dart';
import 'albums_screen.dart';
import 'countdown_screen.dart';

/// "Wir"-Seite: zwei Füchse auf der Brücke, eure Namen und darunter eure
/// Erinnerungen (Alben) als Ordner. Die Einstellungen liegen hinter dem
/// Zahnrad oben rechts auf einer eigenen Seite.
class UsScreen extends StatelessWidget {
  const UsScreen({super.key, required this.couple});

  final Couple couple;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: 236 + top,
            child: Stack(
              fit: StackFit.expand,
              children: [
                SvgPicture.asset(
                  KitsuneArt.foxes.asset,
                  fit: BoxFit.cover,
                  alignment: Alignment.bottomCenter,
                  semanticsLabel: 'Zwei Füchse auf einer Brücke, ihre Schwänze bilden ein Herz',
                ),
                Positioned(
                  top: top + 8,
                  right: 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Kitsune.deep.withValues(alpha: 0.75),
                    ),
                    child: IconButton(
                      tooltip: 'Einstellungen',
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SettingsScreen(couple: couple),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Names(couple: couple),
                const SizedBox(height: 18),
                _Memories(couple: couple),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Einstellungen auf eigener Seite: Benachrichtigungen bis Abmelden.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.couple});

  final Couple couple;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: kitsuneAppBar(
      art: KitsuneArt.lanterns,
      kana: 'せってい',
      titleText: 'Einstellungen',
      height: 96,
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [_Settings(couple: couple)],
    ),
  );
}

/// "Marc & Schatz" und darunter "zusammen seit …" (aus eurem Jahrestag-Countdown).
class _Names extends StatelessWidget {
  const _Names({required this.couple});

  final Couple couple;

  @override
  Widget build(BuildContext context) {
    Widget line() => Container(
      width: 18,
      height: 1,
      color: Kitsune.paper.withValues(alpha: 0.5),
    );
    return StreamBuilder<Map<String, dynamic>?>(
      stream: CoupleService.instance.myProfileStream(),
      builder: (context, me) => StreamBuilder<List<Countdown>>(
        stream: PlannerService.instance.countdowns(couple.coupleId),
        builder: (context, cds) {
          final myName = (me.data?['name'] as String?)?.trim();
          // Der Jahrestag: ein jährlicher Countdown, am liebsten mit Herz oder Ring.
          final yearly = (cds.data ?? []).where((c) => c.yearly).toList()
            ..sort((a, b) {
              int score(Countdown c) => ['❤️', '💍'].contains(c.emoji) ? 0 : 1;
              return score(a).compareTo(score(b));
            });
          final since = yearly.isEmpty ? null : yearly.first.date;
          return Column(
            children: [
              // Antippen: Spitznamen für deinen Schatz festlegen.
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _editNickname(context, couple.partnerLabel),
                child: Text(
                  '${myName == null || myName.isEmpty ? 'Du' : myName} & ${couple.partnerLabel}',
                  textAlign: TextAlign.center,
                  style: AppTheme.serif(size: 24).copyWith(letterSpacing: 1),
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: since != null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CountdownScreen(couple: couple),
                        ),
                      ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    line(),
                    const SizedBox(width: 8),
                    Text(
                      since == null
                          ? 'Jahrestag als Countdown eintragen'
                          : 'zusammen seit ${since.day}. ${monthsLong[since.month - 1]} ${since.year}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Kitsune.mist,
                      ),
                    ),
                    const SizedBox(width: 8),
                    line(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _editNickname(BuildContext context, String current) async {
  final name = await askText(
    context,
    title: 'Wie heisst dein Schatz?',
    initial: current,
    hint: 'Leer lassen = ihr eigener Name',
  );
  if (name != null) await CoupleService.instance.setPartnerNickname(name);
}

/// Alle Alben als Ordner: schräge Polaroids im Raster, am Ende "Neues Album".
class _Memories extends StatelessWidget {
  const _Memories({required this.couple});

  final Couple couple;

  void _open(BuildContext context, String albumId) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AlbumScreen(couple: couple, albumId: albumId),
        ),
      );

  Future<void> _create(BuildContext context) async {
    final name = await askText(
      context,
      title: 'Neues Album',
      hint: 'z. B. Budapest 2027',
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final id = await AlbumService.instance.createAlbum(
      couple.coupleId,
      name.trim(),
    );
    if (context.mounted) _open(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Erinnerungen', style: AppTheme.serif(size: 18)),
        const SizedBox(height: 12),
        StreamBuilder<List<Album>>(
          stream: AlbumService.instance.albums(couple.coupleId),
          builder: (context, snap) {
            final albums = (snap.data ?? []).toList()
              ..sort((a, b) {
                final at = a.createdAt, bt = b.createdAt;
                if (at == null) return -1;
                if (bt == null) return 1;
                return bt.compareTo(at);
              });
            const tilts = [-0.035, 0.026, -0.017, 0.02, -0.028, 0.012];
            final tiles = [
              for (final album in albums)
                _Polaroid(album: album, onTap: () => _open(context, album.id)),
              _Polaroid(onTap: () => _create(context)),
            ];
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: tiles.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 10,
                childAspectRatio: 0.82,
              ),
              itemBuilder: (context, i) => Transform.rotate(
                angle: tilts[i % tilts.length],
                child: tiles[i],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Polaroid extends StatelessWidget {
  const _Polaroid({this.album, required this.onTap});

  final Album? album; // null = leeres Feld "Neues Album"
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = album?.coverUrl;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(5, 5, 5, 8),
        decoration: BoxDecoration(
          color: Kitsune.paper,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            // Bild füllt den Ordner, Name darunter.
            Expanded(
              child: Container(
                width: double.infinity,
                color: Kitsune.indigo,
                child: cover != null
                    ? Image.network(
                        cover,
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      )
                    : Icon(
                        album == null ? Icons.add : Icons.photo_outlined,
                        color: Kitsune.paper,
                      ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              album?.name ?? 'Neues Album',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.serif(size: 11.5, color: Kitsune.night),
            ),
          ],
        ),
      ),
    );
  }
}

/// Einstellungen: Benachrichtigungen, Jahrestag-Erinnerung, Design, Abmelden.
class _Settings extends StatelessWidget {
  const _Settings({required this.couple});

  final Couple couple;

  @override
  Widget build(BuildContext context) {
    const divider = Divider(height: 1, color: Color(0x26F3EBD3));
    return StreamBuilder<Map<String, dynamic>?>(
      stream: CoupleService.instance.myProfileStream(),
      builder: (context, snap) {
        final me = snap.data ?? {};
        final pushOn = me['pushOff'] != true;
        final reminderOn = me['anniversaryReminder'] != false;
        return Container(
          decoration: BoxDecoration(
            color: Kitsune.deep.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0x40F3EBD3)),
          ),
          child: Column(
            children: [
              _Row(
                icon: Icons.notifications_none_rounded,
                label: 'Benachrichtigungen',
                trailing: _Switch(
                  value: pushOn,
                  label: 'Benachrichtigungen',
                  onChanged: (v) => PushService.instance.setEnabled(v),
                ),
              ),
              divider,
              _Row(
                icon: Icons.favorite_border_rounded,
                label: 'Jahrestag-Erinnerung',
                trailing: _Switch(
                  value: reminderOn,
                  label: 'Jahrestag-Erinnerung',
                  onChanged: (v) => FirebaseFirestore.instance
                      .collection('users')
                      .doc(couple.myUid)
                      .set({'anniversaryReminder': v}, SetOptions(merge: true)),
                ),
              ),
              divider,
              ValueListenableBuilder<bool?>(
                valueListenable: AppLock.instance.enabled,
                builder: (context, on, _) => _Row(
                  icon: Icons.fingerprint_rounded,
                  label: 'App-Sperre',
                  trailing: _Switch(
                    value: on == true,
                    label: 'App-Sperre',
                    onChanged: (v) async {
                      final messenger = ScaffoldMessenger.of(context);
                      final error = await AppLock.instance.setEnabled(v);
                      if (error != null) {
                        messenger.showSnackBar(SnackBar(content: Text(error)));
                      }
                    },
                  ),
                ),
              ),
              divider,
              _Row(
                icon: Icons.contrast_rounded,
                label: 'Design & Farben',
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Aktuelles Design: Kitsune Moon'),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final c in [
                      Kitsune.paper,
                      Kitsune.aqua,
                      Kitsune.lantern,
                    ])
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(left: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c,
                        ),
                      ),
                  ],
                ),
              ),
              divider,
              _Row(
                icon: Icons.logout_rounded,
                iconColor: Kitsune.lantern,
                label: 'Abmelden',
                onTap: () async {
                  await PushService.instance.stop();
                  await FirebaseAuth.instance.signOut();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
    this.iconColor = Kitsune.aqua,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 14.5)),
            ),
            ?trailing,
          ],
        ),
      ),
    ),
  );
}

/// Schalter wie im Mockup: rot gefüllt mit cremefarbenem Knopf, aus = nur Umriss.
class _Switch extends StatelessWidget {
  const _Switch({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    label: label,
    child: GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 52,
        height: 30,
        decoration: BoxDecoration(
          color: value ? Kitsune.lantern : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: value ? Kitsune.lantern : const Color(0x73F3EBD3),
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Kitsune.paper,
            ),
          ),
        ),
      ),
    ),
  );
}
