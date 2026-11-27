# Arcane — come si costruisce

Questa guida dice **dove va una cosa nuova e come si scrive**, partendo da quello che il codice fa già. Prima di scrivere codice nuovo, trova qui la ricetta che corrisponde e segui il file d'esempio indicato. Se nessuna ricetta va bene, non inventarne una in silenzio: proponila al maintainer e, una volta approvata, aggiungila qui.

Gli altri documenti:
- [architecture.md](../how-it-works/architecture.md): come funziona ogni area;
- [flows.md](../how-it-works/flows.md): i percorsi completi, dall'input all'effetto;
- [file-map.md](file-map.md): un file per riga;
- [validation.md](validation.md): cosa ha validato il maintainer.

<!-- ARCANE-PERSO:BEGIN -->
## Arcane perso — regole del fork

Queste regole integrano le ricette qui sotto. Sono criteri per il lavoro sul fork, non una descrizione delle coperture già implementate.

### Interfaccia e verifica

- **Selene, senza doppioni.** Usa le viste e i componenti condivisi della sezione 3. Mantieni schermate sobrie, leggibili, con una gerarchia chiara. Confronta la resa con Selene e con l'ultima versione convalidata; riprendi il disegno, non gli asset privi di licenza. Usa token semantici condivisi per dimensioni, spazi, colori, effetti e durate: `canvas.u(…)` converte le unità, non sostituisce un token. Aggiungi il token mancante nel punto condiviso, non un valore locale.
- **Conferme macOS.** Usa `OortActionBar` e `ActionBarOrder`. Con due pulsanti, Annulla sta a sinistra anche se l'azione a destra è distruttiva; in quel caso Annulla ha il focus iniziale. Con tre, la distruttiva sta a sinistra con uno stacco, poi ritorno e azione principale. Da quattro, le risposte vanno in verticale: principale, alternative, distruttive, ritorno. La distruttiva usa `dangerText`, senza il riempimento dell'azione predefinita. Allarga la scheda per le traduzioni; le righe di azioni di un oggetto non sono dialoghi e cominciano dalla principale.
- **Focus e indizi.** Identifica ogni risposta con un caso o un ID stabile (`DialogAnswer`); la posizione serve soltanto a disporle e percorrerle. Annullamento e focus iniziale sono due scelte distinte: Salva può avere il focus mentre Esc/B continua a modificare. L'indizio B riprende la parola del pulsante. Un indizio non è l'unico modo di eseguire un'azione: usa `OortItemActions` (e `oortItemMenu` per il clic destro). La guida ⓘ di una riga di Settings si apre anche con `I`.
- **Input e aiuto.** Solo il livello attivo riceve l'input, è esposto a VoiceOver e mostra la sua `SeleneHintsBar`. Ogni azione annunciata nell'aiuto ha un glifo `ButtonPrompts` adatto alla periferica (anche per i gesti tenuti); niente comandi duplicati o glifi ambigui. Mantieni il focus visibile, proteggi la digitazione e ripristina il focus alla chiusura. Un puntatore fermo non ruba il focus.
- **Movimento e stato.** Usa `seleneReduceMotion` (app e sistema) per togliere il moto decorativo, i loop e gli spostamenti non necessari; lascia leggibili focus e progresso. Le transizioni non bloccano le azioni e si interrompono al ritorno. Niente doppia barra di progresso per la stessa operazione; distingui attesa, lavoro, esito ed errore. Nel Cloud mantieni il lessico coerente: Invia, Scarica, Libera (Cestino); un messaggio con un'azione utile per ogni causa. Per gli stati convalidati (punti, badge, focus, colori) consulta `validation.md`.
- **Prova di consegna.** Rendi le viste reali fuori schermo con i probe `Tests/CatalogAppChecks/run_*.py` e fixture sintetiche; ispeziona personalmente i PNG di ogni schermata, pannello e dialogo toccati. Confronta prima/dopo dove cambia una vista esistente e verifica gli stati rilevanti: focus, sovrapposizioni, finestra piccola, testi lunghi, movimento ridotto ed errori. Per Cloud/porting copri anche offline, annullamento, spazio/quota, profilo assente, Switch 2 e operazioni concorrenti quando pertinenti. Indica i percorsi delle prove e cosa resta da provare con manetta fisica, mouse, tastiera e VoiceOver. I probe non sostituiscono la prova interattiva di Sofian.

