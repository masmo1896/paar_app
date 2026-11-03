/// Japanische Weisheiten für die Home-Seite: jeden Tag eine, bei euch beiden
/// dieselbe. Original (Japanisch), Lesung, Übersetzung und was ihr als Paar
/// daraus lernen könnt.
library;

import 'dates.dart';

class Wisdom {
  const Wisdom(this.japanese, this.reading, this.meaning, this.lesson);

  final String japanese;
  final String reading;
  final String meaning; // wörtlich bzw. Sinn
  final String lesson; // was es für eure Beziehung heisst
}

const wisdoms = [
  Wisdom(
    '一期一会',
    'ichi-go ichi-e',
    'Eine Zeit, eine Begegnung.',
    'Jeder gemeinsame Moment kommt so nie wieder. Leg heute das Handy weg, '
        'wenn ihr zusammen seid, und seid ganz da.',
  ),
  Wisdom(
    '七転び八起き',
    'nana korobi ya oki',
    'Siebenmal fallen, achtmal aufstehen.',
    'Streit und schwere Tage gehören dazu. Stark ist ein Paar, das immer '
        'wieder zueinander zurückfindet.',
  ),
  Wisdom(
    '金継ぎ',
    'kintsugi',
    'Mit Gold flicken.',
    'Zerbrochenes Geschirr wird in Japan mit Gold repariert – die Narbe wird '
        'zum schönsten Teil. Was ihr gemeinsam heilt, macht euch wertvoller.',
  ),
  Wisdom(
    '石の上にも三年',
    'ishi no ue ni mo san-nen',
    'Auch auf einem Stein: drei Jahre.',
    'Sitzt man lange genug auf einem kalten Stein, wird er warm. Geduld und '
        'Beständigkeit lassen Nähe wachsen.',
  ),
  Wisdom(
    '以心伝心',
    'ishin denshin',
    'Von Herz zu Herz, ohne Worte.',
    'Mit der Zeit versteht man sich ohne Worte. Achte heute auf die kleinen '
        'Zeichen deines Schatzes – und sag trotzdem, was du fühlst.',
  ),
  Wisdom(
    '思いやり',
    'omoiyari',
    'Mitgefühl, das vorausdenkt.',
    'Omoiyari heisst, die Bedürfnisse des anderen zu spüren, bevor er sie '
        'ausspricht. Was könnte deinem Schatz heute guttun?',
  ),
  Wisdom(
    '雨降って地固まる',
    'ame futte ji katamaru',
    'Nach dem Regen wird der Boden fest.',
    'Ein ehrlich ausgetragener Streit kann eure Beziehung fester machen als '
        'zuvor – wenn ihr danach wirklich zuhört.',
  ),
  Wisdom(
    '花より団子',
    'hana yori dango',
    'Lieber Klösse als Blüten.',
    'Das Praktische zählt oft mehr als die schöne Geste. Manchmal ist '
        '«Ich koche heute» romantischer als Rosen.',
  ),
  Wisdom(
    '侘寂',
    'wabi-sabi',
    'Schönheit im Unvollkommenen.',
    'Niemand ist perfekt – auch ihr nicht. Liebt gerade die kleinen Macken, '
        'sie machen euch einzigartig.',
  ),
  Wisdom(
    '生き甲斐',
    'ikigai',
    'Wofür es sich zu leben lohnt.',
    'Unterstützt euch gegenseitig bei dem, was euch erfüllt. Frag heute: '
        '«Was gibt dir gerade Energie?»',
  ),
  Wisdom(
    '塵も積もれば山となる',
    'chiri mo tsumoreba yama to naru',
    'Auch Staub wird, aufgehäuft, zum Berg.',
    'Grosse Liebe besteht aus vielen kleinen Gesten. Eine Nachricht, eine '
        'Laterne, ein Kaffee – heute zählt jedes Körnchen.',
  ),
  Wisdom(
    '急がば回れ',
    'isogaba maware',
    'Wenn du es eilig hast, nimm den Umweg.',
    'Wichtige Gespräche nicht zwischen Tür und Angel führen. Nehmt euch Zeit '
        '– der ruhige Weg ist oft der schnellere.',
  ),
  Wisdom(
    '和',
    'wa',
    'Harmonie.',
    'Harmonie heisst nicht, immer gleicher Meinung zu sein, sondern einen Weg '
        'zu finden, mit dem ihr beide gut leben könnt.',
  ),
  Wisdom(
    '猿も木から落ちる',
    'saru mo ki kara ochiru',
    'Auch Affen fallen von Bäumen.',
    'Jeder macht Fehler, auch der Geschickteste. Sei heute nachsichtig – mit '
        'deinem Schatz und mit dir selbst.',
  ),
  Wisdom(
    '感謝',
    'kansha',
    'Dankbarkeit.',
    'Sag deinem Schatz heute eine Sache, für die du dankbar bist. Kleine '
        'Danke halten die Liebe frisch.',
  ),
  Wisdom(
    '縁',
    'en',
    'Die schicksalhafte Verbindung.',
    'In Japan glaubt man an einen unsichtbaren roten Faden zwischen '
        'Menschen, die zusammengehören. Pflegt euren Faden.',
  ),
  Wisdom(
    '案ずるより産むが易し',
    'anzuru yori umu ga yasushi',
    'Tun ist leichter als sich sorgen.',
    'Das Gespräch, vor dem ihr euch drückt, ist meist halb so schlimm wie '
        'gedacht. Sprecht es an – gemeinsam.',
  ),
  Wisdom(
    '十人十色',
    'jūnin toiro',
    'Zehn Menschen, zehn Farben.',
    'Ihr dürft verschieden sein. Neugier auf die Farben des anderen ist '
        'besser als der Wunsch, dass er so ist wie du.',
  ),
  Wisdom(
    '一石二鳥',
    'isseki nichō',
    'Ein Stein, zwei Vögel.',
    'Verbindet Alltag mit Zweisamkeit: zusammen einkaufen, kochen, '
        'spazieren – Pflicht und Nähe in einem.',
  ),
  Wisdom(
    '我慢',
    'gaman',
    'Ausharren mit Würde.',
    'Schwere Zeiten gemeinsam tragen, ohne einander die Schuld zu geben. '
        'Gaman heisst auch: füreinander stark sein.',
  ),
  Wisdom(
    '笑う門には福来る',
    'warau kado ni wa fuku kitaru',
    'Durch das Tor, wo gelacht wird, kommt das Glück.',
    'Lacht viel zusammen – über den Tag, über euch selbst. Ein lachendes '
        'Zuhause zieht das Glück an.',
  ),
  Wisdom(
    '初心',
    'shoshin',
    'Der Geist des Anfängers.',
    'Schau deinen Schatz heute an, als würdest du ihn neu kennenlernen. Was '
        'entdeckst du, das dir bisher entgangen ist?',
  ),
  Wisdom(
    '継続は力なり',
    'keizoku wa chikara nari',
    'Beständigkeit ist Kraft.',
    'Kleine Rituale – der Gute-Nacht-Gruss, die Frage des Tages – geben eurer '
        'Liebe Halt, gerade weil sie jeden Tag passieren.',
  ),
  Wisdom(
    '木を見て森を見ず',
    'ki o mite mori o mizu',
    'Die Bäume sehen, aber nicht den Wald.',
    'Lass dich von einer Kleinigkeit nicht ärgern. Schau aufs Ganze: Was ist '
        'gut zwischen euch?',
  ),
  Wisdom(
    '良薬は口に苦し',
    'ryōyaku wa kuchi ni nigashi',
    'Gute Medizin schmeckt bitter.',
    'Ehrliches Feedback tut manchmal weh, hilft aber. Sag es liebevoll – und '
        'hör es dir offen an.',
  ),
  Wisdom(
    '心',
    'kokoro',
    'Herz, Geist und Gefühl in einem.',
    'Im Japanischen sind Herz und Verstand ein Wort. Hör heute nicht nur auf '
        'die Worte deines Schatzes, sondern auf sein Kokoro.',
  ),
  Wisdom(
    '一寸先は闇',
    'issun saki wa yami',
    'Einen Zoll voraus ist Dunkelheit.',
    'Niemand kennt die Zukunft. Umso wertvoller ist es, heute zu sagen: '
        '«Ich hab dich lieb.»',
  ),
  Wisdom(
    '旅は道連れ世は情け',
    'tabi wa michizure, yo wa nasake',
    'Auf Reisen braucht man Begleitung, im Leben Mitgefühl.',
    'Das Leben ist eine Reise – mit dem richtigen Menschen an der Seite ist '
        'jeder Weg schöner. Plant euer nächstes Abenteuer!',
  ),
  Wisdom(
    '自分を磨く',
    'jibun o migaku',
    'Sich selbst polieren.',
    'Eine gute Beziehung braucht zwei Menschen, die auch an sich selbst '
        'wachsen. Was möchtest du für dich lernen?',
  ),
  Wisdom(
    '花鳥風月',
    'kachō fūgetsu',
    'Blumen, Vögel, Wind und Mond.',
    'Die Schönheit der Natur gemeinsam erleben. Geht heute Abend kurz raus '
        'und schaut zusammen zum Mond.',
  ),
  Wisdom(
    '甘え',
    'amae',
    'Sich liebevoll anlehnen dürfen.',
    'Amae ist das Vertrauen, beim anderen schwach sein zu dürfen. Zeig '
        'deinem Schatz heute, dass er sich bei dir anlehnen kann.',
  ),
  Wisdom(
    '口は禍の門',
    'kuchi wa wazawai no kado',
    'Der Mund ist das Tor des Unglücks.',
    'Im Ärger gesagte Worte lassen sich nicht zurücknehmen. Erst atmen, dann '
        'reden.',
  ),
];

/// Weisheit für einen Tag – bei euch beiden dieselbe.
Wisdom wisdomFor(DateTime day) {
  final index = daysBetween(DateTime(2026), day);
  return wisdoms[index % wisdoms.length];
}
