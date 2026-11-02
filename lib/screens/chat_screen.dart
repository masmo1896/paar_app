import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../services/couple_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import 'camera_page.dart';
import 'search_screen.dart';
import '../widgets/gif_picker.dart';
import '../widgets/fox_bubble.dart';
import '../widgets/partner_header.dart';
import '../widgets/selfie_video.dart';
import '../widgets/voice.dart';
import '../widgets/motion.dart';

// Der Chat: Nachrichten kommen in Echtzeit über einen Firestore-Stream.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.coupleId,
    this.active = true,
    this.onBack,
  });

  final String coupleId;

  /// Zurück-Knopf oben links: wechselt zum zuvor geöffneten Bereich.
  final VoidCallback? onBack;

  /// false, solange ein anderer Tab offen ist: dann werden Nachrichten nicht als gelesen markiert.
  final bool active;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _myUid = FirebaseAuth.instance.currentUser!.uid;
  // Nachrichten, die wir schon als gelesen gemeldet haben (verhindert doppelte Schreibvorgänge).
  final _markedRead = <String>{};
  bool _uploading = false;
  // Nachrichten-Verbindung nur EINMAL aufbauen – nicht bei jedem Neuzeichnen
  // (sonst lädt die Liste bei jedem Tippen kurz neu).
  late final _messages = CoupleService.instance
      .messages(widget.coupleId)
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots();

  // IDs der Nachrichten, die schon angezeigt wurden (null = noch nichts geladen).
  Set<String>? _knownIds;

  // Sprachaufnahme (halten, sperren, anhören); sendet über _sendVoice.
  late final _voice = VoiceRecorderController(onSend: _sendVoice);
  // gesetzt = die nächste Textnachricht ist eine Antwort darauf
  ReplyTo? _replyTo;
  // gesetzt = das Eingabefeld bearbeitet diese eigene Nachricht
  String? _editingId;

  // Liste, die man gezielt zu einer Nachricht scrollen kann (für Zitate und "nach unten").
  final _itemScroll = ItemScrollController();
  final _itemPositions = ItemPositionsListener.create();
  var _docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  bool _atBottom = true; // neueste Nachricht sichtbar?
  int _newWhileAway = 0; // neue Nachrichten, während man weiter oben liest
  String? _newestId;
  String? _highlightId; // kurz hervorgehobene Nachricht (nach Sprung zum Zitat)

  // So hoch ist der Bereich oben, in dem die Sprechblasen ausblenden.
  static const _fadeHeight = 56.0;

  bool _attachOpen = false; // "+"-Popup offen?

  // "schreibt…": höchstens alle 3 Sekunden ein Signal senden.
  DateTime? _lastTypingSignal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _itemPositions.itemPositions.addListener(_onScroll);
    _input.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _itemPositions.itemPositions.removeListener(_onScroll);
    _input.removeListener(_onTextChanged);
    _stopTyping();
    _voice.dispose();
    _input.dispose();
    super.dispose();
  }

  // Wird der Chat-Tab wieder geöffnet, neu zeichnen -> ungelesene werden markiert.
  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) setState(() {});
  }

  // Kommt die App aus dem Hintergrund zurück, neu zeichnen -> ungelesene werden markiert.
  // Geht sie in den Hintergrund, "schreibt…" beenden.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(() {});
    if (state == AppLifecycleState.paused) _stopTyping();
  }

  void _onScroll() {
    // Liste ist umgedreht: Eintrag 0 ist die neueste Nachricht ganz unten.
    final atBottom = _itemPositions.itemPositions.value.any(
      (p) => p.index == 0 && p.itemLeadingEdge < 0.95,
    );
    if (atBottom != _atBottom) {
      setState(() {
        _atBottom = atBottom;
        if (atBottom) _newWhileAway = 0;
      });
    }
  }

  void _onTextChanged() {
    if (_editingId != null) return; // beim Bearbeiten kein "schreibt…"
    if (_input.text.trim().isEmpty) return _stopTyping();
    final last = _lastTypingSignal;
    if (last == null ||
        DateTime.now().difference(last) > const Duration(seconds: 3)) {
      _lastTypingSignal = DateTime.now();
      CoupleService.instance.setTyping(widget.coupleId, true);
    }
  }

  void _stopTyping() {
    if (_lastTypingSignal == null) return;
    _lastTypingSignal = null;
    CoupleService.instance.setTyping(widget.coupleId, false);
  }

  void _scrollToBottom() {
    _itemScroll.scrollTo(
      index: 0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // Suche öffnen; ein angetippter Treffer kommt als Nachrichten-ID zurück.
  Future<void> _openSearch() async {
    final partner = await CoupleService.instance
        .partnerStream(widget.coupleId)
        .first;
    if (!mounted) return;
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          coupleId: widget.coupleId,
          myUid: FirebaseAuth.instance.currentUser!.uid,
          partnerName: (partner?['name'] as String?)?.trim().isNotEmpty == true
              ? (partner!['name'] as String).trim()
              : 'Dein Schatz',
        ),
      ),
    );
    if (id != null && mounted) _jumpToMessage(id);
  }

  // Zitat angetippt: zur Originalnachricht springen und sie kurz hervorheben.
  void _jumpToMessage(String id) {
    final index = _docs.indexWhere((d) => d.id == id);
    if (index < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diese Nachricht ist zu weit zurück.')),
      );
      return;
    }
    _itemScroll.scrollTo(
      index: index,
      alignment: 0.4,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    setState(() => _highlightId = id);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted && _highlightId == id) setState(() => _highlightId = null);
    });
  }

  void _startReply(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data['type'] == 'deleted') return;
    HapticFeedback.selectionClick();
    setState(() {
      _editingId = null;
      _replyTo = ReplyTo(
        id: doc.id,
        senderId: data['senderId'] as String? ?? '',
        preview: CoupleService.previewOf(data),
      );
    });
  }

  // Neue Nachricht der anderen Person, während man oben liest -> Zähler am Knopf erhöhen.
  void _countNewMessages(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final newest = docs.first;
    if (_newestId != null &&
        newest.id != _newestId &&
        !_atBottom &&
        newest['senderId'] != _myUid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _newWhileAway++);
      });
    }
    _newestId = newest.id;
  }

  /// Meldet Nachrichten der Partnerin als gelesen – aber nur, wenn die App sichtbar ist.
  void _markPartnerMessagesRead(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (!widget.active ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final unread = docs
        .where((d) => d['senderId'] != _myUid && d.data()['read'] != true)
        .map((d) => d.id)
        .where(
          _markedRead.add,
        ) // add() liefert false, wenn die ID schon drin war
        .toList();
    if (unread.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback(
      // Klappt es nicht (z. B. offline), beim nächsten Neuzeichnen erneut versuchen.
      (_) => CoupleService.instance
          .markRead(widget.coupleId, unread)
          .onError((_, _) => _markedRead.removeAll(unread)),
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    final editingId = _editingId;
    final replyTo = _replyTo;
    _input.clear();
    _stopTyping();
    setState(() {
      _replyTo = null;
      _editingId = null;
    });
    // Im Bearbeiten-Modus wird die Nachricht geändert statt neu gesendet.
    if (editingId != null) {
      await CoupleService.instance.editMessage(
        widget.coupleId,
        editingId,
        text,
      );
      return;
    }
    await CoupleService.instance.sendMessage(
      widget.coupleId,
      text,
      replyTo: replyTo,
    );
  }

  static const _reactionEmojis = ['❤️', '😂', '🥰', '😮', '😢', '👍', '🔥'];

  // Langes Drücken auf eine Nachricht: Popup direkt an der Nachricht mit
  // Smiley-Leiste und darunter "Antworten" / "Kopieren" (wie bei Messenger-Apps üblich).
  Future<void> _showMessageActions(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Rect bubbleRect,
  ) async {
    HapticFeedback.mediumImpact();
    final data = doc.data();
    final isMine = data['senderId'] == _myUid;
    final myReaction = (data['reactions'] as Map?)?[_myUid] as String?;
    final text = data['type'] == 'text' || data['type'] == null
        ? data['text'] as String?
        : null;
    // Gelöschte Nachrichten haben kein Menü.
    if (data['type'] == 'deleted') return;

    void react(String emoji) {
      // Gleicher Smiley nochmals = Reaktion entfernen.
      CoupleService.instance.setReaction(
        widget.coupleId,
        doc.id,
        emoji == myReaction ? null : emoji,
      );
    }

    void reply() => setState(
      () => _replyTo = ReplyTo(
        id: doc.id,
        senderId: data['senderId'] as String? ?? '',
        preview: CoupleService.previewOf(data),
      ),
    );

    // Text ins Eingabefeld holen; Senden speichert dann die Änderung.
    void edit() {
      _input.text = text!;
      _input.selection = TextSelection.collapsed(offset: text.length);
      setState(() {
        _editingId = doc.id;
        _replyTo = null;
      });
    }

    Future<void> delete() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Nachricht löschen?'),
          content: const Text('Sie wird für euch beide gelöscht.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              child: const Text('Löschen'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await CoupleService.instance.deleteMessage(
          widget.coupleId,
          doc.id,
          data,
        );
      }
    }

    void copy() {
      Clipboard.setData(ClipboardData(text: text!));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Text kopiert')));
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schliessen',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.9, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      pageBuilder: (dialogContext, _, _) => _MessageActionsPopup(
        bubbleRect: bubbleRect,
        alignRight: isMine,
        emojis: _reactionEmojis,
        selected: myReaction,
        onReact: react,
        onReply: reply,
        onCopy: text == null ? null : copy,
        // Bearbeiten und Löschen nur bei eigenen Nachrichten (Bearbeiten nur bei Text).
        onEdit: isMine && text != null ? edit : null,
        onDelete: isMine ? delete : null,
      ),
    );
  }

  // "+": kleines Popup über dem Knopf. Solange es offen ist, zeigt der Knopf "×".
  Future<void> _openAttach(Rect anchor) async {
    FocusScope.of(context).unfocus();
    setState(() => _attachOpen = true);
    final what = await _AttachPopup.show(context, anchor);
    if (!mounted) return;
    setState(() => _attachOpen = false);
    if (what != null) await _attach(what);
  }

  /// Eine Zeile im Popup wurde gewählt.
  Future<void> _attach(_Attachment what) async {
    switch (what) {
      case _Attachment.gallery:
        await _upload(
          () => CoupleService.instance.sendPhoto(
            widget.coupleId,
            ImageSource.gallery,
          ),
          'Foto konnte nicht gesendet werden',
        );
      case _Attachment.camera:
        await _openCamera(CameraMode.photo);
      case _Attachment.video:
        await _recordSelfie();
      case _Attachment.gif:
        await _sendGif();
    }
  }

  // GIF-Fenster öffnen: GIPHY-GIF direkt senden, Galerie-GIF erst hochladen.
  Future<void> _sendGif() async {
    final choice = await GifPickerSheet.show(context);
    switch (choice) {
      case GiphyGif(:final url):
        await CoupleService.instance.sendGif(widget.coupleId, url);
      case GalleryGif():
        await _upload(
          () => CoupleService.instance.sendGalleryGif(widget.coupleId),
          'GIF konnte nicht gesendet werden',
        );
      case null:
        return;
    }
  }

  // Selfie-Video: Kamera direkt im Video-Modus mit der Frontkamera öffnen.
  Future<void> _recordSelfie() => _openCamera(CameraMode.video, front: true);

  /// Eigene Kamera (iPhone-Stil); danach Foto oder Video senden.
  Future<void> _openCamera(CameraMode mode, {bool front = false}) async {
    final shot = await Navigator.of(context).push<CameraShot>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CameraPage(mode: mode, front: front),
      ),
    );
    if (shot == null) return;
    await _upload(
      () => shot.isVideo
          ? CoupleService.instance.sendVideo(
              widget.coupleId,
              shot.path,
              shot.duration,
            )
          : CoupleService.instance.sendPhotoFile(widget.coupleId, shot.path),
      shot.isVideo
          ? 'Video konnte nicht gesendet werden'
          : 'Foto konnte nicht gesendet werden',
    );
  }

  void _sendVoice(String path, Duration duration, List<double> waveform) =>
      _upload(
        () => CoupleService.instance.sendVoice(
          widget.coupleId,
          path,
          duration,
          waveform: waveform,
        ),
        'Sprachnachricht konnte nicht gesendet werden',
      );

  // Gemeinsamer Ablauf für Uploads: Ladebalken zeigen, Fehler als Hinweis anzeigen.
  Future<void> _upload(Future<void> Function() action, String errorText) async {
    setState(() => _uploading = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$errorText: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _bubbleFor(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, dynamic> data,
    DateTime? time,
  ) {
    return _Bubble(
      text: data['text'] as String? ?? '',
      imageUrl: switch (data['type']) {
        'image' => data['imageUrl'] as String?,
        'gif' => data['gifUrl'] as String?,
        _ => null,
      },
      isGif: data['type'] == 'gif',
      audioUrl: data['type'] == 'audio' ? data['audioUrl'] as String? : null,
      waveform: (data['waveform'] as List?)
          ?.map((v) => (v as num).toDouble())
          .toList(),
      videoUrl: data['type'] == 'video' ? data['videoUrl'] as String? : null,
      mediaDuration: Duration(milliseconds: data['durationMs'] as int? ?? 0),
      time: time,
      isMine: data['senderId'] == _myUid,
      // Ohne Server-Zeitstempel ist die Nachricht noch nicht angekommen.
      // (hasPendingWrites wäre auch bei einer neuen Reaktion kurz true.)
      status: data['createdAt'] == null
          ? _Status.pending
          : data['read'] == true
          ? _Status.read
          : _Status.sent,
      reactions: ((data['reactions'] as Map?) ?? const {}).values
          .whereType<String>()
          .toList(),
      replyTo: data['replyTo'] is Map
          ? ReplyTo.fromMap(Map<String, dynamic>.from(data['replyTo'] as Map))
          : null,
      myUid: _myUid,
      deleted: data['type'] == 'deleted',
      edited: data['editedAt'] != null,
      onLongPress: (rect) => _showMessageActions(doc, rect),
      onQuoteTap: _jumpToMessage,
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Schlichte, niedrige Kopfzeile ohne Illustration, damit möglichst viel
      // vom Chat zu sehen ist. Zurück, Profilbild, Suche und ⋮-Menü sind gleich
      // grosse Kreise auf einer Linie, mit gleichem Rand links und rechts.
      appBar: AppBar(
        toolbarHeight: 56,
        automaticallyImplyLeading: false,
        titleSpacing: 12,
        title: Row(
          children: [
            if (widget.onBack != null) ...[
              HeaderCircle(
                child: IconButton(
                  tooltip: 'Zurück',
                  style: HeaderCircle.buttonStyle,
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: widget.onBack,
                ),
              ),
              const SizedBox(width: 10),
            ],
            PartnerPhoto(coupleId: widget.coupleId),
            const Spacer(),
            HeaderCircle(
              child: IconButton(
                tooltip: 'Nachrichten suchen',
                style: HeaderCircle.buttonStyle,
                icon: const Icon(Icons.search_rounded),
                onPressed: _openSearch,
              ),
            ),
            const SizedBox(width: 10),
            HeaderCircle(child: ChatMenu(coupleId: widget.coupleId)),
          ],
        ),
      ),
      body: Column(
        children: [
          _InviteBanner(coupleId: widget.coupleId),
          Expanded(
            // Antippen des Verlaufs schliesst die Tastatur.
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).unfocus(),
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _messages,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(
                      child: Text('Schreibt eure erste Nachricht 💬'),
                    );
                  }
                  _markPartnerMessagesRead(docs);
                  _countNewMessages(docs);
                  _docs = docs;
                  // Beim ersten Laden gelten alle Nachrichten als bekannt –
                  // nur später neu eintreffende gleiten sanft herein.
                  _knownIds ??= {for (final d in docs) d.id};
                  return Stack(
                    children: [
                      // Oben verblassen die Sprechblasen weich, bevor sie unter
                      // der Kopfzeile verschwinden.
                      ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (rect) => LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: const [Colors.transparent, Colors.white],
                          stops: [0, (_fadeHeight / rect.height).clamp(0, 1)],
                        ).createShader(rect),
                        // reverse: true -> neueste Nachricht unten, Liste startet unten.
                        child: ScrollablePositionedList.builder(
                          reverse: true,
                          itemScrollController: _itemScroll,
                          itemPositionsListener: _itemPositions,
                          // Oben Platz lassen, damit auch die älteste Nachricht
                          // ganz aus dem Verblassen herausscrollen kann.
                          padding: const EdgeInsets.fromLTRB(
                            12,
                            _fadeHeight,
                            12,
                            8,
                          ),
                          itemCount: docs.length,
                          itemBuilder: (context, i) {
                            final doc = docs[i];
                            final data = doc.data();
                            final time = (data['createdAt'] as Timestamp?)
                                ?.toDate();
                            // Datumstrenner über der ersten Nachricht eines Tages
                            // (die nächstältere Nachricht ist docs[i + 1]).
                            final older = i + 1 < docs.length
                                ? (docs[i + 1].data()['createdAt']
                                          as Timestamp?)
                                      ?.toDate()
                                : null;
                            final showDate =
                                time != null &&
                                (older == null || !_sameDay(time, older));
                            final isNew = _knownIds!.add(doc.id);
                            final item = Column(
                              children: [
                                if (showDate) _DateChip(date: time),
                                _SwipeToReply(
                                  enabled: data['type'] != 'deleted',
                                  onReply: () => _startReply(doc),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    decoration: BoxDecoration(
                                      color: doc.id == _highlightId
                                          ? Theme.of(context)
                                                .colorScheme
                                                .secondary
                                                .withValues(alpha: 0.25)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: _bubbleFor(doc, data, time),
                                  ),
                                ),
                              ],
                            );
                            return isNew
                                ? FadeSlideIn(
                                    key: ValueKey('neu-${doc.id}'),
                                    offset: 18,
                                    child: item,
                                  )
                                : item;
                          },
                        ),
                      ),
                      // "Nach unten"-Knopf mit Zähler, wenn man weiter oben liest.
                      if (!_atBottom)
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: Badge(
                            isLabelVisible: _newWhileAway > 0,
                            label: Text('$_newWhileAway'),
                            child: FloatingActionButton.small(
                              heroTag: 'nachUnten',
                              tooltip: 'Zur neuesten Nachricht',
                              onPressed: _scrollToBottom,
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          // "schreibt…"-Blase direkt unter der letzten Nachricht.
          TypingBubble(coupleId: widget.coupleId),
          if (_uploading) const LinearProgressIndicator(),
          if (_editingId != null)
            _EditBanner(
              onCancel: () {
                _input.clear();
                setState(() => _editingId = null);
              },
            ),
          if (_replyTo case final reply?)
            _ReplyPreview(
              reply: reply,
              isMine: reply.senderId == _myUid,
              onCancel: () => setState(() => _replyTo = null),
            ),
          _InputBar(
            controller: _input,
            onSend: _send,
            attachOpen: _attachOpen,
            onAttach: _uploading ? null : _openAttach,
            voice: _voice,
            onSelfie: _uploading ? null : _recordSelfie,
          ),
        ],
      ),
    );
  }
}

// Datumstrenner: "Heute", "Gestern" oder z. B. "Mo, 27. Okt."
class _DateChip extends StatelessWidget {
  const _DateChip({required this.date});

  final DateTime date;

  static const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  static const _months = [
    'Jan.',
    'Feb.',
    'März',
    'Apr.',
    'Mai',
    'Juni',
    'Juli',
    'Aug.',
    'Sep.',
    'Okt.',
    'Nov.',
    'Dez.',
  ];

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = daysBetween(day, today);
    if (diff == 0) return 'Heute';
    if (diff == 1) return 'Gestern';
    final base =
        '${_weekdays[date.weekday - 1]}, ${date.day}. ${_months[date.month - 1]}';
    return date.year == now.year ? base : '$base ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _label(),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

// Nachricht nach rechts ziehen = antworten. Ab 64 Pixeln wird ausgelöst, dann springt
// die Blase zurück. Ein Pfeil-Symbol taucht dabei links auf.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({
    required this.child,
    required this.onReply,
    required this.enabled,
  });

  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const _trigger = 64.0;
  double _dx = 0;
  bool _triggered = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final progress = (_dx / _trigger).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) {
        setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, _trigger + 16));
        if (!_triggered && _dx >= _trigger) {
          _triggered = true;
          HapticFeedback.lightImpact();
        }
      },
      onHorizontalDragEnd: (_) {
        if (_triggered) widget.onReply();
        setState(() {
          _dx = 0;
          _triggered = false;
        });
      },
      onHorizontalDragCancel: () => setState(() {
        _dx = 0;
        _triggered = false;
      }),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Opacity(
            opacity: progress,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.reply_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          AnimatedContainer(
            duration: Duration(milliseconds: _dx == 0 ? 200 : 0),
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// pending = noch nicht beim Server, sent = gespeichert (✓), read = gelesen (✓✓)
enum _Status { pending, sent, read }

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.imageUrl,
    required this.isGif,
    required this.audioUrl,
    this.waveform,
    required this.videoUrl,
    required this.mediaDuration,
    required this.time,
    required this.isMine,
    required this.status,
    required this.reactions,
    required this.replyTo,
    required this.myUid,
    required this.deleted,
    required this.edited,
    required this.onLongPress,
    required this.onQuoteTap,
  });

  final List<String> reactions; // Smileys beider Personen
  final ReplyTo? replyTo; // gesetzt = Antwort auf eine andere Nachricht
  final String myUid;
  final bool deleted; // Nachricht wurde gelöscht
  final bool edited; // Text wurde nachträglich bearbeitet
  final ValueChanged<Rect> onLongPress; // bekommt die Position der Blase
  final ValueChanged<String> onQuoteTap; // springt zur zitierten Nachricht (ID)
  final String text;
  final String? imageUrl; // gesetzt = Foto- oder GIF-Nachricht
  final bool isGif;
  final String? audioUrl; // gesetzt = Sprachnachricht
  final List<double>? waveform; // Lautstärke-Balken der Sprachnachricht
  final String? videoUrl; // gesetzt = Selfie-Videobotschaft
  final Duration mediaDuration; // Länge von Sprach- bzw. Videonachricht
  final DateTime? time;
  final bool isMine;
  final _Status status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Videobotschaften stehen frei als Kreis, ohne farbige Blase dahinter.
    final isVideo = videoUrl != null;
    // Fuchsohren-Blasen: eigene in Aqua (mit Schwanzspitze), die der anderen in Creme.
    final bg = isMine ? Kitsune.aqua : Kitsune.paper;
    final fg = isVideo ? scheme.onSurface : Kitsune.night;
    final t = time;
    final timeText = t == null
        ? ''
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    final quote = replyTo;
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.75,
      ),
      margin: isVideo ? const EdgeInsets.symmetric(vertical: 4) : null,
      padding: isVideo
          ? const EdgeInsets.only(bottom: 4)
          : imageUrl != null
          ? const EdgeInsets.fromLTRB(4, 4, 10, 6)
          : const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Zitat der Nachricht, auf die geantwortet wird.
          if (quote != null)
            GestureDetector(
              onTap: () => onQuoteTap(quote.id),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    left: BorderSide(
                      color: fg.withValues(alpha: 0.7),
                      width: 3,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quote.senderId == myUid ? 'Du' : 'Dein Schatz',
                      style: TextStyle(
                        color: fg,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      quote.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.85),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (imageUrl case final url?)
            _ChatImage(url: url, label: isGif ? 'GIF' : 'Foto')
          else if (audioUrl case final url?)
            AudioBubble(
              url: url,
              duration: mediaDuration,
              waveform: waveform,
              color: fg,
              // Eigene Blasen (aqua): Laternenrot, Blasen des Schatzes (Papier): Indigo.
              accent: isMine ? Kitsune.lantern : Kitsune.indigo,
            )
          else if (videoUrl case final url?)
            VideoBubble(url: url, duration: mediaDuration)
          else if (deleted)
            Text(
              '🚫 Nachricht gelöscht',
              style: TextStyle(
                color: fg.withValues(alpha: 0.75),
                fontSize: 15,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            Text(text, style: TextStyle(color: fg, fontSize: 16)),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                edited ? 'bearbeitet · $timeText' : timeText,
                style: TextStyle(
                  color: fg.withValues(alpha: 0.85),
                  fontSize: 11,
                ),
              ),
              // Häkchen nur bei eigenen Nachrichten.
              if (isMine) ...[
                const SizedBox(width: 3),
                Icon(
                  switch (status) {
                    _Status.pending => Icons.schedule,
                    _Status.sent => Icons.done,
                    _Status.read => Icons.done_all,
                  },
                  size: 15,
                  semanticLabel: switch (status) {
                    _Status.pending => 'Wird gesendet',
                    _Status.sent => 'Gesendet',
                    _Status.read => 'Gelesen',
                  },
                  // Gelesen: volle Farbe, sonst leicht gedämpft.
                  color: status == _Status.read
                      ? fg
                      : fg.withValues(alpha: 0.7),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Position der Blase auf dem Bildschirm mitgeben, damit das Popup daneben erscheint.
          Builder(
            builder: (bubbleContext) => GestureDetector(
              onLongPress: () {
                final box = bubbleContext.findRenderObject()! as RenderBox;
                onLongPress(box.localToGlobal(Offset.zero) & box.size);
              },
              // Blasen sind hell: Inhalte darin (z. B. Sprachnachricht) werden dunkel.
              child: isVideo
                  ? bubble
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Paper(
                        child: FoxBubble(
                          color: bg,
                          isMine: isMine,
                          child: bubble,
                        ),
                      ),
                    ),
            ),
          ),
          // Smiley-Reaktionen als kleine Plakette, leicht über den Blasenrand gezogen.
          if (reactions.isNotEmpty)
            Transform.translate(
              offset: const Offset(0, -10),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outline),
                ),
                child: Text(
                  _reactionLabel(reactions),
                  style: TextStyle(fontSize: 15, color: scheme.onSurface),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Gleiche Smileys zusammenfassen: "❤️ 2" statt "❤️❤️".
  static String _reactionLabel(List<String> reactions) {
    final unique = reactions.toSet();
    if (unique.length == 1 && reactions.length > 1) {
      return '${unique.first} ${reactions.length}';
    }
    return unique.join(' ');
  }
}

// Popup an der gedrückten Nachricht: Smiley-Leiste, darunter Antworten/Kopieren.
// Erscheint unterhalb der Nachricht; ist dort zu wenig Platz, oberhalb.
class _MessageActionsPopup extends StatelessWidget {
  const _MessageActionsPopup({
    required this.bubbleRect,
    required this.alignRight,
    required this.emojis,
    required this.selected,
    required this.onReact,
    required this.onReply,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
  });

  final Rect bubbleRect;
  final bool alignRight; // eigene Nachricht -> rechtsbündig
  final List<String> emojis;
  final String? selected;
  final ValueChanged<String> onReact;
  final VoidCallback onReply;
  final VoidCallback? onCopy; // null = keine Textnachricht
  final VoidCallback?
  onEdit; // null = nicht erlaubt (fremde Nachricht oder kein Text)
  final VoidCallback? onDelete; // null = fremde Nachricht

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final actionCount = 1 + [onCopy, onEdit, onDelete].nonNulls.length;
    // Smiley-Leiste (52) + Abstand (8) + eine Zeile (48) pro Aktion.
    final height = 60.0 + 48 * actionCount;
    final fitsBelow =
        bubbleRect.bottom + 8 + height < screen.height - padding.bottom - 8;
    final top = fitsBelow
        ? bubbleRect.bottom + 8
        : (bubbleRect.top - 8 - height).clamp(padding.top + 8, screen.height);

    // Popup schliessen und dann die Aktion ausführen.
    void run(VoidCallback action) {
      Navigator.pop(context);
      action();
    }

    return Stack(
      children: [
        Positioned(
          top: top,
          left: alignRight ? null : 12,
          right: alignRight ? 12 : null,
          child: Column(
            crossAxisAlignment: alignRight
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              // Smiley-Leiste als Pille.
              Material(
                elevation: 6,
                color: scheme.surface,
                borderRadius: BorderRadius.circular(28),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final emoji in emojis)
                        InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => run(() => onReact(emoji)),
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: emoji == selected
                                  ? scheme.secondaryContainer
                                  : null,
                            ),
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 26),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Aktionen darunter als kleine Liste.
              Material(
                elevation: 6,
                color: scheme.surface,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: 220,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ActionRow(
                        icon: Icons.reply_rounded,
                        label: 'Antworten',
                        onTap: () => run(onReply),
                      ),
                      if (onCopy case final copy?)
                        _ActionRow(
                          icon: Icons.copy_rounded,
                          label: 'Kopieren',
                          onTap: () => run(copy),
                        ),
                      if (onEdit case final edit?)
                        _ActionRow(
                          icon: Icons.edit_outlined,
                          label: 'Bearbeiten',
                          onTap: () => run(edit),
                        ),
                      if (onDelete case final delete?)
                        _ActionRow(
                          icon: Icons.delete_outline,
                          label: 'Löschen',
                          color: scheme.error,
                          onTap: () => run(delete),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Eine Zeile im Aktionsmenü des Popups.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color; // z. B. rot für Löschen

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: TextStyle(color: fg, fontSize: 16)),
              ),
              Icon(icon, color: fg, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// Leiste über dem Eingabefeld beim Bearbeiten, mit X zum Abbrechen.
class _EditBanner extends StatelessWidget {
  const _EditBanner({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_outlined, color: scheme.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Nachricht bearbeiten',
              style: TextStyle(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Bearbeiten abbrechen',
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

// Leiste über dem Eingabefeld: "Antwort auf …" mit X zum Abbrechen.
class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({
    required this.reply,
    required this.isMine,
    required this.onCancel,
  });

  final ReplyTo reply;
  final bool isMine;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
      ),
      child: Row(
        children: [
          Icon(Icons.reply_rounded, color: scheme.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMine
                      ? 'Antwort auf deine Nachricht'
                      : 'Antwort an deinen Schatz',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  reply.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Antwort abbrechen',
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

// Foto oder GIF in der Sprechblase als kleine Vorschau; antippen öffnet es gross mit Zoom.
class _ChatImage extends StatelessWidget {
  const _ChatImage({required this.url, this.label = 'Foto'});

  static const _width = 180.0;
  static const _maxHeight = 220.0; // hohe Bilder werden oben/unten beschnitten

  final String url;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
            body: Center(child: InteractiveViewer(child: Image.network(url))),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: _maxHeight),
          child: Image.network(
            url,
            width: _width,
            fit: BoxFit.cover,
            // Nur so gross dekodieren, wie die Blase ist (spart viel Speicher).
            cacheWidth: (_width * MediaQuery.devicePixelRatioOf(context))
                .round(),
            semanticLabel: label,
            // Platzhalter, bis das Bild geladen ist (sonst wäre die Blase kurz flach).
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                frame == null && !wasSynchronouslyLoaded
                ? const SizedBox(
                    width: _width,
                    height: 140,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : child,
            errorBuilder: (context, error, stack) => const SizedBox(
              width: _width,
              height: 100,
              child: Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
      ),
    );
  }
}

// Eingabeleiste: Foto · Textfeld · Senden (wenn Text da ist) oder Mikrofon (wenn leer).
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.attachOpen,
    required this.onAttach,
    required this.voice,
    required this.onSelfie,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool attachOpen; // "+"-Popup offen -> Knopf zeigt "×"
  final ValueChanged<Rect>? onAttach; // null = gerade wird hochgeladen
  final VoiceRecorderController voice;
  final VoidCallback? onSelfie; // null = gerade wird hochgeladen

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
        child: ListenableBuilder(
          listenable: Listenable.merge([controller, voice]),
          builder: (context, _) {
            final hasText = controller.text.trim().isNotEmpty;
            final state = voice.state;
            // Mikrofon behält dank Schlüssel seinen Zustand, auch wenn sich
            // die Knöpfe daneben ändern (sonst bricht das Halten ab).
            final mic = VoiceRecordButton(
              key: const ValueKey('mic'),
              controller: voice,
            );

            // Aufnahme läuft: links Zeit + Live-Welle, rechts Mikrofon bzw. Senden.
            if (state != VoiceState.idle) {
              return Row(
                children: [
                  Expanded(child: VoiceRecordingBar(controller: voice)),
                  const SizedBox(width: 8),
                  if (state == VoiceState.holding)
                    mic
                  else
                    PressScale(
                      child: IconButton.filled(
                        tooltip: 'Sprachnachricht senden',
                        onPressed: voice.send,
                        style: IconButton.styleFrom(
                          backgroundColor: Kitsune.lantern,
                          foregroundColor: Kitsune.paper,
                          minimumSize: const Size(52, 52),
                        ),
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ),
                ],
              );
            }

            return Row(
              children: [
                // "+" wie bei Signal; dreht sich zum "×", solange das Popup offen ist.
                Builder(
                  builder: (buttonContext) => IconButton(
                    tooltip: 'Anhang senden',
                    onPressed: onAttach == null
                        ? null
                        : () {
                            final box =
                                buttonContext.findRenderObject()! as RenderBox;
                            onAttach!(
                              box.localToGlobal(Offset.zero) & box.size,
                            );
                          },
                    icon: AnimatedRotation(
                      turns: attachOpen ? 0.125 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.add_rounded, size: 28),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Nachricht',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (hasText)
                  PressScale(
                    child: IconButton.filled(
                      onPressed: onSend,
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.tertiary,
                        foregroundColor: scheme.onTertiary,
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const Icon(Icons.send_rounded),
                    ),
                  )
                else ...[
                  mic,
                  // Eigener Knopf für Selfie-Videobotschaften, rechts neben dem Mikrofon.
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: 'Selfie-Videobotschaft',
                    onPressed: onSelfie,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    icon: const Icon(Icons.video_camera_front_outlined),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _Attachment { gallery, camera, video, gif }

/// Schlichtes Popup über dem "+": helle Papierkarte mit vier Zeilen.
/// Geht aus der Ecke beim Knopf auf; Tippen daneben schliesst es.
class _AttachPopup extends StatelessWidget {
  const _AttachPopup({required this.anchor});

  final Rect anchor;

  static Future<_Attachment?> show(BuildContext context, Rect anchor) =>
      showGeneralDialog<_Attachment>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Schliessen',
        barrierColor: Colors.black26,
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) => _AttachPopup(anchor: anchor),
        transitionBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(begin: 0.85, end: 1.0).animate(curved),
              alignment: Alignment.bottomLeft,
              child: child,
            ),
          );
        },
      );

  static const _items = [
    (_Attachment.gallery, Icons.photo_library_outlined, 'Galerie'),
    (_Attachment.camera, Icons.photo_camera_outlined, 'Kamera'),
    (_Attachment.video, Icons.videocam_outlined, 'Video'),
    (_Attachment.gif, Icons.gif_box_outlined, 'GIF'),
  ];

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Stack(
      children: [
        Positioned(
          left: anchor.left + 8,
          bottom: screen.height - anchor.top + 6,
          child: Material(
            color: Kitsune.paper,
            elevation: 10,
            shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 200,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, (what, icon, label)) in _items.indexed) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        indent: 52,
                        color: Kitsune.hairline,
                      ),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(what),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        child: Row(
                          children: [
                            Icon(icon, color: Kitsune.night, size: 22),
                            const SizedBox(width: 14),
                            Text(
                              label,
                              style: const TextStyle(
                                color: Kitsune.night,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Zeigt den Einladungscode an, solange die Partnerin noch nicht beigetreten ist.
class _InviteBanner extends StatelessWidget {
  const _InviteBanner({required this.coupleId});

  final String coupleId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('couples')
          .doc(coupleId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final members = (data?['members'] as List?) ?? const [];
        if (data == null || members.length >= 2) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Text(
                'Warte auf deine Partnerin – schick ihr diesen Code:',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 8),
              SelectableText(
                data['inviteCode'] as String? ?? '',
                style: TextStyle(
                  fontSize: 28,
                  letterSpacing: 6,
                  fontWeight: FontWeight.bold,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
