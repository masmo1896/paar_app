import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/app_logger.dart';
import '../../../services/crossword_service.dart';
import '../../../theme.dart';
import '../../../utils/crossword_generator.dart';
import '../../../utils/crossword_logic.dart';
import '../../../widgets/motion.dart';
import '../../../widgets/who.dart';
import '../effects.dart';

/// Gemeinsames Kreuzworträtsel: abwechselnd ein Wort raten oder einen
/// Buchstaben aufdecken. Gelöst wird zusammen.
class CrosswordScreen extends StatelessWidget {
  const CrosswordScreen({super.key, required this.couple});

  final Couple couple;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Kitsune.deeper,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('Kreuzworträtsel', style: AppTheme.serif(size: 20)),
      ),
      body: StreamBuilder<CrosswordGame?>(
        stream: CrosswordService.instance.current(couple.coupleId),
        builder: (context, snap) {
          if (!snap.hasData &&
              snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final game = snap.data;
          if (game == null) return _Start(couple: couple, first: true);
          return _Puzzle(key: ValueKey(game.id), couple: couple, game: game);
        },
      ),
    );
  }
}

Future<void> _newPuzzle(Couple couple, CrosswordLevel level) async {
  final r = generateForLevel(level);
  try {
    await CrosswordService.instance.newGame(
      couple.coupleId,
      r.puzzle.size,
      r.puzzle.words,
      difficulty: level.name,
      revealed: r.revealed,
    );
  } catch (e, s) {
    AppLogger.error(e, s, where: 'Kreuzwort: neues Rätsel');
  }
}

class _Start extends StatelessWidget {
  const _Start({required this.couple, this.first = false});

  final Couple couple;
  final bool first;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Hanko('謎', size: 54),
          const SizedBox(height: 18),
          Text(
            first ? 'Euer erstes Rätsel' : 'Neues Rätsel',
            style: AppTheme.serif(size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            'Ihr löst es zusammen: Abwechselnd ratet ihr ein Wort oder deckt '
            'einen Buchstaben auf. Danach ist ${couple.partnerLabel} dran.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Kitsune.mist),
          ),
          const SizedBox(height: 22),
          _LevelPicker(onPick: (level) => _newPuzzle(couple, level)),
        ],
      ),
    ),
  );
}

/// Drei gleich grosse Knöpfe: Einfach / Mittel / Schwer.
class _LevelPicker extends StatefulWidget {
  const _LevelPicker({required this.onPick});

  final Future<void> Function(CrosswordLevel level) onPick;

  @override
  State<_LevelPicker> createState() => _LevelPickerState();
}