### Rami

- **Nome.** `feat/`, `fix/`, `docs/` o `chore/` seguito dal tema; `release/` per una linea di versione. Mai il nome di un agente o di uno strumento. Un contributo inviato ad Arcane segue il nome di Arcane, `bium/<tema>`. Regole proposte per GitHub: [branch-rules.md](branch-rules.md).

### Dati, rete e distribuzione

- **Cestino sempre.** Nel fork questa regola prevale sulle eccezioni di eliminazione della sezione 5: ogni rimozione di file o cartelle passa dal Cestino locale o remoto, anche per cache e pulizie di build. Se il Cestino non è disponibile, conserva i dati e segnala il problema. Libera solo dopo verifica della copia di recupero nella propria libreria. Installa e verifica il sostituto prima di ritirare la vecchia app o cache; annullamento o errore lasciano recuperabile la copia valida.
- **Confini dei dati.** Separa i salvataggi per profilo nelle modifiche che li riguardano, con migrazione reversibile e prova di ripristino; non dare per scontata la migrazione dei salvataggi esistenti. Conserva code e stato ripristinabili dopo riavvio. Per l'Inbox, identifica e proponi, poi dopo conferma copia e verifica prima di spostare l'originale nel Cestino; il porting continua a collegare i sorgenti senza copiarli nella build.
- **Cloud personale, non distribuzione.** L'eccezione alla regola di rete della sezione 6 è soltanto il flusso personale esplicitamente scelto, verso l'account e le cartelle configurati. Una libreria di riferimento resta in sola lettura: Arcane non cambia i permessi Drive e scrive solo nella libreria personale. Niente link pubblici per importare o distribuire ROM, app portate (contengono il gioco), o altro contenuto di gioco. Chi usa Arcane porta i propri giochi con le proprie chiavi. Mai chiavi, token o salvataggi negli artefatti di build, nelle fixture, nei log o nei report condivisi.
- **Client Google privato.** Solo un bundle privato può incorporare il client OAuth di Sofian. Nessun ID o segreto Google nel repository o in app, ZIP e DMG pubblici; verifica il plist del pacchetto pubblico. Non confondere quel client con l'ID pubblico Nextendo. Segui [development.md](development.md#private-google-drive-builds) per il packaging.
<!-- ARCANE-PERSO:END -->

## 1. Dove va il codice

| Cosa | Dove | Perché |
|---|---|---|
| Modelli, regole, parsing, persistenza, rete, processi, decisioni di focus e di layout calcolabili | `core/OortLibrary` | Si prova con XCTest senza finestre. |
| Codice del Core di un'area | La cartella dell'area: `App`, `Catalog`, `Library`, `Selene`, `Details`, `Artwork`, `Achievements`, `Mods`, `Settings`, `Steam` | Ogni area si trova da un solo posto. |
| Codice che è Switch (nxnative, chiavi, store Nintendo, RomFS, `env.txt`), senza SwiftUI | il target `ArcanePorting`, `Sources/ArcanePorting/`, e la sottocartella della parte: `Setup`, `Build`, `Launch`, `GameSettings`, `Cheats`, `Store`, `Saves`, `Mods` (con `Mods/GameBanana`), `Catalog`, `Library`, `Details`, `Settings`, `App` | La base non importa il modulo: il compilatore tiene il confine. |
| Viste SwiftUI, integrazione AppKit, controller, coordinamento degli store | `Sources/NXLibrary` | Dipende dal Core, mai il contrario. |
| Testi mostrati all'utente | `NXLibraryCore/Resources/Localizable.xcstrings` | Un solo catalogo per le sette lingue. |
| Test | `core/Tests/OortLibraryTests` per un file che compila con la sola base, altrimenti `Tests/ArcanePortingTests`, il file intero; la fixture Steam è un solo file, collegato nel secondo; prove senza finestre dei corpi reali delle viste in `Tests/CatalogAppChecks`; controlli del pacchetto in `Tests/PublicationChecks` | — |

