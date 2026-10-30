import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/couple_service.dart';

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verbinden'),
        actions: [
          IconButton(
            tooltip: 'Abmelden',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Neues Paar erstellen', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Du bekommst einen Code, den du deiner Partnerin schickst. '
            'Danach landest du direkt im Chat.',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(() => CoupleService.instance.createCouple()),
            child: const Text('Code erstellen'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Divider(),
          ),
          Text('Code eingeben', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            decoration: const InputDecoration(labelText: '6-stelliger Code'),
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _busy
                ? null
                : () =>
                      _run(() => CoupleService.instance.joinCouple(_code.text)),
            child: const Text('Beitreten'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