class _LevelPickerState extends State<_LevelPicker> {
  CrosswordLevel? _busy;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final level in CrosswordLevel.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: level == CrosswordLevel.medium
                ? Kitsune.paper
                : Kitsune.deep.withValues(alpha: 0.85),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: const BorderSide(color: Color(0x4DF3EBD3)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _busy != null
                  ? null
                  : () async {
                      setState(() => _busy = level);
                      await widget.onPick(level);
                      if (mounted) setState(() => _busy = null);
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Hanko(
                      switch (level) {
                        CrosswordLevel.easy => '易',
                        CrosswordLevel.medium => '中',
                        CrosswordLevel.hard => '難',
                      },
                      size: 26,
                      filled: level != CrosswordLevel.easy,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            level.label,
                            style: AppTheme.serif(
                              size: 17,
                              color: level == CrosswordLevel.medium
                                  ? Kitsune.night
                                  : Kitsune.paper,
                            ),
                          ),
                          Text(
                            level.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: level == CrosswordLevel.medium
                                  ? Kitsune.inkSoft
                                  : Kitsune.mist,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_busy == level)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _Puzzle extends StatefulWidget {
  const _Puzzle({super.key, required this.couple, required this.game});

  final Couple couple;
  final CrosswordGame game;

  @override
  State<_Puzzle> createState() => _PuzzleState();
}

class _PuzzleState extends State<_Puzzle> with TickerProviderStateMixin {
  String? _selected;
  late final _fx = EffectLayer();
  late final _ticker = createTicker((e) {
    final dt = ((e - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = e;
    _fx.tick(dt);
  });
  Duration _last = Duration.zero;
  late bool _wasDone = widget.game.isDone;
  Size _gridSize = Size.zero;

  // Frisch eingetragene Felder kurz «einstempeln».
  late final _stamp = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..value = 1;
  Set<Point<int>> _fresh = {};
  late Map<String, String> _solvedBefore = Map.of(widget.game.solved);

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void didUpdateWidget(_Puzzle old) {
    super.didUpdateWidget(old);
    final g = widget.game;
    final newly = g.solved.keys.where((k) => !_solvedBefore.containsKey(k));
    if (newly.isNotEmpty) {
      _fresh = {
        for (final w in g.words)
          if (newly.contains(w.id)) ...w.cells,
      };
      _stamp.forward(from: 0);
    }
    _solvedBefore = Map.of(g.solved);
    if (g.isDone && !_wasDone) {
      _wasDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        HapticFeedback.heavyImpact();
        if (!reduceMotion(context) && _gridSize != Size.zero) {
          _fx.fireworks(_gridSize, bursts: 8);
        }
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _fx.dispose();
    _stamp.dispose();
    super.dispose();
  }

  bool get _myTurn =>
      !widget.game.isDone && widget.game.turn == widget.couple.myUid;

  CrosswordWord? get _word =>
      widget.game.words.where((w) => w.id == _selected).firstOrNull;

  void _tapCell(Point<int> p) {
    final words = widget.game.words.where((w) => w.cells.contains(p)).toList();
    if (words.isEmpty) return;
    HapticFeedback.selectionClick();
    // Zweimal auf ein Kreuzungsfeld tippen wechselt zwischen waagrecht und senkrecht.
    final current = words.indexWhere((w) => w.id == _selected);
    final next = words[(current + 1) % words.length];
    setState(() => _selected = next.id);
    _openInput(next);
  }

  Future<void> _openInput(CrosswordWord word) async {
    if (widget.game.solved.containsKey(word.id)) return;
    if (!_myTurn) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${widget.couple.partnerLabel} ist gerade dran.'),
            duration: const Duration(seconds: 2),
          ),
        );
      return;
    }
    await showFormSheet<void>(
      context,
      (_) => _GuessSheet(
        word: word,
        number: clueNumbers(widget.game.words)[Point(word.x, word.y)] ?? 0,
        known: _knownLetters(word),
        onGuess: (text) => _guess(word, text),
        onHint: () => _hint(word),
      ),
    );
  }

  /// Bereits sichtbare Buchstaben (aus Kreuzungen oder Hinweisen), sonst null.
  List<String?> _knownLetters(CrosswordWord word) {
    final filled = widget.game.filledBy;
    return [
      for (var i = 0; i < word.answer.length; i++)
        filled.containsKey(word.cells[i]) ? word.answer[i] : null,
    ];
  }

  Future<void> _guess(CrosswordWord word, String text) async {
    final partner = widget.couple.partnerUid;
    if (partner == null) return;
    try {
      final ok = await CrosswordService.instance.submitWord(
        widget.couple.coupleId,
        widget.game,
        word,
        text,
        partner,
      );
      if (!mounted) return;
      if (ok) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.vibrate();
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Richtig! ✨ Jetzt ist ${widget.couple.partnerLabel} dran.'
                  : 'Leider nicht – jetzt versucht es ${widget.couple.partnerLabel}.',
            ),
          ),
        );
    } catch (e, s) {
      AppLogger.error(e, s, where: 'Kreuzwort: Wort raten');
    }
  }

