import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/couple_service.dart';
import '../services/push_service.dart';
import '../theme.dart';

// Verbindet zwei Konten: einer erstellt einen Code, der andere gibt ihn ein.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Zwei Füchse auf der Brücke – gleich wie auf der Wir-Seite.
          SizedBox(
            height: 210 + top,
            child: Stack(
              fit: StackFit.expand,
              children: [
                SvgPicture.asset(
                  KitsuneArt.foxes.asset,
                  fit: BoxFit.cover,
                  alignment: Alignment.bottomCenter,
                  semanticsLabel: 'Zwei Füchse auf einer Brücke',
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
                      tooltip: 'Abmelden',
                      icon: const Icon(Icons.logout_rounded),
                      onPressed: () async {
                        await PushService.instance.stop();
                        await FirebaseAuth.instance.signOut();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'むすぶ',
                  textAlign: TextAlign.center,
                  style: AppTheme.serif(
                    size: 12,
                    weight: FontWeight.w600,
                    color: Kitsune.aqua,
                  ).copyWith(letterSpacing: 4),
                ),
                Text(
                  'Verbindet euch',
                  textAlign: TextAlign.center,
                  style: AppTheme.serif(size: 26),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Eine Person erstellt einen Code, die andere gibt ihn ein.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Kitsune.mist, fontSize: 13.5),
                ),
                const SizedBox(height: 20),
                _Step(
                  number: '一',
                  title: 'Code erstellen',
                  text:
                      'Du bekommst einen Code, den du deinem Schatz schickst. '
                      'Danach landest du direkt im Chat.',
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : () =>
                              _run(() => CoupleService.instance.createCouple()),
                    style: FilledButton.styleFrom(
                      backgroundColor: Kitsune.indigo,
                      foregroundColor: Kitsune.paper,
                    ),
                    child: const Text('Code erstellen'),
                  ),
                ),
                const SizedBox(height: 14),
                _Step(
                  number: '二',
                  title: 'Code eingeben',
                  text:
                      'Hast du schon einen Code bekommen? Dann hier eintragen.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _code,
                        style: AppTheme.serif(
                          size: 22,
                          color: Kitsune.night,
                        ).copyWith(letterSpacing: 6),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(hintText: 'ABC123'),
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        onSubmitted: (_) => _run(
                          () => CoupleService.instance.joinCouple(_code.text),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                () => CoupleService.instance.joinCouple(
                                  _code.text,
                                ),
                              ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Kitsune.lantern,
                          foregroundColor: Kitsune.paper,
                        ),
                        child: const Text('Beitreten'),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFF8FA8)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Papierkarte mit grossem Zahlzeichen (一, 二), Titel, Text und Knopf.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.text,
    required this.child,
  });

  final String number;
  final String title;
  final String text;
  final Widget child;

  @override
  Widget build(BuildContext context) => Paper(
    child: Card(
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0x40133174)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Hanko(number, size: 28),
                const SizedBox(width: 12),
                Text(title, style: AppTheme.serif(size: 18)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: const TextStyle(color: Kitsune.inkSoft, fontSize: 13.5),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    ),
  );
}