Regole:
- **Una decisione sta nel Core se si può scrivere senza SwiftUI.** Esempi:
  - quali righe mostra il pannello Details: `DetailsFacts`;
  - dove si sposta il focus: `SpotlightState`, `DetailsFocus`, `ModStoreFocus`;
  - la geometria di una riga: `SpotlightRowGeometry`, `GridListLayout`.

  La vista disegna e traduce l'input.
- **La base non usa un tipo né un membro del modulo.** `NXLibraryCore` non importa `ArcanePorting`, quindi un uso non compila. Quando la base ha bisogno del modulo riceve un valore o una chiusura con un parametro obbligatorio. Esempio: `DevelopmentProfileImporter(fileManager:checks:)`, con `DevelopmentProfileImporter()` in `ArcanePorting/App/`.
- **Un'entrata della base per un tipo di `ArcanePorting/` sta in un'estensione dentro `ArcanePorting/`** (`Tipo+Porting.swift`, o `Tipo+Catalog.swift` per la conformità di un tipo del modulo) e chiama l'entrata generica della base. Esempio: `ArcanePorting/Catalog/CatalogStore+Porting.swift` dà `CatalogStore(directory:)` con tutti i tipi noti e l'import di `library.json` sopra `CatalogStore(directory:kinds:legacy:)`.
- **Un file oltre circa 800 righe si divide per compito** in estensioni `Tipo+Compito.swift` nella stessa cartella. Esempi: `PortingModel+Build.swift`, `SpotlightView+Input.swift`. Le proprietà memorizzate restano nel file del tipo; un membro `private` che serve da un altro file diventa interno, mai `public`. Un controllo senza finestre che legge il sorgente di un tipo legge tutti i suoi file (`PortingModel*.swift`).
- **`public` nel Core e nel modulo**, per ciò che l'app usa; **`package`** per ciò della base che usa solo il modulo, membro per membro, come chiede il compilatore. Un'estensione del modulo che crea un valore della base chiama un init `package` con tutti i valori (`GameDetailPresentation(title:…savePath:)`). Il target app è un eseguibile che nessuno importa: i suoi tipi restano interni.
- **Non far crescere `AppViewModel`.** Uno stato che appartiene a una sola schermata o a un solo pannello ha il suo modello. Esempi: `SavePanelModel`, `SetupCheckModel`, `ModStoreHost`, `AchievementsScreenModel`, `CatalogSourcesModel`. Le estensioni `AppViewModel+…` servono solo a collegare il coordinatore a un servizio del Core.
- **Una parte del modulo Switch ha il suo modello di area.** Esempi: `PortingModel`, `SetupModel`, `RuntimeSettingsModel`, `CheatsModel`, `AppIconModel`, `StoreMetadataModel`.
  - È una `final class` con `unowned let app: AppViewModel`; il coordinatore la crea come `lazy var` con un nome breve (`app.porting`).
  - Raggiunge il resto di Arcane solo da `app`. *Perché:* quell'elenco è ciò che il modulo dovrà chiedere alla base.
  - È `ObservableObject` solo se pubblica stato. Ogni schermata che mostra quello stato lo osserva con `@ObservedObject` (dall'`init` o passato dalla shell), mai attraverso il coordinatore.
  - Un lavoro in background non tocca il modello: è una funzione statica (`PortingModel.sweepStaleBuildTemp`).
  - Nessun nome è uguale fra il modello e il coordinatore.
- **Un solo writer per ogni file su disco.** Il catalogo lo scrive solo `CatalogRepository`, le impostazioni solo `AppSettingsStore`, le sessioni solo `PlaySessionStore`, le mod di un gioco solo `ModStore`.

## 2. Una fonte di giochi (Steam oggi, CrossOver e altre domani)

Esempio completo: Steam, documentato in [steam.md](../how-it-works/steam.md).

- Il gioco entra nel catalogo comune come `CatalogGame` con il **suo record reale**, un tipo che rispetta `CatalogSourceRecord` (`SteamCatalogGame` nella base, `PortedGame` nel modulo). Non si costruisce mai un gioco di un'altra fonte finto. Chi crea lo store o il decoder gli passa i tipi noti (`CatalogRecordKinds`); un record di un altro tipo resta conservato.
- Cosa offre la pagina lo dice `CatalogGamePresentation`, dalla presenza del record (`CatalogRecordPresence`): installazioni, operazioni supportate, `CatalogLaunchTarget`. L'ordine delle Opzioni comuni sta in `CatalogGameOptions`. Una fonte dichiara cosa sa fare; non aggiunge schermate parallele.
- I comandi di una fonte ricevono solo il suo record: i comandi Switch prendono `PortedGame`, quindi non possono partire da un gioco Steam.
- La lettura avviene su un worker annullabile, con limiti di dimensione e di cartelle. Il risultato porta una generazione o un ticket, e un risultato superato non si pubblica (`SteamCatalogReconciler`, `CatalogSourcesModel`).
- Un'assenza non è una cancellazione. Un disco scollegato, una scansione parziale o un titolo ambiguo conservano la voce, gli UUID e le scelte personali.
- I file di altre applicazioni si leggono e non si scrivono mai. Le letture protette passano da `InstallationFileSnapshot` e `InstallationDirectorySnapshot`.
- La fonte è facoltativa: se è spenta non si legge nulla e il resto si comporta come prima.
- **La funzione sta nell'app, il formato sta nella fonte.** Salvataggi, mod e cheat sono una sola schermata ciascuno; la fonte dice dove sono i file e come si leggono.

## 3. Una schermata o un pannello Selene

Esempi: `AchievementsScreen` con `AchievementsScreenModel` (schermata intera), `SavesPanel` con `SavePanelModel` (pannello), `ModStorePage` con `ModStoreHost` (pagina che scorre).

- **Misure in unità del canvas** 1920×1080: `canvas.u(…)` da `seleneCanvas` (`SeleneCanvasEnvironment.swift`), mai punti fissi per il layout della scena. Usare `SeleneTokens` per tipografia, spazi, raggi ed effetti, `SeleneTheme` per i colori della palette, `Motion` per le curve e `MaterialIcon` per le icone.
- **Componenti condivisi prima di tutto** (`Views/OortUI` e `Views/Components`):
  - `SeleneOptionRow`, `SeleneRow`, `SeleneToggleRow`, `SeleneValueRow`, `SeleneCycleRow` (in `SeleneSettingsRow.swift`);
  - `SelenePillButton`, `SeleneSwitch`, `SeleneValueChip`, `SeleneStatusDot` (stato in testo con punto decorativo: Cloud e Nextendo);
  - `SeleneOverlay` per il velo e il clic esterno, `SeleneConfirmDialog` e `SeleneSuccessNotice` per le carte;
  - `SeleneHintsBar`, `GamePrimaryActions`, `DetailsPanel`.

  Un componente nuovo nasce solo se nessuno di questi va bene.
- **Focus nel Core, input in un file `+Input`.** Lo stato del focus è un tipo del Core con i suoi test. La vista ha un'estensione `…+Input.swift` che traduce tastiera, mouse e controller in azioni sul modello.
- **Priorità dell'input:** menu e dialoghi nativi vengono prima delle schermate dell'app. La shell (`AppShellView`, `nativeDialogOwnsInput`) sospende il controller prima del routing e condivide il controllo con tastiera e menu. Nell'app dà l'input al livello più alto: un pannello sopra la pagina sospende l'input della pagina sotto.
- **Suggerimenti dei tasti:** `SeleneHintsBar` alla posizione condivisa `SeleneBottomScrim.hintsBottom` (32 unità dal fondo). I simboli vengono da `ButtonPrompts`.
- **Movimento:**
  - un blocco che scorre di un offset animato passa per `GlideGroup`;
  - i loop continui (anelli, bagliori, sfondi) girano in Core Animation o Metal, mai con timer SwiftUI a 30 fps;
  - Riduci movimento si legge da `seleneReduceMotion` e ferma tutto ciò che si muove da solo.
- **Suoni:** `SoundEffectService` con i cue Selene esistenti.
- **Testi:** frasi brevi e semplici, nelle sette lingue (sezione 7).

## 4. Un'impostazione

Esempio: qualunque riga di `SettingsCatalog`.

1. Il valore sta in `AppSettings`, con un default. La decodifica è **compatibile**: un file vecchio senza il campo prende il default, e un valore sconosciuto torna ad Automatic.
2. La riga si dichiara in `SettingsCatalog` (`row`/`action`) con identità stabile, sezione, titolo e descrizione. Così compare in **Search** e in **Changed** e torna al valore iniziale con il reset del gruppo.
3. Va nella sezione giusta di `SettingsSection` / `SettingsSidebarGroup`. Una sezione di piattaforma contiene solo impostazioni che agiscono sui giochi di quella piattaforma. Ogni impostazione sta in un solo posto.
4. Le preferenze fuori da `AppSettings`, come cloud o percorsi, compaiono in Changed attraverso il catalogo. Le credenziali non passano mai da `AppSettings` (sezione 6).

## 5. Un file su disco

Esempi: `AppSettingsStore`, `CatalogStore`, `PlaySessionStore`, `ModStore`.

- **Percorsi solo da `AppData`** (`AppData.supportRoot`, `AppData.cacheRoot`, `AppData.preferences`), così la copia Dev resta separata dalla release. Un file nuovo che la Dev deve ricevere va aggiunto alla lista dichiarata di `DevelopmentProfileImporter`; credenziali e token non si copiano.
- **Formato con versione** e lettura compatibile con i file vecchi; un campo nuovo è sempre facoltativo.
- **Scrittura sicura:** si scrive su un file temporaneo nella stessa cartella e lo si sostituisce in un passo solo. Per un file importante si tiene una copia valida (`.bak`) e si rilegge il candidato prima di pubblicarlo (`CatalogStore`).

  Oggi ogni store scrive per conto suo: non esiste un aiuto condiviso. Un nuovo store segue `CatalogStore` per i dati importanti e `AppSettingsStore` per le preferenze.
- **Un file illeggibile non si sovrascrive in silenzio:** si conserva e si segnala con un dialogo e Retry. Mai una libreria vuota automatica.
- **Eliminare:** si sposta nel Cestino, salvo nei casi documentati. Esempi: la cache di build di un gioco, le cartelle temporanee riconosciute da `BuildScratch.isManaged`.

## 6. Rete, chiavi e dati privati

Esempi: `BoundedDownload`, `GameBananaClient`, `IGDBClient`, `SteamMetadataService`.

- Ogni download passa da `BoundedDownload`, con limite di dimensione, redirect rifiutati e annullamento. Gli host sono fissati in un elenco.
- Richieste coalescenti, un numero massimo in contemporanea, cache su disco con una durata, e uso della copia salvata senza rete. Un errore non diventa un "non trovato" salvato in cache.
- Un risultato che arriva tardi (dopo un cambio di gioco o di lingua, o dopo la rimozione delle credenziali) non si pubblica.
- **Chiavi e credenziali** in un file con modo `0600`, dentro una cartella `0700`. Non vanno mai in log, URL, `AppSettings` o `UserDefaults`. `DiagnosticsReport` toglie la home e i valori che sembrano chiavi.
- Nessun dato personale o privato va in rete, e nessun dato dei giochi altrui viene scritto.

## 7. Testi e lingue

- Il solo nome dell’app viene da `AppIdentity.displayName`. I testi del catalogo mantengono le chiavi upstream: `L10n` applica la marca alla copia resa.

- Ogni testo dell'interfaccia passa da `L10n.text` / `L10n.format` e sta in `Localizable.xcstrings` con en, it, fr, de, es, pt-BR e zh-Hans.
- Le identità restano in inglese e non si traducono: rawValue salvati, rowID, variabili `DM_*`, eventi dell'engine.
- I nomi dei simboli SF (`systemImage`, `systemName`, `systemSymbolName`) sono letterali e non passano da `L10n`: tradotti non trovano il simbolo. `check_localizations.py` lo verifica sui sorgenti.
- Le viste leggono la lingua da `nxAppLocale`, così un cambio di lingua non ricrea stato o focus.
- Parole comuni ai sistemi: `design/vocabulary.json` (proposta, non ancora approvata) le fissa in fr e en; `scripts/check_vocabulary.py` rifiuta uno scarto nuovo e chiede di togliere dal registro quelli risolti (`--prune`). Il job `Mac / checks` della CI lo esegue.
- In francese l'interfaccia dà del « tu », come il sito, Windows e i telefoni. `check_localizations.py` rifiuta « vous », « votre », « vos », « faites », « dites », « êtes » e le parole in « -ez » nel catalogo e nei pacchetti di obiettivi; `FRENCH_FORMAL_EXCEPTIONS` elenca le sole parole che non si rivolgono a nessuno.
- Controllo: `scripts/check_localizations.py`, che verifica copertura, segnaposto, plurali e il « tu » francese.

## 8. Lavoro in background e stato

- Il lavoro su file e rete gira fuori dal thread principale; ciò che cambia l'interfaccia si pubblica sul main actor.
- Un processo si aspetta con `Process.runWithExitWait` (o `CommandRunning`), mai con `waitUntilExit`: quello fa girare il run loop mentre aspetta, e un comando atteso dentro un aggiornamento di SwiftUI lo fa ripartire a metà e chiudere l'app.
- Un comando di cui una vista ha bisogno gira in un task fuori dal thread principale prima che la vista lo legga; la vista legge solo la risposta tenuta. Esempio: `EngineAncestry.answer` e `keptAnswer`, chiesti da `CheatsModel.prepare(for:)`.
- Un `body` e l'initializer di una vista non leggono file: si ridisegnano a ogni cambio della shell. Ciò che viene dal disco si legge quando la pagina si apre o quando può cambiare (`GameOptionsFiles`, `GameDetailView.reloadCheats`), e un'assenza si ricorda (`GameIconProvider`).
- Ogni lavoro annullabile porta un'identità (generazione, ticket, UUID del gioco). Il risultato si applica solo se l'identità è ancora quella attuale.
- Le operazioni su un gioco che si escludono a vicenda (salvataggi, Play, installazioni, aggiornamento dell'app) passano da `SaveOperationGate`.
- Niente ritardi a tempo, ridisegni forzati o errori nascosti per far "sembrare" che funzioni (AGENTS.md).

## 9. Test

- Prima il test che fallisce, poi il codice (TDD). Per un bug: prima la causa, poi un test che la riproduce.
- I dati sono sintetici, in cartelle temporanee, con dipendenze sostituibili: `CommandRunning`, trasporti di rete iniettati, `SaveTestHome`, `SteamTestSupport`, `CatalogTestSupport`. Niente file reali dell'utente, niente chiavi o ROM.
- Per `UserDefaults`, passa il percorso assoluto del file senza `.plist` come `suiteName`, dentro la cartella temporanea già rimossa dalla fixture (esempio: `LocalAchievementTests`). Un nome di dominio univoco non isola la scrittura.
- Si prova il comportamento, non il mock.
- La build di release compila senza warning: un warning nuovo si risolve nello stesso commit che lo introduce.
- Comandi in [development.md](development.md#verification). I test non sostituiscono la validazione del maintainer.

## 10. Documentazione

Ogni modifica aggiorna, nello stesso commit:
- la riga del file in [file-map.md](file-map.md) e il totale;
- la sezione della sua area in [architecture.md](../how-it-works/architecture.md), o il documento dell'area (come [steam.md](../how-it-works/steam.md));
- il percorso in [flows.md](../how-it-works/flows.md), se cambia un flusso;
- [validation.md](validation.md), se il maintainer ha validato qualcosa o se c'è una cosa nuova da validare;
- questa guida, se nasce una ricetta nuova approvata.

I documenti descrivono il **presente**. Lo storico ("prima faceva…") va nel [CHANGELOG](../../CHANGELOG.md), nelle note datate (`docs/history/engine-upgrades/`, `docs/history/reviews/`) o nella cronologia git. Il **perché** di una scelta resta invece accanto alla scelta, in una frase.