  Future<void> _hint(CrosswordWord word) async {
    final partner = widget.couple.partnerUid;
    if (partner == null) return;
    try {
      await CrosswordService.instance.hint(
        widget.couple.coupleId,
        widget.game,
        word,
        partner,
      );
    } catch (e, s) {
      AppLogger.error(e, s, where: 'Kreuzwort: Hinweis');
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final across = g.words.where((w) => w.across).toList();
    final down = g.words.where((w) => !w.across).toList();
    final numbers = clueNumbers(g.words);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        _TurnBar(game: g, couple: widget.couple),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: g.progress,
            minHeight: 6,
            backgroundColor: Kitsune.inkSoft,
            color: Kitsune.lantern,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${CrosswordLevel.fromName(g.difficulty).label} · '
          '${g.solved.length} von ${g.words.length} Wörtern · '
          '${g.attempts} ${g.attempts == 1 ? 'Versuch' : 'Versuche'} · '
          '${g.hintsUsed} ${g.hintsUsed == 1 ? 'Hinweis' : 'Hinweise'}',
          style: const TextStyle(fontSize: 12, color: Kitsune.mist),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final side = c.maxWidth;
            _gridSize = Size.square(side);
            return SizedBox.square(
              dimension: side,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _stamp,
                      builder: (context, _) => _Grid(
                        game: g,
                        couple: widget.couple,
                        numbers: numbers,
                        selected: _word,
                        fresh: _fresh,
                        stamp: _stamp.value,
                        onTap: _tapCell,
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: EffectPainter(_fx)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        if (g.isDone) ...[
          Text(
            'Gelöst! Ihr seid ein Team 🎆',
            textAlign: TextAlign.center,
            style: AppTheme.serif(size: 20),
          ),
          const SizedBox(height: 6),
          Text(
            'Neues Rätsel – wie knifflig?',
            textAlign: TextAlign.center,
            style: AppTheme.label(),
          ),
          const SizedBox(height: 12),
          _LevelPicker(onPick: (level) => _newPuzzle(widget.couple, level)),
          const SizedBox(height: 18),
        ],
        _ClueList(
          title: 'WAAGRECHT →',
          words: across,
          numbers: numbers,
          game: g,
          selected: _selected,
          onTap: (w) {
            setState(() => _selected = w.id);
            _openInput(w);
          },
        ),
        const SizedBox(height: 14),
        _ClueList(
          title: 'SENKRECHT ↓',
          words: down,
          numbers: numbers,
          game: g,
          selected: _selected,
          onTap: (w) {
            setState(() => _selected = w.id);
            _openInput(w);
          },
        ),
      ],
    );
  }
}

class _TurnBar extends StatelessWidget {
  const _TurnBar({required this.game, required this.couple});

  final CrosswordGame game;
  final Couple couple;

