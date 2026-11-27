# Arcane — catalogo dei file

Aggiornato il 28 novembre 2026. Il repository versiona **1679 file**. Le guide e immagini di `docs/guides/` sono verificate da `check_guides.py`; alcuni pacchetti audio, sorgenti e test non hanno una riga. Sono esclusi i dati personali e gli output generati.

La [guida tecnica](../how-it-works/architecture.md) spiega come collaborano i componenti. Qui ogni riga identifica un file e la sua responsabilità. Le sezioni Core seguono le cartelle del Core, una per area; le sezioni Porting seguono le cartelle del target `NxnativeAdapter`, con lo Switch; quelle UI seguono schermate e componenti. Le viste usano i modelli e i servizi del Core attraverso il coordinamento applicativo.

Le cartelle generate `.build/`, `work/` e `dist/` e i dati personali in Application Support sono descritti nella guida.

## Indice

- [Progetto e configurazione](#progetto-e-configurazione)
- [Ingresso e shell dell’app](#ingresso-e-shell-dellapp)
- [Coordinamento applicativo](#coordinamento-applicativo)
- [Modelli dello stato applicativo](#modelli-dello-stato-applicativo)
- [Integrazione con macOS e servizi applicativi](#integrazione-con-macos-e-servizi-applicativi)
- [OortCore · logica portabile](#oortcore--logica-portabile)
- [Core · app: aggiornamento, primo avvio, diagnostica e comandi](#core--app-aggiornamento-primo-avvio-diagnostica-e-comandi)
- [Core · catalogo comune e fonti](#core--catalogo-comune-e-fonti)
- [Core · libreria, sessioni e spazio](#core--libreria-sessioni-e-spazio)
- [Core · Selene: Spotlight, focus, temi e sfondi](#core--selene-spotlight-focus-temi-e-sfondi)
- [Core · pagina del gioco](#core--pagina-del-gioco)
- [Core · artwork e metadati](#core--artwork-e-metadati)
- [Core · achievement](#core--achievement)
- [Core · mod](#core--mod)
- [Core · impostazioni, lingua e testi](#core--impostazioni-lingua-e-testi)
- [Core · Steam](#core--steam)
- [Porting · gioco Switch e libreria nxnative](#porting--gioco-switch-e-libreria-nxnative)
- [Porting · catalogo nxnative](#porting--catalogo-nxnative)
- [Porting · libreria, sessioni e spazio](#porting--libreria-sessioni-e-spazio)
- [Porting · pagina del gioco](#porting--pagina-del-gioco)
- [Porting · impostazioni e app](#porting--impostazioni-e-app)
- [Porting · Setup, motore e chiavi](#porting--setup-motore-e-chiavi)
- [Porting · sorgenti, build e installazione](#porting--sorgenti-build-e-installazione)
- [Porting · avvio e icona del gioco](#porting--avvio-e-icona-del-gioco)
- [Porting · impostazioni del gioco](#porting--impostazioni-del-gioco)
- [Porting · cheat](#porting--cheat)
- [Porting · store Nintendo e copertine](#porting--store-nintendo-e-copertine)
- [Porting · salvataggi, backup e cloud](#porting--salvataggi-backup-e-cloud)
- [Porting · mod RomFS e GameBanana](#porting--mod-romfs-e-gamebanana)
- [UI · Add Game e porting](#ui--add-game-e-porting)
- [UI · Spotlight](#ui--spotlight)
- [UI · Collection e Details](#ui--collection-e-details)
- [UI · Game Options, cheats e salvataggi](#ui--game-options-cheats-e-salvataggi)
- [UI · Settings](#ui--settings)
- [UI · Setup, avvio, ricerca e console](#ui--setup-avvio-ricerca-e-console)
- [UI · componenti condivisi](#ui--componenti-condivisi)
- [UI · temi, rendering e sfondi](#ui--temi-rendering-e-sfondi)
- [UI · fonti, Steam e libreria mista](#ui--fonti-steam-e-libreria-mista)
- [UI · achievement](#ui--achievement)
- [Contributi, skill e controlli di architettura](#contributi-skill-e-controlli-di-architettura)
- [Test e fixture](#test-e-fixture)
- [Script di sviluppo e packaging](#script-di-sviluppo-e-packaging)
- [Risorse incluse](#risorse-incluse)
- [Screenshot e demo](#screenshot-e-demo)
- [Documentazione tecnica e registri datati](#documentazione-tecnica-e-registri-datati)

## Progetto e configurazione

La pubblicazione comprende anche [CONTRIBUTING.md](../../CONTRIBUTING.md), [SECURITY.md](../../SECURITY.md), [il codice di condotta](../../CODE_OF_CONDUCT.md), [la CI](../../.github/workflows/ci.yml) e [i modelli di segnalazione](../../.github/ISSUE_TEMPLATE/). Descrivono come segnalare problemi e suggerimenti, le verifiche del maintainer, il canale per le vulnerabilità e i controlli automatici.

| File | Responsabilità |
|---|---|
| [.github/FUNDING.yml](../../.github/FUNDING.yml) | Collega il pulsante Sponsor del repository alla pagina Buy Me a Coffee di Arcane. |
| [README.fr.md](../../README.fr.md) | Presentazione in francese. |
| [PLAYER-GUIDE.md](../../PLAYER-GUIDE.md) | Guida all’uso in inglese. |
| [PLAYER-GUIDE.fr.md](../../PLAYER-GUIDE.fr.md) | Guida rapida in francese. |
| [.github/ISSUE_TEMPLATE/config.yml](../../.github/ISSUE_TEMPLATE/config.yml) | Instrada le segnalazioni di sicurezza al canale privato. |
| [.github/ISSUE_TEMPLATE/feature.yml](../../.github/ISSUE_TEMPLATE/feature.yml) | Raccoglie idee e richieste. |
| [.github/PULL_REQUEST_TEMPLATE.md](../../.github/PULL_REQUEST_TEMPLATE.md) | Raccoglie perimetro e verifiche, in francese e in inglese. |
| [.github/ISSUE_TEMPLATE/bug-macos.yml](../../.github/ISSUE_TEMPLATE/bug-macos.yml) | Modulo di segnalazione per macOS. |
| [.github/ISSUE_TEMPLATE/bug-windows.yml](../../.github/ISSUE_TEMPLATE/bug-windows.yml) | Modulo di segnalazione per Windows. |
| [.github/ISSUE_TEMPLATE/bug-linux.yml](../../.github/ISSUE_TEMPLATE/bug-linux.yml) | Modulo di segnalazione per Linux. |
| [.github/ISSUE_TEMPLATE/bug-android.yml](../../.github/ISSUE_TEMPLATE/bug-android.yml) | Modulo di segnalazione per Android. |
| [.github/ISSUE_TEMPLATE/bug-iphone-ipad.yml](../../.github/ISSUE_TEMPLATE/bug-iphone-ipad.yml) | Modulo di segnalazione per iPhone e iPad. |
| [.github/ISSUE_TEMPLATE/game.yml](../../.github/ISSUE_TEMPLATE/game.yml) | Modulo di compatibilità per un gioco, senza file di gioco né chiavi. |
| [.github/ISSUE_TEMPLATE/controller.yml](../../.github/ISSUE_TEMPLATE/controller.yml) | Modulo per manette e comandi. |
| [.github/CODEOWNERS](../../.github/CODEOWNERS) | Designa il maintainer come revisore delle aree sensibili: dati, accesso, release, pacchetto, motore. |
| [.github/dependabot.yml](../../.github/dependabot.yml) | Controlla ogni settimana azioni, Swift e (sui rami alpha) Cargo, npm e Gradle; apre solo pull request. |
| [.github/LABELS.md](../../.github/LABELS.md) | Propone le etichette da creare; nessuna è stata applicata su GitHub. |
| [.github/workflows/ci.yml](../../.github/workflows/ci.yml) | Flusso unico: controlli Mac sempre; per Swift, unit test, sonde sulla build Debug condivisa, gruppi di sonde autonome e build Release paralleli, tutti richiesti da Mac / Swift tests. I port girano solo se cambiano i loro percorsi. |
| [CODE_OF_CONDUCT.md](../../CODE_OF_CONDUCT.md) | Regole di condotta brevi e segnalazione privata al maintainer. |
| [.gitignore](../../.gitignore) | Esclude output di build, bundle, cache, work e file personali dell’IDE dal versionamento. |
| [AGENTS.md](../../AGENTS.md) | Definisce vincoli per gli agenti, procedura di upgrade del motore e verifiche assegnate all’utente. |
| [.agents/skills/oort-change/SKILL.md](../../.agents/skills/oort-change/SKILL.md) | Scelta fra modifica visiva e di logica, e lista per la pull request. |
| [.agents/skills/oort-change/evals/cases.md](../../.agents/skills/oort-change/evals/cases.md) | Tre casi di valutazione della skill. |
| [.agents/skills/oort-visual-change/SKILL.md](../../.agents/skills/oort-visual-change/SKILL.md) | Passi e prove per ciò che il giocatore vede, sente o preme. |
| [.agents/skills/oort-visual-change/evals/cases.md](../../.agents/skills/oort-visual-change/evals/cases.md) | Tre casi di valutazione della skill. |
| [.agents/skills/oort-core-change/SKILL.md](../../.agents/skills/oort-core-change/SKILL.md) | Passi e prove per contratti, dati, rete, concorrenza e motore. |
| [.agents/skills/oort-core-change/evals/cases.md](../../.agents/skills/oort-core-change/evals/cases.md) | Tre casi di valutazione della skill. |
| [CHANGELOG.md](../../CHANGELOG.md) | Registra le modifiche visibili all'utente per versione. |
| [LICENSE](../../LICENSE) | Contiene la licenza MIT di Arcane. |
| [.gitattributes](../../.gitattributes) | Conserva senza conversioni i testi delle licenze di terzi verificati per hash. |
| [NOTICE](../../NOTICE) | Conserva attribuzioni del motore al pin corrente, di rclone, dei componenti, dei loghi e delle altre risorse riutilizzate. |
| [Package.swift](../../Package.swift) | Dichiara `OortCore` portabile, `OortLibrary`, il modulo `NxnativeAdapter`, l’app, i tre target di test e il deployment macOS minimo. |
| [README.md](../../README.md) | Presenta Arcane come libreria e launcher Mac, con guide d'uso (anche per la prima connessione cloud), requisiti e crediti. |
| [engines/nxnative/runtime.lock](../../engines/nxnative/runtime.lock) | Fissa versioni, download e hash del runtime Python e degli strumenti inclusi nel bundle. |
| [VERSION](../../VERSION) | Versione in sviluppo usata dal packaging e verificata dalla procedura di release. |

## Ingresso e shell dell’app

| File | Responsabilità |
|---|---|
| [apps/mac/OortMac/NXLibraryApp.swift](../../apps/mac/OortMac/NXLibraryApp.swift) | Punto @main, finestra SwiftUI, notifiche e comandi della barra menu, incluso Add an app; in Debug seleziona anche la fixture o la cattura senza finestra visibile. |
| [apps/mac/OortMac/AppDelegate.swift](../../apps/mac/OortMac/AppDelegate.swift) | Gestisce finestra e chiusura: conferma dell’ospite prima delle code e degli esiti, rinomina di una copia release storica. |
| [apps/mac/OortMac/Views/MainView.swift](../../apps/mac/OortMac/Views/MainView.swift) | Presenta AppShellView come contenuto della finestra principale. |
| [apps/mac/OortMac/Views/Shell/AppShellView.swift](../../apps/mac/OortMac/Views/Shell/AppShellView.swift) | Possiede backdrop e stato condivisi, instrada notifiche, menu e trascinamento di una `.app`. `nativeDialogOwnsInput` sospende controller e tastiera sotto dialoghi nativi. Tiene stato, init e `body`; il resto sta nelle estensioni qui sotto. |
| [apps/mac/OortMac/Views/Components/SeleneOverlay.swift](../../apps/mac/OortMac/Views/Components/SeleneOverlay.swift) | Velo o fondo opaco, stile del blur, clic all'esterno, isolamento di puntatore e VoiceOver, suggerimenti, filtro del focus al passaggio del puntatore e scossa per l'input rifiutato. |
| [apps/mac/OortMac/Views/Shell/AppShellView+Layers.swift](../../apps/mac/OortMac/Views/Shell/AppShellView+Layers.swift) | Strati, contatori Nextendo e comandi di Attività e dei giochi. I collegamenti Mac non aprono Details. Sveglia la coda dopo la scansione; l'importazione cloud ignora le richieste annullate. Azzera le notifiche al cambio di profilo. |
| [apps/mac/OortMac/Views/Shell/AppShellView+Startup.swift](../../apps/mac/OortMac/Views/Shell/AppShellView+Startup.swift) | Avvia la shell, instrada il controller anche verso Integrations e risveglia installazioni, trasferimenti cloud e porting alla chiusura del gioco. |
| [apps/mac/OortMac/Views/Shell/AppShellView+Profiles.swift](../../apps/mac/OortMac/Views/Shell/AppShellView+Profiles.swift) | Home, cambio dopo la chiusura dei giochi, conferme dell’ospite, rinnovo della presenza e dialogo PIN Selene condiviso con tastiera, manetta e mouse. |
| [apps/mac/OortMac/Views/Shell/AppShellView+Overlays.swift](../../apps/mac/OortMac/Views/Shell/AppShellView+Overlays.swift) | Dialoghi e avvisi della shell: cloud, impostazioni, benvenuto, installazione fallita, Close Game, rimozione e aggiornamento. Passa l'indice di Annulla al dialogo condiviso. |
| [apps/mac/OortMac/Views/Shell/AppShellView+Input.swift](../../apps/mac/OortMac/Views/Shell/AppShellView+Input.swift) | Equivalenti da tastiera dei gesti del controller, inclusi Inbox e Integrations, azioni del menu e del centro attività. |
| [apps/mac/OortMac/Views/Shell/AppShellView+Palette.swift](../../apps/mac/OortMac/Views/Shell/AppShellView+Palette.swift) | Cerca ovunque: non si apre sui dialoghi e usa le azioni esistenti per tutte le righe. |
| [apps/mac/OortMac/Views/Shell/AppShellView+Input.swift](../../apps/mac/OortMac/Views/Shell/AppShellView+Input.swift) | Equivalenti da tastiera, azioni del menu e del centro attività; Restart app aspetta la decisione su Settings. |
| [apps/mac/OortMac/Views/Shell/AppShellView+Palette.swift](../../apps/mac/OortMac/Views/Shell/AppShellView+Palette.swift) | Cerca ovunque: apertura, righe, tasti fisici inoltrati alla lista e azione esistente di ogni riga. |
| [apps/mac/OortMac/Views/Shell/IntegrationsView.swift](../../apps/mac/OortMac/Views/Shell/IntegrationsView.swift) | Barra, riepilogo Giochi e Servizi, schede dei dati e collegamenti alle impostazioni esistenti. |
| [apps/mac/OortMac/Views/Shell/IntegrationsView+Input.swift](../../apps/mac/OortMac/Views/Shell/IntegrationsView+Input.swift) | Traduce tastiera e controller per barra e pagina; mentre la barra ha il focus non inoltra i comandi delle tessere. |
| [apps/mac/OortMac/Views/Shell/IntegrationFixtureView.swift](../../apps/mac/OortMac/Views/Shell/IntegrationFixtureView.swift) | Anteprima Debug isolata e PNG delle viste condivise con stati sintetici, senza avviare i servizi o rendere visibile una finestra per le catture. |
| [apps/mac/OortMac/Views/Shell/FullscreenCursorView.swift](../../apps/mac/OortMac/Views/Shell/FullscreenCursorView.swift) | Gestisce il cursore inattivo in fullscreen e l'attività del controller anche in finestra, rispettando pannelli e menu. |
| [apps/mac/OortMac/Views/Shell/StartupWindowView.swift](../../apps/mac/OortMac/Views/Shell/StartupWindowView.swift) | Applica il fullscreen dopo la comparsa della finestra e segnala fine transizione o scadenza alla fase dell’entrata. |
| [apps/mac/OortMac/Views/Shell/MenuOverlayView.swift](../../apps/mac/OortMac/Views/Shell/MenuOverlayView.swift) | Disegna il control center a cinque icone con LB/RB e `MenuCard`, la scheda di pillole di pari larghezza sopra Profilo, Libreria e Power. Mostra le sole voci disponibili. Il puntatore fermo non riprende il focus delle icone. |
| [apps/mac/OortMac/Views/Shell/ProfilePickerView.swift](../../apps/mac/OortMac/Views/Shell/ProfilePickerView.swift) | «Chi gioca?» all’avvio e in sovrapposizione, ritratto condiviso, fila con spazio per l'alone, glifo di aggiunta leggibile fuori focus, modifica e rimozione dei profili idonei. |
| [apps/mac/OortMac/Views/Shell/ProfileEditorView.swift](../../apps/mac/OortMac/Views/Shell/ProfileEditorView.swift) | Bozza dei quattro passi, tastiera a schermo, avatar, ritaglio, anteprima, salvataggio rapido e conferma di scarto con l'aiuto del dialogo condiviso. |
| [apps/mac/OortMac/Views/Shell/ProfileAvatar.swift](../../apps/mac/OortMac/Views/Shell/ProfileAvatar.swift) | Ritaglia artwork locale o file scelti, conserva i tempi dei GIF e mostra l’animazione in un cerchio con ritaglio centrato. |
| [apps/mac/OortMac/Views/Shell/ProfilePage.swift](../../apps/mac/OortMac/Views/Shell/ProfilePage.swift) | Pagina profilo: arte sfumata, statistiche locali, schede percorse anche con LB/RB e ZL/ZR, pulsante Vedi tutto separato dal titolo e nascosto se la scheda è vuota, progressi e sblocchi, amici con miniature dei giochi riconosciuti. |
| [apps/mac/OortMac/Views/Shell/ActivityCenterView.swift](../../apps/mac/OortMac/Views/Shell/ActivityCenterView.swift) | Compilazione e Cloud, code, Resume, progressi ed esiti. Nasconde Annulla quando il worker entra in installazione. |
| [core/OortLibrary/Selene/ActionBarOrder.swift](../../core/OortLibrary/Selene/ActionBarOrder.swift) | Ruoli, ordine e focus: Annulla a sinistra nelle coppie, distruttivo separato nelle terne, elenco verticale da quattro risposte. |
| [core/OortLibrary/Selene/ActivityCenterFocus.swift](../../core/OortLibrary/Selene/ActivityCenterFocus.swift) | Identità e navigazione delle righe attive, in coda, concluse e del comando Clear all. |
| [core/OortLibrary/OortLibrary.swift](../../core/OortLibrary/OortLibrary.swift) | Espone la versione nominale del modulo Core. |
| [LaunchReveal.swift](../../apps/mac/OortMac/Views/Launch/LaunchReveal.swift) | Rende visibile la finestra al primo frame del moonlight, con dissolvenza e scadenza, poi consente il fullscreen; integra il bootstrap con un NSView non interattivo. |
| [DevelopmentStartupView.swift](../../apps/mac/OortMac/Views/Launch/DevelopmentStartupView.swift) | Avvio asincrono: blocco del profilo, copia prima degli scrittori, avanzamento, recupero e conflitto legacy; segnala i lavori lasciati alla versione precedente. |
| [DowngradeWarningView.swift](../../apps/mac/OortMac/Views/Launch/DowngradeWarningView.swift) | Avvisi Selene sul ritorno a 0.3.0, gruppi omessi, spazio insufficiente e scelte con mouse, tastiera e controller. |
| [AppShellState.swift](../../apps/mac/OortMac/Views/Shell/AppShellState.swift) | Prepara coordinatore, router, fonti, lingua e tema. Collega le impostazioni al router e al delegato, che riceve anche le attività per la chiusura. |

## Coordinamento applicativo

| File | Responsabilità |
|---|---|
| [apps/mac/OortMac/ViewModels/AppViewModel.swift](../../apps/mac/OortMac/ViewModels/AppViewModel.swift) | Coordina libreria e catalogo, incluse le richieste di scansione corrente e in attesa, sorgenti, lancio, primo avvio, Game Options, spazio su disco e icona del Dock. Tiene il pin, crea i modelli Switch, conserva il modello Nextendo per profilo e manda gli esiti HTTP e di rete alla Console. Conserva la scelta Steam del Setup. Il modello degli avvisi decide ordine e focus; `confirmSetting` parte da Annulla. |
| [apps/mac/OortMac/ViewModels/AppViewModel+Storage.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+Storage.swift) | Spazio su disco: misura, cancella cache e log. |
| [apps/mac/OortMac/ViewModels/AppViewModel+Library.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+Library.swift) | Scansione e cartella Game apps, scarto delle richieste annullate prima di pubblicare, adozione con conferma e avviso per contenuto non verificato, trascinamento e collegamento di sorgenti per title ID. |
| [apps/mac/OortMac/ViewModels/AppViewModel+CloudLibrary.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+CloudLibrary.swift) | Verifica l’ambito senza importare e distingue ID approvato delle sorgenti da disponibilità. Conserva offerte non verificate del riferimento, lega la coda all’eseguibile e Rebuild alla selezione mostrata. Play riprende solo dopo l’installazione. |
| [apps/mac/OortMac/ViewModels/AppViewModel+CloudLibraryMove.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+CloudLibraryMove.swift) | Ricontrolla l'origine approvata, usa una configurazione privata sotto lock e annulla il comando senza perdere il registro. Salva la destinazione per ID solo dopo l'esito verificato. |
| [apps/mac/OortMac/ViewModels/AppViewModel+DriveTool.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+DriveTool.swift) | Spiega rclone e chiede consenso alla ripresa, incluso il percorso esplicito delle sorgenti 0.3.0; coordina download, esito e Cestino della copia propria. |
| [apps/mac/OortMac/ViewModels/AppViewModel+Activity.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+Activity.swift) | Ripristina, registra e cancella gli esiti; invia Retry al proprietario del lavoro e conserva l'esito dello spostamento pendente o mostra il percorso del registro illeggibile. |
| [apps/mac/OortMac/ViewModels/AppViewModel+Play.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+Play.swift) | Entrata Play comune; prepara il target e il profilo correnti e adatta il percorso nxnative al contratto Core. |
| [apps/mac/OortMac/ViewModels/AppViewModel+Launch.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+Launch.swift) | Play nxnative: ripresa dopo scambio cloud, firma dell'icona o conferma VPN con profilo e osservatore iniziali; salvataggi, mod, Home e schermo. |
| [apps/mac/OortMac/ViewModels/NextendoSettings.swift](../../apps/mac/OortMac/ViewModels/NextendoSettings.swift) | Scheda Nextendo in memoria, store del token del profilo, accesso e disconnessione, aggiornamento amici, ultimi dati noti per l'overlay e stato della pubblicazione. |
| [apps/mac/OortMac/ViewModels/AppViewModel+GameActions.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+GameActions.swift) | Azioni su un gioco: Game options, preferito, nascosto, salvataggi cloud, chiusura, rimozione e Mostra nel Finder. |
| [apps/mac/OortMac/ViewModels/AppViewModel+GameFiles.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+GameFiles.swift) | Verifica giochi e percorsi prima della rimozione; passa al catalogo tutte le sorgenti candidate, anche ripetute, e identifica gli originali nell’avviso di errore; selettore Ryujinx e log. |
| [apps/mac/OortMac/ViewModels/AppViewModel+Mods.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+Mods.swift) | Crea lo `ModStore`, il valore della riga Mods e gli errori, inclusi nomi condivisi da File e Code mods. |
| [apps/mac/OortMac/ViewModels/AppViewModel+Controller.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+Controller.swift) | Sceglie il gioco su cui agiscono i comandi del menu, anche dalla Collection di un profilo. |
| [AppViewModel+PlayersScreen.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+PlayersScreen.swift) | Collega il pannello giocatori al piano, ai profili, al registro delle manette e alle capacità del gioco. |
| [AppViewModel+Players.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+Players.swift) | Legge il piano comune e prepara la cache di prove Git e impronte HID per il Play senza attese di rilevamento. |
| [apps/mac/OortMac/ViewModels/AppViewModel+Diagnostics.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+Diagnostics.swift) | Raccoglie ambiente, toolchain e ultimo build per il rapporto diagnostico ripulito. |
| [apps/mac/OortMac/ViewModels/AppViewModel+PendingInstall.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+PendingInstall.swift) | Riprende le installazioni differite rispettando i lease, espone il motivo dell'errore e aggiorna il confronto cloud dopo la pubblicazione del bundle. |
| [apps/mac/OortMac/ViewModels/AppViewModel+Porting.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+Porting.swift) | Prepara tile, pill e stima del porting; proietta disponibilità locale e remota per il filtro Cloud e i badge senza leggere il disco. |
| [apps/mac/OortMac/ViewModels/AppViewModel+Saves.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+Saves.swift) | Risolve contesto e identità se il profilo è leggibile, coordina i lease con motivo di rifiuto e recupera i journal del profilo selezionato. |
| [apps/mac/OortMac/ViewModels/AppViewModel+SteamGridDB.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+SteamGridDB.swift) | Verifica, salva e rimuove la chiave SteamGridDB dell’utente senza registrarne il valore. |
| [apps/mac/OortMac/ViewModels/LibraryRefreshModel.swift](../../apps/mac/OortMac/ViewModels/LibraryRefreshModel.swift) | Il solo aggiornamento della libreria: app, fonti attive e cloud insieme; la scansione locale conserva la richiesta, che Cancel o un nuovo refresh annulla. Parole del messaggio e del centro attività. |
| [apps/mac/OortMac/ViewModels/AppIconModel.swift](../../apps/mac/OortMac/ViewModels/AppIconModel.swift) | Applica o ripristina l’icona senza toccare giochi in esecuzione o in build. Conserva la richiesta Play legata al dialogo durante la firma; Change artwork ne osserva l’avanzamento. |
| [CommandPalette.swift](../../apps/mac/OortMac/ViewModels/CommandPalette.swift) | Stato di Cerca ovunque: voci, gruppi e focus per identità al refresh, senza una sostituzione implicita. |
| [apps/mac/OortMac/ViewModels/CheatsModel.swift](../../apps/mac/OortMac/ViewModels/CheatsModel.swift) | Adatta Core e bundle installato al pannello Cheats, alla riga di stato, alla pagina del gioco e alla diagnostica; chiede a git l'engine dell'app con `prepare(for:)`; raggiunge il coordinatore solo da `app`. |
| [apps/mac/OortMac/ViewModels/GameInboxModel.swift](../../apps/mac/OortMac/ViewModels/GameInboxModel.swift) | Cartella configurabile, lettura con nxnative solo con Inbox attiva e chiavi valide; conferma col nome del file singolo o il numero di file, verifica del catalogo e Cestino. |
| [apps/mac/OortMac/ViewModels/PortingModel.swift](../../apps/mac/OortMac/ViewModels/PortingModel.swift) | Stato di Add Game e del porting: bozza, selezione delle sorgenti e spazio richiesto, chiavi, passo del wizard, stato della build mostrato ed esito. Il lavoro sta nelle estensioni qui sotto; raggiunge il coordinatore solo da `app`. |
| [apps/mac/OortMac/ViewModels/PortingModel+AddGame.swift](../../apps/mac/OortMac/ViewModels/PortingModel+AddGame.swift) | Selettore e preparazione condivisi dei file, scansione e scelta delle sorgenti, passi di Add Game e regole di Back. |
| [apps/mac/OortMac/ViewModels/PortingModel+Build.swift](../../apps/mac/OortMac/ViewModels/PortingModel+Build.swift) | Avvio con gioco chiuso, annullamento del porting o della verifica cache, nuovo tentativo e FIFO persistente. |
| [apps/mac/OortMac/ViewModels/PortingModel+BuildEvents.swift](../../apps/mac/OortMac/ViewModels/PortingModel+BuildEvents.swift) | Eventi del motore, timer, adozione cache in background, diagnosi da log e codice di uscita e salvataggio dell'esito. |
| [apps/mac/OortMac/ViewModels/PortingModel+Failure.swift](../../apps/mac/OortMac/ViewModels/PortingModel+Failure.swift) | Port anyway con override nella singola richiesta, notifica di fine e azioni dell’errore. |
| [apps/mac/OortMac/ViewModels/PortingModel+Folders.swift](../../apps/mac/OortMac/ViewModels/PortingModel+Folders.swift) | Cartelle della build, spazio libero, sorgenti supportate e durata delle fasi finali per la stima. |
| [apps/mac/OortMac/ViewModels/RuntimeSettingsModel.swift](../../apps/mac/OortMac/ViewModels/RuntimeSettingsModel.swift) | Scelte per Game Options, More settings e default dei nuovi giochi. Copia il piano confermato; Undo rispetta le modifiche successive. |
| [apps/mac/OortMac/ViewModels/SavePanelModel.swift](../../apps/mac/OortMac/ViewModels/SavePanelModel.swift) | Gestisce backup, anteprime e recupero con un percorso fissato dal lease; rifiuta le azioni se il profilo non si legge. |
| [apps/mac/OortMac/ViewModels/SetupCheckModel.swift](../../apps/mac/OortMac/ViewModels/SetupCheckModel.swift) | Esegue probe e installazioni del Setup, chiede conferma con il percorso per cambiare un checkout e inoltra l’errore di importazione delle chiavi. |
| [apps/mac/OortMac/ViewModels/SetupModel.swift](../../apps/mac/OortMac/ViewModels/SetupModel.swift) | Tiene il Setup Switch: cartella, validità e commit dell'engine, sorgenti che l'engine sa leggere, controllo Upstream e scelta della cartella; chiavi importate (percorso, validità, riepilogo, importazione, errore e selettore); controllo dell'ambiente, compatibilità, override della toolchain non testata, gate e suo riepilogo, Python e Xcode dell'engine, versioni Metal. Ricarica la scelta Newest engine senza effetti durante l'inizializzazione. Raggiunge il coordinatore solo da `app`. |
| [apps/mac/OortMac/ViewModels/SetupModel+NewestEngine.swift](../../apps/mac/OortMac/ViewModels/SetupModel+NewestEngine.swift) | Usa l’engine upstream più nuovo o torna a quello testato dal suo repository, accende l’override e controlla se main è utilizzabile. |
| [apps/mac/OortMac/ViewModels/StoreMetadataModel.swift](../../apps/mac/OortMac/ViewModels/StoreMetadataModel.swift) | Tiene i dati dello store Nintendo, le code per lingua, gli screenshot di ripiego e le scelte di Change metadata; svuotando la cache invalida i risultati in corso. |

## Modelli dello stato applicativo

| File | Responsabilità |
|---|---|
| [apps/mac/OortMac/Models/AppIconAppearanceMode.swift](../../apps/mac/OortMac/Models/AppIconAppearanceMode.swift) | Espone trama nativa e particelle, conservando i valori salvati. |
| [apps/mac/OortMac/Models/BuildStageItem.swift](../../apps/mac/OortMac/Models/BuildStageItem.swift) | Rappresenta una fase del porting nella lista di avanzamento. |
| [apps/mac/OortMac/Models/BuildState.swift](../../apps/mac/OortMac/Models/BuildState.swift) | Enumera gli esiti e lo stato operativo del porting nella UI. |
| [apps/mac/OortMac/Models/GameDetailsInfo.swift](../../apps/mac/OortMac/Models/GameDetailsInfo.swift) | Ispeziona DLC e salvataggi del bundle e prepara dimensioni localizzate e dettagli del gioco. |
| [apps/mac/OortMac/Models/GamepadType.swift](../../apps/mac/OortMac/Models/GamepadType.swift) | Definisce brand, azioni semantiche, tabelle Oort e Arcane e dati per la guida del controller. |
| [apps/mac/OortMac/Models/LogEntry.swift](../../apps/mac/OortMac/Models/LogEntry.swift) | Rappresenta messaggi, livelli e identità delle righe di log mostrate dall’app. |
| [apps/mac/OortMac/Models/PlayedGame.swift](../../apps/mac/OortMac/Models/PlayedGame.swift) | Gioco nxnative o Steam per schermata di lancio e card di fine sessione. |
| [apps/mac/OortMac/Models/NXLibraryError.swift](../../apps/mac/OortMac/Models/NXLibraryError.swift) | Raggruppa errori applicativi e relative spiegazioni, compresi i rifiuti prima del porting. |
| [apps/mac/OortMac/Models/SelectableGame.swift](../../apps/mac/OortMac/Models/SelectableGame.swift) | Rappresenta le sorgenti selezionabili, la loro dimensione localizzata e l’ordinamento delle versioni nel wizard. |
| [apps/mac/OortMac/Models/UpstreamCheckState.swift](../../apps/mac/OortMac/Models/UpstreamCheckState.swift) | Rappresenta gli stati del controllo del changelog upstream. |

## Integrazione con macOS e servizi applicativi

| File | Responsabilità |
|---|---|
| [apps/mac/OortMac/Services/AppUpdater.swift](../../apps/mac/OortMac/Services/AppUpdater.swift) | Coordina aggiornamento e riavvio; se il gate blocca l'installazione, conserva lo ZIP verificato per il tentativo successivo. |
| [apps/mac/OortMac/Services/NativeMenuCommands.swift](../../apps/mac/OortMac/Services/NativeMenuCommands.swift) | Coordina tracking, disponibilità nella scena e passaggio differito dai menu macOS alle azioni del launcher. |
| [apps/mac/OortMac/Services/NextendoBrowserSignIn.swift](../../apps/mac/OortMac/Services/NextendoBrowserSignIn.swift) | Apre il browser predefinito e riceve una callback HTTP su loopback, con annullamento e scadenza. |
| [apps/mac/OortMac/Services/ControllerSource.swift](../../apps/mac/OortMac/Services/ControllerSource.swift) | Contratto per connessioni, input, batteria e identificazione esplicita dei pad. |
| [apps/mac/OortMac/Services/ControllerHardwareID.swift](../../apps/mac/OortMac/Services/ControllerHardwareID.swift) | Deriva un HMAC con sale locale dal seriale HID o dall'indirizzo Bluetooth esposto; non salva il valore originale. |
| [apps/mac/OortMac/Services/ControllerRoster.swift](../../apps/mac/OortMac/Services/ControllerRoster.swift) | Assegna ID di connessione e riconcilia gruppi HID/GameController senza attribuire il seriale a un pad per nome. |
| [apps/mac/OortMac/Services/GameControllerService.swift](../../apps/mac/OortMac/Services/GameControllerService.swift) | Pubblica pad, batteria, pressioni e attività. Sorveglia la scadenza HID anche con un pad attivo e filtra le ripetizioni dei tasti di conferma. Giocatori può consumare una pressione prima della navigazione. |
| [apps/mac/OortMac/Services/GCControllerSource.swift](../../apps/mac/OortMac/Services/GCControllerSource.swift) | Osserva i pad GameController e la scelta Home di macOS, legge batteria e simboli e identifica il pad con luce o vibrazione. |
| [apps/mac/OortMac/Services/HIDControllerSource.swift](../../apps/mac/OortMac/Services/HIDControllerSource.swift) | Osserva i pad HID fisici in modalità condivisa; riserva i report Nintendo `0x3F` e `0x30` all'input Nintendo. |
| [apps/mac/OortMac/Services/LaunchReadinessProbe.swift](../../apps/mac/OortMac/Services/LaunchReadinessProbe.swift) | Attende una finestra visibile del gioco (per bundle o, per Steam, per pid) per terminare la schermata di lancio. |
| [apps/mac/OortMac/Services/NotificationService.swift](../../apps/mac/OortMac/Services/NotificationService.swift) | Invia notifiche dei porting e instrada i clic verso il titolo o l’errore interessato. |
| [apps/mac/OortMac/Services/OnlineBackgroundService.swift](../../apps/mac/OortMac/Services/OnlineBackgroundService.swift) | Carica pagine e miniature e scarica wallpaper o video conservando progressi e crediti. |
| [apps/mac/OortMac/Services/RunningGameMonitor.swift](../../apps/mac/OortMac/Services/RunningGameMonitor.swift) | Riconcilia applicazioni e libreria; osserva pausa, ripresa e uscita di `dmhost`, invia Resume e Quit con ripiego SIGTERM. |
| [apps/mac/OortMac/Services/LibraryWindow.swift](../../apps/mac/OortMac/Services/LibraryWindow.swift) | Riporta davanti la finestra di Arcane dopo un gioco nxnative o Steam, mai sopra un gioco della libreria. |
| [apps/mac/OortMac/Services/SoundEffectService.swift](../../apps/mac/OortMac/Services/SoundEffectService.swift) | Riproduce i cue del pacchetto scelto o di Selene, applica attivazione e volume, interrompe l’audio durante il gioco. |
| [apps/mac/OortMac/Services/SystemDetector.swift](../../apps/mac/OortMac/Services/SystemDetector.swift) | Individua checkout nxnative, root personale e possibili percorsi delle chiavi. |

## OortCore · logica portabile

Cartella `core/OortCore/`, senza risorse né dipendenze.

| File | Responsabilità |
|---|---|
| [ControllerInput.swift](../../core/OortCore/ControllerInput.swift) | Decodifica report Nintendo, calibra stick, calcola transizioni e decide il ripiego HID. |
| [FocusIndex.swift](../../core/OortCore/FocusIndex.swift) | Mantiene un indice di focus entro i limiti della lista. |
| [HoldDetector.swift](../../core/OortCore/HoldDetector.swift) | Distingue pressione breve, prolungata e annullata. |
| [LineBuffer.swift](../../core/OortCore/LineBuffer.swift) | Ricompone righe parziali separate da `\n` o `\r`. |
| [Credits.swift](../../core/OortCore/Credits.swift) | Legge `credits.json`: gruppi, ruoli e note legali per sistema e lingua. |
| [MoonlightField.swift](../../core/OortCore/MoonlightField.swift) | Genera i dati delle particelle senza Metal; condivide `SplitMix` nel package per il cue Download. |
| [MoveDirection.swift](../../core/OortCore/MoveDirection.swift) | Espone le quattro direzioni del focus. |
| [Palette.swift](../../core/OortCore/Palette.swift) | Cerca ovunque: confronto tollerante, gruppi, «Vedi tutto», focus e recenti. |
| [ProfileKeypad.swift](../../core/OortCore/ProfileKeypad.swift) | Griglia PIN con lunghezza passata dal chiamante e conferma esplicita. |
| [Engine.swift](../../core/OortCore/Engine.swift) | Contratto di lettura di motore e release: atelier, versione incorporata, stato chiavi e revisione a monte. |
| [PlayReceipt.swift](../../core/OortCore/PlayReceipt.swift) | Identità del gesto, ricevuto e osservazioni portabili; nessuna identità di processo nel contratto. |
| [VersionNumber.swift](../../core/OortCore/VersionNumber.swift) | Confronta numeri di versione puntati parte per parte. |

## Core · app: aggiornamento, primo avvio, diagnostica e comandi

Cartella `core/OortLibrary/App/`.

| File | Responsabilità |
|---|---|
| [FileBrowser.swift](../../core/OortLibrary/App/FileBrowser.swift) | Elenco asincrono dei metadati delle cartelle, luoghi, filtri e risalita del selettore. |
| [core/OortLibrary/App/AppRouter.swift](../../core/OortLibrary/App/AppRouter.swift) | Gestisce route, ritorno, Inbox, menu, ricerca, focus e richieste Spotlight. Una bozza sospende l’uscita da Settings; i suoi dialoghi bloccano la palette. |
| [core/OortLibrary/App/AppRouter.swift](../../core/OortLibrary/App/AppRouter.swift) | Gestisce route, ritorno, Inbox, menu, ricerca, focus e richieste Spotlight. Una bozza di Settings sospende l'azione prima di lasciare la schermata. ShellBackdropCover definisce la priorità degli strati. |
| [core/OortLibrary/App/UndoOffers.swift](../../core/OortLibrary/App/UndoOffers.swift) | L’ultimo gesto reversibile e il modo di annullarlo, una volta: avviso, ⌘Z e centro attività. Un altro profilo lo toglie. |
| [core/OortLibrary/App/NoticeFocus.swift](../../core/OortLibrary/App/NoticeFocus.swift) | I tasti dell’avviso a schermo, raggiunti solo su richiesta; la schermata conserva il proprio focus. |
| [core/OortLibrary/App/Tips.swift](../../core/OortLibrary/App/Tips.swift) | Due suggerimenti, ciascuno una volta su questo Mac, uno per sessione, mai se sono spenti. |
| [core/OortLibrary/App/ProfileLayers.swift](../../core/OortLibrary/App/ProfileLayers.swift) | Strati della schermata profilo (selettore, procedura guidata, domanda di rimozione): solo quella in cima riceve l’input e mostra i suggerimenti; la procedura guidata nasconde il selettore. |
| [core/OortLibrary/App/FirstRunSetup.swift](../../core/OortLibrary/App/FirstRunSetup.swift) | Ordine e ripresa del tour, completamento e riapertura; conserva il percorso legacy e il consumo unico della selezione in Your games. |
| [core/OortLibrary/App/FirstRunFindings.swift](../../core/OortLibrary/App/FirstRunFindings.swift) | Conta giochi Steam senza modifiche, e le app del modulo con il conteggio che riceve; distingue lettura incompleta da assenza e permette nuove letture annullabili. |
| [core/OortLibrary/App/ArcaneWelcome.swift](../../core/OortLibrary/App/ArcaneWelcome.swift) | Decide quando compare il benvenuto in Arcane, l'offerta di Steam, il focus e come ogni uscita lo segna visto. |
| [core/OortLibrary/App/ReleaseNotesLayout.swift](../../core/OortLibrary/App/ReleaseNotesLayout.swift) | Divide le note di release in titoli, voci e testo, una riga per volta, per il dialogo degli aggiornamenti. |
| [PaletteAction.swift](../../core/OortLibrary/App/PaletteAction.swift) | Azioni di Cerca ovunque in cinque sezioni, scorciatoie e recenti per profilo. |
| [core/OortLibrary/App/BoundedCommand.swift](../../core/OortLibrary/App/BoundedCommand.swift) | Gruppi isolati per i comandi cloud; I/O non bloccante, inattività e vita dei figli limitate, lettura fino a EOF con guardia di sicurezza dopo l’uscita. |
| [core/OortLibrary/App/CommandRunner.swift](../../core/OortLibrary/App/CommandRunner.swift) | Comandi sincroni o streaming senza run loop; per il cloud inoltra input e annullamento all'esecutore con scadenza. |
| [core/OortLibrary/App/DiagnosticsReport.swift](../../core/OortLibrary/App/DiagnosticsReport.swift) | Genera il rapporto diagnostico, con i collegamenti dei workspace che non portano a nulla, e rimuove percorso home e valori riconosciuti come chiavi. |
| [core/OortLibrary/App/AppUpdate.swift](../../core/OortLibrary/App/AppUpdate.swift) | Definisce repository, versioni, pagina condivisa per le prerelease, verifica del download e sostituzione atomica; riconosce App Translocation. |
| [core/OortLibrary/App/AppBundleRename.swift](../../core/OortLibrary/App/AppBundleRename.swift) | Decide se una copia release che si chiama ancora `NX Library.app` diventa `Oort NX.app` alla chiusura, e fa lo spostamento nella stessa cartella. |
| [core/OortLibrary/App/AppUpdatePresentation.swift](../../core/OortLibrary/App/AppUpdatePresentation.swift) | Definisce gli stati dell’updater e il gate di installazione per versione e tipo di copia. |
| [core/OortLibrary/App/AppUpdateDownload.swift](../../core/OortLibrary/App/AppUpdateDownload.swift) | Scarica gli aggiornamenti con limiti di dimensione, redirect HTTPS vincolati a GitHub e gestione del file temporaneo. |
| [core/OortLibrary/App/BoundedDownload.swift](../../core/OortLibrary/App/BoundedDownload.swift) | Lettura HTTP limitata a blocchi e senza redirect, condivisa fra base e modulo per i provider, Steam e Nextendo. |
| [core/OortLibrary/App/ConnectivityWatcher.swift](../../core/OortLibrary/App/ConnectivityWatcher.swift) | Avvisa sul main thread quando il Mac torna online, perché il giro delle descrizioni riprenda da solo; la prima lettura non conta. |
| [core/OortLibrary/App/DisplayNameCache.swift](../../core/OortLibrary/App/DisplayNameCache.swift) | Nomi visualizzati di cartelle e volumi letti una volta per URL: la pagina si ricostruisce a ogni disegno e un disco esterno in stop bloccherebbe ogni volta. |
| [core/OortLibrary/App/AppIdentity.swift](../../core/OortLibrary/App/AppIdentity.swift) | Distingue Oort NX (nome visibile) da Arcane (identità e User-Agent), con vecchio nome, modulo Porting e pagine del progetto e del finanziamento. |
| [core/OortLibrary/App/Credits+Bundled.swift](../../core/OortLibrary/App/Credits+Bundled.swift) | I crediti inclusi nell’app. |
| [core/OortLibrary/App/AppDataProfile.swift](../../core/OortLibrary/App/AppDataProfile.swift) | Policy di percorsi e preferenze; separa release, Dev, essai 2 e fixture Debug. |
| [core/OortLibrary/App/LibraryMove.swift](../../core/OortLibrary/App/LibraryMove.swift) | Copia verificata della libreria precedente; conserva il registro di rimozione come documento inattivo. |
| [core/OortLibrary/App/LibraryPaths.swift](../../core/OortLibrary/App/LibraryPaths.swift) | File della libreria con percorsi, nomi dei registri di rimozione e collegamenti morti dei workspace. I percorsi dei log conservano il profilo d'origine. |
| [core/OortLibrary/App/LibraryPathRepair.swift](../../core/OortLibrary/App/LibraryPathRepair.swift) | Riparazione ripetibile di una libreria già copiata: isola il registro ereditato, conserva gli originali e sposta i percorsi verificati. |
| [core/OortLibrary/App/DevelopmentProfileImporter.swift](../../core/OortLibrary/App/DevelopmentProfileImporter.swift) | Copia selettiva senza modificare la sorgente; per l’essai 2 usa un elenco ristretto senza preferenze. Chiude le sessioni copiate all’ultimo heartbeat. |
| [core/OortLibrary/App/DowngradeCheckpoint.swift](../../core/OortLibrary/App/DowngradeCheckpoint.swift) | Copia privata con file essenziali prioritari, SHA-256, gruppi omessi, conferma e rotazione riprendibile senza perdere le due copie precedenti alla pubblicazione. |
| [core/OortLibrary/App/DevelopmentOperationStore.swift](../../core/OortLibrary/App/DevelopmentOperationStore.swift) | Autorizzazioni persistenti per le operazioni richieste nella Dev, distinte da quelle importate. |
| [core/OortLibrary/App/BuildInstallIO.swift](../../core/OortLibrary/App/BuildInstallIO.swift) | Confine sostituibile per la pubblicazione atomica di un bundle (stesso volume, rinomina o scambio) e il suo errore; lo usano installazione dei giochi e aggiornamento di Arcane. |

## Core · catalogo comune e fonti

Cartella `core/OortLibrary/Catalog/`.

| File | Responsabilità |
|---|---|
| [core/OortLibrary/Catalog/CatalogGame.swift](../../core/OortLibrary/Catalog/CatalogGame.swift) | Voce del catalogo attorno al record della sua fonte (`any CatalogSourceRecord`), identità e personalizzazioni con namespace, uguaglianza per tipo e valore; osservazioni delle installazioni Steam; lookup condiviso della prima installazione disponibile, separato dal gate di Play. |
| [core/OortLibrary/Catalog/CatalogSourceRecord.swift](../../core/OortLibrary/Catalog/CatalogSourceRecord.swift) | Contratto del record di una fonte, integrazione aperta come stringa e tipi del lettore (`CatalogRecordKinds`, in `userInfo`); Steam e collegamenti Mac sono nella base. |
| [core/OortLibrary/Catalog/SteamCatalogGame+Record.swift](../../core/OortLibrary/Catalog/SteamCatalogGame+Record.swift) | Record Steam nel contratto: validazione delle installazioni, presenza, gate di Play e termini di ricerca. |
| [core/OortLibrary/Catalog/CatalogDocument.swift](../../core/OortLibrary/Catalog/CatalogDocument.swift) | Schema, revisione, base legacy, fonti e validazione delle identità, inclusa l’unicità dei percorsi dei collegamenti Mac. Conserva intatti i record delle integrazioni sconosciute. |
| [core/OortLibrary/Catalog/CatalogJSON.swift](../../core/OortLibrary/Catalog/CatalogJSON.swift) | Valore JSON tenuto com’è stato letto (numeri `Decimal`), per i record e le fonti che il catalogo non conosce e le impostazioni dei moduli; si converte da e verso un tipo `Codable`. |
| [core/OortLibrary/Catalog/CatalogGamePresentation.swift](../../core/OortLibrary/Catalog/CatalogGamePresentation.swift) | Contratto comune per presentazione, operazioni supportate e target di avvio; nessuna operazione I/O. |
| [PlayEngine.swift](../../core/OortLibrary/Catalog/PlayEngine.swift) | Ammette un adapter per fonte, conserva il gesto e riserva la destinazione prima della consegna. |
| [PlayTarget.swift](../../core/OortLibrary/Catalog/PlayTarget.swift) | Installazione scelta, disponibilità, profilo e intenzione di sola ripresa della libreria. |
| [core/OortLibrary/Catalog/CatalogStore.swift](../../core/OortLibrary/Catalog/CatalogStore.swift) | Conversione legacy con impronta dei byte originali anche se i percorsi cambiano in memoria, letture limitate, revisioni attese, lock, archiviazione dei conflitti e Cestino del volume. |
| [core/OortLibrary/Catalog/CatalogPublication.swift](../../core/OortLibrary/Catalog/CatalogPublication.swift) | Staging verificato, creazione esclusiva e sostituzione atomica, con confine di errore controllabile. |
| [core/OortLibrary/Catalog/CatalogRepository.swift](../../core/OortLibrary/Catalog/CatalogRepository.swift) | Modifiche tipizzate del catalogo, inclusi i collegamenti Mac; delega la rimozione di file alla transazione dello store. |
| [core/OortLibrary/Catalog/CatalogStore+Removal.swift](../../core/OortLibrary/Catalog/CatalogStore+Removal.swift) | Rifiuta le identità ripetute, conserva i registri ereditati senza ripeterli e recupera soltanto le rimozioni della libreria corrente. |
| [core/OortLibrary/Catalog/MacShortcutRecord.swift](../../core/OortLibrary/Catalog/MacShortcutRecord.swift) | UUID, percorso canonico, bundle ID e verifica in sola lettura di un’app Mac scelta; ricollega solo la stessa identità. |
| [core/OortLibrary/Catalog/CatalogRecovery.swift](../../core/OortLibrary/Catalog/CatalogRecovery.swift) | Offerte di recupero e conflitto legacy con impronte degli input, rivalidate all’accettazione. |
| [core/OortLibrary/Catalog/CatalogPersonalizations.swift](../../core/OortLibrary/Catalog/CatalogPersonalizations.swift) | Lookup personali immutabili per identità. |
| [core/OortLibrary/Catalog/CatalogErrorCopy.swift](../../core/OortLibrary/Catalog/CatalogErrorCopy.swift) | Errori recuperabili del catalogo nelle sei lingue. |
| [core/OortLibrary/Catalog/CatalogGameOptions.swift](../../core/OortLibrary/Catalog/CatalogGameOptions.swift) | Ordine unico delle operazioni comuni della libreria; ciò che una fonte può fare dipende dal suo record (nessuna modifica nxnative su un gioco Steam). |
| [core/OortLibrary/Catalog/CatalogSourcesModel.swift](../../core/OortLibrary/Catalog/CatalogSourcesModel.swift) | Opt-in, worker annullabile e stato Steam; discoveryRoot conserva la cartella scelta anche con fonte spenta; pubblica solo documenti salvati dal repository. |
| [core/OortLibrary/Catalog/CatalogLibraryProjection.swift](../../core/OortLibrary/Catalog/CatalogLibraryProjection.swift) | Visibilità comune per fonti attive e giochi riconosciuti; nessuna scansione. |
| [core/OortLibrary/Catalog/SteamCatalogReconciler.swift](../../core/OortLibrary/Catalog/SteamCatalogReconciler.swift) | Ticket e fusione pura degli snapshot Steam, identità conservate e assenza trattata secondo completezza. |

## Core · libreria, sessioni e spazio

Cartella `core/OortLibrary/Library/`.

| File | Responsabilità |
|---|---|
| [core/OortLibrary/Library/LibraryFilter.swift](../../core/OortLibrary/Library/LibraryFilter.swift) | Definisce filtri, storico e query condivisa del catalogo misto; Cloud riceve gli ID solo remoti dal chiamante. `LibraryQueryRecord` è il contratto comune con ricerca e Surprise. |
| [core/OortLibrary/Library/RecentSearches.swift](../../core/OortLibrary/Library/RecentSearches.swift) | Le ultime quattro ricerche che hanno portato a un gioco, per profilo e solo su questo Mac; si cancellano. |
| [core/OortLibrary/Library/LibrarySelectionState.swift](../../core/OortLibrary/Library/LibrarySelectionState.swift) | Mantiene selezione e spostamento nel risultato filtrato della Collection. |
| [core/OortLibrary/Library/LibraryPresentation.swift](../../core/OortLibrary/Library/LibraryPresentation.swift) | Formatta metadati e statistiche temporali per le schermate della libreria: i valori pronti e la strada Steam; quella Switch sta in `NxnativeAdapter/Library/LibraryPresentation+Porting.swift`. |
| [core/OortLibrary/Library/PlaySession.swift](../../core/OortLibrary/Library/PlaySession.swift) | Descrive una sessione persistibile con gioco e riferimenti temporali. |
| [core/OortLibrary/Library/ActivitySummary.swift](../../core/OortLibrary/Library/ActivitySummary.swift) | Aggrega sessioni, giorni e tempi della settimana per la scheda Activity. |
| [core/OortLibrary/Library/ProfilePageCards.swift](../../core/OortLibrary/Library/ProfilePageCards.swift) | Ordine e visibilità per profilo, gruppi dell’attività e geometria della griglia. |
| [core/OortLibrary/Library/PlaySessionStore.swift](../../core/OortLibrary/Library/PlaySessionStore.swift) | Registra avvio, heartbeat e fine; pubblica insieme storico e totali archiviati, importa i file precedenti e unisce i totali Steam con le sessioni successive. |
| [core/OortLibrary/Library/LocalProfileStore.swift](../../core/OortLibrary/Library/LocalProfileStore.swift) | Identità, preferiti, scelta della piattaforma, presenza e visibilità, codice e profilo di avvio; protegge l'originale e include lo storico unico nella copia di migrazione. |
| [core/OortLibrary/Players/PlayerLaunchEnvironment.swift](../../core/OortLibrary/Players/PlayerLaunchEnvironment.swift) | Calcola le opzioni supportate, rispetta `env.txt` e limita il nickname a offline e locale. |
| [PlayerPlan.swift](../../core/OortLibrary/Players/PlayerPlan.swift) | Posti, profili protetti, tre modalità e giocatore destinatario facoltativo per la fusione. |
| [PlayerPlanStore.swift](../../core/OortLibrary/Players/PlayerPlanStore.swift) | Piano JSON v1, formato Codable anche per Settings, lettura dei piani senza destinatario e scrittura atomica del file storico senza perdere i campi sconosciuti. |
| [PlayerControllerResolution.swift](../../core/OortLibrary/Players/PlayerControllerResolution.swift) | Distingue la conferma per una connessione da un’identità hardware e conserva i posti non attivi durante la fusione. |
| [core/OortLibrary/Library/ProfileKeypad.swift](../../core/OortLibrary/Library/ProfileKeypad.swift) | Riesporta `OortCore` e applica la lunghezza del PIN di `LocalProfile` alla tastiera portabile. |
| [core/OortLibrary/Library/GameFocus.swift](../../core/OortLibrary/Library/GameFocus.swift) | Quando un gioco che esce riporta Arcane davanti: solo se era l’app in primo piano e nessun altro gioco della libreria è aperto. |
| [core/OortLibrary/Library/SessionSummary.swift](../../core/OortLibrary/Library/SessionSummary.swift) | Cosa dice la card di fine sessione: gioco, durata di questa sessione e totale scritto come nelle info del gioco; niente card sotto i dieci secondi. |
| [core/OortLibrary/Library/RunningAppsTracker.swift](../../core/OortLibrary/Library/RunningAppsTracker.swift) | Snapshot dei bundle ID delle applicazioni in esecuzione e cosa è partito o finito dall’ultima lettura. |
| [core/OortLibrary/Library/DirectorySize.swift](../../core/OortLibrary/Library/DirectorySize.swift) | Misura le cartelle con fts; il modulo Porting può contare anche i file nascosti nelle cartelle cache ignorate. |
| [core/OortLibrary/App/FileHandle+Chunks.swift](../../core/OortLibrary/App/FileHandle+Chunks.swift) | Legge a blocchi, rilasciandoli uno alla volta durante il calcolo delle impronte. |
| [core/OortLibrary/Library/StorageBackend.swift](../../core/OortLibrary/Library/StorageBackend.swift) | Contratto oggetti remoti: chiavi e impronte serializzabili, trasferimenti, avanzamento e lease condiviso. |
| [core/OortLibrary/Library/CloudLibraryFailure.swift](../../core/OortLibrary/Library/CloudLibraryFailure.swift) | Cause e recupero cloud: distingue volume locale pieno, quota Drive e rete; non riporta l'output di rclone. |
| [core/OortLibrary/Library/RcloneStorageBackend.swift](../../core/OortLibrary/Library/RcloneStorageBackend.swift) | Usa il binario risolto, verifica ID e nomi originali, rifiuta percorsi ambigui e limita il riferimento all’ID esatto in sola lettura. Prima di scrivere verifica che i due alberi siano disgiunti. |
| [core/OortLibrary/Library/VolumeSpace.swift](../../core/OortLibrary/Library/VolumeSpace.swift) | Spazio libero di un disco: dove macOS risponde 0 per l’uso importante (exFAT, FAT32) vale la cifra semplice. |
| [core/OortLibrary/Library/RcloneDownload.swift](../../core/OortLibrary/Library/RcloneDownload.swift) | Scarica rclone dopo consenso, verifica origine, dimensione, hash e firma, pubblica la copia con ricevuta e avvia lo snapshot dei byte approvati. |
| [core/OortLibrary/Library/CloudSetupAssistant.swift](../../core/OortLibrary/Library/CloudSetupAssistant.swift) | Bozza dell'assistente: passi, selezione, verifica, formato dell'ID client e client Google facoltativo nel plist. |
| [core/OortLibrary/Selene/CloudSetupAssistantFocus.swift](../../core/OortLibrary/Selene/CloudSetupAssistantFocus.swift) | Bersagli dell’assistente per tastiera e controller, colonna dei passi e Tab; acceso ciò che serve, mai Cancel. |
| [core/OortLibrary/Selene/ActionBarOrder.swift](../../core/OortLibrary/Selene/ActionBarOrder.swift) | Ordine dei tasti di un piede: ritorno a sinistra, azione principale ultima a destra; quale è acceso all’apertura. |
| [core/OortLibrary/Library/CloudKeptFolders.swift](../../core/OortLibrary/Library/CloudKeptFolders.swift) | Le due cartelle usate con un account, proposte di nuovo solo allo stesso account. |
| [core/OortLibrary/Library/RcloneConfiguration.swift](../../core/OortLibrary/Library/RcloneConfiguration.swift) | Ambito Drive con ID approvati e copie private per gli spostamenti. Cifratura con portachiavi, OAuth senza segreto negli argomenti e controllo del client prima della disconnessione. |
| [core/OortLibrary/Library/LibraryRefresh.swift](../../core/OortLibrary/Library/LibraryRefresh.swift) | Esito per parte di un aggiornamento della libreria: letto, non aggiornato con motivo, annullato; una risposta tardiva non cambia nulla. |
| [core/OortLibrary/Library/RcloneListing.swift](../../core/OortLibrary/Library/RcloneListing.swift) | Una lettura di Drive per gli schermi: conto e cartelle provati prima e dopo, cartelle lette per ID, insieme e una sola volta; connessione condivisa finché la configurazione non cambia. |
| [core/OortLibrary/Library/RcloneRemoteControl.swift](../../core/OortLibrary/Library/RcloneRemoteControl.swift) | Gestisce demoni locali su socket Unix; crea e pulisce le loro cartelle sotto un lock comune, attende il socket fino all'uscita o al termine della richiesta; distingue cartelle mancanti da operazioni non supportate e passa l'input sensibile OAuth via stdin. |
| [core/OortLibrary/Library/CollectionRow.swift](../../core/OortLibrary/Library/CollectionRow.swift) | Definisce proporzioni delle copertine e geometria della riga Collection. |

## Core · Selene: Spotlight, focus, temi e sfondi

Cartella `core/OortLibrary/Selene/`.

| File | Responsabilità |
|---|---|
| [core/OortLibrary/Selene/BackdropArt.swift](../../core/OortLibrary/Selene/BackdropArt.swift) | Regola che tiene l’arte del gioco precedente sullo sfondo Spotlight (`BackdropArtRule`) dissolvenza di un layer calcolata sull’orologio (`OpacityFade`) e livelli ormai coperti da togliere (`ArtStack`). |
| [core/OortLibrary/Selene/TileMotion.swift](../../core/OortLibrary/Selene/TileMotion.swift) | Curve e campioni dei loop di ring, bagliore e riflesso della tile selezionata, sull'orologio condiviso. |
| [core/OortLibrary/Selene/DownloadCloudMotion.swift](../../core/OortLibrary/Selene/DownloadCloudMotion.swift) | Traiettoria smorzata del download, onda calma, assestamento, glifo Oort e bande a dissolvenza. |
| [core/OortLibrary/Selene/Motion.swift](../../core/OortLibrary/Selene/Motion.swift) | Curve di focus, rail, schermate, overlay, carte ancorate, toast e progressi con varianti di movimento ridotto. |
| [core/OortLibrary/Selene/SeleneTokens.swift](../../core/OortLibrary/Selene/SeleneTokens.swift) | Ruoli Selene generati: testo, spazi, raggi, effetti, colore, durata e riferimento di distanza. |
| [core/OortLibrary/Selene/SeleneOverlayStyle.swift](../../core/OortLibrary/Selene/SeleneOverlayStyle.swift) | Associa ogni overlay ai ruoli di velo e sfocatura. |
| [core/Tests/OortLibraryTests/Selene/MotionTests.swift](../../core/Tests/OortLibraryTests/Selene/MotionTests.swift) | Verifica che in movimento ridotto restino solo i fonduti previsti. |
| [core/OortLibrary/Selene/TextScroll.swift](../../core/OortLibrary/Selene/TextScroll.swift) | Scorrimento della colonna del pannello della mod: altezza della descrizione dopo Read more, limiti, riga a fuoco mostrata intera e passo Su/Giù che legge prima della riga seguente. |
| [core/OortLibrary/Selene/CursorIdleState.swift](../../core/OortLibrary/Selene/CursorIdleState.swift) | Politica del ritardo di visibilità del puntatore e reset su mouse o perdita di eleggibilità. |
| [core/OortLibrary/Selene/OnlineBackgrounds.swift](../../core/OortLibrary/Selene/OnlineBackgrounds.swift) | Modella sorgenti e risultati e interpreta le risposte dei provider di sfondi fissi e video. |
| [core/OortLibrary/Selene/SeleneImporter.swift](../../core/OortLibrary/Selene/SeleneImporter.swift) | Importa suoni e wallpaper dalla cartella Selene dell’utente e risolve cue e fallback. |
| [core/OortLibrary/Selene/SoundPack.swift](../../core/OortLibrary/Selene/SoundPack.swift) | Valida manifesti, archivi e audio, sceglie le varianti, pubblica solo copie locali confermate e divide le scelte fra le voci della riga e Other. |
| [core/OortLibrary/Selene/OortSynth.swift](../../core/OortLibrary/Selene/OortSynth.swift) | Calcola i suoni delle voci Oort: note, clic, stanza, Sole e sequenze di Compose. |
| [core/OortLibrary/Selene/OortAmbiance.swift](../../core/OortLibrary/Selene/OortAmbiance.swift) | Timbri e stanza degli ambienti Frost, Mist e Nucleus e livello allineato alla voce Oort. |
| [core/OortLibrary/Selene/ButtonPrompts.swift](../../core/OortLibrary/Selene/ButtonPrompts.swift) | Traduce azioni e direzioni, incluse Su/Giù, in simboli per tastiera e controller Switch, Xbox e PlayStation. |
| [core/OortLibrary/Selene/InputInHand.swift](../../core/OortLibrary/Selene/InputInHand.swift) | Decide quale dispositivo è in mano (controller, tastiera o puntatore) senza sfarfallii: stick nella zona morta e piccoli spostamenti non contano. |
| [core/OortLibrary/Selene/LaunchExit.swift](../../core/OortLibrary/Selene/LaunchExit.swift) | Dopo quattro secondi dice come uscire dalla schermata di avvio: B o Esc se Oort riceve i tasti, altrimenti il clic. |
| [core/OortLibrary/Selene/RailScroll.swift](../../core/OortLibrary/Selene/RailScroll.swift) | Traduce rotella e due dita in passi della riga: un riquadro per riquadro di corsa, uno per scatto. |
| [core/OortLibrary/Selene/OnScreenKeyboard.swift](../../core/OortLibrary/Selene/OnScreenKeyboard.swift) | Pagine, tasti, maiuscole e spostamento del focus della tastiera a schermo. |
| [core/OortLibrary/Selene/MaterialIcon.swift](../../core/OortLibrary/Selene/MaterialIcon.swift) | Elenca i glifi del font incluso, compresi cancellazione e conferma del PIN. |
| [core/OortLibrary/Selene/MenuSelectionModel.swift](../../core/OortLibrary/Selene/MenuSelectionModel.swift) | Gestisce icone, voci delle schede e pillole Power; salta l'Inbox disattivata e lascia il focus sull'icona alla chiusura. |
| [core/OortLibrary/Selene/MoonlightAppearance.swift](../../core/OortLibrary/Selene/MoonlightAppearance.swift) | Identità delle superfici classica/Arcane/Flow e campionamento dei colori locali condiviso fra shader e fallback. |
| [core/OortLibrary/Selene/ScreenshotViewerState.swift](../../core/OortLibrary/Selene/ScreenshotViewerState.swift) | Mantiene indice e limiti della navigazione nel visualizzatore screenshot. |
| [core/OortLibrary/Selene/SeleneCanvas.swift](../../core/OortLibrary/Selene/SeleneCanvas.swift) | Calcola scala uniforme, stage centrato e conversione delle unità del canvas 1920×1080. |
| [core/OortLibrary/Selene/SelenePalette.swift](../../core/OortLibrary/Selene/SelenePalette.swift) | Decodifica palette e metadato moonlight; ordina Oort per prima, la usa come fallback e distingue l’ID del blu classico. |
| [core/OortLibrary/Selene/SpotlightPage.swift](../../core/OortLibrary/Selene/SpotlightPage.swift) | Calcola estratti delle descrizioni e stati dello scorrimento della pagina Spotlight. |
| [core/OortLibrary/Selene/SpotlightRow.swift](../../core/OortLibrary/Selene/SpotlightRow.swift) | Costruisce la sequenza per UUID e salva riordini conservando giochi/fonti/card temporaneamente nascosti; Surprise sceglie fra i giochi visibili di un pool (installati, mai giocati, tutti). |
| [core/OortLibrary/Selene/SpotlightPlatforms.swift](../../core/OortLibrary/Selene/SpotlightPlatforms.swift) | Piattaforme presenti, conteggi, combinazione con la query, cursore e scelta stabilizzata. |
| [core/OortLibrary/Selene/SpotlightRowGeometry.swift](../../core/OortLibrary/Selene/SpotlightRowGeometry.swift) | Posti delle tessere nella riga, camera unica che la fa scorrere e finestra delle tessere create; posto, scala e camera lungo lo scorrimento dalla posizione continua della selezione. |
| [core/OortLibrary/Selene/SpotlightState.swift](../../core/OortLibrary/Selene/SpotlightState.swift) | Gestisce selezione, focus (anche la card Achievements), azioni e spostamento delle tile su Spotlight. |
| [core/OortLibrary/Selene/SpotlightEntrance.swift](../../core/OortLibrary/Selene/SpotlightEntrance.swift) | Tempi e partenze del volo delle tessere, dissolvenza oltre il bordo, sfondo, informazioni, hint e fasi della prima entrata di Spotlight, compreso quando accetta input. |
| [core/OortLibrary/Selene/ThemePicker.swift](../../core/OortLibrary/Selene/ThemePicker.swift) | Gestisce il focus nella griglia colori, tab Wallpapers/Live e scelta dello sfondo successivo. |
| [core/OortLibrary/Selene/WallpaperCatalog.swift](../../core/OortLibrary/Selene/WallpaperCatalog.swift) | Elenca wallpaper e video, gruppi, nomi e file delle risorse incluse o importate. |
| [core/OortLibrary/Selene/WallpaperPlacement.swift](../../core/OortLibrary/Selene/WallpaperPlacement.swift) | Decide dove applicare uno sfondo scelto fra schermi principali e Settings. |
| [core/OortLibrary/Selene/GridListLayout.swift](../../core/OortLibrary/Selene/GridListLayout.swift) | Geometria di una lista a colonne di righe uguali: altezza, posizione di ogni riga, linee da disegnare, riga da mostrare e riga in vista più vicina. |

## Core · pagina del gioco

Cartella `core/OortLibrary/Details/`.

| File | Responsabilità |
|---|---|
| [core/OortLibrary/Details/GameDetailPresentation.swift](../../core/OortLibrary/Details/GameDetailPresentation.swift) | Prepara i dati della pagina Details e compone estratto, testo lungo e crediti per Details e Spotlight; le entrate Steam e Switch sono in estensioni distinte. |
| [core/OortLibrary/Details/MoreLikeThis.swift](../../core/OortLibrary/Details/MoreLikeThis.swift) | Ordina i giochi correlati per generi, sviluppatore ed editore, con precedenza alla stessa fonte e ripiego facoltativo. |
| [core/OortLibrary/Details/DetailsFacts.swift](../../core/OortLibrary/Details/DetailsFacts.swift) | Sceglie le righe del pannello Details (Steam qui, Switch in `NxnativeAdapter/Details/DetailsFacts+Porting.swift`): solo i valori presenti, niente identificativi tecnici. |
| [core/OortLibrary/Details/DetailsFocus.swift](../../core/OortLibrary/Details/DetailsFocus.swift) | Gestisce zone e spostamenti del focus nei link e nelle bande di Details. |
| [core/OortLibrary/Details/GameOptionsPresentation.swift](../../core/OortLibrary/Details/GameOptionsPresentation.swift) | Righe, livelli, focus e titolo Next launch localizzato: Play, rete, azione RomFS in Online e schermo solo per gli host compatibili. |
| [core/OortLibrary/Details/GameDetailPresentation+Steam.swift](../../core/OortLibrary/Details/GameDetailPresentation+Steam.swift) | Dati della pagina Steam e generi della testata Spotlight; ignora i dati di altri AppID e dà precedenza ai campi personali. |

## Core · artwork e metadati

Cartella `core/OortLibrary/Artwork/`.

| File | Responsabilità |
|---|---|
| [core/OortLibrary/Artwork/AutomaticIconResolver.swift](../../core/OortLibrary/Artwork/AutomaticIconResolver.swift) | Risolve icone automatiche con cache, abbinamento prudente e rispetto delle restrizioni del provider. |
| [core/OortLibrary/Artwork/ArtworkStore.swift](../../core/OortLibrary/Artwork/ArtworkStore.swift) | Scarica, ridimensiona e conserva immagini e screenshot nella cache per titolo e tipo. |
| [core/OortLibrary/Artwork/ArtworkPicker.swift](../../core/OortLibrary/Artwork/ArtworkPicker.swift) | Aggrega candidati per cover, sfondo, icona e logo (quelli Steam qui, quelli Switch in `NxnativeAdapter/Store/ArtworkCandidates+Porting.swift`) e conserva le scelte manuali. |
| [core/OortLibrary/Artwork/MetadataPicker.swift](../../core/OortLibrary/Artwork/MetadataPicker.swift) | Campi alternativi e override per campo: `MetadataPicks` scrive atomicamente prima di pubblicare la modifica. |
| [core/OortLibrary/Artwork/GameTitleKey.swift](../../core/OortLibrary/Artwork/GameTitleKey.swift) | Un titolo come parole da confrontare (minuscole, senza ™ ® © né punteggiatura, "&" come "and"), per le ricerche di artwork online e GameTDB. |
| [core/OortLibrary/Artwork/HTMLPlainText.swift](../../core/OortLibrary/Artwork/HTMLPlainText.swift) | Una descrizione HTML (store, Steam, database, mod) come testo semplice: righe ed elenchi tenuti, altri tag tolti, entità decodificate. |
| [core/OortLibrary/Artwork/OnlineArtworkSources.swift](../../core/OortLibrary/Artwork/OnlineArtworkSources.swift) | Ricava artwork Steam e loghi da MediaWiki e Wikimedia Commons. |
| [core/OortLibrary/Artwork/MoreArtworkSources.swift](../../core/OortLibrary/Artwork/MoreArtworkSources.swift) | Matching dei nomi e sorgenti Xbox, GOG, Nintendo Europe, wiki e altri cataloghi; controllo della variante Nintendo più grande prima del primo download. |
| [core/OortLibrary/Artwork/ArtworkBrowse.swift](../../core/OortLibrary/Artwork/ArtworkBrowse.swift) | Sorgenti sfogliabili da Change artwork (LaunchBox, SteamGridDB): nomi cercati e risultati per tutti gli slot. |
| [core/OortLibrary/Artwork/LaunchBoxArt.swift](../../core/OortLibrary/Artwork/LaunchBoxArt.swift) | Legge ricerca e pagina gioco di LaunchBox; dal payload Nuxt ricava anteprime, file pieni, tipo, regione e dimensioni; screenshot Gameplay. |
| [core/OortLibrary/Artwork/SteamGridDBArt.swift](../../core/OortLibrary/Artwork/SteamGridDBArt.swift) | Conserva la chiave SteamGridDB in un file 0600 e interroga l’API v2 per griglie, hero, loghi e icone statiche accreditate. |
| [core/OortLibrary/Artwork/LibraryArtworkRole.swift](../../core/OortLibrary/Artwork/LibraryArtworkRole.swift) | Ruoli di layout delle immagini (copertina, quadrato, sfondo…) separati dal fornitore: un quadrato non chiede né ritaglia mai la copertina verticale. |
| [core/OortLibrary/Artwork/CriticRating.swift](../../core/OortLibrary/Artwork/CriticRating.swift) | Identità pubblica del gioco e console (Mac, Switch, Switch 2), voto originale /100, provenienza e riempimento proporzionale delle cinque stelle. |
| [core/OortLibrary/Artwork/WikidataRatings.swift](../../core/OortLibrary/Artwork/WikidataRatings.swift) | Abbina titoli esatti e ID Steam; seleziona medie della critica documentate, senza confondere piattaforme o raccomandazioni. L'identità del gioco (`entity`) serve anche alle descrizioni di Wikipedia. |
| [core/OortLibrary/Artwork/WikipediaDescription.swift](../../core/OortLibrary/Artwork/WikipediaDescription.swift) | Quando una descrizione non è nella lingua dell'app, sitelink Wikidata e introduzione di Wikipedia in quella lingua (cinese in semplificato); servizio con cache misurabile e svuotabile, host fissi e nessun errore salvato come assenza. |
| [core/OortLibrary/Artwork/CriticRatingService.swift](../../core/OortLibrary/Artwork/CriticRatingService.swift) | Preferenza IGDB personale → Wikidata pubblico, cache Wikidata, ripiego offline e pausa dopo errori. |
| [core/OortLibrary/Artwork/IGDBCredentials.swift](../../core/OortLibrary/Artwork/IGDBCredentials.swift) | Credenziali Twitch personali in file 0600, validazione e messaggi sicuri senza segreti nei log. |
| [core/OortLibrary/Artwork/IGDBRatings.swift](../../core/OortLibrary/Artwork/IGDBRatings.swift) | Abbinamento IGDB esatto o tramite ID Steam, critica preferita e ripiego utenti esplicito, con provenienza distinta da Wikidata. |
| [core/OortLibrary/Artwork/IGDBRatingService.swift](../../core/OortLibrary/Artwork/IGDBRatingService.swift) | Cache dei voti, richieste coalescenti e verifica credenziali tramite il client IGDB condiviso. |
| [core/OortLibrary/Artwork/IGDBClient.swift](../../core/OortLibrary/Artwork/IGDBClient.swift) | Unico accesso Twitch/IGDB per voti e metadati: token in memoria, coda limitata seriale, host vincolati, rinnovo 401 e annullamento. |
| [core/OortLibrary/Artwork/IGDBMetadata.swift](../../core/OortLibrary/Artwork/IGDBMetadata.swift) | Proposte IGDB per campo: identità esatta, ruoli delle aziende e date complete della piattaforma corretta. |
| [core/OortLibrary/Artwork/IGDBMetadataService.swift](../../core/OortLibrary/Artwork/IGDBMetadataService.swift) | Ricerca metadati su richiesta, ID Steam verificato, cache separata e ripiego offline; nessuna scrittura delle scelte personali. |
| [core/OortLibrary/Artwork/DatabaseMetadata.swift](../../core/OortLibrary/Artwork/DatabaseMetadata.swift) | Proposte LaunchBox/TheGamesDB: identità e piattaforma verificate, campi separati, fonte esplicita e date della versione corretta. |
| [core/OortLibrary/Artwork/DatabaseMetadataService.swift](../../core/OortLibrary/Artwork/DatabaseMetadataService.swift) | Letture pubbliche limitate e annullabili, richieste condivise, cache testuale per gioco/piattaforma e recupero offline. |
| [core/OortLibrary/Artwork/GameGenre.swift](../../core/OortLibrary/Artwork/GameGenre.swift) | Generi noti tradotti alla presentazione; dati originali e generi personali conservati. |

## Core · achievement

Cartella `core/OortLibrary/Achievements/`.

| File | Responsabilità |
|---|---|
| [core/OortLibrary/Achievements/AchievementSummary.swift](../../core/OortLibrary/Achievements/AchievementSummary.swift) | Riepilogo puro per la tile e la schermata: conteggi, percentuale, gioco completato (`isComplete`), righe recenti con icona, conteggi per tier, sbloccati di recente, ultimo sblocco, filtri e ordini; maschera i nascosti ancora bloccati. |
| [core/OortLibrary/Achievements/AchievementTier.swift](../../core/OortLibrary/Achievements/AchievementTier.swift) | Tier a cristallo come i trofei PS5: Arcano (viola, al posto del Platino) per il gioco completato, Oro / Argento / Bronzo per rarità Steam (<10%, <30%, il resto); nomi tradotti e PNG nelle risorse del Core; `videoURL` dà il video in loop dell'Arcane (`crystal-arcane.mov`, HEVC con alpha a 384 px). |
| [core/OortLibrary/Achievements/AchievementsScreenState.swift](../../core/OortLibrary/Achievements/AchievementsScreenState.swift) | Filtro e selezione della schermata Achievements: due colonne, bordi fermi, LB/RB che girano i filtri. |
| [LocalAchievementPack.swift](../../core/OortLibrary/Achievements/LocalAchievementPack.swift) | Pack locale, metriche e regole; progressi e primi sblocchi persistenti per gioco e profilo. |

## Core · mod

Cartella `core/OortLibrary/Mods/`.

| File | Responsabilità |
|---|---|
| [core/OortLibrary/Mods/ModsBandLayout.swift](../../core/OortLibrary/Mods/ModsBandLayout.swift) | Ordine delle tessere, Search accanto a Manage e movimento nella griglia (sei per riga). |
| [core/OortLibrary/Mods/LocalMod.swift](../../core/OortLibrary/Mods/LocalMod.swift) | Una mod locale: cartella, stato e radici `romfs` o `exefs`. |

## Core · impostazioni, lingua e testi

Cartella `core/OortLibrary/Settings/`. Il catalogo dei testi sta in `Resources/`.

| File | Responsabilità |
|---|---|
| [core/OortLibrary/Settings/AppSettings.swift](../../core/OortLibrary/Settings/AppSettings.swift) | Impostazioni globali e decodifica compatibile, anche per Inbox, Compilati di recente (attivi per default), Home in gioco e scelta VPN da ZeroTier Automatico. Tiene le chiavi del modulo come JSON e ignora chiavi e card Spotlight sconosciute. |
| [core/OortLibrary/Settings/AppSettingsStore.swift](../../core/OortLibrary/Settings/AppSettingsStore.swift) | Separa bozza, anteprime e valori applicati; salva settings.json con lock, sostituzione atomica e rilettura. Conserva un file illeggibile e scrive l'ultima selezione in background. |
| [core/OortLibrary/Settings/AppSettingsDraft.swift](../../core/OortLibrary/Settings/AppSettingsDraft.swift) | Confronta ogni campo modificabile con l'originale, espone i cambi e unisce le modifiche senza sovrascrivere un conflitto. |
| [core/OortLibrary/Settings/SettingsRowAction.swift](../../core/OortLibrary/Settings/SettingsRowAction.swift) | Identifica azioni e righe Settings, mantenendo una sola azione primaria per riga senza accorpare giochi omonimi. |
| [core/OortLibrary/Settings/SettingsCatalog.swift](../../core/OortLibrary/Settings/SettingsCatalog.swift) | Righe fuori da Porting, incluse Play together, Hidden game apps e Home in gioco; ordina, cerca e confronta per identità. |
| [core/OortLibrary/Settings/SettingsSection.swift](../../core/OortLibrary/Settings/SettingsSection.swift) | Titoli e icone della barra: General, Library, Porting (con Game folders e Porting storage) e System. |
| [core/OortLibrary/Settings/SettingsCategory.swift](../../core/OortLibrary/Settings/SettingsCategory.swift) | Rubriche brevi localizzate e associazione con le sezioni storiche, senza cambiare le rotte. |
| [core/OortLibrary/Settings/SettingsReset.swift](../../core/OortLibrary/Settings/SettingsReset.swift) | Reset group per sezione, anche Inbox con Game folders, Compilati di recente con Spotlight, Home in gioco e scelte Play together, non l'ID Nextendo né i percorsi delle cartelle di gioco. |
| [core/OortLibrary/Settings/OnlinePlayersDisplay.swift](../../core/OortLibrary/Settings/OnlinePlayersDisplay.swift) | I quattro interruttori di Nextendo players, la conversione delle scelte precedenti e la condizione per leggere il conteggio. |
| [core/OortLibrary/Settings/AppLocale.swift](../../core/OortLibrary/Settings/AppLocale.swift) | Sette lingue, risoluzione delle preferenze e regione indipendente; nomi e ricerca delle regioni. |
| [core/OortLibrary/Settings/AppLocalization.swift](../../core/OortLibrary/Settings/AppLocalization.swift) | Contesto osservabile, lookup delle risorse, interpolazioni/plurali e nome Oort NX nei testi resi. |
| [core/OortLibrary/Settings/GeneratedNames.swift](../../core/OortLibrary/Settings/GeneratedNames.swift) | Nome del bundle di risorse compilato, generato da `architecture/names.json`. |
| [core/OortLibrary/Resources/credits.json](../../core/OortLibrary/Resources/credits.json) | Copia generata di `design/credits.json`. |
| [core/OortLibrary/Resources/Localizable.xcstrings](../../core/OortLibrary/Resources/Localizable.xcstrings) | Testi in sette lingue, inclusi errori di avvio di Python, avvisi del Cestino, recupero degli spostamenti cloud e accessi di Integrations. |

## Core · Steam

Cartella `core/OortLibrary/Steam/`.

| File | Responsabilità |
|---|---|
| [core/OortLibrary/Steam/SteamBackgroundLaunch.swift](../../core/OortLibrary/Steam/SteamBackgroundLaunch.swift) | Attesa di un gioco Steam avviato da Play: pazienza (15 s, 45 s se Play avvia Steam), stato della schermata di lancio, regole di «Keep Steam in the background». |
| [core/OortLibrary/Steam/SteamKeyValues.swift](../../core/OortLibrary/Steam/SteamKeyValues.swift) | Parser testuale limitato e lookup condivisi dei lettori: prima chiave, primo valore tipizzato o campo unico, con regole esplicite sui duplicati; nessuna direttiva eseguita. |
| [core/OortLibrary/Steam/SteamPlaytimeReader.swift](../../core/OortLibrary/Steam/SteamPlaytimeReader.swift) | Ore e ultima partita dell’account Steam più recente da `localconfig.vdf`; nient’altro del file esce dal tipo. |
| [core/OortLibrary/Steam/SteamPlaytimeBaselines.swift](../../core/OortLibrary/Steam/SteamPlaytimeBaselines.swift) | Totali Steam con il momento in cui sono stati visti; nuovo valore o account ripartono; mappa ai giochi del catalogo. |
| [core/OortLibrary/Steam/SteamReturnFocus.swift](../../core/OortLibrary/Steam/SteamReturnFocus.swift) | Quando un gioco Steam che esce riporta Arcane davanti: Play premuto qui, gioco in primo piano, nessun altro gioco aperto. |
| [core/OortLibrary/Steam/SteamLaunchQuestions.swift](../../core/OortLibrary/Steam/SteamLaunchQuestions.swift) | Domande con cui Steam ferma un avvio, dalle righe `GameAction` di `logs/console_log.txt`. `ShowInterstitials` è avanzamento; le domande contano dopo 1 s. |
| [core/OortLibrary/Steam/SteamPlaytimeSync.swift](../../core/OortLibrary/Steam/SteamPlaytimeSync.swift) | Una lettura dei file Steam e cosa fa (pubblica, conserva gli ultimi totali buoni dello stesso account o azzera); coda di una lettura alla volta. |
| [core/OortLibrary/Steam/InstallationFileSnapshot.swift](../../core/OortLibrary/Steam/InstallationFileSnapshot.swift) | Letture limitate e non bloccanti di file regolari; verifica dell'identità prima della pubblicazione. |
| [core/OortLibrary/Steam/InstallationDirectorySnapshot.swift](../../core/OortLibrary/Steam/InstallationDirectorySnapshot.swift) | Lettura incrementale delle cartelle, budget anche sulle voci nascoste e annullamento durante l'enumerazione. |
| [core/OortLibrary/Steam/NativeMacApplication.swift](../../core/OortLibrary/Steam/NativeMacApplication.swift) | Evidenze del bundle Mac e degli header eseguibili, architetture e categoria dichiarata, senza avvio. |
| [core/OortLibrary/Steam/SteamLibrarySource.swift](../../core/OortLibrary/Steam/SteamLibrarySource.swift) | Snapshot delle librerie/manifest; omette i percorsi non pubblicabili e segnala una scansione parziale senza modificare il catalogo. |
| [core/OortLibrary/Steam/SteamPlayState.swift](../../core/OortLibrary/Steam/SteamPlayState.swift) | Stato di Play per un gioco Steam: processi osservati con i percorsi risolti, passaggio a Steam, sessione solo quando gira l’app di questa installazione, attese e rifiuti. |
| [core/OortLibrary/Steam/SteamBinaryKeyValues.swift](../../core/OortLibrary/Steam/SteamBinaryKeyValues.swift) | Lettura limitata del formato KeyValues binario di Steam (`appcache/stats`): tipi noti, profondità, voci e dimensione; qualunque altro byte è un errore. |
| [core/OortLibrary/Steam/SteamAchievementReader.swift](../../core/OortLibrary/Steam/SteamAchievementReader.swift) | Achievement di un gioco per l’account corrente: schema (nomi nella lingua dell’app, poi inglese; nascosti; icone) e soli `AchievementTimes` del file delle statistiche; nessun file, account o statistiche: nessun dato. |
| [core/OortLibrary/Steam/SteamAchievementRarity.swift](../../core/OortLibrary/Steam/SteamAchievementRarity.swift) | Rarità pubblica (`GetGlobalAchievementPercentagesForApp`, senza chiave) (una percentuale non numerica, «nan» o «inf», si scarta) e indirizzi delle icone sull’host community-assets del CDN di Steam, solo per nomi di file semplici. |
| [core/OortLibrary/Steam/SteamManifestWatcher.swift](../../core/OortLibrary/Steam/SteamManifestWatcher.swift) | Uno stream FSEvents sulle cartelle `steamapps` delle librerie dell’ultima scansione; segnala solo i manifest `appmanifest_<AppID>.acf` e l’indice `libraryfolders.vdf` della radice, una volta per gruppo di eventi. |
| [core/OortLibrary/Steam/SteamMetadata.swift](../../core/OortLibrary/Steam/SteamMetadata.swift) | Dati store Steam tipizzati, lingua e URL immagini verificati. |
| [core/OortLibrary/Steam/SteamMetadataService.swift](../../core/OortLibrary/Steam/SteamMetadataService.swift) | Fino a sei download coalescenti, cache per lingua, ripiego offline (anche in un'altra lingua) e immagini ridimensionate. Legge i tratti dei giochi correlati solo da cache. |
| [core/OortLibrary/Steam/SteamPersonalizationStore.swift](../../core/OortLibrary/Steam/SteamPersonalizationStore.swift) | Pubblicazione unica di metadati e riferimenti artwork; fallimenti e Automatic conservano le scelte coerenti. |
| [core/OortLibrary/Steam/SteamArtworkRequest.swift](../../core/OortLibrary/Steam/SteamArtworkRequest.swift) | Cosa chiede la tile di un gioco Steam per ogni ruolo: prima la scelta personale, poi per il quadrato l’icona dell’app installata, mai la copertina; gli altri ruoli vanno all’arte dello store. |
| [core/OortLibrary/Steam/SteamBackdropChoice.swift](../../core/OortLibrary/Steam/SteamBackdropChoice.swift) | Sfondo automatico di un gioco Steam: arte 16:9 pulita (Xbox, GOG, TheGamesDB, fan art LaunchBox), poi il primo screenshot, per ultimo il banner della libreria ritagliato. |

## Porting · gioco Switch e libreria nxnative

Cartella `engines/nxnative/NxnativeAdapter/`.

| File | Responsabilità |
|---|---|
| [engines/nxnative/NxnativeAdapter/PortedGame.swift](../../engines/nxnative/NxnativeAdapter/PortedGame.swift) | Modello persistente del gioco, anche solo remoto: bundle, sorgenti, posizione remota relativa, impostazioni, build e installazione in attesa. |
| [engines/nxnative/NxnativeAdapter/LibraryFile.swift](../../engines/nxnative/NxnativeAdapter/LibraryFile.swift) | Contenitore versionato del catalogo della libreria. |
| [engines/nxnative/NxnativeAdapter/GameStatus.swift](../../engines/nxnative/NxnativeAdapter/GameStatus.swift) | Enumera disponibilità e stato del gioco rispetto ad app, sorgenti e porting. |
| [engines/nxnative/NxnativeAdapter/TargetPlatform.swift](../../engines/nxnative/NxnativeAdapter/TargetPlatform.swift) | Definisce il target mac-app e le sue etichette per l’interfaccia. |

## Porting · catalogo nxnative

Cartella `engines/nxnative/NxnativeAdapter/Catalog/`.

| File | Responsabilità |
|---|---|
| [engines/nxnative/NxnativeAdapter/Catalog/PortedGame+Catalog.swift](../../engines/nxnative/NxnativeAdapter/Catalog/PortedGame+Catalog.swift) | `PortedGame` nel contratto del catalogo (validazione, presenza, avvio, ricerca), integrazione `.nxnative`, tipi noti dell’app (`CatalogRecordKinds.standard`) ed entrate `nxnativeGame`, `init(nxnative:)`, `updateNXNative`. |
| [engines/nxnative/NxnativeAdapter/Catalog/CatalogPersonalizations+Porting.swift](../../engines/nxnative/NxnativeAdapter/Catalog/CatalogPersonalizations+Porting.swift) | Chiave personale nxnative (title ID o chiave storica) e radice dei dati personali: nxnative alla radice, ogni altra integrazione in `integrations/<nome>`. |
| [engines/nxnative/NxnativeAdapter/Catalog/CatalogStore+Porting.swift](../../engines/nxnative/NxnativeAdapter/Catalog/CatalogStore+Porting.swift) | Store con tutti i tipi noti e import di `library.json`; riconosce le build in attesa della vecchia libreria anche dal percorso del log. |
| [engines/nxnative/NxnativeAdapter/Catalog/CatalogRepository+Porting.swift](../../engines/nxnative/NxnativeAdapter/Catalog/CatalogRepository+Porting.swift) | Modifiche nxnative del catalogo: merge di scansioni, app e build, aggiornamento delle sorgenti da manifest quando mancano tutte le copie locali, esclusioni e proiezione `nxnativeGames`. |
| [engines/nxnative/NxnativeAdapter/Catalog/CatalogBuildRecoveries.swift](../../engines/nxnative/NxnativeAdapter/Catalog/CatalogBuildRecoveries.swift) | Generazioni di build non ancora salvate, selezione del retry e conferma della sola generazione persistita. |

## Porting · libreria, sessioni e spazio

Cartella `engines/nxnative/NxnativeAdapter/Library/`.

| File | Responsabilità |
|---|---|
| [engines/nxnative/NxnativeAdapter/Library/LibraryQuery+Porting.swift](../../engines/nxnative/NxnativeAdapter/Library/LibraryQuery+Porting.swift) | Filtro, ricerca e selezione della home per i giochi Switch: `PortedGame` come `LibraryQueryRecord`, `LibraryQuery.apply(to:history:)`, `reconcile`, `move` e `jump` di `LibrarySelectionState`. |
| [engines/nxnative/NxnativeAdapter/Library/Surprise+Porting.swift](../../engines/nxnative/NxnativeAdapter/Library/Surprise+Porting.swift) | Surprise me sui giochi Switch, sopra la scelta generica di `Surprise`. |
| [engines/nxnative/NxnativeAdapter/Library/PlaySessionStore+Porting.swift](../../engines/nxnative/NxnativeAdapter/Library/PlaySessionStore+Porting.swift) | Avvio della sessione di un gioco portato: title ID (o chiave unica) e bundle ID dell’app. |
| [engines/nxnative/NxnativeAdapter/Library/SessionSummary+Porting.swift](../../engines/nxnative/NxnativeAdapter/Library/SessionSummary+Porting.swift) | Card di fine sessione per un gioco portato. |
| [engines/nxnative/NxnativeAdapter/Library/LibraryPresentation+Porting.swift](../../engines/nxnative/NxnativeAdapter/Library/LibraryPresentation+Porting.swift) | Valori della libreria per un gioco portato (fatti dello store Nintendo, console, sorgenti staccate) e l’entrata per `CatalogGame`, che sceglie la strada Switch o Steam. |
| [engines/nxnative/NxnativeAdapter/Library/RunningGames.swift](../../engines/nxnative/NxnativeAdapter/Library/RunningGames.swift) | Quali giochi portati sono in esecuzione: confronta il bundle ID effettivo con quelli delle app aperte. |
| [engines/nxnative/NxnativeAdapter/Library/StorageManager.swift](../../engines/nxnative/NxnativeAdapter/Library/StorageManager.swift) | Misura app, cache e log per gioco e totali senza duplicare percorsi condivisi; verifica cartelle e sorgenti prima della pulizia selettiva. I backup appartengono al flusso Saves. |
| [engines/nxnative/NxnativeAdapter/Library/GameInbox.swift](../../engines/nxnative/NxnativeAdapter/Library/GameInbox.swift) | Propone nomi e destinazioni delle sorgenti; distingue chiavi mancanti e ambiguità, riusa le verifiche dei duplicati nell'anteprima e ricalcola gli hash prima del Cestino. |
| [engines/nxnative/NxnativeAdapter/Library/CloudArchiveInventory.swift](../../engines/nxnative/NxnativeAdapter/Library/CloudArchiveInventory.swift) | Controlla gerarchia, link, hash e metadati per Apple Archive e i file; condivide le esclusioni di slot, registro e journal storici. |
| [engines/nxnative/NxnativeAdapter/Library/CloudArtifactFiles.swift](../../engines/nxnative/NxnativeAdapter/Library/CloudArtifactFiles.swift) | Valida percorsi, dimensioni e MD5 di un albero v2, confronta l'elenco rclone, ripristina i link e inventaria il contenuto al netto delle firme per l'adozione. |
| [engines/nxnative/NxnativeAdapter/Library/CloudGameArchive.swift](../../engines/nxnative/NxnativeAdapter/Library/CloudGameArchive.swift) | Pubblica e legge le revisioni di app e cache separatamente; distingue manifest non validi ed errori di lettura; riusa la cache compatibile prima di Rebuild completo; ripristino atomico e recupero di Free up space. |
| [engines/nxnative/NxnativeAdapter/Library/CloudGameArchive+Files.swift](../../engines/nxnative/NxnativeAdapter/Library/CloudGameArchive+Files.swift) | Calcola il diff, riprende il download v2 in staging, clona i file uguali, conserva la cache parziale verificata e ripara l'app prima della pubblicazione locale. |
| [engines/nxnative/NxnativeAdapter/Library/CloudManifestCache.swift](../../engines/nxnative/NxnativeAdapter/Library/CloudManifestCache.swift) | Schede cloud già lette, per SHA-256 del nome e MD5 di Drive; solo le letture per gli schermi la usano. |
| [engines/nxnative/NxnativeAdapter/Library/CloudArchiveFingerprintCache.swift](../../engines/nxnative/NxnativeAdapter/Library/CloudArchiveFingerprintCache.swift) | Cache persistente e limitata delle impronte di app e cache, indicizzata da digest. |
| [engines/nxnative/NxnativeAdapter/Library/CloudGameSources.swift](../../engines/nxnative/NxnativeAdapter/Library/CloudGameSources.swift) | Scopre le sorgenti sotto una radice autorizzata, rifiuta ambiguità e collisioni Unicode e riverifica la selezione, lo spazio, le impronte e l'identità NSP al download. |
| [engines/nxnative/NxnativeAdapter/Library/CloudTransferQueue.swift](../../engines/nxnative/NxnativeAdapter/Library/CloudTransferQueue.swift) | Salva azioni, ambito Drive, fornitore, identità dell'eseguibile e selezione di Rebuild; ammette la pausa volontaria solo su un download valido in testa. |
| [PersonalAppReceipt.swift](../../engines/nxnative/NxnativeAdapter/Library/PersonalAppReceipt.swift) | Ricevuta di trasferimento personale, confronto delle copie e controllo delle impronte prima dello scambio. |
| [engines/nxnative/NxnativeAdapter/Library/CloudTransferPresentation.swift](../../engines/nxnative/NxnativeAdapter/Library/CloudTransferPresentation.swift) | Stati, misura esclusiva, annullamento e posizione del comando Cloud library con link di riserva. |
| [engines/nxnative/NxnativeAdapter/Library/CloudDriveFolders.swift](../../engines/nxnative/NxnativeAdapter/Library/CloudDriveFolders.swift) | Elenca, trova e crea cartelle Drive, rifiuta sovrapposizioni con il riferimento, lega l’anteprima di spostamento alla libreria approvata e verifica dipendenze e residui. |
| [engines/nxnative/NxnativeAdapter/Library/CloudDriveReads.swift](../../engines/nxnative/NxnativeAdapter/Library/CloudDriveReads.swift) | Letture condivise per un minuto, solo per lo schermo. |
| [engines/nxnative/NxnativeAdapter/Library/CloudFolderDiscovery.swift](../../engines/nxnative/NxnativeAdapter/Library/CloudFolderDiscovery.swift) | Cosa contiene ogni cartella, quali proporre e perché una è sbagliata. |
| [engines/nxnative/NxnativeAdapter/GameSettings/RemotePlayAdapters.swift](../../engines/nxnative/NxnativeAdapter/GameSettings/RemotePlayAdapters.swift) | Rileva ZeroTier, Tailscale e NetBird da interfacce IPv4 e identità VPN riportata dal sistema; segnala i tunnel ambigui. |
| [engines/nxnative/NxnativeAdapter/Library/BuildQueue.swift](../../engines/nxnative/NxnativeAdapter/Library/BuildQueue.swift) | FIFO delle compilazioni, richiesta serializzabile con scelta della cache locale, deduplica e controllo delle sorgenti al ripristino. |
| [engines/nxnative/NxnativeAdapter/Library/ActivityQueueFile.swift](../../engines/nxnative/NxnativeAdapter/Library/ActivityQueueFile.swift) | Lettura tollerante e scrittura atomica di code ed esiti; la riconferma attende la sincronizzazione del file e della directory. |
| [engines/nxnative/NxnativeAdapter/Library/ActivityHistory.swift](../../engines/nxnative/NxnativeAdapter/Library/ActivityHistory.swift) | Esiti di attività, lock tra processi e registro durevole dello spostamento con identità dell'eseguibile ed esito verificato. |
| [engines/nxnative/NxnativeAdapter/Library/GameStorageUsage.swift](../../engines/nxnative/NxnativeAdapter/Library/GameStorageUsage.swift) | Dimensioni per gioco e totali: distingue assenza e indisponibilità, segnala cache condivise e conserva identità stabili per il focus. |

## Porting · pagina del gioco

Cartella `engines/nxnative/NxnativeAdapter/Details/`.

| File | Responsabilità |
|---|---|
| [engines/nxnative/NxnativeAdapter/Details/GameDetailPresentation+Porting.swift](../../engines/nxnative/NxnativeAdapter/Details/GameDetailPresentation+Porting.swift) | La pagina di un gioco portato: fatti dello store Nintendo, toolchain della build, sorgenti, Rebuild e cartella dei salvataggi. |
| [engines/nxnative/NxnativeAdapter/Details/DetailsFacts+Porting.swift](../../engines/nxnative/NxnativeAdapter/Details/DetailsFacts+Porting.swift) | Le righe Details di un gioco portato: crediti, versione del gioco, data e stato del motore, dimensione e cartella dell’app. |
| [engines/nxnative/NxnativeAdapter/Details/GameOptionsPresentation+Porting.swift](../../engines/nxnative/NxnativeAdapter/Details/GameOptionsPresentation+Porting.swift) | Converte `GameSettingsSnapshot` in `GameOptionsBuildSettings`, incluso Play together se la build dichiara modalità di rete. |
| [engines/nxnative/NxnativeAdapter/Details/MoreLikeThis+Porting.swift](../../engines/nxnative/NxnativeAdapter/Details/MoreLikeThis+Porting.swift) | More like this fra giochi portati, con autori e generi dello store Nintendo. |

## Porting · impostazioni e app

Cartelle `engines/nxnative/NxnativeAdapter/Settings/` e `NxnativeAdapter/App/`.

| File | Responsabilità |
|---|---|
| [engines/nxnative/NxnativeAdapter/Settings/AppSettings+Porting.swift](../../engines/nxnative/NxnativeAdapter/Settings/AppSettings+Porting.swift) | Game defaults, schermo globale e per gioco, Cloud saves, cartella scelta e ID client pubblico Nextendo in `settings.json`; un valore assente o illeggibile è il suo default. |
| [engines/nxnative/NxnativeAdapter/Settings/SettingsReset+Porting.swift](../../engines/nxnative/NxnativeAdapter/Settings/SettingsReset+Porting.swift) | Reset group completo: quello della base più New games (default e scelta globale dello schermo). |
| [engines/nxnative/NxnativeAdapter/App/AppDataProfile+Porting.swift](../../engines/nxnative/NxnativeAdapter/App/AppDataProfile+Porting.swift) | Cartelle temporanee pulite all’avvio: quella del profilo e, nella release non migrata, anche quelle accanto alle app. |
| [engines/nxnative/NxnativeAdapter/App/FirstRunFindings+Porting.swift](../../engines/nxnative/NxnativeAdapter/App/FirstRunFindings+Porting.swift) | Il primo avvio conta le app nxnative della cartella Game apps, nella lettura e nel lettore annullabile. |
| [engines/nxnative/NxnativeAdapter/App/OnboardingInventory.swift](../../engines/nxnative/NxnativeAdapter/App/OnboardingInventory.swift) | Scoperta locale annullabile di app nxnative e file Switch senza chiavi, raggruppamento per titolo e stato già in libreria. |
| [engines/nxnative/NxnativeAdapter/App/DevelopmentProfileImporter+Porting.swift](../../engines/nxnative/NxnativeAdapter/App/DevelopmentProfileImporter+Porting.swift) | I controlli Porting della copia di sviluppo (`library.json`, catalogo con i tipi noti e l’import legacy) e `DevelopmentProfileImporter()` e `AppData.prepare()` con questi. |
| [engines/nxnative/NxnativeAdapter/Settings/SettingsCatalog+Porting.swift](../../engines/nxnative/NxnativeAdapter/Settings/SettingsCatalog+Porting.swift) | Righe Porting (inclusi Inbox e Cestino per le cache), disponibilità Nextendo in Play together e apertura di Cloud → Advanced da Search e Changed. |
| [engines/nxnative/NxnativeAdapter/Settings/IntegrationOverview.swift](../../engines/nxnative/NxnativeAdapter/Settings/IntegrationOverview.swift) | Proietta fatti in righe, con oggetti letti, scritture e destinatari esterni; `open` naviga senza eseguire i controlli. |

## Porting · Setup, motore e chiavi

Cartella `engines/nxnative/NxnativeAdapter/Setup/`.

| File | Responsabilità |
|---|---|
| [engines/nxnative/NxnativeAdapter/Setup/ToolchainRequirements.swift](../../engines/nxnative/NxnativeAdapter/Setup/ToolchainRequirements.swift) | Centralizza requisiti Xcode e asset Metal. |
| [engines/nxnative/NxnativeAdapter/Setup/ToolchainInfo.swift](../../engines/nxnative/NxnativeAdapter/Setup/ToolchainInfo.swift) | Registra provenienza e verifica della toolchain associata a un build. |
| [engines/nxnative/NxnativeAdapter/Setup/ToolchainGateCopy.swift](../../engines/nxnative/NxnativeAdapter/Setup/ToolchainGateCopy.swift) | Traduce il gate in testi distinguendo Metal certificato, precedente e successivo. |
| [engines/nxnative/NxnativeAdapter/Setup/SetupCheck.swift](../../engines/nxnative/NxnativeAdapter/Setup/SetupCheck.swift) | Converte i fatti in schede localizzate, distingue runtime assente e guasto ed esclude i checkout esistenti da Install all. |
| [engines/nxnative/NxnativeAdapter/Setup/GameFoldersCopy.swift](../../engines/nxnative/NxnativeAdapter/Setup/GameFoldersCopy.swift) | Condivide nomi delle cartelle, formati e descrizioni tra Setup, Settings e selettori dei percorsi; indica Game folders per cambiarle. |
| [engines/nxnative/NxnativeAdapter/Setup/SetupGrid.swift](../../engines/nxnative/NxnativeAdapter/Setup/SetupGrid.swift) | Calcola disposizione, centratura e navigazione del focus nella griglia del Setup. |
| [engines/nxnative/NxnativeAdapter/Setup/UpstreamCopy.swift](../../engines/nxnative/NxnativeAdapter/Setup/UpstreamCopy.swift) | Prepara i testi del changelog upstream e dell’adozione degli aggiornamenti tramite Arcane. |
| [engines/nxnative/NxnativeAdapter/Setup/NXNativeEnvironment.swift](../../engines/nxnative/NxnativeAdapter/Setup/NXNativeEnvironment.swift) | Ispeziona strumenti, Python, Xcode e Metal e restituisce uno stato dell’ambiente. |
| [engines/nxnative/NxnativeAdapter/Setup/EngineLocation.swift](../../engines/nxnative/NxnativeAdapter/Setup/EngineLocation.swift) | Risolve checkout predefinito o scelto e produce i candidati per prod.keys. |
| [engines/nxnative/NxnativeAdapter/Setup/EngineToolchain.swift](../../engines/nxnative/NxnativeAdapter/Setup/EngineToolchain.swift) | Individua runtime incluso o venv del checkout e prepara ambiente e PATH dei processi. |
| [engines/nxnative/NxnativeAdapter/Setup/EnginePackageReader.swift](../../engines/nxnative/NxnativeAdapter/Setup/EnginePackageReader.swift) | Legge content meta e capacità del checkout, compresa selezione NUP multiprogramma, senza esporre chiavi. |
| [engines/nxnative/NxnativeAdapter/Setup/NewestEngine.swift](../../engines/nxnative/NxnativeAdapter/Setup/NewestEngine.swift) | Scelta dell’engine più nuovo: testi condivisi, lettura del Metal dal lock di main, cambio di commit con Git senza toccare file modificati; usa il repository del pin per tornare all’engine testato. |
| [engines/nxnative/NxnativeAdapter/Setup/CompatibilityChecker.swift](../../engines/nxnative/NxnativeAdapter/Setup/CompatibilityChecker.swift) | Controlla commit, modifiche del checkout, Metal e opzioni CLI richieste dal frontend. |
| [engines/nxnative/NxnativeAdapter/Setup/SetupProbe.swift](../../engines/nxnative/NxnativeAdapter/Setup/SetupProbe.swift) | Raccoglie i fatti del Setup, compresi runtime attivo e stato del checkout; rilegge il checkout prima di cambiarlo. |
| [engines/nxnative/NxnativeAdapter/Setup/MacNXNative.swift](../../engines/nxnative/NxnativeAdapter/Setup/MacNXNative.swift) | Adapter: legge il checkout e `DMCommit`, compara le versioni e presenta data e stato localizzati. |
| [engines/nxnative/NxnativeAdapter/Setup/SetupActions.swift](../../engines/nxnative/NxnativeAdapter/Setup/SetupActions.swift) | Legge il pin facoltativo dal plist e costruisce i comandi Git per installare o allineare il motore al pin. |
| [engines/nxnative/NxnativeAdapter/Setup/KeyStore.swift](../../engines/nxnative/NxnativeAdapter/Setup/KeyStore.swift) | Valida chiavi in sola lettura; importa atomicamente in 0600 e ripristina 0700/0600 solo in installazione. |
| [engines/nxnative/NxnativeAdapter/Setup/KeyCheck.swift](../../engines/nxnative/NxnativeAdapter/Setup/KeyCheck.swift) | Verifica le chiavi contro le intestazioni NCA, con intervalli di lettura limitati dalla dimensione del pacchetto. |
| [engines/nxnative/NxnativeAdapter/Setup/UpstreamChecker.swift](../../engines/nxnative/NxnativeAdapter/Setup/UpstreamChecker.swift) | Consulta i commit upstream tramite HTTP e produce stato e collegamento di confronto. |

## Porting · sorgenti, build e installazione

Cartella `engines/nxnative/NxnativeAdapter/Build/`.

| File | Responsabilità |
|---|---|
| [engines/nxnative/NxnativeAdapter/Build/GameResourceState.swift](../../engines/nxnative/NxnativeAdapter/Build/GameResourceState.swift) | Distingue app mancanti, sorgenti assenti e workspace non compilati; rifiuta gli alias locali nelle selezioni scoperte dal cloud. Una build esistente mantiene Play. |
| [engines/nxnative/NxnativeAdapter/Build/AppSizeCache.swift](../../engines/nxnative/NxnativeAdapter/Build/AppSizeCache.swift) | Conserva dimensioni per percorso e data del bundle e decide lo stato vuoto della libreria. |
| [engines/nxnative/NxnativeAdapter/Build/BuildWarningCopy.swift](../../engines/nxnative/NxnativeAdapter/Build/BuildWarningCopy.swift) | Testo mostrato a fine build per `warn` dell’engine: archivio mancante o pipeline da preparare al primo avvio. |
| [engines/nxnative/NxnativeAdapter/Build/NUPSourceCatalog.swift](../../engines/nxnative/NxnativeAdapter/Build/NUPSourceCatalog.swift) | Legge NUP con base o soli update; tiene distinti programma, applicazione e base DLC tramite il lettore upstream e conserva il default selezionato. |
| [engines/nxnative/NxnativeAdapter/Build/InstallProgress.swift](../../engines/nxnative/NxnativeAdapter/Build/InstallProgress.swift) | Interpreta avanzamento Git, percentuali e byte per le installazioni. |
| [engines/nxnative/NxnativeAdapter/Build/GameFileItem.swift](../../engines/nxnative/NxnativeAdapter/Build/GameFileItem.swift) | Sorgenti salvate con layout, tipo, requisiti e selezione NUP facoltativa, compatibile con i vecchi record e con il manifest cloud. |
| [engines/nxnative/NxnativeAdapter/Build/NUPProgramSelection.swift](../../engines/nxnative/NxnativeAdapter/Build/NUPProgramSelection.swift) | Identità tipizzata del programma NUP, applicazione e base add-on; indice ricavato dal programma, persistito con i sorgenti e portabile nel manifest cloud. |
| [engines/nxnative/NxnativeAdapter/Build/SourceSelection.swift](../../engines/nxnative/NxnativeAdapter/Build/SourceSelection.swift) | Collega un titolo compilabile per ID esatto; scelte dei contenuti, dimensioni e versione di build; verifica coerenza e supporto del programma NUP e ne vincola l’indice nel rebuild. |
| [engines/nxnative/NxnativeAdapter/Build/BuildRecord.swift](../../engines/nxnative/NxnativeAdapter/Build/BuildRecord.swift) | Conserva esito, tempi, log, provenienza, richiesta di Nextendo e descrittori ExeFS. Ordina i giochi visibili per ultima compilazione riuscita. |
| [engines/nxnative/NxnativeAdapter/Build/PipelineArchiveProgress.swift](../../engines/nxnative/NxnativeAdapter/Build/PipelineArchiveProgress.swift) | Legge il log pipeline della build corrente e conta solo i gruppi confermati pronti dal motore. |
| [engines/nxnative/NxnativeAdapter/Build/PortingProgress.swift](../../engines/nxnative/NxnativeAdapter/Build/PortingProgress.swift) | Aggrega eventi del motore in fasi e percentuale complessiva; identifica archivio e prewarm senza dedurre conteggi dal tempo trascorso. |
| [engines/nxnative/NxnativeAdapter/Build/PortingPresentation.swift](../../engines/nxnative/NxnativeAdapter/Build/PortingPresentation.swift) | Definisce fallimento persistito, ETA, attività senza stima del prewarm, aspetto della tile e pill del porting. |
| [engines/nxnative/NxnativeAdapter/Build/PortingFailureReason.swift](../../engines/nxnative/NxnativeAdapter/Build/PortingFailureReason.swift) | Distingue il mancato avvio di Python dagli errori del motore e delle chiavi; classifica anche tabelle shader diverse dal profilo ed errori Nextendo. |
| [engines/nxnative/NxnativeAdapter/Build/PortingNotice.swift](../../engines/nxnative/NxnativeAdapter/Build/PortingNotice.swift) | Decide quando notificare l’esito di un porting e prepara il relativo messaggio. |
| [engines/nxnative/NxnativeAdapter/Build/PendingInstall.swift](../../engines/nxnative/NxnativeAdapter/Build/PendingInstall.swift) | Conserva il bundle pronto e l’identità attesa; un vecchio record senza identità richiede un posto libero o una ricevuta corrispondente. |
| [engines/nxnative/NxnativeAdapter/Build/SourceCatalog.swift](../../engines/nxnative/NxnativeAdapter/Build/SourceCatalog.swift) | Riconosce sorgenti NSP/XCI/NSZ/XCZ e raggruppa titoli, update e DLC; DetectedSource conserva la selezione NUP tipizzata. |
| [engines/nxnative/NxnativeAdapter/Build/ExtractedSourceCatalog.swift](../../engines/nxnative/NxnativeAdapter/Build/ExtractedSourceCatalog.swift) | Verifica il layout di un gioco estratto, legge NPDM e profilo registrato e rileva update e DLC. |
| [engines/nxnative/NxnativeAdapter/Build/WorkspaceManager.swift](../../engines/nxnative/NxnativeAdapter/Build/WorkspaceManager.swift) | Rifiuta collisioni fra sorgenti prima di preparare i collegamenti; lascia intatta la cache e verifica i link interrotti. |
| [engines/nxnative/NxnativeAdapter/Build/BuildScratch.swift](../../engines/nxnative/NxnativeAdapter/Build/BuildScratch.swift) | Sceglie dove stanno workspace e app temporanea (sul volume dell'app quando può ospitarli), riconosce i workspace gestiti e le cartelle temporanee da pulire. |
| [engines/nxnative/NxnativeAdapter/Build/BuildCommand.swift](../../engines/nxnative/NxnativeAdapter/Build/BuildCommand.swift) | Valore con eseguibile, argomenti, ambiente e directory di lavoro del processo di porting. |
| [engines/nxnative/NxnativeAdapter/Build/BuildCommandBuilder.swift](../../engines/nxnative/NxnativeAdapter/Build/BuildCommandBuilder.swift) | Contratto CLI nxnative: Mac, JSON, versione pacchetto, selezione --program esplicita, override toolchain e Nextendo con ID pubblico. |
| [engines/nxnative/NxnativeAdapter/Build/BuildEvent.swift](../../engines/nxnative/NxnativeAdapter/Build/BuildEvent.swift) | Definisce gli eventi di fase, step, avanzamento e log ricevuti dal motore. |
| [engines/nxnative/NxnativeAdapter/Build/BuildEventParser.swift](../../engines/nxnative/NxnativeAdapter/Build/BuildEventParser.swift) | Decodifica eventi JSON e tratta le altre righe come log. |
| [engines/nxnative/NxnativeAdapter/Build/BuildService.swift](../../engines/nxnative/NxnativeAdapter/Build/BuildService.swift) | Gestisce processi, cancellazione, log ed eventi; continua a leggere l’engine se non può scrivere il log. Conserva il bundle valido quando fallisce solo l’installazione. |
| [engines/nxnative/NxnativeAdapter/Build/BuildOutputInstaller.swift](../../engines/nxnative/NxnativeAdapter/Build/BuildOutputInstaller.swift) | Firma ad hoc e verifica; controlla la destinazione attesa, pubblica con rinomina o scambio atomico e riprende tramite ricevuta. |
| [engines/nxnative/NxnativeAdapter/Build/GameAppDestination.swift](../../engines/nxnative/NxnativeAdapter/Build/GameAppDestination.swift) | Risolve la destinazione per build, rebuild e adozione; evita conflitti di nome e rimanda a Game folders se la destinazione non è disponibile. |

## Porting · avvio e icona del gioco

Cartella `engines/nxnative/NxnativeAdapter/Launch/`.

| File | Responsabilità |
|---|---|
| [engines/nxnative/NxnativeAdapter/Launch/ImportService.swift](../../engines/nxnative/NxnativeAdapter/Launch/ImportService.swift) | Identità e scansione dei bundle nxnative; ripara la copia in staging e verifica l'impronta del bundle da sostituire. Firma ad hoc solo se la firma originale non verifica e la politica dei manifest lo consente. |
| [engines/nxnative/NxnativeAdapter/Launch/AppIconProgress.swift](../../engines/nxnative/NxnativeAdapter/Launch/AppIconProgress.swift) | Stati e testi della preparazione icona, con esito informativo aggiunto al log della build conclusa. |
| [engines/nxnative/NxnativeAdapter/Launch/IconLaunchWait.swift](../../engines/nxnative/NxnativeAdapter/Launch/IconLaunchWait.swift) | Conserva una richiesta Play durante la firma dell'icona e la revoca su annullamento, errore o chiusura del dialogo. |
| [engines/nxnative/NxnativeAdapter/Launch/LaunchService.swift](../../engines/nxnative/NxnativeAdapter/Launch/LaunchService.swift) | Scrive le impostazioni runtime su file quando richiesto; avvia con NSWorkspace e ambiente consentito, passa chiavi overlay e Home al processo, rimuove lo snapshot all'uscita o all'errore. |
| [NativePlayTarget.swift](../../engines/nxnative/NxnativeAdapter/Launch/NativePlayTarget.swift) | Identità esatta del bundle, elenco processi, apertura senza sostituzione e lettura del solo marcatore della consegna. |
| [PlayAttribution.swift](../../engines/nxnative/NxnativeAdapter/Launch/PlayAttribution.swift) | Distingue un nuovo processo attribuibile da un riaggancio neutro. |
| [PlayersLaunch.swift](../../engines/nxnative/NxnativeAdapter/Launch/PlayersLaunch.swift) | Limita ordine, fusione, nomi e ritratti al bundle provato e ai valori che il gioco non fissa; conserva la fusione P1 per gli host precedenti. |
| [PlayerPadFingerprint.swift](../../engines/nxnative/NxnativeAdapter/Launch/PlayerPadFingerprint.swift) | Unisce i due usi dello stesso dispositivo HID, rifiuta le identità ambigue e calcola l'impronta di avvio senza conservare numeri di serie. |
| [engines/nxnative/NxnativeAdapter/Launch/HomeMenu.swift](../../engines/nxnative/NxnativeAdapter/Launch/HomeMenu.swift) | Rileva il protocollo Home del bundle, identifica `dmhost` e modella pausa, ripresa e uscita. |
| [engines/nxnative/NxnativeAdapter/Launch/GameOverlayLaunch.swift](../../engines/nxnative/NxnativeAdapter/Launch/GameOverlayLaunch.swift) | Riconosce le chiavi overlay nel `dmhost`; prepara palette, tempo, copertina e snapshot JSON privato con i soli campi visibili. |
| [engines/nxnative/NxnativeAdapter/Launch/InstalledEngineCapabilities.swift](../../engines/nxnative/NxnativeAdapter/Launch/InstalledEngineCapabilities.swift) | Risolve Home, overlay, `DM_SCREEN` e descrittore Z-A dal bundle, con cache Git per le verifiche di ascendenza. |
| [engines/nxnative/NxnativeAdapter/Launch/GameDisplay.swift](../../engines/nxnative/NxnativeAdapter/Launch/GameDisplay.swift) | Associa display a UUID di Core Graphics, risolve la scelta e il ripiego, riconosce `DM_SCREEN` in `env.txt`. |
| [engines/nxnative/NxnativeAdapter/Launch/NextendoLaunch.swift](../../engines/nxnative/NxnativeAdapter/Launch/NextendoLaunch.swift) | Verifica Nextendo nel checkout e nell’host, valida la sessione e compone l’ambiente, inclusi ospite offline e visibilità del gioco. |
| [engines/nxnative/NxnativeAdapter/Launch/NextendoAccountService.swift](../../engines/nxnative/NxnativeAdapter/Launch/NextendoAccountService.swift) | Legge profilo e amici, aggiorna le liste, rinnova la presenza OAuth e risolve ritratti e titoli pubblici senza bearer. Conserva la diagnostica delle letture e distingue le verifiche Discord ed e-mail. |
| [engines/nxnative/NxnativeAdapter/Launch/NextendoOnlineCounts.swift](../../engines/nxnative/NxnativeAdapter/Launch/NextendoOnlineCounts.swift) | Solo con un token e se almeno un posto è attivo, legge e valida il conteggio pubblico per title ID, con download limitato e cache breve. |
| [engines/nxnative/NxnativeAdapter/Launch/NextendoOAuth.swift](../../engines/nxnative/NxnativeAdapter/Launch/NextendoOAuth.swift) | Genera la richiesta PKCE, valida la callback, scambia e ruota i token e legge userinfo. Il trasporto è limitato e registra solo percorso e codice. |
| [engines/nxnative/NxnativeAdapter/Launch/NextendoTokenStore.swift](../../engines/nxnative/NxnativeAdapter/Launch/NextendoTokenStore.swift) | Legge, sostituisce e rimuove il refresh token condiviso sotto il lock nxnative, con permessi privati. |
| [engines/nxnative/NxnativeAdapter/Launch/AppIconWriter.swift](../../engines/nxnative/NxnativeAdapter/Launch/AppIconWriter.swift) | Cambia o ripristina l'icona, rifirma e verifica; conserva le copie e il manifesto se il rollback non riesce. |
| [engines/nxnative/NxnativeAdapter/Launch/NXNativeLibraryMerge.swift](../../engines/nxnative/NxnativeAdapter/Launch/NXNativeLibraryMerge.swift) | Merge nxnative: preserva l'identità di libreria, ma aggiorna la provenienza se il disco restituisce un bundle diverso. |

## Porting · impostazioni del gioco

Cartella `engines/nxnative/NxnativeAdapter/GameSettings/`.

| File | Responsabilità |
|---|---|
| [engines/nxnative/NxnativeAdapter/GameSettings/NXNativeGameSettings.swift](../../engines/nxnative/NxnativeAdapter/GameSettings/NXNativeGameSettings.swift) | Risolve la modalità multigiocatore, le scelte precedenti e le variabili esplicite, e compone l'ambiente VPN di Play. |
| [engines/nxnative/NxnativeAdapter/GameSettings/GameSettingsCopy.swift](../../engines/nxnative/NxnativeAdapter/GameSettings/GameSettingsCopy.swift) | Cosa cambierebbe copiando le impostazioni di un gioco su un altro: solo ciò che entrambe le build offrono, mai la rete; tutto o niente. |
| [engines/nxnative/NxnativeAdapter/GameSettings/GameSettingValues.swift](../../engines/nxnative/NxnativeAdapter/GameSettings/GameSettingValues.swift) | Modalità multigiocatore dichiarate, impostazioni residue di More settings, etichette e passi dei valori. |
| [engines/nxnative/NxnativeAdapter/GameSettings/SavedChoicesStore.swift](../../engines/nxnative/NxnativeAdapter/GameSettings/SavedChoicesStore.swift) | Legge e scrive le scelte salvate launcher.<env> nel dominio preferenze dell’app gioco. |
| [engines/nxnative/NxnativeAdapter/GameSettings/GameRuntimeConfig.swift](../../engines/nxnative/NxnativeAdapter/GameSettings/GameRuntimeConfig.swift) | Persiste opzioni per titolo con preferenze sostituibili, prepara Review e lingua del rebuild, mappa DM_* e unisce env.txt. |
| [engines/nxnative/NxnativeAdapter/GameSettings/LauncherSettings.swift](../../engines/nxnative/NxnativeAdapter/GameSettings/LauncherSettings.swift) | Legge launcher.json e verifica i controlli supportati, con fallback per le build precedenti. |
| [engines/nxnative/NxnativeAdapter/GameSettings/EnvFileEditor.swift](../../engines/nxnative/NxnativeAdapter/GameSettings/EnvFileEditor.swift) | Cambia una sola variabile di un `env.txt` lasciando intatte le altre righe. |

## Porting · cheat

Cartella `engines/nxnative/NxnativeAdapter/Cheats/`.

| File | Responsabilità |
|---|---|
| [engines/nxnative/NxnativeAdapter/Cheats/CheatFile.swift](../../engines/nxnative/NxnativeAdapter/Cheats/CheatFile.swift) | Decodifica cheats, sezioni, metadati e collegamenti dei codici secondo il parser del motore. |
| [engines/nxnative/NxnativeAdapter/Cheats/CheatInstall.swift](../../engines/nxnative/NxnativeAdapter/Cheats/CheatInstall.swift) | Valuta file e cartelle in ingresso rispetto a title ID, build ID e necessità di conferma. |
| [engines/nxnative/NxnativeAdapter/Cheats/CheatLocator.swift](../../engines/nxnative/NxnativeAdapter/Cheats/CheatLocator.swift) | Risolve build ID, title ID e cartella cheats seguendo i file e l’ambiente del launcher. |
| [engines/nxnative/NxnativeAdapter/Cheats/CheatStatus.swift](../../engines/nxnative/NxnativeAdapter/Cheats/CheatStatus.swift) | Valuta il supporto del motore tramite ancestry (git in un task staccato, risposta tenuta per l'avvio) e prepara stato della riga e indicatore attivo. |
| [engines/nxnative/NxnativeAdapter/Cheats/CheatCopy.swift](../../engines/nxnative/NxnativeAdapter/Cheats/CheatCopy.swift) | Centralizza testi di stato, rifiuto, importazione, sostituzione e rimozione dei cheats. |
| [engines/nxnative/NxnativeAdapter/Cheats/CheatStore.swift](../../engines/nxnative/NxnativeAdapter/Cheats/CheatStore.swift) | Legge e modifica cheat, file enabled, master switch e metadati; sostituisce o ripristina l'intero set. |

## Porting · store Nintendo e copertine

Cartella `engines/nxnative/NxnativeAdapter/Store/`.

| File | Responsabilità |
|---|---|
| [engines/nxnative/NxnativeAdapter/Store/BoxArtService.swift](../../engines/nxnative/NxnativeAdapter/Store/BoxArtService.swift) | Trova copertine Switch in GameTDB e ricorda copertine e ricerche senza risultato. |
| [engines/nxnative/NxnativeAdapter/Store/GameTDB.swift](../../engines/nxnative/NxnativeAdapter/Store/GameTDB.swift) | Decodifica il database GameTDB, abbina nomi e regioni e conserva l’indice locale. |
| [engines/nxnative/NxnativeAdapter/Store/ArtworkCandidates+Porting.swift](../../engines/nxnative/NxnativeAdapter/Store/ArtworkCandidates+Porting.swift) | Le immagini del picker per un gioco Switch: Nintendo Europe, GameTDB per regione, Title DB, poi quelle trovate online. |
| [engines/nxnative/NxnativeAdapter/Store/MetadataOptions.swift](../../engines/nxnative/NxnativeAdapter/Store/MetadataOptions.swift) | I valori di Change metadata per un gioco Switch: store Nintendo, Title DB e GameTDB, senza ripetizioni. |
| [engines/nxnative/NxnativeAdapter/Store/MetadataPicks+Porting.swift](../../engines/nxnative/NxnativeAdapter/Store/MetadataPicks+Porting.swift) | Le scelte del giocatore applicate ai metadati dello store Nintendo. |
| [engines/nxnative/NxnativeAdapter/Store/CriticRatingQuery+Porting.swift](../../engines/nxnative/NxnativeAdapter/Store/CriticRatingQuery+Porting.swift) | La ricerca dei voti per un gioco portato, con la console di Details (Switch o Switch 2). |
| [engines/nxnative/NxnativeAdapter/Store/NintendoEuropeCatalog.swift](../../engines/nxnative/NxnativeAdapter/Store/NintendoEuropeCatalog.swift) | Decodifica il catalogo Nintendo Europe e seleziona il prodotto base per ID e console. |
| [engines/nxnative/NxnativeAdapter/Store/NintendoStoreMetadata.swift](../../engines/nxnative/NxnativeAdapter/Store/NintendoStoreMetadata.swift) | Trasporto, ricerca, ripiego Title DB e cache Nintendo Store originali di Arcane. |
| [engines/nxnative/NxnativeAdapter/Store/SwitchGameMetadataService.swift](../../engines/nxnative/NxnativeAdapter/Store/SwitchGameMetadataService.swift) | Conserva i dati Arcane e riempie i vuoti per campo e lingua con Nintendo Europe, Title DB, LaunchBox e l'indice locale GameTDB. |
| [engines/nxnative/NxnativeAdapter/Store/ScreenshotFallback.swift](../../engines/nxnative/NxnativeAdapter/Store/ScreenshotFallback.swift) | Conserva per 30 giorni gli screenshot LaunchBox dei giochi senza screenshot Title DB e li sovrappone ai metadati. |

## Porting · salvataggi, backup e cloud

Cartella `engines/nxnative/NxnativeAdapter/Saves/`.

| File | Responsabilità |
|---|---|
| [engines/nxnative/NxnativeAdapter/Saves/SaveLocation.swift](../../engines/nxnative/NxnativeAdapter/Saves/SaveLocation.swift) | Percorsi storici e separati per profilo, ambiente di avvio, account/device, utenti aggiuntivi, registro e cloud effettivo. |
| [LinksAwakeningAchievements.swift](../../engines/nxnative/NxnativeAdapter/Saves/LinksAwakeningAchievements.swift) | Legge in sola lettura gli slot confermati, controlla versione e CRC ed estrae i progressi Zelda. |
| [engines/nxnative/NxnativeAdapter/Saves/CloudSaves.swift](../../engines/nxnative/NxnativeAdapter/Saves/CloudSaves.swift) | Descrive scelta cloud, cartelle iCloud o personalizzate e passaggi fra le opzioni. |
| [engines/nxnative/NxnativeAdapter/Saves/CloudSavesPreferences.swift](../../engines/nxnative/NxnativeAdapter/Saves/CloudSavesPreferences.swift) | Prepara la cartella e riapplica la scelta cloud ai domini dei giochi prima di ogni avvio, anche Off. |
| [engines/nxnative/NxnativeAdapter/Saves/RyujinxSaveFolder.swift](../../engines/nxnative/NxnativeAdapter/Saves/RyujinxSaveFolder.swift) | Riconosce contenitori Ryujinx, controlla il title ID e seleziona l’intero albero committed 0. |
| [engines/nxnative/NxnativeAdapter/Saves/SaveSnapshot.swift](../../engines/nxnative/NxnativeAdapter/Saves/SaveSnapshot.swift) | Identità, inventario, manifest schema 1/2 e anteprime; rifiuta dichiarazioni storiche con componenti nuovi. |
| [engines/nxnative/NxnativeAdapter/Saves/SavePresentation.swift](../../engines/nxnative/NxnativeAdapter/Saves/SavePresentation.swift) | Riepiloghi e ambito dei restore storici/multiutente, nomi dei componenti e limite cloud a primario/device. |
| [engines/nxnative/NxnativeAdapter/Saves/SaveFileIO.swift](../../engines/nxnative/NxnativeAdapter/Saves/SaveFileIO.swift) | Copie, hash e xattr portabili; inventario di directory e registro regolare limitato, controlli dei percorsi e scritture durevoli. |
| [engines/nxnative/NxnativeAdapter/Saves/SaveSnapshotStore.swift](../../engines/nxnative/NxnativeAdapter/Saves/SaveSnapshotStore.swift) | Backup completi degli utenti locali e registro, formati storici compatibili, staging e import User/Device. |
| [engines/nxnative/NxnativeAdapter/Saves/SaveRestorePreview.swift](../../engines/nxnative/NxnativeAdapter/Saves/SaveRestorePreview.swift) | Staging e validazione dei pezzi registrati nel backup, compreso il file utenti, con rilevamento dei cambiamenti concorrenti. |
| [engines/nxnative/NxnativeAdapter/Saves/SaveTransaction.swift](../../engines/nxnative/NxnativeAdapter/Saves/SaveTransaction.swift) | Sostituzioni e copia fra profili con backup e journal 1/2; staging di rollback ricreabile dopo una copia parziale. |
| [engines/nxnative/NxnativeAdapter/Saves/SaveOperationGate.swift](../../engines/nxnative/NxnativeAdapter/Saves/SaveOperationGate.swift) | Assegna lease attivi per titolo, blocchi di recupero per percorso e un’esclusione globale per l’updater. |
| [engines/nxnative/NxnativeAdapter/Saves/SaveFailure.swift](../../engines/nxnative/NxnativeAdapter/Saves/SaveFailure.swift) | Errori delle operazioni sui salvataggi; localizza anche l’origine della configurazione cloud prima di inserirla nel messaggio. |
| [engines/nxnative/NxnativeAdapter/Saves/SaveFiles.swift](../../engines/nxnative/NxnativeAdapter/Saves/SaveFiles.swift) | Controlli dei percorsi dei salvataggi con lstat: nessun link sostituito e solo cartelle e file normali. |

## Porting · mod RomFS e GameBanana

Cartelle `engines/nxnative/NxnativeAdapter/Mods/` e `NxnativeAdapter/Mods/GameBanana/`.

| File | Responsabilità |
|---|---|
| [engines/nxnative/NxnativeAdapter/Mods/ModStore.swift](../../engines/nxnative/NxnativeAdapter/Mods/ModStore.swift) | Ordine, overlay, ambiente ExeFS, snapshot, conflitti e Cestino. Rifiuta le scritture con nomi condivisi fra le due radici e tiene spento il gruppo ExeFS noto se la selezione non è risolvibile. |
| [engines/nxnative/NxnativeAdapter/Mods/ModFolderScanner.swift](../../engines/nxnative/NxnativeAdapter/Mods/ModFolderScanner.swift) | Elenca cartelle, archivi e file RomFS; classifica il contenuto come visivo, dati o incerto per il gioco online. |
| [engines/nxnative/NxnativeAdapter/Mods/ModSupport.swift](../../engines/nxnative/NxnativeAdapter/Mods/ModSupport.swift) | Quali file di mod funzionano (solo RomFS), dov'è la loro cartella `romfs`, nomi di cartella sicuri. |
| [engines/nxnative/NxnativeAdapter/Mods/GameBanana/GameBananaAPI.swift](../../engines/nxnative/NxnativeAdapter/Mods/GameBanana/GameBananaAPI.swift) | URL di ricerca e ID dai link, host fidati, risposte GameBanana e testo dalle descrizioni HTML. |
| [engines/nxnative/NxnativeAdapter/Mods/GameBanana/GameBananaClient.swift](../../engines/nxnative/NxnativeAdapter/Mods/GameBanana/GameBananaClient.swift) | Richieste e ricerche GameBanana con User-Agent, limite di 4 alla volta e cache su disco. |
| [engines/nxnative/NxnativeAdapter/Mods/GameBanana/GameBananaImageCache.swift](../../engines/nxnative/NxnativeAdapter/Mods/GameBanana/GameBananaImageCache.swift) | Cache su disco delle immagini delle mod dal CDN di GameBanana. |
| [engines/nxnative/NxnativeAdapter/Mods/GameBanana/GameBananaMatch.swift](../../engines/nxnative/NxnativeAdapter/Mods/GameBanana/GameBananaMatch.swift) | Abbina un gioco alla sua pagina GameBanana per nome e ricorda la scelta. |
| [engines/nxnative/NxnativeAdapter/Mods/GameBanana/AvailableModsFinder.swift](../../engines/nxnative/NxnativeAdapter/Mods/GameBanana/AvailableModsFinder.swift) | Verifica compatibilità da lista, ricerca o link e indica la pagina successiva e gli aggiornamenti. |
| [engines/nxnative/NxnativeAdapter/Mods/GameBanana/ModInstaller.swift](../../engines/nxnative/NxnativeAdapter/Mods/GameBanana/ModInstaller.swift) | Controlla, estrae con `bsdtar` e adotta le radici RomFS ed ExeFS della mod scaricata. |
| [engines/nxnative/NxnativeAdapter/Mods/GameBanana/GameBananaBandModel.swift](../../engines/nxnative/NxnativeAdapter/Mods/GameBanana/GameBananaBandModel.swift) | Stato della fascia Mods: abbinamento, ricerca, paginazione e installazioni. |
| [engines/nxnative/NxnativeAdapter/Mods/GameBanana/ModCatalog.swift](../../engines/nxnative/NxnativeAdapter/Mods/GameBanana/ModCatalog.swift) | Categorie nostre, ordinamenti e sezioni della pagina dello store (altezze fisse). |
| [engines/nxnative/NxnativeAdapter/Mods/GameBanana/ModCatalogSnapshots.swift](../../engines/nxnative/NxnativeAdapter/Mods/GameBanana/ModCatalogSnapshots.swift) | Le mod di ogni gioco salvate su disco, per aprire lo store subito; solo link GameBanana. |
| [engines/nxnative/NxnativeAdapter/Mods/GameBanana/ModStoreModel.swift](../../engines/nxnative/NxnativeAdapter/Mods/GameBanana/ModStoreModel.swift) | Dati dello store: apre dalle copie su disco, aggiorna in background due giochi alla volta, abbina solo se sicuro. |
| [engines/nxnative/NxnativeAdapter/Mods/GameBanana/ModStoreFocus.swift](../../engines/nxnative/NxnativeAdapter/Mods/GameBanana/ModStoreFocus.swift) | Focus nella pagina dello store, ancorato al tipo di sezione; ogni sezione ricorda la sua tessera. |
| [engines/nxnative/NxnativeAdapter/Mods/GameBanana/GameBananaFindModel.swift](../../engines/nxnative/NxnativeAdapter/Mods/GameBanana/GameBananaFindModel.swift) | Stato della ricerca per nome: campo, risultati, None of these. |
| [engines/nxnative/NxnativeAdapter/Mods/GameBanana/ModDownload.swift](../../engines/nxnative/NxnativeAdapter/Mods/GameBanana/ModDownload.swift) | Scarica un file di GameBanana con avanzamento e Cancel, solo da host fidati. |

## UI · Add Game e porting

| File | Responsabilità |
|---|---|
| [apps/mac/OortMac/Views/AddGame/AddGameView.swift](../../apps/mac/OortMac/Views/AddGame/AddGameView.swift) | Compone il wizard Choose/Review/Porting, gestisce il rilascio di file e i blocchi cloud; alla chiusura non sovrascrive una selezione Spotlight in attesa. |
| [apps/mac/OortMac/Views/AddGame/AddGameView+Rows.swift](../../apps/mac/OortMac/Views/AddGame/AddGameView+Rows.swift) | Righe e focus del wizard, spiegazione del blocco dell'adozione locale e stato della verifica della cache di compilazione cloud. |
| [apps/mac/OortMac/Views/AddGame/AddGameRows.swift](../../apps/mac/OortMac/Views/AddGame/AddGameRows.swift) | Rende le righe riutilizzabili per sorgenti e azioni di Add Game. |
| [apps/mac/OortMac/Views/AddGame/AddGameAction.swift](../../apps/mac/OortMac/Views/AddGame/AddGameAction.swift) | Identifica le azioni navigabili dei passaggi del wizard. |
| [apps/mac/OortMac/Views/AddGame/AddGameStepThreeView.swift](../../apps/mac/OortMac/Views/AddGame/AddGameStepThreeView.swift) | Mostra progresso, log, annullamento durante la compilazione, fase di installazione ed esito con Retry. |
| [apps/mac/OortMac/Views/Porting/GameInboxView.swift](../../apps/mac/OortMac/Views/Porting/GameInboxView.swift) | Pagina Selene con rilascio file, destinazione nel carattere del corpo, motivo del blocco o azioni singole o in gruppo. |
| [apps/mac/OortMac/Views/Porting/GameInboxView+Input.swift](../../apps/mac/OortMac/Views/Porting/GameInboxView+Input.swift) | Traduce tastiera e controller in focus e azioni dell'Inbox. |

## UI · Spotlight

| File | Responsabilità |
|---|---|
| [apps/mac/OortMac/Views/Spotlight/SpotlightView.swift](../../apps/mac/OortMac/Views/Spotlight/SpotlightView.swift) | Compone home, tessere e pagina; espone la card Inbox solo se attiva, osserva il cloud, collega Profili alla shell e libera il focus di ordinamento all’uscita. |
| [apps/mac/OortMac/Views/Spotlight/SpotlightView+Stage.swift](../../apps/mac/OortMac/Views/Spotlight/SpotlightView+Stage.swift) | Palco Spotlight: riga, testate per fonte, azioni cloud, arte hero, overlay, focus di ordinamento e ultime cinque compilazioni. |
| [apps/mac/OortMac/Views/Spotlight/SpotlightView+Hints.swift](../../apps/mac/OortMac/Views/Spotlight/SpotlightView+Hints.swift) | Suggerimenti per il focus, incluse le azioni dei collegamenti Mac, Download e X per la cronologia delle compilazioni. |
| [apps/mac/OortMac/Views/Spotlight/SpotlightView+Platforms.swift](../../apps/mac/OortMac/Views/Spotlight/SpotlightView+Platforms.swift) | Input, attesa prima di montare le nuove copertine, filtro del profilo e accesso a un gioco fuori filtro. |
| [apps/mac/OortMac/Views/Spotlight/SpotlightView+Selection.swift](../../apps/mac/OortMac/Views/Spotlight/SpotlightView+Selection.swift) | Selezione, filtri e libreria; entrando nella pagina si lascia il focus della testata. |
| [apps/mac/OortMac/Views/Spotlight/SpotlightView+Mods.swift](../../apps/mac/OortMac/Views/Spotlight/SpotlightView+Mods.swift) | Fascia Mods e store delle mod che si apre da lì. |
| [apps/mac/OortMac/Views/Spotlight/SpotlightView+PageLayout.swift](../../apps/mac/OortMac/Views/Spotlight/SpotlightView+PageLayout.swift) | Offset e maschera della pagina, riga Mods a fuoco sempre visibile e cosa mostra About. |
| [apps/mac/OortMac/Views/Spotlight/SpotlightView+PageContent.swift](../../apps/mac/OortMac/Views/Spotlight/SpotlightView+PageContent.swift) | Cosa contiene la pagina per un gioco Switch o Steam: About, Details, screenshot e giochi correlati. |
| [apps/mac/OortMac/Views/Spotlight/SpotlightView+Input.swift](../../apps/mac/OortMac/Views/Spotlight/SpotlightView+Input.swift) | Traduce input, card, azioni cloud, screenshot e ordinamento. X sulla carta Attività cambia la visibilità delle compilazioni. Le frecce orizzontali nella riga usano solo le tessere. |
| [apps/mac/OortMac/Views/Spotlight/SpotlightView+Entrance.swift](../../apps/mac/OortMac/Views/Spotlight/SpotlightView+Entrance.swift) | Coordina l’entrata su moonlight condiviso: coperture e fullscreen, pausa, attesa dell’arte, effetti di volo e dissolvenza, barra in alto e hint per ultimi, atterraggio di sicurezza; nessun input salta l’entrata. |
| [apps/mac/OortMac/Views/Spotlight/SpotlightRowView.swift](../../apps/mac/OortMac/Views/Spotlight/SpotlightRowView.swift) | Disegna la riga, il focus e i cue Cloud; mostra le facce scorrevoli della piattaforma e quella della carta Mods (`ModsCardCover`). |
| [apps/mac/OortMac/Views/Spotlight/SpotlightTopBar.swift](../../apps/mac/OortMac/Views/Spotlight/SpotlightTopBar.swift) | Disegna Integrations a sinistra, filtri al centro, ritratto e orologio a destra; il menu di ordinamento parte dal prompt in fondo. |
| [apps/mac/OortMac/Views/Spotlight/SpotlightInfoView.swift](../../apps/mac/OortMac/Views/Spotlight/SpotlightInfoView.swift) | Mostra logo, Play o Download con fase e byte, Cloud, statistiche e stato di porting. |
| [apps/mac/OortMac/Views/Spotlight/SpotlightCardInfoView.swift](../../apps/mac/OortMac/Views/Spotlight/SpotlightCardInfoView.swift) | Mostra informazioni e azioni delle card Spotlight, incluse Inbox e le tessere quadrate con date di compilazione su Attività. |
| [apps/mac/OortMac/Views/Spotlight/SpotlightPageSections.swift](../../apps/mac/OortMac/Views/Spotlight/SpotlightPageSections.swift) | Modello della pagina inferiore con dettagli, link e giochi correlati del catalogo; generi e descrizione; la descrizione può venire da Wikipedia (`WikipediaAbout`). |
| [apps/mac/OortMac/Views/Spotlight/SpotlightScreenshotStrip.swift](../../apps/mac/OortMac/Views/Spotlight/SpotlightScreenshotStrip.swift) | Disegna la striscia di screenshot con focus e stile adattabile alle schermate. |
| [apps/mac/OortMac/Views/Spotlight/SeleneArtBackground.swift](../../apps/mac/OortMac/Views/Spotlight/SeleneArtBackground.swift) | Compone wallpaper, sfondo del gioco, transizioni e maschere leggendo la palette dallo snapshot condiviso; l'arte è un `CALayer` che dissolve nel render server (`SeleneArtLayer`) e che l'entrata di Spotlight tiene nascosto (`ArtReveal`). |
| [apps/mac/OortMac/Views/Spotlight/SeleneHeroArt.swift](../../apps/mac/OortMac/Views/Spotlight/SeleneHeroArt.swift) | Coordina il caricamento differito di hero e logo del gioco selezionato; aggiorna l'hero quando arriva l'URL del catalogo. |
| [apps/mac/OortMac/Views/Spotlight/GameArtLoader.swift](../../apps/mac/OortMac/Views/Spotlight/GameArtLoader.swift) | Carica hero e loghi, con le scelte personali prima del catalogo e il vecchio hero disponibile offline. Limita le cache degli sfondi anche per byte decodificato. |
| [apps/mac/OortMac/Views/Spotlight/GameArtLoader+Played.swift](../../apps/mac/OortMac/Views/Spotlight/GameArtLoader+Played.swift) | Hero e logo di un `PlayedGame` per schermata di lancio e card di fine sessione; per Steam le stesse scelte delle sue pagine. |

## UI · Collection e Details

| File | Responsabilità |
|---|---|
| [apps/mac/OortMac/Views/Collection/CollectionView.swift](../../apps/mac/OortMac/Views/Collection/CollectionView.swift) | Compone copertine e filtro Cloud; distingue configurazione, ricerca, controllo incompleto e inventario verificato senza giochi. |
| [apps/mac/OortMac/Views/Collection/CollectionView+Input.swift](../../apps/mac/OortMac/Views/Collection/CollectionView+Input.swift) | Muove il focus nella barra, nell’elenco o tra le azioni della Collection vuota; inoltra Play, Download e opzioni per fonte, e apre l’ordinamento nella Collection principale. |
| [apps/mac/OortMac/Views/Collection/CollectionCoverRow.swift](../../apps/mac/OortMac/Views/Collection/CollectionCoverRow.swift) | Disegna copertine e scorrimento della riga Collection, con cue Cloud sopra l'arte. |
| [apps/mac/OortMac/Views/Detail/GameDetailView.swift](../../apps/mac/OortMac/Views/Detail/GameDetailView.swift) | Compone Details; coordina focus e suggerimenti e non propone Select per un download passivo. |
| [apps/mac/OortMac/Views/Detail/GameDetailView+Input.swift](../../apps/mac/OortMac/Views/Detail/GameDetailView+Input.swift) | Gestisce azioni, Download, screenshot, navigazione e passaggio ai giochi correlati da Details. |
| [apps/mac/OortMac/Views/Detail/DetailsBackground.swift](../../apps/mac/OortMac/Views/Detail/DetailsBackground.swift) | Compone hero e maschere dello sfondo dedicato alla pagina Details. |
| [apps/mac/OortMac/Views/Detail/DetailsTopBlock.swift](../../apps/mac/OortMac/Views/Detail/DetailsTopBlock.swift) | Mostra logo, prossima azione, luogo dei contenuti, stato o misura non duplicati, statistiche, generi e descrizione. |
| [apps/mac/OortMac/Views/Detail/DetailsBands.swift](../../apps/mac/OortMac/Views/Detail/DetailsBands.swift) | Disegna screenshot, mod e fascia correlati condivisa, con copertine Switch o Steam secondo la fonte. |
| [apps/mac/OortMac/Views/Detail/DetailsPanel.swift](../../apps/mac/OortMac/Views/Detail/DetailsPanel.swift) | Pannello Details uguale per ogni fonte: righe con icona, voto della critica in ultima riga e link in `SeleneActionGrid`; carica solo il voto del gioco mostrato. |
| [apps/mac/OortMac/Views/Detail/CloudLibraryPanel.swift](../../apps/mac/OortMac/Views/Detail/CloudLibraryPanel.swift) | Cloud library: copie, azioni per artefatto, Pause/Resume e app precedente; somma la selezione locale da liberare e distingue verifica e avanzamento. |
| [CloudPersonalAppUpdateRow.swift](../../apps/mac/OortMac/Views/Detail/CloudPersonalAppUpdateRow.swift) | Mostra aggiornamento personale e quantità da scaricare, oppure copie diverse senza invito alla sostituzione. |
| [apps/mac/OortMac/Views/Detail/CriticRatingValue.swift](../../apps/mac/OortMac/Views/Detail/CriticRatingValue.swift) | Valore della riga Critic score: cinque stelle, numero /100 e fonte, senza finestre aggiuntive; caricamento e assenza espliciti. |
| [apps/mac/OortMac/ViewModels/IGDBSettings.swift](../../apps/mac/OortMac/ViewModels/IGDBSettings.swift) | Configurazione IGDB facoltativa: verifica prima del salvataggio, rimozione e invalidazione delle richieste/voti precedenti. |
| [apps/mac/OortMac/Views/Components/IGDBCredentialsDialog.swift](../../apps/mac/OortMac/Views/Components/IGDBCredentialsDialog.swift) | Guida sintetica in cinque passi, Client ID, Client Secret nascosto, verifica/salvataggio e annullamento; input Settings sospeso. |
| [apps/mac/OortMac/Views/Settings/SettingsAPISection.swift](../../apps/mac/OortMac/Views/Settings/SettingsAPISection.swift) | Online services, Play together e Nextendo; mostra i messaggi di accesso sotto la riga del conto, conferma le scelte della rete e conserva i titoli risolti per gli amici. Da Integrations attende Check status o Sign in. |
| [apps/mac/OortMac/Views/Settings/SettingsCloudLibrarySection.swift](../../apps/mac/OortMac/Views/Settings/SettingsCloudLibrarySection.swift) | Cloud library: account, biblioteche nel cloud e scelte di questo Mac sempre visibili; rclone, test e biblioteca seguita in Avanzate. Da Integrations ispeziona rclone solo in Avanzate. |
| [apps/mac/OortMac/Views/Settings/CloudSetupAssistant.swift](../../apps/mac/OortMac/Views/Settings/CloudSetupAssistant.swift) | Stato, barra d’azioni e domande dell’assistente cloud in tre passi; il lavoro attivo governa l’attesa della verifica. |
| [apps/mac/OortMac/Views/Settings/CloudSetupAssistant+Input.swift](../../apps/mac/OortMac/Views/Settings/CloudSetupAssistant+Input.swift) | Focus, tastiera, controller e azioni dell’assistente: verifica, attivazione, spostamento. |
| [apps/mac/OortMac/Views/Settings/CloudSetupAssistant+Account.swift](../../apps/mac/OortMac/Views/Settings/CloudSetupAssistant+Account.swift) | Passo 1: tenere l’account, incollare un client Google o crearlo in cinque passi. |
| [apps/mac/OortMac/Views/Settings/CloudSetupAssistant+Folders.swift](../../apps/mac/OortMac/Views/Settings/CloudSetupAssistant+Folders.swift) | Passo 2: una domanda per cartella, creazione dopo conferma e verifica della vecchia cartella legata al ticket e all’ambito Drive. |
| [apps/mac/OortMac/Views/Settings/CloudSetupAssistant+Browser.swift](../../apps/mac/OortMac/Views/Settings/CloudSetupAssistant+Browser.swift) | Selettore Drive: percorso, recenti, cosa contiene ogni cartella; riprende la verifica interrotta al ritorno. |
| [apps/mac/OortMac/Views/Settings/CloudSetupAssistant+Ready.swift](../../apps/mac/OortMac/Views/Settings/CloudSetupAssistant+Ready.swift) | Passo 3: riepilogo e verifica. |
| [apps/mac/OortMac/ViewModels/CloudLibraryModel+KeptFolders.swift](../../apps/mac/OortMac/ViewModels/CloudLibraryModel+KeptFolders.swift) | Ricorda le cartelle prima di lasciare una connessione. |
| [apps/mac/OortMac/ViewModels/CloudRecentFolders.swift](../../apps/mac/OortMac/ViewModels/CloudRecentFolders.swift) | Cartelle Drive scelte di recente per connessione. |
| [apps/mac/OortMac/Views/Settings/SettingsCloudLibrarySection.swift](../../apps/mac/OortMac/Views/Settings/SettingsCloudLibrarySection.swift) | Cloud library: verifica, recupero e configurazione; la scelta esplicita di rclone conserva il collegamento stabile. |
| [apps/mac/OortMac/Views/Settings/CloudSetupAssistant.swift](../../apps/mac/OortMac/Views/Settings/CloudSetupAssistant.swift) | Spiega il diritto Google, sceglie le cartelle, mostra blocchi e indica Collection → Cloud dopo l’attivazione; uno spostamento pendente si riprende da Attività. |
| [apps/mac/OortMac/Views/Settings/CloudSetupAssistant+Input.swift](../../apps/mac/OortMac/Views/Settings/CloudSetupAssistant+Input.swift) | Traduce tastiera e controller in azioni sul bersaglio corrente, lasciando precedenza al menu e alla conferma di uscita. |
| [apps/mac/OortMac/Views/Settings/CloudReferenceDialog.swift](../../apps/mac/OortMac/Views/Settings/CloudReferenceDialog.swift) | Editor del link o ID Drive: spiega sola lettura e assenza di condivisione reciproca; un ID non valido lascia il focus su Cancel. |
| [apps/mac/OortMac/Views/Settings/NextendoClientDialog.swift](../../apps/mac/OortMac/Views/Settings/NextendoClientDialog.swift) | Dialogo Selene per scegliere e validare l’ID client pubblico o riprendere il default della build. |

## UI · Game Options, cheats e salvataggi

| File | Responsabilità |
|---|---|
| [apps/mac/OortMac/Views/GameOptions/GameOptionsView.swift](../../apps/mac/OortMac/Views/GameOptions/GameOptionsView.swift) | Opzioni del gioco, Edit details e pannelli; aggiorna capacità dello schermo, adattatori e rischio RomFS. |
| [PlayersScreen.swift](../../apps/mac/OortMac/Views/Players/PlayersScreen.swift) | Otto posti, modalità, profili in linea e dialoghi, composti con le viste Selene. |
| [PlayersScreenModel.swift](../../apps/mac/OortMac/Views/Players/PlayersScreenModel.swift) | Risoluzione dei controller, arrivo, spostamento, aggiornamento del piano, sessione e PIN. |
| [PlayersScreen+Input.swift](../../apps/mac/OortMac/Views/Players/PlayersScreen+Input.swift) | Focus nella griglia, comandi diretti del posto, tastiera e controller nello strato attivo. |
| [PlayersScreenHost.swift](../../apps/mac/OortMac/Views/Players/PlayersScreenHost.swift) | Collega la pagina alle notifiche del genitore, alla cattura delle pressioni, al registro e alla diagnostica. |
| [apps/mac/OortMac/Views/GameOptions/GameOptionsView+Rows.swift](../../apps/mac/OortMac/Views/GameOptions/GameOptionsView+Rows.swift) | Colonna, ciclo Play together con icona a due persone, frecce quando modificabili, percorso di rete, accessibilità e barra Rebuild. |
| [apps/mac/OortMac/Views/GameOptions/GameOptionsView+Confirmation.swift](../../apps/mac/OortMac/Views/GameOptions/GameOptionsView+Confirmation.swift) | Conferma: overlay, testi, richiesta, annullamento ed esecuzione dell’azione confermata. |
| [apps/mac/OortMac/Views/GameOptions/GameOptionsView+Focus.swift](../../apps/mac/OortMac/Views/GameOptions/GameOptionsView+Focus.swift) | Focus: impostazione, spostamento, ingresso e uscita da Edit details. |
| [apps/mac/OortMac/Views/GameOptions/GameOptionsView+Input.swift](../../apps/mac/OortMac/Views/GameOptions/GameOptionsView+Input.swift) | Tastiera, rotella e controller: navigazione, attivazione, indietro o annullamento della verifica Rebuild. |
| [apps/mac/OortMac/Views/GameOptions/GameOptionsView+Actions.swift](../../apps/mac/OortMac/Views/GameOptions/GameOptionsView+Actions.swift) | Azioni delle righe, incluso il ciclo multigiocatore e schermo con focus, la disattivazione RomFS e Rebuild. |
| [apps/mac/OortMac/Views/GameOptions/ChangeArtworkView.swift](../../apps/mac/OortMac/Views/GameOptions/ChangeArtworkView.swift) | Seleziona artwork per titolo da rete o file e indica dove viene usato, con stato ad altezza stabile. Il file tiene stato, geometria, `body`, schede, ricerca, stato e griglia; il resto sta nelle estensioni qui sotto. |
| [apps/mac/OortMac/Views/GameOptions/ChangeArtworkView+Tiles.swift](../../apps/mac/OortMac/Views/GameOptions/ChangeArtworkView+Tiles.swift) | Tile della griglia: anteprima, didascalia e segno dell’artwork in uso. |
| [apps/mac/OortMac/Views/GameOptions/ChangeArtworkView+Loading.swift](../../apps/mac/OortMac/Views/GameOptions/ChangeArtworkView+Loading.swift) | Caricamento: candidati e anteprime della scheda, risultati di una fonte, scelta del giocatore e icona automatica. |
| [apps/mac/OortMac/Views/GameOptions/ChangeArtworkView+Choosing.swift](../../apps/mac/OortMac/Views/GameOptions/ChangeArtworkView+Choosing.swift) | Scelta di una tile o immagine; selettore manuale di file condiviso con i collegamenti Mac. |
| [apps/mac/OortMac/Views/GameOptions/ChangeArtworkView+Browse.swift](../../apps/mac/OortMac/Views/GameOptions/ChangeArtworkView+Browse.swift) | Sfoglia una fonte: apertura, ricerca, chiusura e pagina della fonte. |
| [apps/mac/OortMac/Views/GameOptions/ChangeArtworkView+Input.swift](../../apps/mac/OortMac/Views/GameOptions/ChangeArtworkView+Input.swift) | Input: schede, focus, indietro e chiusura, scelta, controller e monitor dei tasti. |
| [apps/mac/OortMac/Views/GameOptions/ChangeMetadataView.swift](../../apps/mac/OortMac/Views/GameOptions/ChangeMetadataView.swift) | Offre alternative per campo da store, Title DB, GameTDB e IGDB, oppure testo personale; anteprima, scelta, annullamento e retry con lo stesso input. |
| [apps/mac/OortMac/Views/GameOptions/CheatsPanel.swift](../../apps/mac/OortMac/Views/GameOptions/CheatsPanel.swift) | Presenta file, master switch, codici, importazione, rimozione e stato di scrittura dei cheats. |
| [apps/mac/OortMac/Views/GameOptions/ModsPanel.swift](../../apps/mac/OortMac/Views/GameOptions/ModsPanel.swift) | Righe File mods e Code mods, avvisi Online, focus, importazione ExeFS, Rebuild, interruttori, conflitti, ordine e Cestino. |
| [apps/mac/OortMac/Views/Detail/ModDetailPanel.swift](../../apps/mac/OortMac/Views/Detail/ModDetailPanel.swift) | Dettaglio di una mod GameBanana: immagini, autore, versione, descrizione, Install/Update e link. |
| [apps/mac/OortMac/Views/Detail/GameBananaFindPanel.swift](../../apps/mac/OortMac/Views/Detail/GameBananaFindPanel.swift) | Pannelli per trovare il gioco e cercare le sue mod, con lo stesso campo GameBanana. |
| [apps/mac/OortMac/ViewModels/ModStoreHost.swift](../../apps/mac/OortMac/ViewModels/ModStoreHost.swift) | Store della card Mods: mantiene la cover fra schermate, rivalida abbinamenti e snapshot; rilegge i badge a ogni apertura e scarta i risultati di generazioni precedenti. |
| [apps/mac/OortMac/Views/Store/ModStorePage.swift](../../apps/mac/OortMac/Views/Store/ModStorePage.swift) | Pagina dello store: barra di ordinamento, banner Featured, righe di tessere; disegna solo le sezioni vicine al focus. |
| [apps/mac/OortMac/Views/Store/GameBananaBlur.swift](../../apps/mac/OortMac/Views/Store/GameBananaBlur.swift) | Arte di una mod rimpicciolita e sfocata una volta, fuori dal main thread, e tenuta in memoria: sfondo del Featured. |
| [apps/mac/OortMac/ViewModels/ModsBandHost.swift](../../apps/mac/OortMac/ViewModels/ModsBandHost.swift) | Fascia Mods condivisa da Spotlight e Details. Legge mod installate, coordina GameBanana e pannelli, svuota i dati del gioco precedente sulla riga Spotlight. |
| [apps/mac/OortMac/ViewModels/GameBananaServices.swift](../../apps/mac/OortMac/ViewModels/GameBananaServices.swift) | Client, cache delle immagini e abbinamenti GameBanana condivisi da tutta l'app. |
| [apps/mac/OortMac/Views/GameOptions/SavesPanel.swift](../../apps/mac/OortMac/Views/GameOptions/SavesPanel.swift) | Azioni, anteprime ed esiti dei salvataggi; la scelta del profilo parte da Annulla a destra e mostra il suo aiuto. |
| [apps/mac/OortMac/Views/GameOptions/GameSettingsScreen.swift](../../apps/mac/OortMac/Views/GameOptions/GameSettingsScreen.swift) | Pagina completa raggiunta da All settings per Switch e Steam; barra, focus, input e ritorno al pannello rapido. |
| [apps/mac/OortMac/Views/GameOptions/GameOptionsView+FullSettings.swift](../../apps/mac/OortMac/Views/GameOptions/GameOptionsView+FullSettings.swift) | Traduce i gruppi del catalogo e le azioni esistenti del gioco Switch in righe; riusa Mods, Cheats e Saves. |
| [apps/mac/OortMac/Views/GameOptions/MoreSettingsPanel.swift](../../apps/mac/OortMac/Views/GameOptions/MoreSettingsPanel.swift) | Mostra le impostazioni del launcher.json senza riga dedicata: interruttori, scelte e intervalli; le righe fissate da env.txt restano attenuate. |
| [apps/mac/OortMac/Views/GameOptions/CopySettingsPanel.swift](../../apps/mac/OortMac/Views/GameOptions/CopySettingsPanel.swift) | Gli altri giochi a cui copiare le impostazioni; A mostra il piano completo. Un piano cambiato richiede una nuova conferma. |
| [apps/mac/OortMac/Views/GameOptions/SaveImportDetails.swift](../../apps/mac/OortMac/Views/GameOptions/SaveImportDetails.swift) | Disegna percorsi From/To centrati, riquadri leggeri e freccia con riflesso direzionale. |

## UI · Settings

| File | Responsabilità |
|---|---|
| [apps/mac/OortMac/Views/Settings/SettingsView.swift](../../apps/mac/OortMac/Views/Settings/SettingsView.swift) | Coordina sezioni, bozza e dialoghi; comunica al router quando un sottopannello possiede l’input. |
| [apps/mac/OortMac/Views/OortUI/ControllerShape.swift](../../apps/mac/OortMac/Views/OortUI/ControllerShape.swift) | Sagoma e posti dei tasti di ogni tipo di controller. |
| [apps/mac/OortMac/Views/OortUI/OortSettingsShell.swift](../../apps/mac/OortMac/Views/OortUI/OortSettingsShell.swift) | Layout riusabile: barra, titolo, pila di pagine, ritorno, collegamenti e campo di ricerca. |
| [apps/mac/OortMac/Views/OortUI/OortAssistantPanel.swift](../../apps/mac/OortMac/Views/OortUI/OortAssistantPanel.swift) | Pannello a passi e scheda di una cartella. |
| [apps/mac/OortMac/Views/OortUI/OortActionBar.swift](../../apps/mac/OortMac/Views/OortUI/OortActionBar.swift) | Piede di pannelli e domande: ritorno a sinistra, azione principale a destra. |
| [apps/mac/OortMac/Views/Settings/SettingsDraftFields.swift](../../apps/mac/OortMac/Views/Settings/SettingsDraftFields.swift) | Elenca le chiavi di Settings, distingue anteprima e applicazione differita e descrive i cambi in ordine di importanza. |
| [apps/mac/OortMac/Views/Settings/SettingsSidebar.swift](../../apps/mac/OortMac/Views/Settings/SettingsSidebar.swift) | Associa le pagine alle rubriche, al campo di ricerca e ai filtri; mantiene i collegamenti diretti alle sezioni. |
| [apps/mac/OortMac/Views/Settings/SettingsSectionContent.swift](../../apps/mac/OortMac/Views/Settings/SettingsSectionContent.swift) | Instrada le sezioni, distingue Play together da Online services, passa gli ingressi cloud e mostra le azioni del blocco profilo. Usa un trattino se manca il commit del motore. |
| [apps/mac/OortMac/Views/Settings/SettingsSearchSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsSearchSection.swift) | Presenta risultati e valori modificati filtrati dal campo nella barra; ciascun risultato apre la riga nella sua pagina. |
| [apps/mac/OortMac/Views/Settings/SettingsStartUpSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsStartUpSection.swift) | Espone il profilo all’avvio, schermata iniziale, animazione e aggiornamenti; `SettingsProfileCardsSection` ordina e attiva le schede del profilo. |
| [apps/mac/OortMac/Views/Settings/SettingsProfileIdentitySection.swift](../../apps/mac/OortMac/Views/Settings/SettingsProfileIdentitySection.swift) | Identità del profilo attivo: nome, illustrazione e immagine personale. |
| [apps/mac/OortMac/Views/Settings/SettingsNavigationSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsNavigationSection.swift) | Espone le preferenze di navigazione e dei suggerimenti dei tasti. |
| [apps/mac/OortMac/Views/Settings/SettingsSpotlightSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsSpotlightSection.swift) | Espone card, ordine e preferenze della home Spotlight. |
| [apps/mac/OortMac/Views/Settings/SettingsSoundSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsSoundSection.swift) | Espone volume, scelta e anteprima sonora; mostra la licenza prima di importare e rimuove solo la copia; mantiene l’import Selene storico. |
| [apps/mac/OortMac/Views/Settings/SettingsLookSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsLookSection.swift) | Separa palette, sfondi e adattamento del profilo da luminosità, movimento e icona di Look. |
| [apps/mac/OortMac/Views/Settings/SettingsGamesSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsGamesSection.swift) | Porting → New games: default dei nuovi giochi, vibrazione e schermo globale applicato al Play. |
| [apps/mac/OortMac/Views/Settings/SettingsLibraryGamesSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsLibraryGamesSection.swift) | Library → Games: schermata di lancio, Surprise me, card della sessione e app di gioco portate nascoste. |
| [apps/mac/OortMac/Views/Settings/SettingsCloudSavesSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsCloudSavesSection.swift) | Porting → Cloud saves: scelta e cartella; chiarisce che sincronizzano solo primario e device. |
| [apps/mac/OortMac/Views/Settings/SettingsControllersSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsControllersSection.swift) | Espone disposizione del profilo, riepilogo dei tasti, sostituzioni Home di macOS, zona morta, Players e tre scelte per Home in gioco. |
| [apps/mac/OortMac/Views/Settings/SettingsLibrarySection.swift](../../apps/mac/OortMac/Views/Settings/SettingsLibrarySection.swift) | Porting → Game folders: cartelle, interruttore Inbox, scansione e notifiche dei porting. |
| [apps/mac/OortMac/Views/Settings/SettingsStorageSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsStorageSection.swift) | Library → Storage: spazio occupato, log, cache di metadati e artwork, cartella comune dei backup verificati. |
| [apps/mac/OortMac/Views/Settings/SettingsPortingStorageSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsPortingStorageSection.swift) | Porting → Porting storage: dimensioni e conferma per spostare nel Cestino la cache di uno o di tutti i giochi. |
| [apps/mac/OortMac/Views/Settings/SettingsConsoleSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsConsoleSection.swift) | System → Console: apre la console dei log di build e avvio. |
| [apps/mac/OortMac/Views/Settings/SettingsEngineSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsEngineSection.swift) | Porting → Setup and engine: checkout, pin, gate, conferme per cambio motore e override, runtime, changelog upstream e Setup; l'arrivo da Integrations non avvia controlli né importa chiavi. |
| [apps/mac/OortMac/Views/Settings/SettingsKeysSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsKeysSection.swift) | Porting → Keys: stato, importazione, sostituzione e rilevamento di prod.keys. |
| [apps/mac/OortMac/Views/Settings/SettingsAboutSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsAboutSection.swift) | Mostra versione, aggiornamenti, guida online, diagnostica, sostegno volontario e i crediti di `design/credits.json` in schede comuni. I due titoli dei crediti usano lo scrim nelle palette chiare. |
| [apps/mac/OortMac/Views/Settings/SettingsAboutSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsAboutSection.swift) | Mostra versione, aggiornamenti, guida online, diagnostica, collegamenti distinti al sostegno di Bium23 e al finanziamento di Oort NX, e crediti di `design/credits.json`. |
| [apps/mac/OortMac/Views/Settings/LocalePicker.swift](../../apps/mac/OortMac/Views/Settings/LocalePicker.swift) | Scelta diretta della lingua e ricerca dei formati regionali, con focus tastiera/controller e codici stabili. |

## UI · Setup, avvio, ricerca e console

| File | Responsabilità |
|---|---|
| [apps/mac/OortMac/Views/Setup/SetupCheckView.swift](../../apps/mac/OortMac/Views/Setup/SetupCheckView.swift) | Schede dei requisiti, errore chiavi, progressi e conferme distinte per Metal e motore; continua senza installare. |
| [apps/mac/OortMac/Views/Setup/OnboardingView.swift](../../apps/mac/OortMac/Views/Setup/OnboardingView.swift) | Pagine e input del tour locale, inventario, importazione selettiva e rinvii ai servizi e alla modifica profilo. |
| [apps/mac/OortMac/Views/Setup/OnboardingScreen.swift](../../apps/mac/OortMac/Views/Setup/OnboardingScreen.swift) | Composizione Selene del tour, novità della 0.4.0 e conferma della copia locale. |
| [apps/mac/OortMac/Views/Setup/SetupCheckView+Input.swift](../../apps/mac/OortMac/Views/Setup/SetupCheckView+Input.swift) | Gestisce focus iniziale, navigazione della griglia, attivazione delle schede Setup e B verso `found` durante il primo avvio. |
| [apps/mac/OortMac/Views/Setup/ArcaneWelcomeView.swift](../../apps/mac/OortMac/Views/Setup/ArcaneWelcomeView.swift) | Disegna il benvenuto in Arcane: nome nuovo, novità, offerta Steam dalla cartella scelta, Add / Not now e Open library. |
| [apps/mac/OortMac/Views/Setup/ArcaneWelcomeView+Input.swift](../../apps/mac/OortMac/Views/Setup/ArcaneWelcomeView+Input.swift) | Gestisce focus, mouse, tastiera e controller del benvenuto. |
| [apps/mac/OortMac/Views/Setup/FoundGamesSetupView.swift](../../apps/mac/OortMac/Views/Setup/FoundGamesSetupView.swift) | Prima pagina del Setup: Steam con scelta salvata o attivazione esistente, Retry, app portate e card Porting; condivide il solo disegno con la fixture. |
| [apps/mac/OortMac/Views/Setup/FoundGamesSetupView+Input.swift](../../apps/mac/OortMac/Views/Setup/FoundGamesSetupView+Input.swift) | Focus, mouse, tastiera e controller di found; Retry della lettura Steam e uscita che annulla la richiesta prima di aprire la libreria. |
| [apps/mac/OortMac/Views/Setup/YourGamesSetupView.swift](../../apps/mac/OortMac/Views/Setup/YourGamesSetupView.swift) | Disegna scelta cartella, primo gioco, apertura libreria e Skip; contiene l'indicatore localizzato dei passi e `SetupCardRow`, la riga condivisa con `found`. |
| [apps/mac/OortMac/Views/Launch/LaunchScreenView.swift](../../apps/mac/OortMac/Views/Launch/LaunchScreenView.swift) | Mostra artwork e logo per nxnative e Steam. Il pulsante per chiudere la schermata inattiva resta visibile con i suggerimenti spenti. |
| [apps/mac/OortMac/Views/Launch/LaunchMotion.swift](../../apps/mac/OortMac/Views/Launch/LaunchMotion.swift) | Movimento della schermata di lancio in Core Animation: artwork che si avvicina e logo del gioco che sale una volta. Con Riduci movimento resta la dissolvenza del logo. |
| [apps/mac/OortMac/Views/Launch/LaunchCoverWindow.swift](../../apps/mac/OortMac/Views/Launch/LaunchCoverWindow.swift) | Ordina la finestra d’attesa sopra ogni app e Space e avvisa il coordinatore dopo aver inviato il pannello al server delle finestre. |
| [apps/mac/OortMac/Views/Search/FindGameView.swift](../../apps/mac/OortMac/Views/Search/FindGameView.swift) | Presenta ricerca nella libreria e risultati navigabili e inoltra il gioco scelto alla home. |
| [CommandPaletteView.swift](../../apps/mac/OortMac/Views/Search/CommandPaletteView.swift) | Cerca ovunque: campo, gruppi, righe con scorciatoia, annunci VoiceOver e ritorno del focus. |
| [CommandPaletteProbe.swift](../../apps/mac/OortMac/Views/Search/CommandPaletteProbe.swift) | Tasti, pulsanti, aggiornamenti del focus e catture Debug con voci sintetiche. |
| [CommandPaletteView.swift](../../apps/mac/OortMac/Views/Search/CommandPaletteView.swift) | Cerca ovunque: campo, gruppi, righe con scorciatoia, annunci VoiceOver su nome e azione della riga attiva, ritorno del focus. |
| [CommandPaletteProbe.swift](../../apps/mac/OortMac/Views/Search/CommandPaletteProbe.swift) | Controllo Debug di tasti e pulsanti e catture di ogni stato, senza finestra e con voci sintetiche. |
| [apps/mac/OortMac/Views/Console/ConsoleView.swift](../../apps/mac/OortMac/Views/Console/ConsoleView.swift) | Mostra log e stato corrente e offre copia di log e diagnostica. |
| [apps/mac/OortMac/Views/ControlsView.swift](../../apps/mac/OortMac/Views/ControlsView.swift) | Guida Selene separata fra Library e In game; stato controller, rilevamento e scorrimento delle righe con tastiera/controller. |

## UI · componenti condivisi

| File | Responsabilità |
|---|---|
| [apps/mac/OortMac/Views/Components/WikipediaAbout.swift](../../apps/mac/OortMac/Views/Components/WikipediaAbout.swift) | Richiesta dell'introduzione di Wikipedia per About this game (Spotlight e Details), chiesta solo quando la risposta dello store nella lingua dell'app è definitiva, valida solo per lo stesso gioco e lingua, e credito con link alla voce. |
| [apps/mac/OortMac/Views/Components/GameIconProvider.swift](../../apps/mac/OortMac/Views/Components/GameIconProvider.swift) | Fornisce e conserva l’icona estratta dai bundle dei giochi; ricorda anche quando manca. |
| [apps/mac/OortMac/Views/Components/PortingArtLook.swift](../../apps/mac/OortMac/Views/Components/PortingArtLook.swift) | Desatura la tile; mantiene la linea, la barra di avanzamento del porting e il riempimento lineare degli invii. |
| [apps/mac/OortMac/Views/Components/DownloadCloudOverlay.swift](../../apps/mac/OortMac/Views/Components/DownloadCloudOverlay.swift) | Proiezione del trasferimento, campioni Core Animation su tessere visibili, maschera di colore e ritaglio del titolo. |
| [apps/mac/OortMac/Views/Components/ScreenshotViewer.swift](../../apps/mac/OortMac/Views/Components/ScreenshotViewer.swift) | Mostra screenshot a schermo pieno e navigazione fra le immagini. |
| [apps/mac/OortMac/Views/Components/SeleneBottomScrim.swift](../../apps/mac/OortMac/Views/Components/SeleneBottomScrim.swift) | Definisce sfumatura inferiore, posizione condivisa dei comandi (32 unità dal fondo) e fascia libera dai contenuti. |
| [apps/mac/OortMac/Views/OortUI/OortPage.swift](../../apps/mac/OortMac/Views/OortUI/OortPage.swift) | Pagina con sfondo opaco o Selene storico, scroll e focus, intestazione di sezione e stato vuoto. |
| [OortFilePicker.swift](../../apps/mac/OortMac/Views/OortUI/OortFilePicker.swift) | Selettore in-app, navigazione e passaggio facoltativo al selettore di macOS. |
| [OortFilePickerProbe.swift](../../apps/mac/OortMac/Views/OortUI/OortFilePickerProbe.swift) | Catture Debug larghe e strette in francese, con cartelle sintetiche. |
| [apps/mac/OortMac/Views/OortUI/OortActionBar.swift](../../apps/mac/OortMac/Views/OortUI/OortActionBar.swift) | Piede comune di pannelli e domande: ritorno a sinistra, principale ultima a destra, distruttivo staccato; la colonna segue il focus se non entra. |
| [apps/mac/OortMac/Views/OortUI/OortControls.swift](../../apps/mac/OortMac/Views/OortUI/OortControls.swift) | Preset per righe, azioni e stati, e riga con cursore. |
| [apps/mac/OortMac/Views/OortUI/OortItemActions.swift](../../apps/mac/OortMac/Views/OortUI/OortItemActions.swift) | Azioni che l'indizio annuncia, anche sullo schermo e nel clic destro, dagli stessi HintItem. |
| [apps/mac/OortMac/Views/OortUI/OortLink.swift](../../apps/mac/OortMac/Views/OortUI/OortLink.swift) | Collegamento tra i campi di un dialogo: clic, oppure Tab e Invio. |
| [apps/mac/OortMac/Views/OortUI/OortGameTile.swift](../../apps/mac/OortMac/Views/OortUI/OortGameTile.swift) | Tessera con preset Spotlight e Collection, input e accessibilità; l'arte resta al chiamante. |
| [apps/mac/OortMac/Views/OortUI/OortSecondaryClick.swift](../../apps/mac/OortMac/Views/OortUI/OortSecondaryClick.swift) | Clic destro (o Ctrl-clic) su un riquadro: le stesse opzioni di +; ogni altro evento passa al riquadro. |
| [apps/mac/OortMac/Views/OortUI/OortWebPage.swift](../../apps/mac/OortMac/Views/OortUI/OortWebPage.swift) | Apre una pagina nel browser; dal controller chiede prima, perché nulla riporta a Oort. |
| [apps/mac/OortMac/Views/OortUI/OortKeyboard.swift](../../apps/mac/OortMac/Views/OortUI/OortKeyboard.swift) | Tastiera a schermo unica: segue campo e periferica senza cambiare il primo responder. |
| [apps/mac/OortMac/Views/OortUI/OortKeyboardProbe.swift](../../apps/mac/OortMac/Views/OortUI/OortKeyboardProbe.swift) | Prova Debug fuori schermo: scrittura e cambio di periferica in un campo corto e in uno lungo. |
| [apps/mac/OortMac/Views/OortUI/PlayerSlot.swift](../../apps/mac/OortMac/Views/OortUI/PlayerSlot.swift) | Posto giocatore ad altezza stabile con ritratto, stato e valore accessibile. |
| [DESIGN.md](../../DESIGN.md) | Sistema di design: token, pezzi, regole. |
| [PRODUCT.md](../../PRODUCT.md) | Per chi è Oort, cosa promette e cosa evita. |
| [apps/mac/OortMac/Services/ControllerLive.swift](../../apps/mac/OortMac/Services/ControllerLive.swift) | Stato vivo del controller attivo (tasti tenuti, stick), separato dal servizio per non ridisegnare le altre viste. |
| [apps/mac/OortMac/Views/OortUI/OortControllerView.swift](../../apps/mac/OortMac/Views/OortUI/OortControllerView.swift) | Controller disegnato a punti, con gli ingressi reali accesi, e la sua mappa dei comandi. |
| [apps/mac/OortMac/Views/OortUI/OortMeter.swift](../../apps/mac/OortMac/Views/OortUI/OortMeter.swift) | Barra di avanzamento, misurata o indeterminata. |
| [apps/mac/OortMac/Views/OortUI/OortSearchField.swift](../../apps/mac/OortMac/Views/OortUI/OortSearchField.swift) | Campo di ricerca condiviso. |
| [apps/mac/OortMac/Views/OortUI/OortSetupCard.swift](../../apps/mac/OortMac/Views/OortUI/OortSetupCard.swift) | Scheda di scelta della prima configurazione. |
| [apps/mac/OortMac/Views/OortUI/OortTabs.swift](../../apps/mac/OortMac/Views/OortUI/OortTabs.swift) | Schede condivise: scelta, focus, conteggio. |
| [apps/mac/OortMac/Views/OortUI/OortTag.swift](../../apps/mac/OortMac/Views/OortUI/OortTag.swift) | Etichetta breve: genere, versione, stato. |
| [apps/mac/OortMac/Views/OortUI/OortCreditCard.swift](../../apps/mac/OortMac/Views/OortUI/OortCreditCard.swift) | Scheda di un credito e gruppo di schede: griglia piena, di altezza uguale, o lista. |
| [core/Tests/OortLibraryTests/PaletteContrastTests.swift](../../core/Tests/OortLibraryTests/PaletteContrastTests.swift) | Contrasto di testo, focus e simboli in ogni palette. |
| [apps/mac/OortMac/Views/OortUI/OortUIGallery.swift](../../apps/mac/OortMac/Views/OortUI/OortUIGallery.swift) | Esempi sintetici Debug delle primitive OortUI e catture senza finestre su tre palette. |
| [apps/mac/OortMac/Views/OortUI/SeleneConfirmDialog.swift](../../apps/mac/OortMac/Views/OortUI/SeleneConfirmDialog.swift) | Card e aiuto condivisi, annullamento a sinistra e conferma a destra con `OortActionBar`, scelte multiple con testo a larghezza definita e note, SeleneSuccessNotice. |
| [apps/mac/OortMac/Views/OortUI/SeleneConfirmDialog.swift](../../apps/mac/OortMac/Views/OortUI/SeleneConfirmDialog.swift) | Card e aiuto condivisi, conferma a sinistra e annullamento a destra, scelte multiple con testo a larghezza definita e note, SeleneSuccessNotice. |
| [apps/mac/OortMac/Views/OortUI/OortActionBar.swift](../../apps/mac/OortMac/Views/OortUI/OortActionBar.swift) | Barra e domanda con Annulla a sinistra, azione principale a destra e azione distruttiva su una riga separata. |
| [core/OortLibrary/Selene/ActionBarOrder.swift](../../core/OortLibrary/Selene/ActionBarOrder.swift), [test](../../core/Tests/OortLibraryTests/ActionBarOrderTests.swift) | Ordine e focus iniziale delle azioni secondo il ruolo, in comune fra disegno e input. |
| [apps/mac/OortMac/Views/Components/AppUpdateDialog.swift](../../apps/mac/OortMac/Views/Components/AppUpdateDialog.swift) | Presenta controllo aggiornamenti, note di release, errori e progresso nel dialogo dell’app. |
| [apps/mac/OortMac/Views/OortUI/SeleneHintsBar.swift](../../apps/mac/OortMac/Views/OortUI/SeleneHintsBar.swift) | Disegna i suggerimenti contestuali: ogni voce ha un glifo o un'etichetta di tasto; ⌘F appare senza manetta. |
| [apps/mac/OortMac/Views/Components/SeleneHomeChrome.swift](../../apps/mac/OortMac/Views/Components/SeleneHomeChrome.swift) | Rende elementi condivisi della cornice e dei controlli della home Selene; trattiene gli hint durante l’entrata. |
| [apps/mac/OortMac/Views/OortUI/SeleneOptionRow.swift](../../apps/mac/OortMac/Views/OortUI/SeleneOptionRow.swift) | Disegna righe di opzioni con icona, titolo, descrizione con carattere configurabile, focus, contenuto laterale e dettaglio a tutta larghezza facoltativo. |
| [apps/mac/OortMac/Views/Components/SeleneExpandableText.swift](../../apps/mac/OortMac/Views/Components/SeleneExpandableText.swift) | Rivela la descrizione completa animando l'altezza fra due layout di testo stabili; usato solo dalle righe dei metadati. |
| [apps/mac/OortMac/Views/OortUI/SelenePillButton.swift](../../apps/mac/OortMac/Views/OortUI/SelenePillButton.swift) | Disegna il pulsante condiviso, il contorno come anello pieno, la larghezza piena in una colonna e il riempimento mascherato di Download. |
| [apps/mac/OortMac/Views/OortUI/SeleneStepper.swift](../../apps/mac/OortMac/Views/OortUI/SeleneStepper.swift) | Indicatore di passo e superficie dei campi per l'assistente Selene. |
| [apps/mac/OortMac/Views/OortUI/SelenePromptBadge.swift](../../apps/mac/OortMac/Views/OortUI/SelenePromptBadge.swift) | Rende simbolo o etichetta del controller e della tastiera, compresa la croce direzionale a contrasto. |
| [apps/mac/OortMac/Views/Components/GlideGroup.swift](../../apps/mac/OortMac/Views/Components/GlideGroup.swift) | Usa `geometryGroup` per spostare un blocco come un pezzo unico. `RailCamera` limita la posizione interpolata dei rail Spotlight e Collection alla lunghezza corrente. |
| [apps/mac/OortMac/Views/Components/SeleneReveal.swift](../../apps/mac/OortMac/Views/Components/SeleneReveal.swift) | Applica l’animazione di comparsa Selene rispettando la preferenza Riduci movimento. |
| [apps/mac/OortMac/Views/OortUI/SeleneSettingsRow.swift](../../apps/mac/OortMac/Views/OortUI/SeleneSettingsRow.swift) | Righe delle impostazioni e ciclo di valore condiviso da Settings e Game Options. |
| [apps/mac/OortMac/Views/OortUI/SeleneStatsRow.swift](../../apps/mac/OortMac/Views/OortUI/SeleneStatsRow.swift) | Disegna le statistiche compatte del gioco nella libreria. |
| [apps/mac/OortMac/Views/Components/SeleneSwitch.swift](../../apps/mac/OortMac/Views/Components/SeleneSwitch.swift) | Disegna lo switch coerente con il tema. |
| [apps/mac/OortMac/Views/OortUI/SeleneTileRing.swift](../../apps/mac/OortMac/Views/OortUI/SeleneTileRing.swift) | Ring e riflesso della tile selezionata; con Reduce motion il ring fermo disegnato da SwiftUI. |
| [apps/mac/OortMac/Views/Components/TileMotionLayers.swift](../../apps/mac/OortMac/Views/Components/TileMotionLayers.swift) | Ring e riflesso come layer Core Animation in loop: nessun ridisegno dell'app tra un frame e l'altro. |
| [apps/mac/OortMac/Views/OortUI/SeleneValueChip.swift](../../apps/mac/OortMac/Views/OortUI/SeleneValueChip.swift) | Rende valori e badge compatti nel linguaggio visivo Selene. |
| [apps/mac/OortMac/Views/Components/NextendoOnlineBadge.swift](../../apps/mac/OortMac/Views/Components/NextendoOnlineBadge.swift) | Punto e numero sulla copertina; tiene i valori d’ambiente con i conteggi e gli interruttori. |
| [apps/mac/OortMac/Views/OortUI/SeleneStatusDot.swift](../../apps/mac/OortMac/Views/OortUI/SeleneStatusDot.swift) | Punto decorativo di 7 unità per testo o badge; l'alone Core Animation facoltativo può comparire senza punto e rispetta Riduci movimento e finestra attiva. |
| [apps/mac/OortMac/Views/Components/SpotlightTileArtwork.swift](../../apps/mac/OortMac/Views/Components/SpotlightTileArtwork.swift) | Disegna subito l’icona nxnative già decodificata; cache condivisa `TileArtMemo` con fonte e revisione delle scelte, caricamento annullabile e segnale `TileArtPendingKey`. |
| [apps/mac/OortMac/Views/Components/SwitchBoxArtCover.swift](../../apps/mac/OortMac/Views/Components/SwitchBoxArtCover.swift) | Disegna la copertina Switch dalle immagini in cache o compone il ripiego e fornisce i limiti del titolo. |
| [apps/mac/OortMac/Views/Components/SteamGridDBKeyDialog.swift](../../apps/mac/OortMac/Views/Components/SteamGridDBKeyDialog.swift) | Popup per incollare e verificare la chiave SteamGridDB da Settings → Look e da Change artwork. |
| [apps/mac/OortMac/Views/OortUI/PlatformLabel.swift](../../apps/mac/OortMac/Views/OortUI/PlatformLabel.swift) | Etichetta condivisa: simbolo monocromatico, nome e indicatore Switch 2. |
| [apps/mac/OortMac/Views/Components/GameLogoArea.swift](../../apps/mac/OortMac/Views/Components/GameLogoArea.swift) | Area del logo del gioco con la geometria condivisa da Spotlight e Collection; caricamento e impostazioni restano fuori. |
| [apps/mac/OortMac/Views/Components/GamePrimaryActions.swift](../../apps/mac/OortMac/Views/Components/GamePrimaryActions.swift) | Azioni principali con avanzamento di Download, Options, pillola Cloud e preferito con bersagli di input stabili. |
| [apps/mac/OortMac/Views/Components/SessionCard.swift](../../apps/mac/OortMac/Views/Components/SessionCard.swift) | Card di fine sessione e toast degli obiettivi con titolo plurale: aspettano che Arcane sia davanti, compaiono 1,8 s dopo per 8 s e si azzerano al cambio di profilo. |
| [apps/mac/OortMac/Views/Components/UndoNotice.swift](../../apps/mac/OortMac/Views/Components/UndoNotice.swift) | Avviso Undo e suggerimento vicino alla card di fine sessione; prendono il focus solo su richiesta, mai sopra un dialogo o Game Options. |

## UI · temi, rendering e sfondi

| File | Responsabilità |
|---|---|
| [apps/mac/OortMac/Views/Theme/ThemeStore.swift](../../apps/mac/OortMac/Views/Theme/ThemeStore.swift) | Mantiene palette attiva, wallpaper inclusi e importati e operazioni sulle scelte dell’utente. |
| [apps/mac/OortMac/Views/Theme/SeleneTheme.swift](../../apps/mac/OortMac/Views/Theme/SeleneTheme.swift) | Espone colori, stili, curve di animazione, focus e ambiente Selene; solo il blu classico usa inchiostro tenue per i glifi delle righe. |
| [apps/mac/OortMac/Views/Theme/SeleneFonts.swift](../../apps/mac/OortMac/Views/Theme/SeleneFonts.swift) | Registra il font incluso e definisce MaterialIconView. |
| [apps/mac/OortMac/Views/Theme/SeleneCanvasEnvironment.swift](../../apps/mac/OortMac/Views/Theme/SeleneCanvasEnvironment.swift) | Pubblica il canvas, scala unità e font e applica le sfumature sui bordi orizzontali richiesti. |
| [apps/mac/OortMac/Views/Theme/SeleneBackdrop.swift](../../apps/mac/OortMac/Views/Theme/SeleneBackdrop.swift) | Nella shell dichiara la richiesta di sfondo condiviso, fuori dalla shell disegna; consuma lo snapshot completo della palette e compone gradiente, wallpaper e Moonlight a particelle morbide; conserva le immagini decodificate e il fallback statico. |
| [apps/mac/OortMac/Views/Theme/MoonlightRenderer.swift](../../apps/mac/OortMac/Views/Theme/MoonlightRenderer.swift) | Gestisce Metal, il `CAMetalDisplayLink` e il rendering live/statico. Disegna solo il link, anche il frame fermo, e il primo drawable presentato sblocca `LaunchReveal`; nella Dev registra creazione e prima presentazione. |
| [apps/mac/OortMac/Views/Theme/MoonlightShaders.swift](../../apps/mac/OortMac/Views/Theme/MoonlightShaders.swift) | Contiene gli shader Metal del Moonlight, superfici analitiche Arcane/Flow, filamenti sottili antialias piegati da onde viaggianti e particelle morbide, compilati a runtime. |
| [apps/mac/OortMac/Views/Theme/LiveBackdrop.swift](../../apps/mac/OortMac/Views/Theme/LiveBackdrop.swift) | Integra video AVFoundation in loop e adatta riproduzione e frame alla visibilità della finestra. |
| [apps/mac/OortMac/Views/Theme/OnlineBrowsePanel.swift](../../apps/mac/OortMac/Views/Theme/OnlineBrowsePanel.swift) | Mantiene stato di ricerca e download e presenta griglia e miniature degli sfondi online. |
| [apps/mac/OortMac/Views/Theme/ThemePickerView.swift](../../apps/mac/OortMac/Views/Theme/ThemePickerView.swift) | Presenta i colori con anteprima viva nel primo passo; sfondi, provider e destinazione nel passo successivo. Il file tiene stato, `body`, transizioni, intestazione, griglia, `TileFocus` e `WallpaperThumb`; il resto sta nelle estensioni qui sotto. |
| [apps/mac/OortMac/Views/Theme/ThemePickerView+ThemeStep.swift](../../apps/mac/OortMac/Views/Theme/ThemePickerView+ThemeStep.swift) | Passo dei temi: campioni delle palette con scrim di lettura per quelle chiare, colori e sfondo di anteprima. |
| [apps/mac/OortMac/Views/Theme/ThemePickerView+BackgroundStep.swift](../../apps/mac/OortMac/Views/Theme/ThemePickerView+BackgroundStep.swift) | Passo degli sfondi: schede, tile degli sfondi e delle fonti, anteprime, crediti ed etichette. |
| [apps/mac/OortMac/Views/Theme/ThemePickerView+Input.swift](../../apps/mac/OortMac/Views/Theme/ThemePickerView+Input.swift) | Input: apertura, schede, controller, focus, tocchi, conferma e indietro. |
| [apps/mac/OortMac/Views/Theme/ThemePickerView+Online.swift](../../apps/mac/OortMac/Views/Theme/ThemePickerView+Online.swift) | Sfondi online: apertura di una fonte, suo input, categorie, ricerca e uso dell’immagine scelta. |
| [apps/mac/OortMac/Views/Theme/ThemePickerView+Placement.swift](../../apps/mac/OortMac/Views/Theme/ThemePickerView+Placement.swift) | Collocazione: chiede come lo sfondo scelto riempie lo schermo e applica la risposta. |
| [apps/mac/OortMac/Views/Theme/ThemePickerView+OwnWallpapers.swift](../../apps/mac/OortMac/Views/Theme/ThemePickerView+OwnWallpapers.swift) | Sfondi del giocatore: aggiunta da file e rimozione dopo conferma. |
| [apps/mac/OortMac/Views/Theme/ThemePreview.swift](../../apps/mac/OortMac/Views/Theme/ThemePreview.swift) | Disegna un’anteprima della home con palette, sfondo e particelle morbide; il movimento segue le preferenze. |
| [apps/mac/OortMac/Views/Theme/AppLocaleEnvironment.swift](../../apps/mac/OortMac/Views/Theme/AppLocaleEnvironment.swift) | Contesto della lingua reattivo per le viste; conserva identità, selezione e focus. |

## UI · fonti, Steam e libreria mista

| File | Responsabilità |
|---|---|
| [AppViewModel+Catalog.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+Catalog.swift) | Salvataggio e retry del risultato di build senza libreria di ripiego; aggiorna il confronto cloud per l’app installata. |
| [CatalogPersonalizationsEnvironment.swift](../../apps/mac/OortMac/Views/Theme/CatalogPersonalizationsEnvironment.swift) | Dipendenza SwiftUI esplicita per le chiavi personali stabili. |
| [AppViewModel+Sources.swift](../../apps/mac/OortMac/ViewModels/AppViewModel+Sources.swift) | Proiezione visibile, selezione comune e modifiche personali tipizzate. |
| [SettingsSourcesSection.swift](../../apps/mac/OortMac/Views/Settings/SettingsSourcesSection.swift) | Aggiunta manuale di un’app Mac; attivazione, refresh, cartella e controllo della fonte Steam. |
| [CatalogNativeArtwork.swift](../../apps/mac/OortMac/Views/Catalog/CatalogNativeArtwork.swift) | Icona nativa in sola lettura; testata dei collegamenti Mac e immagine scelta localmente. |
| [MacShortcutAdapter.swift](../../apps/mac/OortMac/Services/MacShortcutAdapter.swift) | Selettore, esito del trascinamento, ricollegamento e opzioni della tessera; Play consegna a macOS senza osservare sessioni. |
| [CatalogSteamInfo.swift](../../apps/mac/OortMac/Views/Catalog/CatalogSteamInfo.swift) | Intestazione condivisa nelle due librerie: Play/Riprendi/Annulla/Riprova, Opzioni e preferito, con la nota di stato. |
| [SteamPlayCoordinator.swift](../../apps/mac/OortMac/Services/SteamPlayCoordinator.swift) | Play tramite il client verificato; distingue consegna e apertura, e registra sessioni dal processo dell’app installata. La fonte spenta lascia finire le sessioni, senza aprirne altre. |
| [SteamPlaytimeCoordinator.swift](../../apps/mac/OortMac/Services/SteamPlaytimeCoordinator.swift) | Aggiorna le ore Steam fuori dal thread principale; conserva il totale se una sessione Steam appartiene a un profilo secondario. |
| [SteamOptionsView.swift](../../apps/mac/OortMac/Views/GameOptions/SteamOptionsView.swift) | Opzioni di un gioco Steam con l’aspetto e l’input di Game options: Play, Edit details, Move, preferito, nascosto, Finder. |
| [PersonalizationSubject.swift](../../apps/mac/OortMac/Views/GameOptions/PersonalizationSubject.swift) | Il gioco che Change artwork e Change metadata personalizzano: scelte nxnative o archivio personale Steam, senza icona Mac per Steam. |
| [SteamGamePage.swift](../../apps/mac/OortMac/Views/Catalog/SteamGamePage.swift) | Dati store Steam dei giochi a schermo, una copia condivisa da Spotlight e Collection, per AppID e lingua; una risposta per un gioco o una lingua non più chiesti si scarta; offline mostra il testo di un'altra lingua con l'avviso. |
| [SteamArtwork.swift](../../apps/mac/OortMac/Views/Catalog/SteamArtwork.swift) | Immagini Steam con cache disponibile prima del task, identità di richiesta/build e ripiego in colore Selene; rivalidazione dei file, scelte personali, annullamento e `TileArtPendingKey`. |
| [SteamPersonalizations.swift](../../apps/mac/OortMac/Views/Catalog/SteamPersonalizations.swift) | Archivio delle scelte personali Steam (metadati e artwork), modificate da Change artwork e Change metadata. |

## UI · achievement

| File | Responsabilità |
|---|---|
| [SteamAchievementsStore.swift](../../apps/mac/OortMac/Services/SteamAchievementsStore.swift) | Legge gli achievement fuori dal thread principale (selezione, apertura della schermata e, per il gioco selezionato, fine di una sessione Steam: subito e dopo un minuto), uno per AppID alla volta; tiene gli ultimi 16 giochi e aggiunge la rarità quando arriva. |
| [ArcaneOrbVideo.swift](../../apps/mac/OortMac/Views/Spotlight/ArcaneOrbVideo.swift) | L'Arcane della card come video: grigio e fermo a riposo, a colori e in movimento con hover o focus, si ferma sul suo fotogramma e riparte da lì; colore, luce e scala animati da Core Animation. Usato anche, grande e sempre attivo, in testa alla schermata Achievements quando l'Arcane è conquistato. |
| [DetailsAchievementsCard.swift](../../apps/mac/OortMac/Views/Detail/DetailsAchievementsCard.swift) | Card Achievements sopra Details; prende il focus e apre la schermata. Definisce la barra misurata con colore di riempimento configurabile. |
| [AchievementIcon.swift](../../apps/mac/OortMac/Views/Detail/AchievementIcon.swift) | Icona di un achievement dalla cache di `SteamMetadataService`, decodificata fuori dal thread principale e tenuta in memoria (niente lampo quando una riga torna in vista), con un riquadro neutro finché manca; un segreto non sbloccato è sfocato sotto un lucchetto. |
| [AchievementsScreen.swift](../../apps/mac/OortMac/Views/Spotlight/AchievementsScreen.swift) | Obiettivi Selene: logo e sbloccati a sinistra, cristalli o medaglione a destra, lista con offset proprio. LB/RB affiancano i filtri; nel dettaglio aperto i suggerimenti passano nella barra in basso. |
| [AchievementDetail.swift](../../apps/mac/OortMac/Views/Spotlight/AchievementDetail.swift) | Dettaglio di un obiettivo come medaglione (A sulla riga o clic sulla riga in focus): icona grande con il cristallo della tier come piccolo distintivo sull’angolo, nome e descrizione interi centrati, percentuale dei giocatori, data di sblocco; le frecce scorrono la lista, A/B o un clic fuori chiudono. |
| [TierCrystal.swift](../../apps/mac/OortMac/Views/Spotlight/TierCrystal.swift) | Il cristallo di una tier dalle risorse del Core, decodificato una volta; non ancora ottenuto, tenue con una traccia del suo colore, così oro, argento e bronzo restano distinguibili. |
| [AchievementsScreenModel.swift](../../apps/mac/OortMac/ViewModels/AchievementsScreenModel.swift) | Selezione, filtro e scroll di Achievements; LB/RB cambiano filtro o scorrono i dettagli aperti. Dopo la rotella la prima freccia riporta il focus in vista. |
| [ListScroll.swift](../../apps/mac/OortMac/ViewModels/ListScroll.swift) | Offset di una lista (`TextScroll`) con la planata del pannello delle mod: rotella, trackpad e frecce muovono lo stesso valore. |

## Contributi, skill e controlli di architettura

| File | Responsabilità |
|---|---|
| [scripts/check](../../scripts/check) | Unico ingresso dei controlli, usato dalla CI e dalla documentazione: ogni regola pronta (R1, R2, R4, R5, R8, R10, R13), `--base` per i debiti che possono solo ridursi, `--list` con i test rossi di ogni regola, e i passi pesanti (`swift`, `app-build`, `app-probes`, `release-build`). |
| [scripts/generate](../../scripts/generate) | Unico ingresso dei file generati (token, crediti); `--check` rifiuta un'uscita non aggiornata o modificata a mano. |
| [scripts/repo_model.py](../../scripts/repo_model.py) | Legge da `architecture/structure.c4` le cartelle dichiarate, i file della radice e le cartelle di documentazione. |
| [scripts/check_structure.py](../../scripts/check_structure.py) | R1: rifiuta un file della radice o una cartella di primo o secondo livello non dichiarati, e una dichiarazione senza file. |
| [scripts/check_docs.py](../../scripts/check_docs.py) | R8: `.md` solo nelle cartelle di documentazione, link relativi risolti, nessun marcatore privato nuovo. |
| [scripts/private-markers.json](../../scripts/private-markers.json) | Marcatori privati vietati nei `.md` e file che li contengono già; l'elenco può solo ridursi. |
| [scripts/check_probes.py](../../scripts/check_probes.py) | R13: una sonda che legge il testo reso deve provarne la visibilità con `assertVisible`. |
| [scripts/ci_changed_areas.py](../../scripts/ci_changed_areas.py) | Decide quali aree della CI girano secondo i percorsi modificati; una cartella assente lascia l’area spenta. |
| [scripts/ci_catalog_checks.py](../../scripts/ci_catalog_checks.py) | Divide le sonde tra build Debug condivisa e gruppi autonomi di due, esegue ciascuna con home isolata e ne registra l'esito e il tempo. |
| [scripts/check_module_boundaries.py](../../scripts/check_module_boundaries.py) | Legge moduli, tipi e livelli da `architecture/names.json`, li confronta con SwiftPM e verifica gli import; solo il punto d'ingresso di un'app importa un motore (ADR 0002). |
| [scripts/core-import-debt.json](../../scripts/core-import-debt.json) | Debito di R3: i file del Core che non compilano ancora su ogni sistema; la lista può solo scendere. |
| [scripts/engine-import-debt.json](../../scripts/engine-import-debt.json) | Debito dell'ADR 0002: i file del Mac che importano ancora l'adattatore nxnative; la lista può solo scendere. |
| [scripts/check_names.py](../../scripts/check_names.py) | Rifiuta un nome tecnico scritto a mano fuori da `architecture/names.json` e verifica i valori congelati dei giocatori. |
| [scripts/names.py](../../scripts/names.py) | Legge `architecture/names.json` per gli script e le sonde; `stage()` prepara il pacchetto temporaneo di una sonda. |
| [scripts/generate_names.py](../../scripts/generate_names.py) | Scrive le copie dei nomi: blocchi di `Package.swift` e `build_app.sh`, `architecture/names.c4`, `GeneratedNames.swift`. |
| [architecture/likec4.config.json](../../architecture/likec4.config.json) | Configurazione del progetto LikeC4. |
| [architecture/spec.c4](../../architecture/spec.c4) | Tipi di elementi del modello. |
| [architecture/model.c4](../../architecture/model.c4) | Sistemi e responsabilità dei domini. |
| [architecture/names.json](../../architecture/names.json) | Unica fonte dei nomi tecnici: pacchetto, moduli con tipo, livello e cartella, target di test, punto d'ingresso; valori congelati dei giocatori. |
| [architecture/names.c4](../../architecture/names.c4) | Moduli Swift del modello, generati da `names.json`. |
| [architecture/structure.c4](../../architecture/structure.c4) | Cartelle e file della radice del repository, e dove può stare la documentazione; letto da `scripts/check`. |
| [architecture/views.c4](../../architecture/views.c4) | Ecosistema, percorso verso il motore, responsabilità dei domini e sequenza di gioco. |
| [scripts/tests/CIChecks/test_changed_areas.py](../../scripts/tests/CIChecks/test_changed_areas.py) | Verifica quali aree si accendono per documentazione, core, workflow e cartelle mancanti. |
| [scripts/tests/CIChecks/test_catalog_checks.py](../../scripts/tests/CIChecks/test_catalog_checks.py) | Verifica che tutti i candidati siano assegnati una sola volta, che i gruppi autonomi siano limitati e che un errore non nasconda il risultato successivo. |
| [scripts/tests/ModuleChecks/test_oort_core.py](../../scripts/tests/ModuleChecks/test_oort_core.py) | Esempi rossi di R3: import Apple dietro `#if`, libc fuori da `System/`, nomi solo Apple, test con AppKit, debito che scende. |
| [scripts/tests/ModuleChecks/test_module_boundaries.py](../../scripts/tests/ModuleChecks/test_module_boundaries.py) | Verifica i confini dei moduli con fixture sintetiche e sul repository. |
| [scripts/tests/SkillChecks/test_skills.py](../../scripts/tests/SkillChecks/test_skills.py) | Verifica formato, tre casi per skill, link e assenza di percorsi personali nelle skill pubbliche. |
| [scripts/tests/RepoChecks/support.py](../../scripts/tests/RepoChecks/support.py) | Repository Git usa e getta per i controlli del repository. |
| [scripts/tests/RepoChecks/test_structure.py](../../scripts/tests/RepoChecks/test_structure.py) | Esempi rossi di R1: cartella, sottocartella e file non dichiarati, dichiarazione senza file. |
| [scripts/tests/RepoChecks/test_docs.py](../../scripts/tests/RepoChecks/test_docs.py) | Esempi rossi di R8: documentazione fuori posto, link morto, marcatore privato, eccezione nuova o superata. |
| [scripts/tests/RepoChecks/test_probes.py](../../scripts/tests/RepoChecks/test_probes.py) | Esempio rosso di R13: una sonda che legge il testo del PDF senza `assertVisible`. |
| [scripts/tests/RepoChecks/test_check.py](../../scripts/tests/RepoChecks/test_check.py) | Elenco delle regole, nome sconosciuto, un errore che fa fallire la corsa e uscita generata non aggiornata. |
| [docs/working-on-it/architecture-map.md](architecture-map.md) | Collegamento al modello, controlli e dove mettere il codice. |
| [docs/working-on-it/branch-rules.md](branch-rules.md) | Regole proposte per rami, tag e controlli richiesti; nessuna applicata su GitHub. |
| [.agents/skills/oort-contribute/SKILL.md](../../.agents/skills/oort-contribute/SKILL.md) | Prepara un contributo: sistema, controlli, dati privati, bozza di pull request. |
| [.agents/skills/oort-contribute/evals/cases.md](../../.agents/skills/oort-contribute/evals/cases.md) | Tre casi di valutazione di oort-contribute. |
| [.agents/skills/oort-triage/SKILL.md](../../.agents/skills/oort-triage/SKILL.md) | Propone tipo, sistema, fonte, priorità e informazioni mancanti; non applica nulla. |
| [.agents/skills/oort-triage/evals/cases.md](../../.agents/skills/oort-triage/evals/cases.md) | Tre casi di valutazione di oort-triage. |
| [.agents/skills/oort-release/SKILL.md](../../.agents/skills/oort-release/SKILL.md) | Prepara una release senza pubblicarla: stato pulito, controlli, note, somme SHA-256. |
| [.agents/skills/oort-release/evals/cases.md](../../.agents/skills/oort-release/evals/cases.md) | Tre casi di valutazione di oort-release. |
| [.agents/skills/oort-guides/SKILL.md](../../.agents/skills/oort-guides/SKILL.md) | Scrive o corregge una guida in tempo presente, verificata sul codice. |
| [.agents/skills/oort-guides/evals/cases.md](../../.agents/skills/oort-guides/evals/cases.md) | Tre casi di valutazione di oort-guides. |

## Test e fixture

| File | Responsabilità aggiuntiva |
|---|---|
| [FileBrowserTests.swift](../../core/Tests/OortLibraryTests/FileBrowserTests.swift) | Filtri, ordine, collegamenti, permessi, volume non disponibile e cartella con 2.000 file sintetici. |
| [core/Tests/OortLibraryTests/SettingsRowActionTests.swift](../../core/Tests/OortLibraryTests/SettingsRowActionTests.swift) | Regressioni per giochi omonimi e azioni secondarie della medesima riga. |
| [engines/nxnative/Tests/NxnativeAdapterTests/ScreenshotFallbackTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/ScreenshotFallbackTests.swift) | Screenshot LaunchBox cercati una volta e conservati, precedenza di quelli propri e dimensione piena della scelta. |
| [core/Tests/OortLibraryTests/SteamGridDBArtTests.swift](../../core/Tests/OortLibraryTests/SteamGridDBArtTests.swift) | Chiave privata, richieste con la chiave solo a SteamGridDB, crediti, anteprime e ricerca da Browse online. |
| [scripts/tests/PublicationChecks/test_publication.py](../../scripts/tests/PublicationChecks/test_publication.py) | Esegue il controllo in repository temporanee: file vietati, chiavi sintetiche redatte, runtime non conforme e testi o sorgenti mancanti o alterati. |
| [scripts/tests/PublicationChecks/test_release_target.py](../../scripts/tests/PublicationChecks/test_release_target.py) | Verifica senza rete i controlli, la destinazione unica di tag e release e il ripiego DMG mantenendo il nome dell'asset, attraverso repository locali e comandi sostitutivi. |
| [scripts/tests/PublicationChecks/test_update_archive.py](../../scripts/tests/PublicationChecks/test_update_archive.py) | Verifica il controllo ZIP reale con bundle sintetici, symlink, percorsi non sicuri, collisioni Unicode, header incoerenti e dimensioni eccessive. |

| File | Responsabilità |
|---|---|
| [core/Tests/OortLibraryTests/ActivitySummaryTests.swift](../../core/Tests/OortLibraryTests/ActivitySummaryTests.swift) | Totali settimanali, distribuzione giornaliera, sessioni aperte e passaggi di mezzanotte. |
| [core/Tests/OortLibraryTests/ProfilePageCardsTests.swift](../../core/Tests/OortLibraryTests/ProfilePageCardsTests.swift) | Ordine persistente, visibilità senza conto, geometria adattiva e isolamento delle sessioni. |
| [core/Tests/OortLibraryTests/AppBundleRenameTests.swift](../../core/Tests/OortLibraryTests/AppBundleRenameTests.swift) | Rinomina alla chiusura: solo `NX Library.app`, verso `Oort NX.app` se libero e scrivibile; `Arcane.app` resta al suo posto. |
| [core/Tests/OortLibraryTests/AppRouterTests.swift](../../core/Tests/OortLibraryTests/AppRouterTests.swift) | Route, overlay, precedenza degli input, tasti e ritorno del control center; i dialoghi di Settings impediscono ⌘K. |
| [core/Tests/OortLibraryTests/ActionBarOrderTests.swift](../../core/Tests/OortLibraryTests/ActionBarOrderTests.swift) | Ordine della barra, elenco verticale, domande e focus iniziale. |
| [core/Tests/OortLibraryTests/AppRouterTests.swift](../../core/Tests/OortLibraryTests/AppRouterTests.swift) | Route, overlay, precedenza fullscreen, tasti di ogni sottomenu e navigazione LB/RB del control center, focus senza Inbox, navigazione del centro attività e ritorno distinto dal clic fuori. |
| [core/Tests/OortLibraryTests/UndoOffersTests.swift](../../core/Tests/OortLibraryTests/UndoOffersTests.swift) | Annullare una volta, l’ultimo gesto soltanto, anche dal centro attività. |
| [core/Tests/OortLibraryTests/TipsTests.swift](../../core/Tests/OortLibraryTests/TipsTests.swift) | Un suggerimento una volta, uno per sessione, nessuno da spenti. |
| [core/Tests/OortLibraryTests/RecentSearchesTests.swift](../../core/Tests/OortLibraryTests/RecentSearchesTests.swift) | Ricerche recenti per profilo; errori e schermate vuote dicono cosa fare nelle sette lingue. |
| [engines/nxnative/Tests/NxnativeAdapterTests/AppSettingsStoreTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/AppSettingsStoreTests.swift) | Default e reset di Inbox, errori, recupero, nomi e ordine delle sezioni, chiavi correnti e del modulo, card Spotlight rimosse, ultima selezione in background e alla chiusura. |
| [core/Tests/OortLibraryTests/AppSettingsDraftTests.swift](../../core/Tests/OortLibraryTests/AppSettingsDraftTests.swift) | Anteprima, scarto, ordine nel riepilogo, merge senza perdita, conflitto, file illeggibile e interruzione prima della sostituzione. |
| [core/Tests/OortLibraryTests/OnlinePlayersDisplayTests.swift](../../core/Tests/OortLibraryTests/OnlinePlayersDisplayTests.swift) | Sedici combinazioni, migrazione delle quattro scelte precedenti, default, reset e catalogo. |
| [engines/nxnative/Tests/NxnativeAdapterTests/AppSizeCacheTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/AppSizeCacheTests.swift) | Riuso delle dimensioni, invalidazione sui bundle modificati e scansione senza falso stato vuoto. |
| [core/Tests/OortLibraryTests/AppUpdateTests.swift](../../core/Tests/OortLibraryTests/AppUpdateTests.swift) | Versioni, pagina mista per le prerelease, asset, requisiti, digest, identità del bundle e guasti di copia, scambio e Cestino. |
| [core/Tests/OortLibraryTests/AppUpdatePresentationTests.swift](../../core/Tests/OortLibraryTests/AppUpdatePresentationTests.swift) | Verifica che i controlli manuali non permettano sostituzioni di copie di sviluppo, in sola lettura o con una versione uguale/più recente. |
| [core/Tests/OortLibraryTests/ArcaneWelcomeTests.swift](../../core/Tests/OortLibraryTests/ArcaneWelcomeTests.swift) | Una volta dopo l'aggiornamento, mai dopo un primo Setup né con un recupero in corso, decodifica di un file vecchio, offerta di Steam, focus e uscite. |
| [core/Tests/OortLibraryTests/ShellOverlayInputTests.swift](../../core/Tests/OortLibraryTests/ShellOverlayInputTests.swift) | Ogni monitor della tastiera che cede all'offerta di aggiornamento cede anche al benvenuto, così Invio non arriva alla schermata sotto. Sotto il centro di controllo e la schermata profilo, schermata, Aggiungi gioco e console nascondono i propri suggerimenti. |
| [core/Tests/OortLibraryTests/ArcaneNameTests.swift](../../core/Tests/OortLibraryTests/ArcaneNameTests.swift) | Nessun testo del catalogo, in nessuna lingua, mostra il vecchio nome; User-Agent con il nome Arcane e nessuna sorgente con il vecchio. |
| [core/Tests/OortLibraryTests/ArtworkPickerFocusTests.swift](../../core/Tests/OortLibraryTests/ArtworkPickerFocusTests.swift) | Spostamenti nella griglia dei candidati e passaggi fra slot di artwork. |
| [engines/nxnative/Tests/NxnativeAdapterTests/ArtworkPickerTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/ArtworkPickerTests.swift) | Decodifica Title DB, candidati per slot e scelte manuali. |
| [core/Tests/OortLibraryTests/AutomaticIconTests.swift](../../core/Tests/OortLibraryTests/AutomaticIconTests.swift) | Priorità delle fonti, ambiguità, edizioni, cache offline, immagini invalide e opt-out del sito. |
| [core/Tests/OortLibraryTests/ArtworkStoreTests.swift](../../core/Tests/OortLibraryTests/ArtworkStoreTests.swift) | Cache, download, immagini trasparenti, ridimensionamento e fallback. |
| [engines/nxnative/Tests/NxnativeAdapterTests/BoxArtServiceTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/BoxArtServiceTests.swift) | Matching GameTDB, regioni e durata delle ricerche senza risultato. |
| [engines/nxnative/Tests/NxnativeAdapterTests/BuildCommandBuilderTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/BuildCommandBuilderTests.swift) | Contratto CLI, override Metal, flag e ambiente Nextendo e compatibilità dei record precedenti. |
| [engines/nxnative/Tests/NxnativeAdapterTests/BuildEventParserTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/BuildEventParserTests.swift) | Eventi JSON, fasi, percentuali e righe ordinarie di log. |
| [engines/nxnative/Tests/NxnativeAdapterTests/BuildOutputInstallerTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/BuildOutputInstallerTests.swift) | Pubblicazione atomica, interruzioni, tentativi ripetuti, copie fra volumi e conservazione dei bundle in caso di errore. |
| [engines/nxnative/Tests/NxnativeAdapterTests/BuildScratchTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/BuildScratchTests.swift) | Posto dei file di build per Mac, disco esterno, exFAT e workspaces spostati; workspace gestiti e cartelle temporanee. |
| [engines/nxnative/Tests/NxnativeAdapterTests/BuildServiceTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/BuildServiceTests.swift) | Processi, eventi, cancellazione con verifica della fine dei figli, lease e conservazione della build dopo un errore d’installazione o profili illeggibili, con retry senza nuova esecuzione del motore. |
| [core/Tests/OortLibraryTests/SystemCommandRunnerTests.swift](../../core/Tests/OortLibraryTests/SystemCommandRunnerTests.swift) | Un comando atteso, sincrono o in streaming, non fa girare il run loop mentre aspetta. |
| [core/Tests/OortLibraryTests/CommandRunnerTests.swift](../../core/Tests/OortLibraryTests/CommandRunnerTests.swift) | Verifica stdout e stderr tardivi, guardia dopo l’uscita, attesa senza run loop, protezione delle pipe da exec estranei, annullamento, scadenze e progresso reale. |
| [core/Tests/OortLibraryTests/RcloneListingTests.swift](../../core/Tests/OortLibraryTests/RcloneListingTests.swift) | Letture raggruppate e uniche, ambito prima e dopo, ambiguità, annullamento, rclone meno recenti, rifiuto di ogni scrittura. |
| [core/Tests/OortLibraryTests/LibraryRefreshTests.swift](../../core/Tests/OortLibraryTests/LibraryRefreshTests.swift) | Esiti, parti non aggiornate, risposte tardive e posizione della riga. |
| [core/Tests/OortLibraryTests/RcloneStorageBackendTests.swift](../../core/Tests/OortLibraryTests/RcloneStorageBackendTests.swift) | Binario, oggetti, impronte, avanzamento e annullamento; prefissi assenti o vuoti; Drive configurato e ID esatto per il riferimento in sola lettura; demone lento ad avviarsi e pulizia concorrente alla creazione. |
| [VolumeSpaceTests.swift](../../core/Tests/OortLibraryTests/VolumeSpaceTests.swift) | Ripiego per lo zero di exFAT, cartella non ancora creata e disco reale facoltativo. |
| [core/Tests/OortLibraryTests/RcloneDownloadTests.swift](../../core/Tests/OortLibraryTests/RcloneDownloadTests.swift) | Trasporto locale e archivi sintetici: rifiuti, annullamento, firma, pubblicazione atomica e protezione delle copie altrui. |
| [core/Tests/OortLibraryTests/RcloneConfigurationTests.swift](../../core/Tests/OortLibraryTests/RcloneConfigurationTests.swift) | Preferenze, comandi OAuth, cifratura e recuperi tipizzati con runner finto; prova stdin su una configurazione rclone temporanea; senza configurazione o portachiavi reali. |
| [core/Tests/OortLibraryTests/CloudSetupAssistantTests.swift](../../core/Tests/OortLibraryTests/CloudSetupAssistantTests.swift) | Bozza, verifica, formato dell’ID client, focus iniziale, colonna dei passi e Tab. |
| [core/Tests/OortLibraryTests/ActionBarOrderTests.swift](../../core/Tests/OortLibraryTests/ActionBarOrderTests.swift) | Ordine dei tasti e tasto acceso. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CloudGameArchiveTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CloudGameArchiveTests.swift) | App firmata sintetica e cache con rclone finto o locale: invio incrementale, manifest intermedio visibile dal riferimento, annullamento, riuso della cache locale, migrazione `.aar` e importazione con conflitti nei percorsi dichiarati. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CloudReadingTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CloudReadingTests.swift) | Numero di richieste per 1 e 40 giochi, schede conservate, sostituite o danneggiate, interruzioni; una lettura non decide e non scrive. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CloudArchiveListingTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CloudArchiveListingTests.swift) | Doppioni Drive con ID distinti, varianti di maiuscole e Unicode, rifiuto prima di Send o lettura e importazione senza falsi assenti. |
| [engines/nxnative/Tests/NxnativeAdapterTests/GameAppDestinationTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/GameAppDestinationTests.swift) | Installazione e scoperta nella cartella scelta, rebuild dopo il cambio cartella, conflitti di nome, sorgenti protette e cartelle non disponibili o di sola lettura. |
| [core/Tests/OortLibraryTests/ButtonPromptsTests.swift](../../core/Tests/OortLibraryTests/ButtonPromptsTests.swift) | Etichette e simboli per tastiera, controller e scelte esplicite dell’utente. |
| [core/Tests/OortLibraryTests/InputInHandTests.swift](../../core/Tests/OortLibraryTests/InputInHandTests.swift) | Ultimo dispositivo usato, urti del mouse, movimento reale e attesa dopo un tasto. |
| [core/Tests/OortLibraryTests/LaunchExitTests.swift](../../core/Tests/OortLibraryTests/LaunchExitTests.swift) | Attesa, azione accettata e precedenza della schermata di avvio. |
| [core/Tests/OortLibraryTests/ClickableHintsTests.swift](../../core/Tests/OortLibraryTests/ClickableHintsTests.swift) | Suggerimenti cliccabili nelle schermate iniziali, nello spostamento e nelle catture. |
| [core/Tests/OortLibraryTests/RailScrollTests.swift](../../core/Tests/OortLibraryTests/RailScrollTests.swift) | Passi, direzione, scatti, pausa e asse della rotella sulle righe. |
| [core/Tests/OortLibraryTests/SafeDefaultsTests.swift](../../core/Tests/OortLibraryTests/SafeDefaultsTests.swift) | Schermate che si aprono da sole: Indietro nel primo avvio e scelta iniziale dell'aggiornamento. |
| [core/Tests/OortLibraryTests/VocabularyTests.swift](../../core/Tests/OortLibraryTests/VocabularyTests.swift) | Parole del contratto: Rimuovi e Elimina, Spotlight, compilazione. |
| [core/Tests/OortLibraryTests/OnScreenKeyboardTests.swift](../../core/Tests/OortLibraryTests/OnScreenKeyboardTests.swift) | Caratteri disponibili, maiuscole, focus e cambio pagina della tastiera a schermo. |
| [core/Tests/OortLibraryTests/SettingsResetQuestionTests.swift](../../core/Tests/OortLibraryTests/SettingsResetQuestionTests.swift) | Domanda prima di ogni ripristino di gruppo e suo testo. |
| [core/Tests/OortCoreTests/ControllerInputTests.swift](../../core/Tests/OortCoreTests/ControllerInputTests.swift) | Report Nintendo sintetici, calibrazione, transizioni e precedenza di GameController. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CheatCopyTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CheatCopyTests.swift) | Testi di intestazione, rifiuto, conferma e rimozione dei cheats. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CheatFileTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CheatFileTests.swift) | Parsing dei codici secondo il motore, sezioni, metadati, nomi duplicati e codici non validi. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CheatInstallTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CheatInstallTests.swift) | Build ID, title ID, file senza nome, cartelle e decisioni di installazione. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CheatLocatorTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CheatLocatorTests.swift) | Identità nel bundle e precedenza dei percorsi cheats e delle variabili del launcher. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CheatStatusTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CheatStatusTests.swift) | Ancestry del motore, necessità di rebuild, valore della riga e indicatore attivo. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CheatStoreTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CheatStoreTests.swift) | Installazione, enabled, master switch, sostituzione e ripristino se il Cestino rifiuta il set. |
| [engines/nxnative/Tests/NxnativeAdapterTests/ModStoreTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/ModStoreTests.swift) | Overlay (anche dopo errore di scrittura), conflitti, omonimi fra RomFS ed ExeFS, Cestino e gruppo ExeFS escluso in Online o con selezione illeggibile. |
| [engines/nxnative/Tests/NxnativeAdapterTests/ModFolderScannerTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/ModFolderScannerTests.swift) | Voci della cartella mods, layout `romfs`/Atmosphère, symlink, file relativi e file nascosti. |
| [engines/nxnative/Tests/NxnativeAdapterTests/EnvFileEditorTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/EnvFileEditorTests.swift) | Modifica di una chiave dell'`env.txt`: commenti, duplicati, CRLF, merge al lancio. |
| [engines/nxnative/Tests/NxnativeAdapterTests/GameBananaAPITests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/GameBananaAPITests.swift) | Decodifica tollerante delle risposte, URL, host fidati, contenuto degli archivi e testo dalle descrizioni. |
| [engines/nxnative/Tests/NxnativeAdapterTests/GameBananaClientTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/GameBananaClientTests.swift) | User-Agent, durata della cache, rete assente, errori del server, limite di richieste e cache immagini. |
| [engines/nxnative/Tests/NxnativeAdapterTests/GameBananaBandModelTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/GameBananaBandModelTests.swift) | Cambio di gioco, avanzi di installazione, ricerca per nome con controller, mod in due gruppi con l'arte pronta. |
| [core/Tests/OortLibraryTests/TextScrollTests.swift](../../core/Tests/OortLibraryTests/TextScrollTests.swift) | Descrizione dopo Read more, limiti dello scorrimento, riga mostrata intera e passo Su/Giù tra le righe. |
| [engines/nxnative/Tests/NxnativeAdapterTests/GameBananaMatchTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/GameBananaMatchTests.swift) | Abbinamento per nome, voci per piattaforma e memoria della scelta. |
| [engines/nxnative/Tests/NxnativeAdapterTests/ModSupportTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/ModSupportTests.swift) | Quali archivi funzionano, radice `romfs`, title ID, visibilità e nomi di cartella. |
| [engines/nxnative/Tests/NxnativeAdapterTests/AvailableModsFinderTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/AvailableModsFinderTests.swift) | Mod che funzionano in ordine, limiti di ricerca, rete assente e aggiornamenti. |
| [engines/nxnative/Tests/NxnativeAdapterTests/ModInstallerTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/ModInstallerTests.swift) | Installazione con archivi veri: MD5, percorsi pericolosi, mod di codice, errori, gioco aperto, spazio, nomi, aggiornamenti. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CloudSavesTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CloudSavesTests.swift) | Cartelle cloud, preferenze per gioco e decodifica delle impostazioni precedenti. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CompatibilityCheckerTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CompatibilityCheckerTests.swift) | Commit, modifiche ammesse nel checkout, Metal, CLI e override del gate. |
| [core/Tests/OortLibraryTests/ConnectivityWatcherTests.swift](../../core/Tests/OortLibraryTests/ConnectivityWatcherTests.swift) | Solo il passaggio da offline a online conta come ritorno della connessione; la prima lettura no. |
| [core/Tests/OortLibraryTests/DetailsFocusTests.swift](../../core/Tests/OortLibraryTests/DetailsFocusTests.swift) | Spostamento nelle bande di Details, limiti e sezioni vuote. |
| [core/Tests/OortLibraryTests/DirectorySizeTests.swift](../../core/Tests/OortLibraryTests/DirectorySizeTests.swift) | Somma dei file regolari ignorando nascosti e collegamenti; cartella mancante a zero. |
| [core/Tests/OortLibraryTests/DiagnosticsReportTests.swift](../../core/Tests/OortLibraryTests/DiagnosticsReportTests.swift) | Rimozione di percorsi personali e chiavi e contenuto delle sezioni diagnostiche. |
| [core/Tests/OortLibraryTests/LibraryPathsTests.swift](../../core/Tests/OortLibraryTests/LibraryPathsTests.swift) | Copia e riparazione dei percorsi su cartelle sintetiche: URL, accenti composti e decomposti, altro account, lock, interruzioni, rimozione in sospeso e collegamenti morti. |
| [core/Tests/OortLibraryTests/DowngradeCheckpointTests.swift](../../core/Tests/OortLibraryTests/DowngradeCheckpointTests.swift) | Prova avviso singolo, verifica, rotazione, conservazione dei file essenziali al limite, link rifiutati e dati esclusi. |
| [engines/nxnative/Tests/NxnativeAdapterTests/EngineLocationTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/EngineLocationTests.swift) | Percorso predefinito, cartella scelta e fallback quando scompare. |
| [engines/nxnative/Tests/NxnativeAdapterTests/EngineToolchainTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/EngineToolchainTests.swift) | Rilevamento del runtime incluso e fallback a Python e strumenti del checkout. |
| [engines/nxnative/Tests/NxnativeAdapterTests/EnvironmentTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/EnvironmentTests.swift) | Parsing di Metal e controlli dell’ambiente mediante runner sintetico. |
| [core/Tests/OortCoreTests/FocusIndexTests.swift](../../core/Tests/OortCoreTests/FocusIndexTests.swift) | Movimento limitato agli elementi della lista e liste vuote. |
| [engines/nxnative/Tests/NxnativeAdapterTests/GameDetailPresentationTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/GameDetailPresentationTests.swift) | Disponibilità di build e sorgenti e formattazione di metadati e azioni Details. |
| [engines/nxnative/Tests/NxnativeAdapterTests/GameResourceStateTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/GameResourceStateTests.swift) | App spostata e ripristinata, input assenti, Play senza sorgenti e conservazione di workspace e build attive durante Refresh. |
| [engines/nxnative/Tests/NxnativeAdapterTests/GameOptionsPresentationTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/GameOptionsPresentationTests.swift) | Ordine, focus e capacità della build, incluse le righe multigiocatore e RomFS. |
| [engines/nxnative/Tests/NxnativeAdapterTests/GameRuntimeConfigTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/GameRuntimeConfigTests.swift) | Review di giochi nuovi ed esistenti, persistenza con plist temporaneo, lingua del rebuild e conversione DM_* con merge di env.txt. |
| [engines/nxnative/Tests/NxnativeAdapterTests/GameTDBTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/GameTDBTests.swift) | Database, normalizzazione dei nomi, regioni e matching delle copertine. |
| [core/Tests/OortCoreTests/HoldDetectorTests.swift](../../core/Tests/OortCoreTests/HoldDetectorTests.swift) | Soglia temporale e distinzione fra pressione breve e prolungata. |
| [engines/nxnative/Tests/NxnativeAdapterTests/ImportServiceTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/ImportServiceTests.swift) | Identità, firma originale o di ripiego senza cloud, spazio, riparazione, rifiuto di sidecar non sicuri, conflitto, modifica dopo l'anteprima e rollback. |
| [core/Tests/OortLibraryTests/CursorIdleTests.swift](../../core/Tests/OortLibraryTests/CursorIdleTests.swift) | Ritardo del cursore, ripristino e ripartenza dopo interruzione o attività del mouse. |
| [engines/nxnative/Tests/NxnativeAdapterTests/InstallProgressTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/InstallProgressTests.swift) | Fasi Git, percentuali e byte. |
| [core/Tests/OortCoreTests/LineBufferTests.swift](../../core/Tests/OortCoreTests/LineBufferTests.swift) | Ricomposizione delle righe parziali e separatori dei progressi. |
| [core/Tests/OortCoreTests/CreditsTests.swift](../../core/Tests/OortCoreTests/CreditsTests.swift) | Autori, gruppi per sistema, lingue e immagini permesse dei crediti. |
| [engines/nxnative/Tests/NxnativeAdapterTests/KeyCheckTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/KeyCheckTests.swift) | Cifratura e lettura di intestazioni sintetiche, intervalli troncati e chiavi richieste dalle sorgenti. |
| [engines/nxnative/Tests/NxnativeAdapterTests/KeyStoreTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/KeyStoreTests.swift) | Importazione e sostituzione atomica, conservazione della copia precedente anche con header malformato, permessi 0600 e riepilogo. |
| [engines/nxnative/Tests/NxnativeAdapterTests/LaunchServiceTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/LaunchServiceTests.swift) | Processo fittizio, impostazioni runtime e profilo, ambiente ereditato senza segreti, Home e overlay, permessi e pulizia dello snapshot; capacità, ripiego e override dello schermo. |
| [PlayAttributionTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/PlayAttributionTests.swift) | Condizioni minime per attribuire al gesto il nuovo processo esatto. |
| [engines/nxnative/Tests/NxnativeAdapterTests/HomeQuitTextTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/HomeQuitTextTests.swift) | Domanda di uscita del gioco nella lingua del giocatore, riga per riga. |
| [PlayersLaunchTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/PlayersLaunchTests.swift) | Bundle sintetici per prove motore, precedenze, fusione P1/P2–P8, ordine e profili di gioco. |
| [engines/nxnative/Tests/NxnativeAdapterTests/HomeMenuTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/HomeMenuTests.swift) | Capacità e ambiente del bundle, stati e segnale al solo figlio sintetico. |
| [engines/nxnative/Tests/NxnativeAdapterTests/LauncherSettingsTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/LauncherSettingsTests.swift) | Metadati launcher.json e fallback dei controlli per build precedenti. |
| [core/Tests/OortLibraryTests/LaunchBoxArtTests.swift](../../core/Tests/OortLibraryTests/LaunchBoxArtTests.swift) | Risultati di ricerca, scelta della voce Switch/Switch 2, payload Nuxt con file pieni e screenshot. |
| [engines/nxnative/Tests/NxnativeAdapterTests/LibraryPresentationTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/LibraryPresentationTests.swift) | Formattazione dei metadati e delle statistiche della libreria. |
| [engines/nxnative/Tests/NxnativeAdapterTests/LibraryQueryTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/LibraryQueryTests.swift) | Filtri, ricerca, ordinamento e rapporto con la cronologia di gioco. |
| [engines/nxnative/Tests/NxnativeAdapterTests/NXNativeCatalogPersistenceTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/NXNativeCatalogPersistenceTests.swift) | Persistenza e merge nxnative, ripresa e copia senza eseguire rimozioni o build ereditate; staging esterno preservato e nuova build ancora in coda. |
| [core/Tests/OortLibraryTests/MaterialIconTests.swift](../../core/Tests/OortLibraryTests/MaterialIconTests.swift) | Integrità dei glifi e del font delle icone. |
| [engines/nxnative/Tests/NxnativeAdapterTests/MetadataPickerTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/MetadataPickerTests.swift) | Alternative per campo, override persistiti e applicazione ai metadati del gioco. |
| [core/Tests/OortCoreTests/MoonlightFieldTests.swift](../../core/Tests/OortCoreTests/MoonlightFieldTests.swift) | Generazione deterministica e limiti dei dati delle particelle. |
| [MoonlightAppearanceTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/MoonlightAppearanceTests.swift) | Ignora la preferenza storica delle particelle senza perdere altri valori; continuità del ciclo e bordi della griglia colori. |
| [engines/nxnative/Tests/NxnativeAdapterTests/MoreArtworkSourcesTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/MoreArtworkSourcesTests.swift) | Matching dei titoli e risposte delle sorgenti artwork aggiuntive. |
| [engines/nxnative/Tests/NxnativeAdapterTests/MoreLikeThisTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/MoreLikeThisTests.swift) | Ranking condiviso, precedenza Steam e ripiego Switch, giochi nascosti e metadati incompleti. |
| [engines/nxnative/Tests/NxnativeAdapterTests/NintendoStoreMetadataTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/NintendoStoreMetadataTests.swift) | Decodifica store e Title DB, cache, screenshot e risposte incomplete della fonte Arcane. |
| [engines/nxnative/Tests/NxnativeAdapterTests/SwitchGameMetadataServiceTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SwitchGameMetadataServiceTests.swift) | Priorità Arcane per campo, richiesta pubblica Europe, prodotto base, lingue, cache e ripieghi. |
| [core/Tests/OortLibraryTests/ReleaseNotesLayoutTests.swift](../../core/Tests/OortLibraryTests/ReleaseNotesLayoutTests.swift) | Titoli, voci e righe vuote delle note di release, una voce per riga. |
| [engines/nxnative/Tests/NxnativeAdapterTests/NewestEngineTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/NewestEngineTests.swift) | Lock e Metal di main, validità della scelta, comandi git del cambio, gate Newest engine, scheda Setup e frase. |
| [engines/nxnative/Tests/NxnativeAdapterTests/NUPSourceCatalogTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/NUPSourceCatalogTests.swift) | NUP storici, multiprogramma e soli update; identità DLC, JSON, capacità checkout, programma zero nei vecchi record e argv coerenti. |
| [engines/nxnative/Tests/NxnativeAdapterTests/NXNativeGameSettingsTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/NXNativeGameSettingsTests.swift) | Migrazione da un plist temporaneo, precedenza di `env.txt`, scelta VPN, ripiego locale e tutte le scelte runtime macOS con ambiente filtrato. |
| [engines/nxnative/Tests/NxnativeAdapterTests/NextendoLaunchTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/NextendoLaunchTests.swift) | Online solo per build compatibili, ordine e focus di Play, presenza di Favorite, Search e blocco senza sessione. |
| [engines/nxnative/Tests/NxnativeAdapterTests/NextendoAccountServiceTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/NextendoAccountServiceTests.swift) | Account, liste, stati di presenza e rinnovo OAuth con trasporto finto, messaggi diagnostici, verifiche Discord ed e-mail e annullamento. |
| [engines/nxnative/Tests/NxnativeAdapterTests/NextendoOnlineCountsTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/NextendoOnlineCountsTests.swift) | Verifica assenza di richieste senza token o con tutti gli interruttori spenti, normalizzazione, collisioni, zeri e forma del conteggio. |
| [engines/nxnative/Tests/NxnativeAdapterTests/NextendoOAuthTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/NextendoOAuthTests.swift) | PKCE RFC 7636, callback, scambio e rotazione sintetici, scadenza ed errore temporaneo. |
| [engines/nxnative/Tests/NxnativeAdapterTests/NextendoTokenStoreTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/NextendoTokenStoreTests.swift) | Permessi, sostituzione atomica, flock POSIX, annullamento, disconnessione e link rifiutati. |
| [engines/nxnative/Tests/NxnativeAdapterTests/OnlineArtworkSourcesTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/OnlineArtworkSourcesTests.swift) | Ricerca Steam e loghi MediaWiki/Commons con risposte sintetiche. |
| [core/Tests/OortLibraryTests/OnlineBackgroundsTests.swift](../../core/Tests/OortLibraryTests/OnlineBackgroundsTests.swift) | Parser degli sfondi fissi, risoluzioni, crediti e nomi dei download. |
| [core/Tests/OortLibraryTests/OnlineLiveSourcesTests.swift](../../core/Tests/OortLibraryTests/OnlineLiveSourcesTests.swift) | Parser e indirizzi dei provider di sfondi video. |
| [engines/nxnative/Tests/NxnativeAdapterTests/PendingInstallTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/PendingInstallTests.swift) | Staging, rifiuto di un bundle estraneo con record vecchio, ripresa a destinazione libera e riconoscimento dopo pubblicazione. |
| [engines/nxnative/Tests/NxnativeAdapterTests/LibraryPathsPortingTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/LibraryPathsPortingTests.swift) | Riparazione e prima conversione di una libreria copiata: percorsi aggiornati, input legacy principale o di backup intatto e catalogo riapribile. |
| [engines/nxnative/Tests/NxnativeAdapterTests/PlaySessionStoreTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/PlaySessionStoreTests.swift) | Persistenza atomica di storico e totali, import dei file precedenti senza sovrascriverli, conservazione dei dati illeggibili, durata, heartbeat, riconciliazione e bundle ID. |
| [core/Tests/OortLibraryTests/LocalProfileStoreTests.swift](../../core/Tests/OortLibraryTests/LocalProfileStoreTests.swift) | Migrazione, profilo corrente, protezione del profilo originale, dati illeggibili e attribuzione al profilo che avvia il gioco. |
| [core/Tests/OortLibraryTests/PlayerPlanTests.swift](../../core/Tests/OortLibraryTests/PlayerPlanTests.swift) | Posti, accesso ai profili, identità ambigue e conferme dei controller. |
| [core/Tests/OortLibraryTests/PlayerPlanStoreTests.swift](../../core/Tests/OortLibraryTests/PlayerPlanStoreTests.swift) | Persistenza e conservazione dei campi sconosciuti; rifiuto dei documenti non validi. |
| [core/Tests/OortLibraryTests/PlayerLaunchEnvironmentTests.swift](../../core/Tests/OortLibraryTests/PlayerLaunchEnvironmentTests.swift) | Modalità di lancio, capacità dichiarate, precedenza di `env.txt` e limiti del nickname. |
| [core/Tests/OortCoreTests/ProfileKeypadTests.swift](../../core/Tests/OortCoreTests/ProfileKeypadTests.swift) | Navigazione, cancellazione, zero iniziale e lunghezza del PIN fornita dal chiamante. |
| [core/Tests/OortCoreTests/PaletteTests.swift](../../core/Tests/OortCoreTests/PaletteTests.swift) | Accenti, errori, ordine, gruppi, focus e recenti di Cerca ovunque. |
| [core/Tests/OortLibraryTests/PaletteActionTests.swift](../../core/Tests/OortLibraryTests/PaletteActionTests.swift) | Sezioni, scorciatoie, traduzioni e recenti per profilo di Cerca ovunque. |
| [core/Tests/OortLibraryTests/ProfileLayersTests.swift](../../core/Tests/OortLibraryTests/ProfileLayersTests.swift) | In ogni stato un solo strato della schermata profilo riceve l’input e mostra i suggerimenti; la procedura guidata sostituisce il selettore. |
| [engines/nxnative/Tests/NxnativeAdapterTests/PortedGameTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/PortedGameTests.swift) | Modello del gioco, compatibilità dei record, disponibilità dell’app e selezione delle ultime compilazioni riuscite. |
| [engines/nxnative/Tests/NxnativeAdapterTests/PortingFailureReasonTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/PortingFailureReasonTests.swift) | Classificazione dei fallimenti, distinzione fra avvio di Python e chiavi, e corrispondenza con i messaggi del pin (anche con NX_TEST_ENGINE_REPO). |
| [engines/nxnative/Tests/NxnativeAdapterTests/PortingNoticeTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/PortingNoticeTests.swift) | Condizioni e testi delle notifiche di esito del porting. |
| [engines/nxnative/Tests/NxnativeAdapterTests/PortingPresentationTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/PortingPresentationTests.swift) | ETA, prewarm, tile, fallimenti del porting e posizione e focus della pill Cloud. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CloudGameSourcesTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CloudGameSourcesTests.swift) | Scoperta con solo metadati, radici isolate, errori e rifiuti; voci solo remote, esclusioni, Unfollow, spazio, conflitti, lease e Cestino sintetico. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CloudTransferQueueTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CloudTransferQueueTests.swift) | Persistenza, ordine, vecchie richieste con `offer`, errori di scrittura e marcatore di pausa volontaria valido solo in testa. |
| [PersonalAppReceiptTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/PersonalAppReceiptTests.swift) | Ricevuta personale, origine, revisione, cambiamenti nell’app e stima dei byte. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CloudTransferPresentationTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CloudTransferPresentationTests.swift) | Stati e azioni, misura esclusiva per superficie, movimento ridotto e punto d'ingresso unico. |
| [engines/nxnative/Tests/NxnativeAdapterTests/BuildQueueTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/BuildQueueTests.swift) | FIFO, ripristino, voci non valide, sorgenti mancanti, persistenza degli esiti e retry. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CloudDriveFoldersTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CloudDriveFoldersTests.swift) | Manifest e archivi su file temporanei: residui prima e dopo lo spostamento, identità cambiate, concorrenza e ripresa dopo risposte perse. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CloudDriveReadsTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CloudDriveReadsTests.swift) | Letture condivise, annullamento, e rifiuto di ogni scrittura. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CloudFolderDiscoveryTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CloudFolderDiscoveryTests.swift) | Cartelle trovate, tenute, proposte, spiegate e create. |
| [engines/nxnative/Tests/NxnativeAdapterTests/CloudAssistantNetworkTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CloudAssistantNetworkTests.swift) | Misura dell’assistente su un Drive sintetico lento, solo su richiesta. |
| [engines/nxnative/Tests/NxnativeAdapterTests/AppIconPreferenceTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/AppIconPreferenceTests.swift) | Ambito dell’icona: scelta esplicita, vecchie librerie, scansioni, persistenza e rebuild. |
| [engines/nxnative/Tests/NxnativeAdapterTests/AppIconProgressTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/AppIconProgressTests.swift) | Verifica che l'esito di un'icona mancante non sovrascriva il log o segnali una build fallita. |
| [engines/nxnative/Tests/NxnativeAdapterTests/IconLaunchWaitTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/IconLaunchWaitTests.swift) | Attesa Play: successo, errore, annullamento, gioco diverso e nuova firma in coda. |
| [engines/nxnative/Tests/NxnativeAdapterTests/PipelineArchiveProgressTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/PipelineArchiveProgressTests.swift) | Log obsoleti, righe incomplete, cache riusata, gruppi paralleli e GPU diverse. |
| [engines/nxnative/Tests/NxnativeAdapterTests/PortingProgressTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/PortingProgressTests.swift) | Aggregazione delle fasi, avanzamento monotono, peso degli shader e avvisi di archivio/prewarm. |
| [engines/nxnative/Tests/NxnativeAdapterTests/ProdKeysLocationsTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/ProdKeysLocationsTests.swift) | Selezione e validazione dei possibili percorsi delle chiavi. |
| [engines/nxnative/Tests/NxnativeAdapterTests/RunningGamesTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/RunningGamesTests.swift) | Associazione bundle ID, applicazioni aperte e voci della libreria. |
| [engines/nxnative/Tests/NxnativeAdapterTests/RyujinxSaveImportTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/RyujinxSaveImportTests.swift) | Contenitori e slot Ryujinx, identità del titolo e importazioni con strutture e destinazioni differenti. |
| [engines/nxnative/Tests/NxnativeAdapterTests/SaveLocationTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SaveLocationTests.swift) | Identificativi, percorsi sicuri, precedenze dell’ambiente e cloud effettivo. |
| [engines/nxnative/Tests/NxnativeAdapterTests/SaveOperationGateTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SaveOperationGateTests.swift) | Lease per titolo, esclusione updater, isolamento dei blocchi di recupero a I/O concluso. |
| [engines/nxnative/Tests/NxnativeAdapterTests/SavePresentationTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SavePresentationTests.swift) | Azioni e messaggi del pannello; distingue backup storico/completo e limite cloud. |
| [engines/nxnative/Tests/NxnativeAdapterTests/SaveSnapshotStoreTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SaveSnapshotStoreTests.swift) | Inventari, xattr, integrità dei backup, staging e selezione dei backup datati. |
| [MultiuserSaveTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/MultiuserSaveTests.swift) | Backup e restore utenti/registro, compatibilità storica, import circoscritti, fault injection e conservazione di dati cambiati da fuori. |
| [engines/nxnative/Tests/NxnativeAdapterTests/SaveTestHome.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SaveTestHome.swift) | Fixture condivisa che crea una home e un bundle sintetici in una directory temporanea dedicata. |
| [engines/nxnative/Tests/NxnativeAdapterTests/SaveTransactionTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SaveTransactionTests.swift) | Sostituzioni, interruzioni, rollback, modifiche esterne e compatibilità dei journal precedenti. |
| [core/Tests/OortLibraryTests/ScreenshotViewerStateTests.swift](../../core/Tests/OortLibraryTests/ScreenshotViewerStateTests.swift) | Indice, avanzamento e limiti del visualizzatore screenshot. |
| [core/Tests/OortLibraryTests/SeleneCanvasTests.swift](../../core/Tests/OortLibraryTests/SeleneCanvasTests.swift) | Scala, centratura e conversione delle unità del canvas. |
| [core/Tests/OortLibraryTests/SeleneImporterTests.swift](../../core/Tests/OortLibraryTests/SeleneImporterTests.swift) | Copia delle risorse Selene e risoluzione dei cue sonori. |
| [core/Tests/OortLibraryTests/SelenePaletteTests.swift](../../core/Tests/OortLibraryTests/SelenePaletteTests.swift) | Lettura delle 26 palette, valori RGB di Oort e blu, alternative Crystal/Flow, persistenza ID, ordine e fallback. |
| [engines/nxnative/Tests/NxnativeAdapterTests/SettingsCatalogTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SettingsCatalogTests.swift) | Ordine, ricerca (anche Hidden game apps, Home in gioco e Inbox), Advanced, Changed e reset, compresa la migrazione della preferenza ZeroTier. |
| [engines/nxnative/Tests/NxnativeAdapterTests/IntegrationOverviewTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/IntegrationOverviewTests.swift) | Distingue scansione vuota, lavoro e panne; controlla destinazioni esistenti, identità e ritorno del focus. |
| [engines/nxnative/Tests/NxnativeAdapterTests/SetupActionsTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SetupActionsTests.swift) | Pin facoltativo nel plist, comandi Git del Setup upstream e del fork, rispetto delle modifiche locali. |
| [engines/nxnative/Tests/NxnativeAdapterTests/SetupCheckTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SetupCheckTests.swift) | Stati e condizioni di riapertura del Setup, runtime con o senza bundle, errori chiavi ed esclusione dei checkout da Install all. |
| [engines/nxnative/Tests/NxnativeAdapterTests/SetupGridTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SetupGridTests.swift) | Bilanciamento delle righe e spostamento del focus fra le schede. |
| [engines/nxnative/Tests/NxnativeAdapterTests/FirstRunSetupTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/FirstRunSetupTests.swift) | Pagina iniziale, Porting, scelta Steam acceso/spento dopo interruzione, completamento e pulizia della scelta salvata, focus, scansione e ripresa. |
| [engines/nxnative/Tests/NxnativeAdapterTests/FirstRunFindingsTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/FirstRunFindingsTests.swift) | Steam assente, solo giochi Mac pronti, zero giochi, errore/parziale distinto da assenza, annullamento, app portate contate e conteggio ricevuto. |
| [core/Tests/OortLibraryTests/SmokeTests.swift](../../core/Tests/OortLibraryTests/SmokeTests.swift) | Importabilità e versione nominale del modulo Core. |
| [core/Tests/OortLibraryTests/WikipediaDescriptionTests.swift](../../core/Tests/OortLibraryTests/WikipediaDescriptionTests.swift) | Quando cercare Wikipedia (lingua dal testo, scelta del giocatore, scrittura cinese, testi corti), sitelink dell'entità giusta, introduzione e link, host rifiutati, cache ed errori di rete non salvati. |
| [core/Tests/OortLibraryTests/CriticRatingTests.swift](../../core/Tests/OortLibraryTests/CriticRatingTests.swift) | Abbinamenti esatti, metriche e piattaforme, stelle proporzionali, cache offline, richieste seriali/condivise, errori e annullamento delle valutazioni. |
| [engines/nxnative/Tests/NxnativeAdapterTests/IGDBRatingTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/IGDBRatingTests.swift) | Credenziali 0600 sintetiche, isolamento degli host, voti critica/utenti, rinnovo accesso, annullamento, cache offline e ripiego Wikidata. |
| [core/Tests/OortLibraryTests/IGDBMetadataTests.swift](../../core/Tests/OortLibraryTests/IGDBMetadataTests.swift) | Identità, ruoli, date precise per piattaforma, Steam, cache offline, retry, annullamento e token/coda condivisi. |
| [core/Tests/OortLibraryTests/DatabaseMetadataTests.swift](../../core/Tests/OortLibraryTests/DatabaseMetadataTests.swift) | Parser pubblici, identità/ambiguità, date, conteggio richieste, letture concorrenti, cache, annullamento, risposte errate e retry. |
| [engines/nxnative/Tests/NxnativeAdapterTests/SourceCatalogTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SourceCatalogTests.swift) | Fixture PFS0/CNMT e riconoscimento di base, aggiornamenti e DLC. |
| [engines/nxnative/Tests/NxnativeAdapterTests/GameInboxTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/GameInboxTests.swift) | Nomi, chiavi mancanti, metadati ambigui, collisioni, duplicati, copia interrotta, ritrovamento e Cestino simulato. |
| [engines/nxnative/Tests/NxnativeAdapterTests/EngineUpgradeSourcesTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/EngineUpgradeSourcesTests.swift) | Cartelle estratte, pacchetti multipli, collegamento per ID esatto, persistenza, bridge Python e restaging senza perdita di originali. |
| [core/Tests/OortLibraryTests/SpotlightPageTests.swift](../../core/Tests/OortLibraryTests/SpotlightPageTests.swift) | Estratti, precedenza e crediti del testo nella lingua del giocatore, e stati dello scorrimento. |
| [engines/nxnative/Tests/NxnativeAdapterTests/SpotlightRowTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SpotlightRowTests.swift) | Ordine, card, riordino delle tile, gioco avviato primo nell’ordine salvato e selezione Surprise. |
| [core/Tests/OortLibraryTests/SpotlightStateTests.swift](../../core/Tests/OortLibraryTests/SpotlightStateTests.swift) | Focus, selezione, filtri, azioni e spostamento delle tile Spotlight. |
| [core/Tests/OortLibraryTests/SpotlightPlatformsTests.swift](../../core/Tests/OortLibraryTests/SpotlightPlatformsTests.swift) | Conteggi, filtri, ordine, rimozione di piattaforme e cursore dell’anteprima. |
| [core/Tests/OortLibraryTests/SpotlightEntranceTests.swift](../../core/Tests/OortLibraryTests/SpotlightEntranceTests.swift) | Partenze, tempi di volo e dissolvenza, bordi, durata, messaggio vuoto, avanzamento degli effetti e fasi dell’entrata; interruttore e Riduci movimento. |
| [engines/nxnative/Tests/NxnativeAdapterTests/StorageManagerTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/StorageManagerTests.swift) | Misure per gioco, cache condivise e nascoste, pulizia selettiva, protezione di app/sorgenti/symlink, file incoerenti e volumi/cartelle non disponibili. |
| [core/Tests/OortLibraryTests/ThemePickerTests.swift](../../core/Tests/OortLibraryTests/ThemePickerTests.swift) | Navigazione della griglia, tab e selezione degli sfondi. |
| [engines/nxnative/Tests/NxnativeAdapterTests/ToolchainGateCopyTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/ToolchainGateCopyTests.swift) | Testi del gate per Metal certificato, precedente, successivo e altre cause di blocco. |
| [engines/nxnative/Tests/NxnativeAdapterTests/ToolchainRequirementsTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/ToolchainRequirementsTests.swift) | Versioni minime e identificativi degli asset Metal da scaricare. |
| [core/Tests/OortCoreTests/VersionNumberTests.swift](../../core/Tests/OortCoreTests/VersionNumberTests.swift) | Confronto numerico delle versioni. |
| [engines/nxnative/Tests/NxnativeAdapterTests/UpstreamCheckerTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/UpstreamCheckerTests.swift) | Changelog HTTP, cache e gestione degli errori del provider. |
| [engines/nxnative/Tests/NxnativeAdapterTests/UpstreamCopyTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/UpstreamCopyTests.swift) | Testi della riga upstream e adozione dei commit attraverso gli aggiornamenti dell’app. |
| [core/Tests/OortLibraryTests/WallpaperBrightnessTests.swift](../../core/Tests/OortLibraryTests/WallpaperBrightnessTests.swift) | Maschere e livelli di luminosità dello sfondo. |
| [core/Tests/OortLibraryTests/WallpaperCatalogTests.swift](../../core/Tests/OortLibraryTests/WallpaperCatalogTests.swift) | Catalogo dei file inclusi/importati, gruppi e tipi immagine/video. |
| [core/Tests/OortLibraryTests/WallpaperPlacementTests.swift](../../core/Tests/OortLibraryTests/WallpaperPlacementTests.swift) | Destinazione dello sfondo fra home e impostazioni. |
| [engines/nxnative/Tests/NxnativeAdapterTests/WorkspaceManagerTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/WorkspaceManagerTests.swift) | Collegamenti simbolici, collisioni fra sorgenti, cache conservata e link interrotti. |
| [engines/nxnative/Tests/NxnativeAdapterTests/AppIconWriterTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/AppIconWriterTests.swift) | Icona scelta scritta e ripristinata, originale ricordato anche se assente, ricostruzione dell’app, firma fallita senza modifiche, icona rifilata e opaca. |
| [core/Tests/OortLibraryTests/BackdropArtTests.swift](../../core/Tests/OortLibraryTests/BackdropArtTests.swift) | Arte tenuta fra un gioco e l’altro e mai fra card e gioco, dissolvenze sull’orologio come Core Animation, livelli coperti tolti e scorrimento rapido. |
| [core/Tests/OortLibraryTests/BoundedDownloadTests.swift](../../core/Tests/OortLibraryTests/BoundedDownloadTests.swift) | Blocchi raccolti fino al limite, corpo o lunghezza dichiarata oltre il limite rifiutati, nessun redirect, annullamento della lettura. |
| [engines/nxnative/Tests/NxnativeAdapterTests/DetailsFactsTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/DetailsFactsTests.swift) | Righe Details per Switch e Steam: ordine, valori mancanti o vuoti nascosti, mai la versione Steam, solo crediti durante il download, simboli. |
| [engines/nxnative/Tests/NxnativeAdapterTests/InstalledEngineVersionTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/InstalledEngineVersionTests.swift) | Plist e checkout sintetici: motore attuale, anteriore, successivo o ignoto; app mancante, file di gioco e precedenza del badge. |
| [engines/nxnative/Tests/NxnativeAdapterTests/DetailsReviewFixTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/DetailsReviewFixTests.swift) | Play costruisce un gioco non ancora costruito con le sorgenti; nome di cartella o volume letto una volta per URL. |
| [core/Tests/OortLibraryTests/EngineRuntimeRequirementsTests.swift](../../core/Tests/OortLibraryTests/EngineRuntimeRequirementsTests.swift) | Il runtime incluso porta ogni pacchetto Python che il motore fissato chiede (riga `pip install` del README e `tools.txt`). |
| [core/Tests/OortLibraryTests/GameFocusTests.swift](../../core/Tests/OortLibraryTests/GameFocusTests.swift) | Ritorno della libreria davanti solo per il gioco in primo piano, mai con un altro gioco aperto, uscita contata una volta. |
| [engines/nxnative/Tests/NxnativeAdapterTests/ModStoreModelTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/ModStoreModelTests.swift) | Store delle mod da copia fresca o vecchia, abbinamenti incerti o sicuri, ordine della libreria, copie di un altro gioco, chiusura senza perdite. |
| [engines/nxnative/Tests/NxnativeAdapterTests/SessionSummaryTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SessionSummaryTests.swift) | Card di fine sessione: gioco, sessione e totale, meno di un minuto, sessioni troppo brevi o in corso, altri giochi, giochi Steam. |
| [core/Tests/OortLibraryTests/SettingsRowButtonsTests.swift](../../core/Tests/OortLibraryTests/SettingsRowButtonsTests.swift) | Riga con due pulsanti: Sinistra/Destra fra i pulsanti, uscita dalla riga, riga con un solo pulsante, A preme quello in focus. |
| [core/Tests/OortLibraryTests/SpotlightRowGeometryTests.swift](../../core/Tests/OortLibraryTests/SpotlightRowGeometryTests.swift) | Posto a schermo = camera più posto nella riga, tessere che restano ferme durante lo scorrimento, distanze costanti e quattro tessere di riserva ai bordi. |
| [core/Tests/OortLibraryTests/TileMotionTests.swift](../../core/Tests/OortLibraryTests/TileMotionTests.swift) | Curve di bagliore, ring e riflesso; continuità a 60 Hz tra raffiche, pausa, verifica, riavvio e movimento ridotto. |
| [engines/nxnative/Tests/NxnativeAdapterTests/AppLocaleTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/AppLocaleTests.swift) | Preferenze, formati, traduzioni e nome Oort NX senza cambiare trofeo, argomenti o User-Agent. |
| [scripts/tests/PublicationChecks/test_check_guides.py](../../scripts/tests/PublicationChecks/test_check_guides.py) | Le guide pubblicate passano; ogni regola rifiuta il suo errore. |
| [scripts/tests/PublicationChecks/test_localizations.py](../../scripts/tests/PublicationChecks/test_localizations.py) | Rifiuto di cataloghi incompleti e bundle senza risorse. |
| [scripts/tests/PublicationChecks/test_vocabulary.py](../../scripts/tests/PublicationChecks/test_vocabulary.py) | Prova le regole del vocabolario, il registro che può solo ridursi e le fonti lette per sistema. |
| [DevelopmentProfileTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/DevelopmentProfileTests.swift) | Identità separate, copie e filtro dell’essai 2, sorgente intatta, symlink, sovrascrittura, sessioni e totali. |
| [DevelopmentProfileEffectTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/DevelopmentProfileEffectTests.swift) | Isolamento Dev, staging e richieste esplicite. Verifica anche che la riconciliazione delle mod conservi record e overlay dopo un errore di lettura. |
| [test_profile_boundaries.py](../../scripts/tests/PublicationChecks/test_profile_boundaries.py) | Guardia contro percorsi/defaults del launcher non centralizzati. |
| [SteamKeyValuesTests.swift](../../core/Tests/OortLibraryTests/SteamKeyValuesTests.swift) | Formato, escape, Unicode, duplicati, input troncati e limiti del parser. |
| [SteamPlaytimeReaderTests.swift](../../core/Tests/OortLibraryTests/SteamPlaytimeReaderTests.swift) | Campi letti, ultima partita, scelta dell’account, duplicati e tipi errati di blocchi/scalari, file grandi, malformati o non sicuri. |
| [SteamPlaytimeBaselinesTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SteamPlaytimeBaselinesTests.swift) | Base mantenuta o ripartita, minuto conservato, cambio account, salvataggio e mappatura sul catalogo. |
| [SteamReturnFocusTests.swift](../../core/Tests/OortLibraryTests/SteamReturnFocusTests.swift) | Ritorno ad Arcane solo per Play premuto qui, gioco davanti e nessun altro gioco aperto. |
| [SteamLaunchQuestionsTests.swift](../../core/Tests/OortLibraryTests/SteamLaunchQuestionsTests.swift) | Fase `ShowInterstitials` a freddo, domande aperte o risposte subito, log per righe intere e sostituzione del file. |
| [SteamPlaytimeSyncTests.swift](../../core/Tests/OortLibraryTests/SteamPlaytimeSyncTests.swift) | Letture con o senza account, file illeggibili, file invariato, regole di pubblicazione e coda delle letture. |
| [NativeMacApplicationTests.swift](../../core/Tests/OortLibraryTests/NativeMacApplicationTests.swift) | Fixture native, classificazione, traversal/link, metadata non regolari e header invalidi. |
| [SoundPackTests.swift](../../core/Tests/OortLibraryTests/SoundPackTests.swift) | Verifica manifesti, ZIP, limiti, link, copia controllata, eventi mancanti e persistenza della scelta. |
| [OortAmbianceTests.swift](../../core/Tests/OortLibraryTests/OortAmbianceTests.swift) | Copertura degli eventi, nomi nelle sette lingue, livello e picco, assenza di clic, carattere dei tre ambienti e note di Compose. |
| [SteamLibrarySourceTests.swift](../../core/Tests/OortLibraryTests/SteamLibrarySourceTests.swift) | Più fonti, dischi assenti, identità, manifest/path con campi duplicati o di tipo errato, file cambiati, limiti e assenza di scritture. |
| [SteamDiscoveryConsistencyTests.swift](../../core/Tests/OortLibraryTests/SteamDiscoveryConsistencyTests.swift) | Mutazioni reali di inventario e app durante scan, indice inizialmente assente, budget e propagazione dell'annullamento. |
| [SteamTestSupport.swift](../../core/Tests/OortLibraryTests/SteamTestSupport.swift) | Genera solo metadati e header sintetici nelle directory temporanee dei test. |
| [engines/nxnative/Tests/NxnativeAdapterTests/SteamTestSupport.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SteamTestSupport.swift) | Collegamento simbolico a `OortLibraryTests/SteamTestSupport.swift`: i test del modulo usano la stessa fixture Steam, da un solo file. |
| [SteamPlayStateTests.swift](../../core/Tests/OortLibraryTests/SteamPlayStateTests.swift) | Symlink, passaggio senza sessione, Play doppi e risposte tardive, rifiuti e timeout, giochi già aperti, argomenti silenziosi, pazienza di Steam a freddo e schermata di lancio. |
| [SteamBinaryKeyValuesTests.swift](../../core/Tests/OortLibraryTests/SteamBinaryKeyValuesTests.swift) | Tipi, annidamento, fine dei dati, input troncati, tipi ignoti e limiti del parser binario. |
| [SteamAchievementReaderTests.swift](../../core/Tests/OortLibraryTests/SteamAchievementReaderTests.swift) | Percorsi, account e file mancanti/non sicuri, lingue con ripiego anche su stringhe vuote duplicate, primo valore tipizzato, nascosti, icone, ordine numerico e file corrotti. |
| [SteamAchievementRarityTests.swift](../../core/Tests/OortLibraryTests/SteamAchievementRarityTests.swift) | Percentuali numeriche o testuali (non numeriche scartate), host e percorso ammessi, cache di un giorno, cache vecchia offline, icone in cache, coda oltre sei download con annullamento, errore recente senza attesa e file che non sono immagini. |
| [AchievementSummaryTests.swift](../../core/Tests/OortLibraryTests/AchievementSummaryTests.swift) | Conteggi, gioco completato, ordini dei filtri, rarità sconosciute in fondo, soglia del raro, maschera dei nascosti e icone recenti (segreti compresi). |
| [LocalAchievementTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/LocalAchievementTests.swift) | Fixture Zelda, soglie, versione e CRC, nessuna scrittura sul salvataggio, percorso `DM_SAVE`, persistenza per profilo con plist temporaneo e formato overlay. |
| [AchievementsScreenStateTests.swift](../../core/Tests/OortLibraryTests/AchievementsScreenStateTests.swift) | Movimento in due colonne, bordi, liste vuote, cambio filtro e liste che si accorciano. |
| [GridListLayoutTests.swift](../../core/Tests/OortLibraryTests/GridListLayoutTests.swift) | Linee, altezza, posizione delle righe, spazio da mostrare, linee visibili e riga in vista più vicina dopo la rotella. |
| [AchievementTierTests.swift](../../core/Tests/OortLibraryTests/AchievementTierTests.swift) | Soglie, tier dalla percentuale mostrata, ordine dal più raro, conteggi per tier, Arcane solo al 100% e mai senza achievement, miglior tier ottenuto, rarità sconosciuta. |
| [SteamManifestWatcherTests.swift](../../core/Tests/OortLibraryTests/SteamManifestWatcherTests.swift) | Filtri e durata dello stream; eventi reali da librerie tornate disponibili, da sole o accanto a una già osservata, inclusa la normalizzazione `/private`. |
| [CatalogPreservationTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CatalogPreservationTests.swift) | Giochi e fonti di un’integrazione sconosciuta: letti, invisibili, riscritti uguali, controlli di forma e duplicati, catalogo noto scritto come prima. |
| [CatalogModelTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CatalogModelTests.swift) | Conservazione del record precedente, proprietà comuni e separazione delle azioni per integrazione. |
| [CatalogStoreTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CatalogStoreTests.swift) | Conversione, backup, corruzione, versioni, input cambiati, scrittori concorrenti, guasti di pubblicazione e tipi noti disattivati in un nuovo profilo. |
| [MacShortcutTests.swift](../../core/Tests/OortLibraryTests/MacShortcutTests.swift) | Aggiunta e deduplicazione, persistenza, app spostate o sostituite, ricollegamento e rimozione con bundle sintetici compilati. |
| [MacShortcutProbe.swift](../../apps/mac/Tests/CatalogAppChecks/MacShortcutProbe.swift) | Sorgenti, libreria e dialoghi EN/FR fuori schermo; Play mediante Launch Services della sola fixture compilata, senza sessioni né modifiche al bundle. |
| [ControllerIdentityProbe.swift](../../apps/mac/Tests/CatalogAppChecks/ControllerIdentityProbe.swift) | Twin, duplicati HID/GameController, pressioni, identificazione, sospensione e riconnessione con sorgenti sintetiche; ripiego HID senza refresh manuale. |
| [Beta4InputScreens.swift](../../apps/mac/Tests/CatalogAppChecks/Beta4InputScreens.swift) | Sonda fuori schermo per annunci della ricerca, pulsante di chiusura dell'avvio e attività del cursore in finestra. |
| [run_beta4_input_screens.py](../../apps/mac/Tests/CatalogAppChecks/run_beta4_input_screens.py) | Esegue le sonde schermate e cattura il pulsante di chiusura del lancio inattivo. |
| [run_beta4_input_routing.py](../../apps/mac/Tests/CatalogAppChecks/run_beta4_input_routing.py) | Verifica i tasti della shell e il riavvio di prova con monitor e processo fittizi. |
| [SteamCatalogReconcilerTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SteamCatalogReconcilerTests.swift) | Identità, aggiornamenti, installazioni ambigue, fonti assenti e scansioni obsolete/parziali. |
| [CatalogTestSupport.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CatalogTestSupport.swift) | Record legacy sintetico completo e scrittura di fixture; nessun contenuto di gioco. |
| [CatalogRepositoryTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CatalogRepositoryTests.swift) | Modifiche concorrenti, confini per integrazione, campi build, conservazione Steam/legacy e import cloud del programma NUP esatto. |
| [CatalogRecoveryTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CatalogRecoveryTests.swift) | Recupero esplicito, conflitto legacy senza fusione, archivi, offerte obsolete, guasti di pubblicazione, restore point e importazione Dev. |
| [CatalogPersonalizationTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CatalogPersonalizationTests.swift) | Rinomina senza perdita del lookup e isolamento di chiavi uguali tra fonti. |
| [CatalogBuildRecoveryTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CatalogBuildRecoveryTests.swift) | Vecchia build persistita e nuova conservata, sospensione automatica e conferme obsolete. |
| [run_notices.py](../../apps/mac/Tests/CatalogAppChecks/run_notices.py) | Esegue il modello e i metodi reali degli avvisi e del ponte legacy senza finestre, dopo swift test. |
| [run_onscreen_keyboard.py](../../apps/mac/Tests/CatalogAppChecks/run_onscreen_keyboard.py) | Avvia la prova della tastiera a schermo su una home isolata. |
| [run_update_wait.py](../../apps/mac/Tests/CatalogAppChecks/run_update_wait.py) | Bundle di prova: conserva l'aggiornamento verificato mentre un gioco o un lease blocca; riprende dallo ZIP senza rete e rifiuta modifiche. |
| [run_review.py](../../apps/mac/Tests/CatalogAppChecks/run_review.py) | Verifica senza finestre achievement, loghi, focus, input del centro e di Integrations, badge mod in Online, priorità dei dialoghi e Steam durante Play. |
| [audit_probe_host.py](../../apps/mac/Tests/CatalogAppChecks/audit_probe_host.py) | Collega sonde headless al binario di debug; home temporanea, dominio delle preferenze proprio a ogni sonda e rimosso dopo, sandbox salvo la fixture locale di LaunchServices. |
| [run_native_play.py](../../apps/mac/Tests/CatalogAppChecks/run_native_play.py) | Costruisce un'app accessoria muta e prova il riaggancio in concorrenza nel percorso Play reale. |
| [NativePlayFixture.swift](../../apps/mac/Tests/CatalogAppChecks/NativePlayFixture.swift) | Témoin AppKit senza finestre o dati di gioco. |
| [NativePlayRace.swift](../../apps/mac/Tests/CatalogAppChecks/NativePlayRace.swift) | Intercala la fixture esterna prima della consegna e verifica zero storico e durata. |
| [run_platform_cards.py](../../apps/mac/Tests/CatalogAppChecks/run_platform_cards.py) | Lancia Spotlight isolato e conserva i PNG e, con ffmpeg, lo scorrimento video. |
| [run_credits.py](../../apps/mac/Tests/CatalogAppChecks/run_credits.py) | Apre About isolata, conserva i PNG e prova i crediti con il controller. |
| [CreditsProbe.swift](../../apps/mac/Tests/CatalogAppChecks/CreditsProbe.swift) | Host della prova di About: tre lingue, tutte le schede, ordine delle righe e destinazione localizzata del finanziamento con browser simulato. |
| [PlatformCardsProbe.swift](../../apps/mac/Tests/CatalogAppChecks/PlatformCardsProbe.swift) | Verifica input, filtro, chiusura e recupero su tre fonti, una fonte e libreria vuota; rende Spotlight in francese con sfondo chiaro. |
| [run_steam_disabled_tracking.py](../../apps/mac/Tests/CatalogAppChecks/run_steam_disabled_tracking.py) | Disattiva una fonte Steam sintetica, chiude una sessione già aperta e rifiuta una nuova osservazione. |
| [run_steam_scoped_playtime.py](../../apps/mac/Tests/CatalogAppChecks/run_steam_scoped_playtime.py) | Aggiorna le ore Steam dopo sessioni Switch secondarie, anche archiviate, e congela dopo una sessione Steam secondaria. |
| [run_keymap_screens.py](../../apps/mac/Tests/CatalogAppChecks/run_keymap_screens.py) | Verifica tabelle Oort e Arcane, suggerimenti e glifi; rende le barre Selene senza aprire finestre. |
| [run_inbox_screens.py](../../apps/mac/Tests/CatalogAppChecks/run_inbox_screens.py) | Verifica e rende Inbox, menu e card; controlla Inbox disattivata, riletture, duplicati e sorgenti collegate durante il triage con preferenze e Cestino simulati. |
| [run_cloud_screens.py](../../apps/mac/Tests/CatalogAppChecks/run_cloud_screens.py) | Verifica Cloud, coda, accesso Google, scoperta delle sorgenti, spostamento, glifi, Play together e schermo su fixture locali. Separa schermate, trasferimenti, giochi solo cloud e risultati incompleti in processi con directory e preferenze proprie. Condivide l’isolamento dell’avvio nelle copie di test. Verifica anche il fornitore e la selezione di Rebuild. `--compare-with-5047557` confronta la scheda con Riduci movimento. |
| [run_cloud_assistant.py](../../apps/mac/Tests/CatalogAppChecks/run_cloud_assistant.py) | Disegna impostazioni e assistente in finestre nascoste, poi va dall’account ai giochi con la sola tastiera, il solo puntatore e il solo controller. |
| [CloudAssistantProbe.swift](../../apps/mac/Tests/CatalogAppChecks/CloudAssistantProbe.swift) | La sonda: schermate, percorsi completi, riconnessione, nomi per VoiceOver. |
| [fake_rclone.py](../../apps/mac/Tests/CatalogAppChecks/fake_rclone.py) | rclone sintetico: una cartella risponde come Drive, con attesa e conteggio. |
| [run_library_refresh.py](../../apps/mac/Tests/CatalogAppChecks/run_library_refresh.py) | Aggiornamento sul modello reale: cloud spento, fuori rete, ripetuto, annullato (catalogo intatto, scansione indipendente riuscita), interrotto, cartella sostituita; catture facoltative in francese e inglese. |
| [fake_drive_rclone.py](../../apps/mac/Tests/CatalogAppChecks/fake_drive_rclone.py) | Finto rclone con `rcd` su socket Unix e un Drive in un file JSON. |
| [run_download_cloud.py](../../apps/mac/Tests/CatalogAppChecks/run_download_cloud.py) | Con una destinazione esplicita, verifica pixel, contrasto e compositing del download; video facoltativo a 60 Hz e tabella dei livelli reali e visivi. |
| [run_cloud_queue_pause.py](../../apps/mac/Tests/CatalogAppChecks/run_cloud_queue_pause.py) | Riapre una coda sintetica con pausa registrata e confronta le righe Attività in francese prima e dopo, senza backend. |
| [run_cloud_pause.py](../../apps/mac/Tests/CatalogAppChecks/run_cloud_pause.py) | Verifica la pausa e la ripresa esplicita dopo riavvio, ordine e controlli in Cloud e Attività con un backend sintetico. |
| [run_cloud_shelf.py](../../apps/mac/Tests/CatalogAppChecks/run_cloud_shelf.py) | Rende lo scaffale Cloud in francese e verifica gli stati vuoti, i titoli importati e il recupero nell’assistente con fixture. |
| [run_cloud_reference.py](../../apps/mac/Tests/CatalogAppChecks/run_cloud_reference.py) | Rende il dialogo del riferimento e la riga con accesso, senza accesso e in controllo, usando dati sintetici. |
| [run_cloud_free_space.py](../../apps/mac/Tests/CatalogAppChecks/run_cloud_free_space.py) | Rende la conferma di liberazione con selezioni e lo stato di verifica, senza toccare il Cestino. Identifica il PNG se Vision non riesce a leggerlo. |
| [run_store_next_step.py](../../apps/mac/Tests/CatalogAppChecks/run_store_next_step.py) | Rende le prossime azioni e gli stati passivi di Details in francese su dati sintetici. |
| [StoreNextStepText.swift](../../apps/mac/Tests/CatalogAppChecks/StoreNextStepText.swift) | Legge il testo del PDF della sonda Details, verifica testi, origine e assenze, e prova con `assertVisible` che i testi attesi si vedono. |
| [ProbeRenderedText.swift](../../apps/mac/Tests/CatalogAppChecks/ProbeRenderedText.swift) | Salva il PDF accanto al PNG e disegna subito, nello stesso stato, il fotogramma e la stessa vista con i testi oscurati; `assertVisible` prova dai pixel che un testo è nel riquadro, in primo piano e contrastato, con un autotest di quattro esempi rossi. |
| [probe_visible.py](../../apps/mac/Tests/CatalogAppChecks/probe_visible.py) | Collega `assertVisible` alla funzione di rendering di una sonda, con la soglia di contrasto del testo dei token. |
| [ocr/read.cjs](../../apps/mac/Tests/CatalogAppChecks/ocr/read.cjs) | Legge i PNG delle finestre AppKit nascoste con OCR su CPU e modelli locali. |
| [ocr/package.json](../../apps/mac/Tests/CatalogAppChecks/ocr/package.json), [ocr/package-lock.json](../../apps/mac/Tests/CatalogAppChecks/ocr/package-lock.json) | Dipendenze e integrità dei soli strumenti OCR di test. |
| [run_cloud_personal_update.py](../../apps/mac/Tests/CatalogAppChecks/run_cloud_personal_update.py) | Esercita l’offerta personale, la conferma e le copie sostituite o conservate tramite un cloud e bundle sintetici. |
| [run_settings_confirmations.py](../../apps/mac/Tests/CatalogAppChecks/run_settings_confirmations.py) | Lancia la sonda di Settings con dati, selettore rclone e preferenze sintetici. |
| [SettingsConfirmationProbe.swift](../../apps/mac/Tests/CatalogAppChecks/SettingsConfirmationProbe.swift) | Prova bozza, conferme, collegamento rclone, blocco di ⌘K e avvisi di avvio fuori schermo. |
| [run_settings_confirmations.py](../../apps/mac/Tests/CatalogAppChecks/run_settings_confirmations.py) | Lancia la sonda delle conferme in un processo con dati e preferenze propri, in francese e senza servizi reali. |
| [SettingsConfirmationProbe.swift](../../apps/mac/Tests/CatalogAppChecks/SettingsConfirmationProbe.swift) | Verifica la bozza e le conferme separate di Cloud/rclone/motore e rende Settings con sfondo e riepilogo in una finestra non mostrata. |
| [AttentionsProbe.swift](../../apps/mac/Tests/CatalogAppChecks/AttentionsProbe.swift) | Undo, ricerche recenti, ripristino di una riga, copia delle impostazioni e suggerimenti in fr, de, en; solo questa parte con `OORT_ATTENTIONS_ONLY=1` in `run_settings_confirmations.py`. |
| [run_integration_contract.py](../../apps/mac/Tests/CatalogAppChecks/run_integration_contract.py) | Controlla il collegamento di Integrations alle viste reali senza aprirle. |
| [run_profiles.py](../../apps/mac/Tests/CatalogAppChecks/run_profiles.py) | Rende profili, raccolte, impostazioni, primo avvio e PIN. Verifica focus da Integrations, alone, moto ridotto, salvataggi e ripresa di Play dopo scambio cloud, firma o conferma VPN. Prova i collegamenti Mac su richiesta, sempre con preferenze temporanee. |
| [run_startup_recovery.py](../../apps/mac/Tests/CatalogAppChecks/run_startup_recovery.py) | Coordinatore di avvio reale su profili sintetici: avviso prima della scrittura, copia non valida, prosecuzione solo per l’avvio corrente, conflitto legacy e Retry; nessuna finestra. |
| [run_downgrade.py](../../apps/mac/Tests/CatalogAppChecks/run_downgrade.py) | Con un checkout 0.3.0 e una destinazione espliciti, collega i binari Debug, confronta letture e riscritture e ripristina entrambe le versioni su dati sintetici; rende l’avviso su richiesta. |
| [DowngradeProbe.swift](../../apps/mac/Tests/CatalogAppChecks/DowngradeProbe.swift) | Verifica i lettori e gli scrittori effettivi su sessioni, impostazioni, profili, catalogo, integrazioni, coda e stato cloud e immagini. |
| [run_source_access.py](../../apps/mac/Tests/CatalogAppChecks/run_source_access.py) | Esegue avvio, observer, selettori e preparazione dei file in Add Game: scansione limitata, cartella ricordata e riconoscimento del percorso estratto. |
| [run_catalog_removal.py](../../apps/mac/Tests/CatalogAppChecks/run_catalog_removal.py) | Prova il Cestino con arresti, concorrenza, file sostituiti e alias. Due avvii del profilo 0.3.0 sintetico verificano anche la coda cloud e la build in attesa. |
| [run_onboarding.py](../../apps/mac/Tests/CatalogAppChecks/run_onboarding.py) | Prova ripresa e chiusura del tour oltre ai casi legacy di Steam, modali e notifiche; può rendere le viste in francese su due taglie. |
| [run_artwork_return.py](../../apps/mac/Tests/CatalogAppChecks/run_artwork_return.py) | Viste, task e host Mods reali su fixture: primo body con arte warm, scelte personali, aggiornamenti Steam nello stesso percorso, badge dopo rimozione, cambi abbinamento e snapshot completato fuori ordine; nessuna finestra o rendering. |
| [run_nested_bundles.py](../../apps/mac/Tests/CatalogAppChecks/run_nested_bundles.py) | App sintetiche con bundle dati annidati e firme reali: installazione, icona, rollback, copia forzata, ripresa e rifiuto di dati alterati; nessuna UI. |
| [run_nup_programs.py](../../apps/mac/Tests/CatalogAppChecks/run_nup_programs.py) | Esegue il probe NUP opzionale su snapshot sintetico, convertitori UI reali, persistenza e argv del rebuild. |
| [run_add_game_back.py](../../apps/mac/Tests/CatalogAppChecks/run_add_game_back.py) | Esegue le regole di Back e verifica che poco spazio per compilare non blocchi l'aggiunta alla libreria. Nessuna finestra. |
| [run_build_cache_thread.py](../../apps/mac/Tests/CatalogAppChecks/run_build_cache_thread.py) | Verifica che l’adozione della cache a fine porting non venga eseguita sul thread dell’interfaccia. |
| [run_build_gates.py](../../apps/mac/Tests/CatalogAppChecks/run_build_gates.py) | Verifica il cambio motore e i limiti di annullamento per installazione e spostamento nel centro attività. |
| [run_controller_identity.py](../../apps/mac/Tests/CatalogAppChecks/run_controller_identity.py) | Compila la verifica dei pad con il servizio effettivo e senza periferiche fisiche. |
| [run_players_screen.py](../../apps/mac/Tests/CatalogAppChecks/run_players_screen.py) | Prova focus e stati con controller sintetici; rende anche Giocatori aperto da Impostazioni e Opzioni con sfondi a contrasto. |
| [run_build_queue_engine.py](../../apps/mac/Tests/CatalogAppChecks/run_build_queue_engine.py) | Verifica il collegamento tra la fine del cambio motore e il risveglio della coda, anche quando il clone non produce un motore valido. |
| [run_guest_quit.py](../../apps/mac/Tests/CatalogAppChecks/run_guest_quit.py) | Esegue il veto durante l’adozione della cache, la conferma ospite e l’uscita con esiti sintetici. |
| [run_profile_collection_game.py](../../apps/mac/Tests/CatalogAppChecks/run_profile_collection_game.py) | Verifica la selezione dei giochi Switch e Steam nel menu nativo della Collection di un profilo. |
| [run_logo_cancellation.py](../../apps/mac/Tests/CatalogAppChecks/run_logo_cancellation.py) | Verifica il recupero del logo tornando prima che la ricerca annullata finisca, senza rete. |
| [run_metadata_preload.py](../../apps/mac/Tests/CatalogAppChecks/run_metadata_preload.py) | Verifica le letture fuori dal main thread, la pubblicazione sul main thread e lo scarto dei risultati dopo lo svuotamento (EN/FR). |
| [run_spotlight_notification_select.py](../../apps/mac/Tests/CatalogAppChecks/run_spotlight_notification_select.py) | Verifica la selezione da una notifica, anche chiudendo Add Game mentre è in corso un altro porting. |
| [run_sort_native_menu.py](../../apps/mac/Tests/CatalogAppChecks/run_sort_native_menu.py) | Verifica disponibilità e consegna di Gioca dal menu nativo con l’ordinamento aperto. |
| [run_empty_collection_input.py](../../apps/mac/Tests/CatalogAppChecks/run_empty_collection_input.py) | Invia comandi di navigazione alla Collection vuota e verifica Aggiungi gioco e Importa build esistenti. |
| [run_hero_cache_budget.py](../../apps/mac/Tests/CatalogAppChecks/run_hero_cache_budget.py) | Verifica che le cache degli sfondi ricevano i byte decodificati e abbiano un limite di costo. |
| [run_collection_query_count.py](../../apps/mac/Tests/CatalogAppChecks/run_collection_query_count.py) | Conta le valutazioni della query di Collection con una selezione Switch su 300 giochi sintetici. |
| [run_save_restart.py](../../apps/mac/Tests/CatalogAppChecks/run_save_restart.py) | Arresti reali e nuovi processi nei checkpoint di transazione, recovery e pulizia; verifica tutti gli utenti, registro e integrità dei backup su fixture temporanee. |
| [run_save_profile_isolation.py](../../apps/mac/Tests/CatalogAppChecks/run_save_profile_isolation.py) | Un recupero fallito in un profilo non impedisce a un altro di giocare allo stesso titolo. |
| [run_save_unreadable_profile.py](../../apps/mac/Tests/CatalogAppChecks/run_save_unreadable_profile.py) | Profili illeggibili: rifiuta contesto, backup, apertura cartella e recupero dei salvataggi originali. |
| [run_install_profiles_wiring.py](../../apps/mac/Tests/CatalogAppChecks/run_install_profiles_wiring.py) | Verifica che il rifiuto dei profili raggiunga worker, retry e dialogo d'installazione. |
| [run_entrance.py](../../apps/mac/Tests/CatalogAppChecks/run_entrance.py) | Esegue i metodi reali di input e readiness: nessun comando agisce o salta l’entrata prima dell’atterraggio, clic su Profili, precedenza delle coperture, drawable mancante e presentazione su entrambi i percorsi. Nessuna finestra o GPU reale. |
| [run_icon_cache.py](../../apps/mac/Tests/CatalogAppChecks/run_icon_cache.py) | Esegue il vero `GameIconProvider`: un gioco senza icona non si rilegge dal disco a ogni disegno; dopo `forget` o la build si legge di nuovo. |
| [run_theme.py](../../apps/mac/Tests/CatalogAppChecks/run_theme.py) | Regressioni delle richieste condivise (precedenza, frame mantenuto e pausa) e del cambio palette a wallpaper/card invariati con snapshot e apply reali, ordine Look e input del selettore; shader Metal fuori schermo, colori locali GPU/Core, profilo sottile, deformazione delle onde, superfici distinte, frame fermo e uniform Mods. |
| [run_achievement_scroll.py](../../apps/mac/Tests/CatalogAppChecks/run_achievement_scroll.py) | Verifica fuori schermo lista, LB/RB in filtri e dettagli, riaperture rapide, ridimensionamento e Riduci movimento. |
| [run_mods_band_scroll.py](../../apps/mac/Tests/CatalogAppChecks/run_mods_band_scroll.py) | Verifica fuori schermo che la riga Mods a fuoco resti intera in Spotlight e Details e che la rotella raggiunga l’ultima riga. |
| [run_online_players.py](../../apps/mac/Tests/CatalogAppChecks/run_online_players.py) | Rende fuori schermo Spotlight, Collection, scheda e Settings con giochi e conteggi sintetici: default, tutto acceso e tutto spento. |
| [run_game_header.py](../../apps/mac/Tests/CatalogAppChecks/run_game_header.py) | Esegue i corpi reali di logo e azioni condivisi senza finestra né store applicativi, per entrambi i layout. |
| [NoticeHost.swift](../../apps/mac/Tests/CatalogAppChecks/NoticeHost.swift) | Host minimo per Retry, annullamento e ordine delle scelte Rebuild, con storage reale e dati sintetici temporanei. |
| [SharedGamePresentationTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SharedGamePresentationTests.swift) | Presentazione Steam con identità, personalizzazioni e cronologia; prima installazione disponibile coerente per artwork e dettagli, con Play bloccato se ambiguo; confine nxnative e opzioni comuni. |
| [PlayEngineTests.swift](../../core/Tests/OortLibraryTests/PlayEngineTests.swift) | Adapter intercambiabili, ripetizione dello stesso ricevuto e rifiuto di ripetere una consegna interrotta attraverso un alias. |
| [CatalogSourcesRepositoryTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CatalogSourcesRepositoryTests.swift) | Compatibilità generazioni, cambi fonte, preferenze concorrenti e adozione NX esplicita. |
| [CatalogSourcesModelTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CatalogSourcesModelTests.swift) | Opt-in, annullamento, cambio radice, recupero errori e intervallo tra riscansioni, misurato dagli avvii pubblicati dal modello. |
| [CatalogLibraryQueryTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/CatalogLibraryQueryTests.swift) | Visibilità, ricerca/filtri misti e selezione per UUID senza sessioni simulate. |
| [SteamOptionsTests.swift](../../engines/nxnative/Tests/NxnativeAdapterTests/SteamOptionsTests.swift) | Righe delle opzioni Steam come quelle comuni nxnative, niente di nxnative, Play e Finder spenti senza installazione, artwork e impostazione «Keep Steam in the background». |
| [SteamMetadataTests.swift](../../core/Tests/OortLibraryTests/SteamMetadataTests.swift) | Identità, lingue, offline, URL, concorrenza, tratti correlati in cache ed esito del salvataggio. |
| [SteamArtworkRequestTests.swift](../../core/Tests/OortLibraryTests/SteamArtworkRequestTests.swift) | Quadrato dall’icona originale e mai dalla copertina, scelta personale prima, link che escono dal bundle ignorati, icona automatica solo senza app. |
| [SteamAutomaticIconTests.swift](../../core/Tests/OortLibraryTests/SteamAutomaticIconTests.swift) | Quadrato LaunchBox della voce PC preso intero, scaricato una volta e conservato; nessun quadrato non si richiede di nuovo nella sessione. |
| [SteamBackdropChoiceTests.swift](../../core/Tests/OortLibraryTests/SteamBackdropChoiceTests.swift) | Solo arte in formato schermo, ordine store → screenshot → banner, fan art LaunchBox fra store e screenshot, ripiego sulla prima immagine che si carica. |
| [test_app_bundle.py](../../scripts/tests/PublicationChecks/test_app_bundle.py) | Verifica Game Mode, iniezione della coppia OAuth nel plist solo se completa e rifiuto delle variabili in pubblicazione. |

## Script di sviluppo e packaging

| File | Responsabilità |
|---|---|
| [scripts/build_app.sh](../../scripts/build_app.sh) | Compila in staging e prepara risorse senza rclone; può registrare nel bundle Dev lo SHA dell’albero pulito. Firma e pubblica con sostituzione atomica. |
| [scripts/inject_google_client.py](../../scripts/inject_google_client.py) | Scrive la coppia OAuth Google nel plist della build privata solo se completa, senza argomenti con credenziali. |
| [scripts/install_built_app.swift](../../scripts/install_built_app.swift) | Ingresso CLI che riusa BuildOutputInstaller per firmare, verificare e installare Arcane dopo il packaging. |
| [scripts/check_publication.py](../../scripts/check_publication.py) | Rifiuta contenuti personali o di gioco versionati e rclone nel bundle; verifica runtime, licenze, avvisi e sorgenti. |
| [scripts/check_guides.py](../../scripts/check_guides.py) | Verifica le guide dei giocatori e la matrice: FR = EN, immagini, link, versioni, sistemi e prove; può scrivere il JSON del sito. |
| [scripts/bundle-licences.json](../../scripts/bundle-licences.json) | Percorsi e SHA-256 dei testi e dei sorgenti verificati nel bundle di release. |
| [scripts/build_dmg.sh](../../scripts/build_dmg.sh) | Confeziona `Oort NX.app` in un DMG compresso, con veste Oort o ripiego semplice; verifica il contenuto su un montaggio invisibile in sola lettura. |
| [scripts/style_dmg.py](../../scripts/style_dmg.py) | Genera la trama e scrive layout Finder, TIFF Retina e icona alla radice del volume. |
| [scripts/make_dmg_background.swift](../../scripts/make_dmg_background.swift) | Disegna il fondo Oort del DMG a 1× e 2×. |
| [scripts/dmg-requirements.txt](../../scripts/dmg-requirements.txt) | Versioni e SHA-256 dei tool Python usati solo per confezionare il DMG. |
| [scripts/bundle_runtime.sh](../../scripts/bundle_runtime.sh) | Prepara e firma il runtime dalle versioni bloccate, verifica hash e avvio, scarta il percorso home del costruttore Python. |
| [scripts/release.sh](../../scripts/release.sh) | Verifica il pin effettivo in un checkout anonimo temporaneo; produce ZIP con radice `NXLibrary.app` e DMG Oort NX. Riprende la pubblicazione solo con tag identici sul commit atteso e release assente. |
| [scripts/validate_update.py](../../scripts/validate_update.py) | Verifica struttura, percorsi e limiti degli archivi prima dell'estrazione, sia nel bundle sia durante il packaging delle release. |
| [scripts/relink_macho.py](../../scripts/relink_macho.py) | Riscrive riferimenti Mach-O dei binari e delle librerie affinché il runtime incluso sia rilocabile. |
| [scripts/make_icons.swift](../../scripts/make_icons.swift) | Rigenera il cristallo dell’icona originale. |
| [scripts/brand_icons.py](../../scripts/brand_icons.py) | Genera le varianti a trama e a particelle, con i loro progetti Icon Composer. |
| [scripts/import_selene_palettes.py](../../scripts/import_selene_palettes.py) | Converte le palette Selene nel catalogo JSON usato dall’app. |
| [scripts/check_localizations.py](../../scripts/check_localizations.py) | Verifica copertura, placeholder, plurali e risorse nel bundle installato. |
| [scripts/check_vocabulary.py](../../scripts/check_vocabulary.py) | Confronta le traduzioni di Mac, desktop, Android, iOS e sito con il vocabolario, da cartelle o ref Git. |
| [scripts/check_localizations.py](../../scripts/check_localizations.py) | Verifica copertura, placeholder, plurali, il « tu » francese e risorse nel bundle installato. |
| [scripts/extract_downgrade_checkpoint.py](../../scripts/extract_downgrade_checkpoint.py) | Verifica le impronte della copia di compatibilità e la estrae in una cartella privata nuova; non modifica i dati attivi. |
| [scripts/check_selene_tokens.py](../../scripts/check_selene_tokens.py) | Blocca misure e stili letterali e nuovi componenti duplicati. |
| [design/oort.tokens.json](../../design/oort.tokens.json) | Fonte DTCG dei token Selene e della palette predefinita Oort. |
| [design/vocabulary.json](../../design/vocabulary.json) | Vocabolario proposto comune ai sistemi: parole fr/en, stati di un gioco, comandi e chiavi che le traduzioni devono rispettare. |
| [design/vocabulary-debt.json](../../design/vocabulary-debt.json) | Scarti di traduzione già noti, per sistema; può solo ridursi. |
| [design/credits.json](../../design/credits.json) | Fonte unica dei crediti: nome, autore, ruolo, licenza, link, sistemi, icona permessa; ordine delle sei schede di base. |
| [design/credits.css](../../design/credits.css) | Schede dei crediti per sito e Windows/Linux, solo con variabili generate. |
| [design/oort-tokens.css](../../design/oort-tokens.css) | Copia CSS generata di `design/oort.tokens.json`. |
| [scripts/generate_oort_tokens.py](../../scripts/generate_oort_tokens.py) | Controlla il contrasto e genera Swift e la sola voce Oort del catalogo. |
| [scripts/tests/PublicationChecks/test_oort_tokens.py](../../scripts/tests/PublicationChecks/test_oort_tokens.py) | Prova generazione stabile, output obsoleti e contrasto insufficiente. |
| [scripts/check_oort_core.py](../../scripts/check_oort_core.py) | R3: il Core compila su ogni sistema. Legge manifest, import (anche nei rami `#if`), nomi solo Apple e condizioni di sistema di `core/` e dei suoi test; le varianti di sistema solo in `core/OortLibrary/System/`. |
| [scripts/generate_credits.py](../../scripts/generate_credits.py) | Copia i crediti in app, NOTICE e sito; le voci `noticeOnly` restano solo nel NOTICE. Fallisce se manca un credito o una copia differisce. |
| [scripts/selene-token-debt.json](../../scripts/selene-token-debt.json) | Occorrenze letterali preesistenti per file e firma, escluse le misure già migrate ai token; le voci obsolete fanno fallire il controllo. |
| [scripts/tests/PublicationChecks/test_selene_tokens.py](../../scripts/tests/PublicationChecks/test_selene_tokens.py) | Prova argomenti multilinea, valori scalati ed esclusioni. |
| [scripts/check_ui_rules.py](../../scripts/check_ui_rules.py) | Misura menu, profondità, testi senza traduzione, misure e forme locali, nomi di accessibilità, ordine dei pulsanti, focus iniziale pericoloso e percorsi da tastiera e mouse; blocca il nuovo. |
| [scripts/ui-rules.json](../../scripts/ui-rules.json) | Superfici contate, valori, righe di pulsanti note, percorsi dichiarati di mouse e tastiera, parti non misurate e debito che può solo diminuire. |
| [scripts/tests/UIRulesChecks/test_ui_rules.py](../../scripts/tests/UIRulesChecks/test_ui_rules.py) | Prove negative di ogni regola e coerenza fra controllo, criteri e skill. |
| [scripts/tests/PublicationChecks/test_credits.py](../../scripts/tests/PublicationChecks/test_credits.py) | Prova che una dipendenza senza credito, un NOTICE o un sito diversi falliscono. |
| [scripts/check_metadata_text_layout.swift](../../scripts/check_metadata_text_layout.swift) | Verifica fuori schermo il layout delle descrizioni e la destinazione dello scroll dopo cambi di focus, anche rapidi e con Riduci movimento. |
| [check_app_profile.swift](../../scripts/check_app_profile.swift) | Prova senza UI di identità, accesso reale alle preferenze e percorsi nel pacchetto prodotto dalla build; non importa né scrive dati. |

## Risorse incluse

| File | Responsabilità aggiuntiva |
|---|---|
| [design/Icons/IconArtwork.png](../../design/Icons/IconArtwork.png) | Master quadrato originale dell’icona (cristallo nella sfera di vetro), fornito dall’utente e creato con AI. |
| [design/Icons/IconArtwork.md](../../design/Icons/IconArtwork.md) | Riproduzione delle icone native e Dock, e provenienza del cristallo originale. |
| [crystal-arcane.png](../../core/OortLibrary/Resources/crystal-arcane.png) | Immagine ferma del trofeo Arcane, anche come ripiego del video. |
| [crystal-arcane.mov](../../core/OortLibrary/Resources/crystal-arcane.mov) | Animazione con alpha del trofeo Arcane. |
| [achievements-01006BB00C6F0000.json](../../core/OortLibrary/Resources/achievements-01006BB00C6F0000.json) | Pack degli obiettivi locali di Link’s Awakening in sette lingue. |
| [crystal-gold.png](../../core/OortLibrary/Resources/crystal-gold.png) | Immagine del trofeo Oro. |
| [crystal-silver.png](../../core/OortLibrary/Resources/crystal-silver.png) | Immagine del trofeo Argento. |
| [crystal-bronze.png](../../core/OortLibrary/Resources/crystal-bronze.png) | Immagine del trofeo Bronzo. |

| File | Responsabilità |
|---|---|
| [design/Icons/AppIcon.icon/icon.json](../../design/Icons/AppIcon.icon/icon.json) | Icona Icon Composer a trama: sfondo, livelli e colori. |
| [design/Icons/AppIcon.icon/Assets/glyph.svg](../../design/Icons/AppIcon.icon/Assets/glyph.svg) | Livello vettoriale della trama. |
| [design/Icons/AppIcon.icon/Assets/sun.svg](../../design/Icons/AppIcon.icon/Assets/sun.svg) | Livello vettoriale del Sole. |
| [design/Icons/AppIconParticles.icon/icon.json](../../design/Icons/AppIconParticles.icon/icon.json) | Sorgente Icon Composer per le immagini del Dock a particelle. |
| [design/Icons/AppIconParticles.icon/Assets/glyph.svg](../../design/Icons/AppIconParticles.icon/Assets/glyph.svg) | Livello vettoriale delle particelle. |
| [design/Icons/AppIconParticles.icon/Assets/sun.svg](../../design/Icons/AppIconParticles.icon/Assets/sun.svg) | Livello vettoriale del Sole nella variante a particelle. |
| [apps/mac/AppIcon.icns](../../apps/mac/AppIcon.icns) | Ripiego `.icns` della trama. |
| [design/Icons/AppIcon-Light.png](../../design/Icons/AppIcon-Light.png) | Anteprima chiara della trama nel README. |
| [design/Icons/AppIcon-Particles-Dark.png](../../design/Icons/AppIcon-Particles-Dark.png) | Icona Dock a particelle scura. |
| [design/Icons/AppIcon-Particles-Light.png](../../design/Icons/AppIcon-Particles-Light.png) | Icona Dock a particelle chiara. |
| [design/Selene/palettes.json](../../design/Selene/palettes.json) | Catalogo delle 26 palette: Oort predefinito, blu classico Arcane e superfici opzionali Crystal e Flow. |
| [design/Selene/Fonts/MaterialIcons-Regular.ttf](../../design/Selene/Fonts/MaterialIcons-Regular.ttf) | Font dei glifi Material Icons disegnati dalla UI. |
| [design/Selene/Fonts/MaterialIcons-LICENSE.txt](../../design/Selene/Fonts/MaterialIcons-LICENSE.txt) | Licenza del font Material Icons incluso. |
| [design/Selene/NOTICE.txt](../../design/Selene/NOTICE.txt) | Attribuzioni delle risorse Selene incluse. |
| [design/Brands/Platforms/LICENSE-Lucide.txt](../../design/Brands/Platforms/LICENSE-Lucide.txt) | Licenza ISC e nota Feather MIT. |
| [design/Brands/Credits/arcane.png](../../design/Brands/Credits/arcane.png) | Icona di Arcane, dal suo deposito MIT, solo per il credito. |
| [design/Brands/Credits/playnite.png](../../design/Brands/Credits/playnite.png) | Icona di Playnite, dal suo deposito MIT, solo per il credito. |
| [design/Brands/Credits/selene.png](../../design/Brands/Credits/selene.png) | Icona di Selene, dal suo deposito MIT, solo per il credito. |
| [Buy Me a Coffee.svg](../../design/Brands/Platforms/Marks/Buy%20Me%20a%20Coffee.svg) | Simbolo piattaforma revisionato; fonte e impronta nel manifesto licenze. |
| [CrossOver.svg](../../design/Brands/Platforms/Marks/CrossOver.svg) | Simbolo piattaforma revisionato; fonte e impronta nel manifesto licenze. |
| [Epic Games.svg](../../design/Brands/Platforms/Marks/Epic%20Games.svg) | Simbolo piattaforma revisionato; fonte e impronta nel manifesto licenze. |
| [GOG.svg](../../design/Brands/Platforms/Marks/GOG.svg) | Simbolo piattaforma revisionato; fonte e impronta nel manifesto licenze. |
| [Google Drive.svg](../../design/Brands/Platforms/Marks/Google%20Drive.svg) | Simbolo piattaforma revisionato; fonte e impronta nel manifesto licenze. |
| [Nintendo Switch 2.svg](../../design/Brands/Platforms/Marks/Nintendo%20Switch%202.svg) | Simbolo piattaforma revisionato; fonte e impronta nel manifesto licenze. |
| [Nintendo Switch.svg](../../design/Brands/Platforms/Marks/Nintendo%20Switch.svg) | Simbolo piattaforma revisionato; fonte e impronta nel manifesto licenze. |
| [Steam.svg](../../design/Brands/Platforms/Marks/Steam.svg) | Simbolo piattaforma revisionato; fonte e impronta nel manifesto licenze. |
| [design/Brands/Platforms/NOTICE.txt](../../design/Brands/Platforms/NOTICE.txt) | Provenienza e nota sui marchi. |
| [design/Brands/Platforms/arrow-left-right.svg](../../design/Brands/Platforms/arrow-left-right.svg) | Simbolo generico CrossOver. |
| [design/Brands/Platforms/boxes.svg](../../design/Brands/Platforms/boxes.svg) | Simbolo generico Minecraft. |
| [design/Brands/Platforms/cloud.svg](../../design/Brands/Platforms/cloud.svg) | Simbolo Lucide per i salvataggi iCloud. |
| [design/Brands/Platforms/image.svg](../../design/Brands/Platforms/image.svg) | Simbolo Lucide per immagini e valutazioni. |
| [design/Brands/Platforms/network.svg](../../design/Brands/Platforms/network.svg) | Simbolo Lucide per Nextendo. |
| [design/Brands/Platforms/coffee.svg](../../design/Brands/Platforms/coffee.svg) | Tazza generica per il collegamento di sostegno. |
| [design/Brands/Platforms/disc-3.svg](../../design/Brands/Platforms/disc-3.svg) | Simbolo generico Steam. |
| [design/Brands/Platforms/gamepad-2.svg](../../design/Brands/Platforms/gamepad-2.svg) | Simbolo generico Switch e base del segno Switch 2. |
| [design/Brands/Platforms/hard-drive.svg](../../design/Brands/Platforms/hard-drive.svg) | Simbolo generico Google Drive. |
| [design/Brands/Platforms/laptop.svg](../../design/Brands/Platforms/laptop.svg) | Simbolo generico dei collegamenti alle app Mac. |
| [design/Brands/Platforms/package.svg](../../design/Brands/Platforms/package.svg) | Simbolo generico GOG. |
| [design/Brands/Platforms/shield.svg](../../design/Brands/Platforms/shield.svg) | Simbolo generico Epic Games. |
| [design/Selene/NOTICE-palettes.txt](../../design/Selene/NOTICE-palettes.txt) | Attribuzioni delle palette incluse con esse. |
| [design/ThirdPartyLicenses/omarchy-LICENSE.txt](../../design/ThirdPartyLicenses/omarchy-LICENSE.txt) | Testo MIT di Omarchy per le palette derivate. |
| [design/ThirdPartyLicenses/python-LICENSES.txt](../../design/ThirdPartyLicenses/python-LICENSES.txt) | Licenze delle dipendenze native di CPython, Tcl/Tk e delle estensioni. |
| [design/ThirdPartyLicenses/rclone-LICENSES.txt](../../design/ThirdPartyLicenses/rclone-LICENSES.txt) | Licenze e avvisi di rclone, delle dipendenze Go incluse e della libreria standard. |
| [design/ThirdPartyLicenses/wheel-NOTICES.txt](../../design/ThirdPartyLicenses/wheel-NOTICES.txt) | Avvisi aggiuntivi per il codice incorporato nelle wheel Python. |
| [design/Selene/Sounds/Boot.wav](../../design/Selene/Sounds/Boot.wav) | Cue sonoro incluso per l’avvio. |
| [design/Selene/Sounds/Key.wav](../../design/Selene/Sounds/Key.wav) | Cue sonoro incluso per la pressione dei tasti. |
| [design/Selene/Sounds/Success.wav](../../design/Selene/Sounds/Success.wav) | Cue sonoro incluso per il completamento di un’azione. |
| [design/Selene/Sounds/navigation.wav](../../design/Selene/Sounds/navigation.wav) | Cue sonoro incluso per la navigazione. |
| [design/SoundPacks/oort.oortsound](../../design/SoundPacks/oort.oortsound) | Manifesto CC0 e dieci cue WAV originali; firma punto/risposta al ritorno. |
| [design/SoundPacks/pollen.oortsound](../../design/SoundPacks/pollen.oortsound) | Manifesto CC0 e dodici cue WAV chiari e brevi. |
| [design/SoundPacks/umbra.oortsound](../../design/SoundPacks/umbra.oortsound) | Manifesto CC0 e dodici cue WAV morbidi. |
| [design/SoundPacks/impulsion.oortsound](../../design/SoundPacks/impulsion.oortsound) | Manifesto CC0 e dodici cue WAV elettronici. |

## Screenshot e demo

| File | Responsabilità |
|---|---|
| [docs/guides/README.md](../guides/README.md) | Formato delle guide per sistema in `docs/guides/<fr\|en>/<sistema>/`, immagini in `docs/guides/media/` e passi dopo una release. Le singole guide e immagini non hanno una riga propria: le verifica `check_guides.py`. |
| [docs/features.json](../features.json) | Matrice delle funzioni per sistema, con versione e prova. |
| [docs/media/README.md](../media/README.md) | Registra i media del README e la loro posizione. |
| [docs/media/spotlight.webp](../media/spotlight.webp) | Presenta Spotlight e la libreria nell'apertura del README. |
| [docs/media/game-details.webp](../media/game-details.webp) | Mostra dettagli, attività e informazioni di build di un gioco. |
| [docs/media/mod-store.webp](../media/mod-store.webp) | Presenta lo store delle mod nel README. |
| [docs/media/quick-menu.webp](../media/quick-menu.webp) | Illustra il menu rapido sopra la libreria. |
| [docs/media/porting-progress.webp](../media/porting-progress.webp) | Mostra l'avanzamento di un porting dalla schermata Spotlight. |
| [docs/media/settings.webp](../media/settings.webp) | Cattura storica di Settings in NX Library. |
| [docs/media/color-themes.webp](../media/color-themes.webp) | Mostra la scelta delle palette con anteprima della libreria. |
| [docs/media/static-wallpapers.webp](../media/static-wallpapers.webp) | Illustra il browser degli sfondi statici e la relativa anteprima. |
| [docs/media/live-wallpapers.webp](../media/live-wallpapers.webp) | Mostra il selettore degli sfondi animati e l'importazione di video personali. |

## Documentazione tecnica e registri datati

[Misure delle letture rclone](../history/reviews/2026-11-21-rclone-rc.md): comandi singoli e sessione persistente.
[Divergenza dell’inventario cloud](../history/reviews/2026-11-21-cloud-upload-inventory.md): diagnosi del controllo prima dell’invio.
[Uscita cloud e AppKit](../history/reviews/2026-11-21-cloud-quit-appkit.md): prova del ciclo di eventi.
[Aggiornamento unico della libreria](../history/reviews/2026-11-25-library-refresh.md): misure prima e dopo, cause e limiti.
[Giochi con sole sorgenti cloud](../history/reviews/2026-11-24-cloud-only.md): elenco confinato, personalizzazione, trasferimento e riapertura offline su fixture.
[Luce di Download](../history/reviews/2026-11-24-download-cloud-light.md): contrasto, fotogrammi reali e misura in finestra isolata.
[Versione del motore installato](../history/reviews/2026-11-24-installed-engine-version.md): origine del commit e risultati della sonda visiva.
[Conferme delle impostazioni](../history/reviews/2026-11-24-settings-confirmations.md): inventario, risultati della sonda e limiti.

| File | Responsabilità |
|---|---|
| [docs/README.md](../README.md) | Indice della documentazione: cosa c'è in ogni cartella, per chi è e da dove partire. |
| [docs/how-it-works/architecture.md](../how-it-works/architecture.md) | Come funziona oggi ogni area: confini dei componenti, regole, dati su disco e verifiche; niente storia né stati di validazione. |
| [docs/how-it-works/flows.md](../how-it-works/flows.md) | Schemi dei flussi completi: avvio, libreria, Play Switch e Steam, Add Game, salvataggi, mod, impostazioni, aggiornamento dell’app. |
| [docs/how-it-works/keymap.md](../how-it-works/keymap.md) | Keymap per tasto e schermata, azioni LB/RB, precedenza dei dialoghi e glifi per famiglia. |
| [docs/how-it-works/steam.md](../how-it-works/steam.md) | Riferimento unico dell’integrazione Steam: file letti, stati, osservazione, libreria, Play, ore, achievement, scelte e limiti. |
| [docs/how-it-works/achievements.md](../how-it-works/achievements.md) | Obiettivi locali, lettura a fine sessione e come aggiungere un gioco. |
| [docs/working-on-it/conventions.md](conventions.md) | Dove va il codice; ricette per fonti, interfaccia Selene e conferme, impostazioni, dati, rete, testi, test e documentazione. |
| [docs/working-on-it/components.md](components.md) | Inventario OortUI: componenti, preset, stati e regole d'uso. |
| [docs/working-on-it/change-criteria.md](change-criteria.md) | Criteri verificabili per ogni modifica visiva o di logica, con fonte e motivo; conflitti risolti e aperti. |
| [docs/working-on-it/development.md](development.md) | Documenta prerequisiti, runtime, build, debug, verifiche, CI e release, compreso l'ID Nextendo pubblico della release personale. |
| [docs/working-on-it/perso-release-notes.md](perso-release-notes.md) | Modello francese delle note di release del fork: versione, pin, giochi da ricompilare e novità. |
| [docs/working-on-it/file-map.md](file-map.md) | Catalogo corrente delle responsabilità di tutti i file versionati, suddiviso per area. |
| [docs/working-on-it/validation.md](validation.md) | Elenco unico di ciò che il maintainer ha validato o deve ancora provare, compresi i pin dell’engine. |
| [docs/history/engine-upgrades/README.md](../history/engine-upgrades/README.md) | Checklist obbligatoria e indice delle revisioni del pin upstream. |
| [docs/history/engine-upgrades/2026-10-27-06b7b3e-4f24ce6.md](../history/engine-upgrades/2026-10-27-06b7b3e-4f24ce6.md) | Registro della revisione del delta, scelte di adozione e verifiche per questo upgrade del motore. |
| [docs/history/engine-upgrades/2026-10-27-4f24ce6-1963fab.md](../history/engine-upgrades/2026-10-27-4f24ce6-1963fab.md) | Registro della revisione del delta, scelte di adozione e verifiche per questo upgrade del motore. |
| [docs/history/engine-upgrades/2026-10-29-1963fab-ee369f0.md](../history/engine-upgrades/2026-10-29-1963fab-ee369f0.md) | Registro della revisione del delta, scelte di adozione e verifiche per questo upgrade del motore. |
| [docs/history/engine-upgrades/2026-10-31-ee369f0-2716f78.md](../history/engine-upgrades/2026-10-31-ee369f0-2716f78.md) | Registro della revisione del delta, scelte di adozione e verifiche per questo upgrade del motore. |
| [docs/history/engine-upgrades/2026-11-02-163a9905-65501fbb-review.md](../history/engine-upgrades/2026-11-02-163a9905-65501fbb-review.md) | Registra l’adozione di 65501fbb, le decisioni UI/backend, i test, la build certificata e l’avvio manuale. |
| [docs/history/engine-upgrades/2026-11-02-2716f78-163a9905-review.md](../history/engine-upgrades/2026-11-02-2716f78-163a9905-review.md) | Registra revisione e adozione del pin: toolchain certificata, nuove sorgenti, interventi UI, prove sintetiche e conferma manuale di build e avvio. |
| [docs/history/engine-upgrades/2026-11-03-65501fbb-b64a5ff0-review.md](../history/engine-upgrades/2026-11-03-65501fbb-b64a5ff0-review.md) | Registra l’adozione di b64a5ff0, le scelte UI/backend, la build certificata e la conferma manuale di avvio. |
| [docs/history/engine-upgrades/2026-11-05-b64a5ff0-4a0551e4-review.md](../history/engine-upgrades/2026-11-05-b64a5ff0-4a0551e4-review.md) | Registra l’adozione di 4a0551e4: righe Front-ends, profili provvisori, avviso dell’archivio pipeline, uscita con Home, build Wonder certificata e avvio confermato. |
| [docs/history/engine-upgrades/2026-11-06-04df08d4-b2d46b86-review.md](../history/engine-upgrades/2026-11-06-04df08d4-b2d46b86-review.md) | Revisione del delta engine del 6 novembre e compatibilità della toolchain. |
| [docs/history/engine-upgrades/2026-11-06-4a0551e4-04df08d4-review.md](../history/engine-upgrades/2026-11-06-4a0551e4-04df08d4-review.md) | Revisione del candidato 04df08d4: tre righe Front-ends, cache e librerie shader in un file, etichetta **Updating shader cache**, pacchetti solo di sviluppo in tools.txt; in attesa di build certificato e avvio confermato. |
| [docs/history/engine-upgrades/2026-11-07-7fe9fc4d-e5f03403-review.md](../history/engine-upgrades/2026-11-07-7fe9fc4d-e5f03403-review.md) | Revisione engine del 7 novembre, eventi di progresso e prompt dei controller. |
| [docs/history/engine-upgrades/2026-11-07-b2d46b86-7fe9fc4d-review.md](../history/engine-upgrades/2026-11-07-b2d46b86-7fe9fc4d-review.md) | Revisione engine del 7 novembre, shader e requisiti. |
| [docs/history/engine-upgrades/2026-11-08-e5f03403-bd979ced-review.md](../history/engine-upgrades/2026-11-08-e5f03403-bd979ced-review.md) | Revisione engine dell’8 novembre e nuova catena di traduzione shader. |
| [docs/history/engine-upgrades/2026-11-09-bd979ced-79741184-review.md](../history/engine-upgrades/2026-11-09-bd979ced-79741184-review.md) | Adozione engine per 0.1.4.2 e limiti della validazione registrata. |
| [docs/history/engine-upgrades/2026-11-12-79741184-8a5c5e7e-review.md](../history/engine-upgrades/2026-11-12-79741184-8a5c5e7e-review.md) | Adozione engine per 0.1.4.3 e limiti della validazione registrata. |
| [docs/history/engine-upgrades/2026-11-18-8a5c5e7e-461a5f9f-review.md](../history/engine-upgrades/2026-11-18-8a5c5e7e-461a5f9f-review.md) | Revisione engine per 0.2.0, confronto con il commit già provato, scelte d'integrazione e prove del gate. |
| [docs/history/engine-upgrades/2026-11-20-461a5f9f-99224562-review.md](../history/engine-upgrades/2026-11-20-461a5f9f-99224562-review.md) | Revisione engine per 0.2.1: superficie del contratto, delta per area, cosa non si adotta (microfono, polacco e tailandese, switch di regolazione), gate certificato e test sull'hash esatto. |
| [docs/history/reviews/2026-11-09-hotfix-0.1.4.2.md](../history/reviews/2026-11-09-hotfix-0.1.4.2.md) | Ambito della release 0.1.4.2, autorizzazione del maintainer e verifiche ancora non confermate. |
| [docs/history/reviews/2026-11-16-ratings-metadata-evidence.md](../history/reviews/2026-11-16-ratings-metadata-evidence.md) | Prove e misure dietro le scelte di voti e metadati: abbinamenti Wikidata, console Switch 2 in IGDB, download a blocchi, movimento del selettore, sonde LaunchBox/TheGamesDB. |
| [docs/history/reviews/2026-11-17-arcane-moonlight.md](../history/reviews/2026-11-17-arcane-moonlight.md) | Contratti provati fuori schermo e tempi GPU del Moonlight prima/dopo, con limiti delle misure. |
| [docs/history/reviews/2026-11-17-dock-rename-probe.md](../history/reviews/2026-11-17-dock-rename-probe.md) | Sonda: il Dock apre ancora un'app rinominata nella stessa cartella. |
| [docs/history/reviews/2026-11-17-entrance-frames.md](../history/reviews/2026-11-17-entrance-frames.md) | Metodo, campioni e limiti delle misure temporanee dell’entrata e del passaggio al fullscreen. |
| [docs/history/reviews/2026-11-18-spotlight-glide.md](../history/reviews/2026-11-18-spotlight-glide.md) | Campioni dei primi cambi gioco e costo di mod e salvataggio selezione. |
| [docs/history/reviews/2026-11-18-steam-launch-spaces.md](../history/reviews/2026-11-18-steam-launch-spaces.md) | Riscontro video e log dei cambi rapidi di Space durante Play Steam, causa e regressione. |
| [docs/history/reviews/2026-11-22-rebuild-cache.md](../history/reviews/2026-11-22-rebuild-cache.md) | Tempi prima e dopo della verifica Rebuild su cache sintetica e limiti della prova. |
| [docs/history/reviews/2026-11-22-browser-app-adoption.md](../history/reviews/2026-11-22-browser-app-adoption.md) | Sonda locale: riparazione e firma di ripiego di una copia estratta dallo ZIP del browser. |
| [docs/history/reviews/2026-11-22-cloud-per-file.md](../history/reviews/2026-11-22-cloud-per-file.md) | Sonda locale: byte e tempo per il cambio di un solo file, archivio rispetto a copia incrementale. |
| [docs/history/reviews/2026-11-22-local-removal-inventory.md](../history/reviews/2026-11-22-local-removal-inventory.md) | Inventario delle cancellazioni locali e verifica del contratto `DM_SAVE`. |
| [docs/history/reviews/2026-11-24-profile-focus.md](../history/reviews/2026-11-24-profile-focus.md) | Sonda dell'alone profili, misure dei bordi negli altri viewport e diagnosi del banding. |
| [docs/history/reviews/2026-11-25-cloud-assistant.md](../history/reviews/2026-11-25-cloud-assistant.md) | Processi, richieste e tempi prima e dopo, su Drive sintetico. |
| [docs/history/reviews/2026-11-26-cloud-command-drain.md](../history/reviews/2026-11-26-cloud-command-drain.md) | EOF dei comandi cloud sotto carico, guardia dopo l’uscita e regressioni. |
| [docs/history/reviews/2026-11-27-cloud-under-load.md](../history/reviews/2026-11-27-cloud-under-load.md) | Avvio di `rcd` sotto carico, pulizia concorrente delle cartelle e preferenze condivise delle sonde. |
| [docs/history/reviews/2026-11-26-mac-ci.md](../history/reviews/2026-11-26-mac-ci.md) | Tempi dei runner, compilazioni indipendenti e diagnosi dell'errore OCR. |

## Aggiornare questo catalogo

Quando si aggiunge, rinomina o rimuove un file versionato, aggiornare la sua riga nella sezione della sua area e il totale iniziale; una funzione nuova non apre una sezione in fondo al catalogo. Le regole complete sono in [conventions.md](conventions.md#10-documentazione). Quando cambia un flusso o una responsabilità, aggiornare anche la sezione corrispondente della guida tecnica. Le descrizioni dei test indicano l’ambito dei controlli, mentre l’esito di esecuzione appartiene ai rapporti di verifica.
