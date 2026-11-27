# Obiettivi locali

Arcane legge salvataggi confermati, non la memoria del gioco. Il primo catalogo è
Link’s Awakening (`01006BB00C6F0000`, versione gioco `1.0.0`): 1, 10 e 30
conchiglie e 4 e 12 frammenti di cuore. Il layout `0xE` viene dalla
[specifica LASRecomp](https://github.com/peiikai/LASRecomp/blob/main/docs/save-format.md)
([MIT, © 2026 Peiikai](https://github.com/peiikai/LASRecomp/blob/main/LICENSE)).
Non si distribuiscono salvataggi Nintendo. [TrophyNX](https://github.com/Imp3r1us/TrophyNX)
è il precedente per regole dichiarative e lettura all'uscita; Arcane non ne incorpora il codice.

## Lettura e presentazione

- `LaunchService` osserva l’uscita di un gioco lanciato da Arcane. Il lettore lavora sulla
  coda dei salvataggi, con il lease del titolo, sulla cartella account confermata di nxnative.
  Ogni `savedataN.bin` ha lunghezza esatta, versione e due CRC verificati. Non si sommano gli
  slot; si conserva il massimo per metrica. File illeggibili, corrotti o sconosciuti non valgono zero.
- Lo stato è per UUID del profilo, Title ID, versione del gioco e schema. Le date indicano la
  **prima conferma in Arcane**, anche per un traguardo già ottenuto; non sono date storiche.
  La lettura non modifica il salvataggio. Il profilo fissato al lancio determina il percorso:
  quello originale usa la cartella storica, gli altri il proprio `DM_SAVE`, verificato contro
  il percorso preparato da Arcane. Cambiare profilo prima dell'uscita non cambia l'attribuzione.
  Arcane Dev non legge salvataggi reali. Percorsi personalizzati, recuperi pendenti e cartelle
  con più utenti nxnative non si leggono.
- La scheda Spotlight e la schermata Obiettivi usano il riepilogo condiviso con Steam,
  senza una rarità fittizia. La schermata rispetta Riduci movimento anche nei filtri, nelle
  righe, nella transizione del dettaglio e nella sfumatura della lista. Il toast compare
  quando Arcane torna davanti, con un titolo al singolare o al plurale. Al Play seguente
  l’overlay compatibile riceve l’ultimo snapshot, solo con totale, sbloccati e titoli recenti.
  L’host fissato a `99224562` non dichiara `DM_OVERLAY_DATA`; l’overlay richiede una build
  del gioco con un host compatibile.

## Aggiungere un titolo

1. Identificare Title ID base e versione esatta del bundle. Documentare formato,
   provenienza e licenza. Aggiungere sotto `ArcanePorting/Saves` un lettore che
   restituisce metriche tipizzate o nessun dato, con letture limitate e soli file confermati.
2. Aggiungere in `OortLibrary/Resources` un pack JSON: `schemaVersion`, `titleID`,
   `gameVersion` e `reader`. Ogni record include `id` stabile, `title` e `description`
   (`en`, `it`, `fr`, `de`, `es`, `pt-BR`, `zh-Hans`), `icon` (SF Symbol) e `rule`
   (`metric`, `op: "gte"`, `threshold`). Registrare il pack e la dispatch del lettore.
3. Provare su fixture sintetiche appena prima e dopo le soglie, con corruzione,
   versione sconosciuta e profili separati. Verificare che i byte del salvataggio
   non cambino e che l’overlay non riceva ID di profilo o dati grezzi.

Esempio, non supportato: per il Pokédex di Pokémon Legends: Z-A,
[`SAV9ZA`](https://github.com/kwsch/PKHeX/blob/master/PKHeX.Core/Saves/SAV9ZA.cs)
e [`Zukan9a`](https://github.com/kwsch/PKHeX/blob/master/PKHeX.Core/Saves/Substructures/Gen9/ZA/Zukan9a.cs)
di PKHeX indicano come distinguere revisione, specie viste e catturate. Una metrica
conta le specie uniche catturate nel Pokédex base, non forme, box o DLC, e si
confronta con la schermata del gioco prima di fissare soglie come 10, 50 e 100.
PKHeX è GPL-3.0: verificare la licenza prima di riusarne il codice.