  @override
  Widget build(BuildContext context) {
    final mine = !game.isDone && game.turn == couple.myUid;
    final text = game.isDone
        ? 'Geschafft – alle Wörter gefunden'
        : mine
        ? 'Du bist dran – tippe ein Wort an'
        : '${couple.partnerLabel} ist dran';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine
            ? Kitsune.lantern.withValues(alpha: 0.18)
            : Kitsune.deep.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: mine
              ? Kitsune.lantern.withValues(alpha: 0.6)
              : const Color(0x4DF3EBD3),
        ),
      ),
      child: Row(
        children: [
          Hanko(game.isDone ? '済' : (mine ? '番' : '待'), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Das Papiergitter. Von dir gelöst = Indigo, vom Schatz = Pflaume, Hinweis = Rot.
class _Grid extends StatelessWidget {
  const _Grid({
    required this.game,
    required this.couple,
    required this.numbers,
    required this.selected,
    required this.fresh,
    required this.stamp,
    required this.onTap,
  });

  final CrosswordGame game;
  final Couple couple;
  final Map<Point<int>, int> numbers;
  final CrosswordWord? selected;
  final Set<Point<int>> fresh;
  final double stamp;
  final ValueChanged<Point<int>> onTap;

  @override
  Widget build(BuildContext context) {
    final solution = solutionGrid(game.words);
    final filled = game.filledBy;
    final sel = selected?.cells.toSet() ?? const <Point<int>>{};
    return LayoutBuilder(
      builder: (context, c) {
        final cell = c.maxWidth / game.size;
        // Schmale Rätsel waagrecht/senkrecht mittig setzen.
        final xs = solution.keys.map((p) => p.x),
            ys = solution.keys.map((p) => p.y);
        final dx = (game.size - (xs.reduce(max) + 1)) * cell / 2;
        final dy = (game.size - (ys.reduce(max) + 1)) * cell / 2;
        return Stack(
          children: [
            for (final e in solution.entries)
              Positioned(
                left: dx + e.key.x * cell,
                top: dy + e.key.y * cell,
                width: cell,
                height: cell,
                child: GestureDetector(
                  onTap: () => onTap(e.key),
                  child: _Cell(
                    letter: filled.containsKey(e.key) ? e.value : null,
                    by: filled[e.key],
                    myUid: couple.myUid,
                    number: numbers[e.key],
                    selected: sel.contains(e.key),
                    scale: fresh.contains(e.key)
                        ? Curves.elasticOut.transform(stamp)
                        : 1,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.letter,
    required this.by,
    required this.myUid,
    required this.number,
    required this.selected,
    required this.scale,
  });

  final String? letter;
  final String? by;
  final String myUid;
  final int? number;
  final bool selected;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final color = by == null
        ? Kitsune.indigo
        : by == ''
        ? Kitsune.lantern
        : by == myUid
        ? Kitsune.indigo
        : Kitsune.plum;
    return Padding(
      padding: const EdgeInsets.all(1),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF4D6) : Kitsune.paper,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: selected ? Kitsune.lantern : const Color(0x33133174),
            width: selected ? 1.6 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, c) => Stack(
            children: [
              if (number != null)
                Positioned(
                  left: 2,
                  top: 1,
                  child: Text(
                    '$number',
                    style: TextStyle(
                      fontSize: c.maxWidth * 0.24,
                      color: Kitsune.inkSoft,
                      height: 1,
                    ),
                  ),
                ),
              if (letter != null)
                Center(
                  child: Transform.scale(
                    scale: scale,
                    child: Text(
                      letter!,
                      style: AppTheme.serif(
                        size: c.maxWidth * 0.55,
                        color: color,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClueList extends StatelessWidget {
  const _ClueList({
    required this.title,
    required this.words,
    required this.numbers,
    required this.game,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final List<CrosswordWord> words;
  final Map<Point<int>, int> numbers;
  final CrosswordGame game;
  final String? selected;
  final ValueChanged<CrosswordWord> onTap;

  @override
  Widget build(BuildContext context) {
    if (words.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: AppTheme.label()),
        const SizedBox(height: 6),
        for (final w in words)
          InkWell(
            onTap: () => onTap(w),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: w.id == selected
                    ? Kitsune.lantern.withValues(alpha: 0.12)
                    : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 26,
                    child: Text(
                      '${numbers[Point(w.x, w.y)]}',
                      style: AppTheme.serif(size: 14, color: Kitsune.aqua),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${w.clue} (${w.answer.length})',
                      style: TextStyle(
                        fontSize: 14,
                        decoration: game.solved.containsKey(w.id)
                            ? TextDecoration.lineThrough
                            : null,
                        color: game.solved.containsKey(w.id)
                            ? Kitsune.dim
                            : Kitsune.paper,
                      ),
                    ),
                  ),
                  if (game.solved.containsKey(w.id))
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Hanko('済', size: 20),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Eingabe für ein Wort, mit bekannten Buchstaben als Vorlage.
class _GuessSheet extends StatefulWidget {
  const _GuessSheet({
    required this.word,
    required this.number,
    required this.known,
    required this.onGuess,
    required this.onHint,
  });

  final CrosswordWord word;
  final int number;
  final List<String?> known;
  final Future<void> Function(String) onGuess;
  final Future<void> Function() onHint;

  @override
  State<_GuessSheet> createState() => _GuessSheetState();
}

class _GuessSheetState extends State<_GuessSheet>
    with SingleTickerProviderStateMixin {
  final _input = TextEditingController();
  late final _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = normalizeAnswer(_input.text);
    if (text.length != widget.word.answer.length) {
      HapticFeedback.selectionClick();
      _shake.forward(from: 0);
      return;
    }
    setState(() => _busy = true);
    await widget.onGuess(text);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.word;
    final pattern = widget.known.map((c) => c ?? '_').join(' ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${widget.number} ${w.across ? 'waagrecht' : 'senkrecht'}',
          style: AppTheme.label(),
        ),
        const SizedBox(height: 6),
        Text(w.clue, style: AppTheme.serif(size: 19)),
        const SizedBox(height: 10),
        Text(
          pattern,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            letterSpacing: 2,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) => Transform.translate(
            offset: Offset(
              sin(_shake.value * pi * 6) * 8 * (1 - _shake.value),
              0,
            ),
            child: child,
          ),
          child: TextField(
            controller: _input,
            autofocus: true,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            maxLength: w.answer.length + 4,
            decoration: InputDecoration(
              hintText: '${w.answer.length} Buchstaben',
              counterText: '',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        await widget.onHint();
                        if (context.mounted) Navigator.pop(context);
                      },
                icon: const Icon(Icons.lightbulb_outline_rounded),
                label: const Text('Buchstabe'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: const Text('Raten'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Raten oder Buchstabe aufdecken – beides beendet deinen Zug.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Kitsune.mist),
        ),
      ],
    );
  }
}
