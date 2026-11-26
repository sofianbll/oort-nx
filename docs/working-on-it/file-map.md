# Arcane — catalogo dei file

Aggiornato il 25 novembre 2026. Il repository versiona **1577 file**, compresi sorgenti, test, controlli di pubblicazione, risorse e guide. Le singole guide e immagini di `docs/guides/` non hanno una riga propria (le verifica `check_guides.py`); altri 73 file, i pacchetti di suoni e alcuni sorgenti e test recenti, aspettano ancora la loro. Le cartelle personali, gli output generati e gli appunti non versionati sono esclusi.
Aggiornato il 25 novembre 2026. Il repository versiona **1595 file**, compresi sorgenti, test, controlli di pubblicazione, risorse e guide. Le singole guide e immagini di `docs/guides/` non hanno una riga propria (le verifica `check_guides.py`); altri 73 file, i pacchetti di suoni e alcuni sorgenti e test recenti, aspettano ancora la loro. Le cartelle personali, gli output generati e gli appunti non versionati sono esclusi.
Aggiornato il 25 novembre 2026. Il repository versiona **1581 file**, compresi sorgenti, test, controlli di pubblicazione, risorse e guide. Le singole guide e immagini di `docs/guides/` non hanno una riga propria (le verifica `check_guides.py`); altri 73 file, i pacchetti di suoni e alcuni sorgenti e test recenti, aspettano ancora la loro. Le cartelle personali, gli output generati e gli appunti non versionati sono esclusi.
Aggiornato il 25 novembre 2026. Il repository versiona **1578 file**, compresi sorgenti, test, controlli di pubblicazione, risorse e guide. Le singole guide e immagini di `docs/guides/` non hanno una riga propria (le verifica `check_guides.py`); altri 73 file, i pacchetti di suoni e alcuni sorgenti e test recenti, aspettano ancora la loro. Le cartelle personali, gli output generati e gli appunti non versionati sono esclusi.
Aggiornato il 25 novembre 2026. Il repository versiona **1577 file**, compresi sorgenti, test, controlli di pubblicazione, risorse e guide. Le singole guide e immagini di `docs/guides/` non hanno una riga propria (le verifica `check_guides.py`); altri 72 file, i pacchetti di suoni e alcuni sorgenti e test recenti, aspettano ancora la loro. Le cartelle personali, gli output generati e gli appunti non versionati sono esclusi.
Aggiornato il 25 novembre 2026. Il repository versiona **1585 file**, compresi sorgenti, test, controlli di pubblicazione, risorse e guide. Le singole guide e immagini di `docs/guides/` non hanno una riga propria (le verifica `check_guides.py`); altri 73 file, i pacchetti di suoni e alcuni sorgenti e test recenti, aspettano ancora la loro. Le cartelle personali, gli output generati e gli appunti non versionati sono esclusi.
Aggiornato il 25 novembre 2026. Il repository versiona **1591 file**, compresi sorgenti, test, controlli di pubblicazione, risorse e guide. Le singole guide e immagini di `docs/guides/` non hanno una riga propria (le verifica `check_guides.py`); altri 73 file, i pacchetti di suoni e alcuni sorgenti e test recenti, aspettano ancora la loro. Le cartelle personali, gli output generati e gli appunti non versionati sono esclusi.

La [guida tecnica](../how-it-works/architecture.md) spiega come collaborano i componenti. Qui ogni riga identifica un file e la sua responsabilità. Le sezioni Core seguono le cartelle del Core, una per area; le sezioni Porting seguono le cartelle del target `ArcanePorting`, con lo Switch; quelle UI seguono schermate e componenti. Le viste usano i modelli e i servizi del Core attraverso il coordinamento applicativo.

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
| [.github/workflows/ci.yml](../../.github/workflows/ci.yml) | Flusso unico: controlli Mac sempre; Swift, desktop, iPhone e iPad, Android solo se cambiano i loro percorsi. |
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
| [Package.swift](../../Package.swift) | Dichiara `OortCore` portabile, `NXLibraryCore`, il modulo `ArcanePorting`, l’app, i tre target di test e il deployment macOS minimo. |
| [README.md](../../README.md) | Presenta Arcane come libreria e launcher Mac, con guide d'uso (anche per la prima connessione cloud), requisiti e crediti. |
| [runtime.lock](../../runtime.lock) | Fissa versioni, download e hash del runtime Python e degli strumenti inclusi nel bundle. |
| [VERSION](../../VERSION) | Versione in sviluppo usata dal packaging e verificata dalla procedura di release. |

## Ingresso e shell dell’app

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/NXLibraryApp.swift](../../Sources/NXLibrary/NXLibraryApp.swift) | Punto @main, finestra SwiftUI, notifiche e comandi della barra menu, incluso Add an app; in Debug seleziona anche la fixture o la cattura senza finestra visibile. |
| [Sources/NXLibrary/AppDelegate.swift](../../Sources/NXLibrary/AppDelegate.swift) | Gestisce finestra e chiusura: conferma dell’ospite prima delle code e degli esiti, rinomina di una copia release storica. |
| [Sources/NXLibrary/Views/MainView.swift](../../Sources/NXLibrary/Views/MainView.swift) | Presenta AppShellView come contenuto della finestra principale. |
| [Sources/NXLibrary/Views/Shell/AppShellView.swift](../../Sources/NXLibrary/Views/Shell/AppShellView.swift) | Possiede backdrop e stato condivisi, instrada notifiche, menu e trascinamento di una `.app`. `nativeDialogOwnsInput` sospende controller e tastiera sotto dialoghi nativi. Tiene stato, init e `body`; il resto sta nelle estensioni qui sotto. |
| [Sources/NXLibrary/Views/Components/SeleneOverlay.swift](../../Sources/NXLibrary/Views/Components/SeleneOverlay.swift) | Velo o fondo opaco, stile del blur, clic all'esterno, isolamento di puntatore e VoiceOver, suggerimenti, filtro del focus al passaggio del puntatore e scossa per l'input rifiutato. |
| [Sources/NXLibrary/Views/Shell/AppShellView+Layers.swift](../../Sources/NXLibrary/Views/Shell/AppShellView+Layers.swift) | Strati, contatori Nextendo e comandi di Attività e dei giochi. I collegamenti Mac non aprono Details. Sveglia la coda dopo la scansione; l'importazione cloud ignora le richieste annullate. Azzera le notifiche al cambio di profilo. |
| [Sources/NXLibrary/Views/Shell/AppShellView+Startup.swift](../../Sources/NXLibrary/Views/Shell/AppShellView+Startup.swift) | Avvia la shell, instrada il controller anche verso Integrations e risveglia installazioni, trasferimenti cloud e porting alla chiusura del gioco. |
| [Sources/NXLibrary/Views/Shell/AppShellView+Profiles.swift](../../Sources/NXLibrary/Views/Shell/AppShellView+Profiles.swift) | Home, cambio dopo la chiusura dei giochi, conferme dell’ospite, rinnovo della presenza e dialogo PIN Selene condiviso con tastiera, manetta e mouse. |
| [Sources/NXLibrary/Views/Shell/AppShellView+Overlays.swift](../../Sources/NXLibrary/Views/Shell/AppShellView+Overlays.swift) | Dialoghi e avvisi della shell: cloud, impostazioni, benvenuto, installazione fallita, Close Game, rimozione e aggiornamento. Passa l'indice di Annulla al dialogo condiviso. |
| [Sources/NXLibrary/Views/Shell/AppShellView+Input.swift](../../Sources/NXLibrary/Views/Shell/AppShellView+Input.swift) | Equivalenti da tastiera dei gesti del controller, inclusi Inbox e Integrations, azioni del menu e del centro attività. |
| [Sources/NXLibrary/Views/Shell/AppShellView+Palette.swift](../../Sources/NXLibrary/Views/Shell/AppShellView+Palette.swift) | Cerca ovunque: non si apre sui dialoghi e usa le azioni esistenti per tutte le righe. |
| [Sources/NXLibrary/Views/Shell/AppShellView+Input.swift](../../Sources/NXLibrary/Views/Shell/AppShellView+Input.swift) | Equivalenti da tastiera, azioni del menu e del centro attività; Restart app aspetta la decisione su Settings. |
| [Sources/NXLibrary/Views/Shell/AppShellView+Palette.swift](../../Sources/NXLibrary/Views/Shell/AppShellView+Palette.swift) | Cerca ovunque: apertura, righe, tasti fisici inoltrati alla lista e azione esistente di ogni riga. |
| [Sources/NXLibrary/Views/Shell/IntegrationsView.swift](../../Sources/NXLibrary/Views/Shell/IntegrationsView.swift) | Barra, riepilogo Giochi e Servizi, schede dei dati e collegamenti alle impostazioni esistenti. |
| [Sources/NXLibrary/Views/Shell/IntegrationsView+Input.swift](../../Sources/NXLibrary/Views/Shell/IntegrationsView+Input.swift) | Traduce tastiera e controller per barra e pagina; mentre la barra ha il focus non inoltra i comandi delle tessere. |
| [Sources/NXLibrary/Views/Shell/IntegrationFixtureView.swift](../../Sources/NXLibrary/Views/Shell/IntegrationFixtureView.swift) | Anteprima Debug isolata e PNG delle viste condivise con stati sintetici, senza avviare i servizi o rendere visibile una finestra per le catture. |
| [Sources/NXLibrary/Views/Shell/FullscreenCursorView.swift](../../Sources/NXLibrary/Views/Shell/FullscreenCursorView.swift) | Gestisce il cursore inattivo in fullscreen e l'attività del controller anche in finestra, rispettando pannelli e menu. |
| [Sources/NXLibrary/Views/Shell/StartupWindowView.swift](../../Sources/NXLibrary/Views/Shell/StartupWindowView.swift) | Applica il fullscreen dopo la comparsa della finestra e segnala fine transizione o scadenza alla fase dell’entrata. |
| [Sources/NXLibrary/Views/Shell/MenuOverlayView.swift](../../Sources/NXLibrary/Views/Shell/MenuOverlayView.swift) | Disegna il control center a cinque icone con LB/RB e `MenuCard`, la scheda di pillole di pari larghezza sopra Profilo, Libreria e Power. Mostra le sole voci disponibili. Il puntatore fermo non riprende il focus delle icone. |
| [Sources/NXLibrary/Views/Shell/ProfilePickerView.swift](../../Sources/NXLibrary/Views/Shell/ProfilePickerView.swift) | «Chi gioca?» all’avvio e in sovrapposizione, ritratto condiviso, fila con spazio per l'alone, glifo di aggiunta leggibile fuori focus, modifica e rimozione dei profili idonei. |
| [Sources/NXLibrary/Views/Shell/ProfileEditorView.swift](../../Sources/NXLibrary/Views/Shell/ProfileEditorView.swift) | Bozza dei quattro passi, tastiera a schermo, avatar, ritaglio, anteprima, salvataggio rapido e conferma di scarto con l'aiuto del dialogo condiviso. |
| [Sources/NXLibrary/Views/Shell/ProfileAvatar.swift](../../Sources/NXLibrary/Views/Shell/ProfileAvatar.swift) | Ritaglia artwork locale o file scelti, conserva i tempi dei GIF e mostra l’animazione in un cerchio con ritaglio centrato. |
| [Sources/NXLibrary/Views/Shell/ProfilePage.swift](../../Sources/NXLibrary/Views/Shell/ProfilePage.swift) | Pagina profilo: arte sfumata, statistiche locali, schede percorse anche con LB/RB, pulsante Vedi tutto separato dal titolo, progressi e sblocchi, amici con miniature dei giochi riconosciuti. |
| [Sources/NXLibrary/Views/Shell/ActivityCenterView.swift](../../Sources/NXLibrary/Views/Shell/ActivityCenterView.swift) | Compilazione e Cloud, code, Resume, progressi ed esiti. Nasconde Annulla quando il worker entra in installazione. |
| [Sources/NXLibraryCore/Selene/ActionBarOrder.swift](../../Sources/NXLibraryCore/Selene/ActionBarOrder.swift) | Ruoli e ordine dei pulsanti di un pannello o di una domanda: distruttivo, ritorno, altri, principale; elenco verticale e focus iniziale. |
| [Sources/NXLibraryCore/Selene/ActivityCenterFocus.swift](../../Sources/NXLibraryCore/Selene/ActivityCenterFocus.swift) | Identità e navigazione delle righe attive, in coda, concluse e del comando Clear all. |
| [Sources/NXLibraryCore/NXLibraryCore.swift](../../Sources/NXLibraryCore/NXLibraryCore.swift) | Espone la versione nominale del modulo Core. |
| [LaunchReveal.swift](../../Sources/NXLibrary/Views/Launch/LaunchReveal.swift) | Rende visibile la finestra al primo frame del moonlight, con dissolvenza e scadenza, poi consente il fullscreen; integra il bootstrap con un NSView non interattivo. |
| [DevelopmentStartupView.swift](../../Sources/NXLibrary/Views/Launch/DevelopmentStartupView.swift) | Avvio asincrono: blocco del profilo, copia prima degli scrittori, avanzamento, recupero e conflitto legacy; segnala i lavori lasciati alla versione precedente. |
| [DowngradeWarningView.swift](../../Sources/NXLibrary/Views/Launch/DowngradeWarningView.swift) | Avvisi Selene sul ritorno a 0.3.0, gruppi omessi, spazio insufficiente e scelte con mouse, tastiera e controller. |
| [AppShellState.swift](../../Sources/NXLibrary/Views/Shell/AppShellState.swift) | Prepara coordinatore, router, fonti, lingua e tema. Collega le impostazioni al router e al delegato, che riceve anche le attività per la chiusura. |

## Coordinamento applicativo

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/ViewModels/AppViewModel.swift](../../Sources/NXLibrary/ViewModels/AppViewModel.swift) | Coordina libreria e catalogo, incluse le richieste di scansione corrente e in attesa, sorgenti, lancio, primo avvio, Game Options, spazio su disco e icona del Dock. Tiene il pin, crea i modelli Switch, conserva il modello Nextendo per profilo e manda gli esiti HTTP e di rete alla Console. Conserva la scelta Steam del Setup. Il modello degli avvisi decide ordine e focus; `confirmSetting` parte da Annulla. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Storage.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Storage.swift) | Spazio su disco: misura, cancella cache e log. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Library.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Library.swift) | Scansione e cartella Game apps, scarto delle richieste annullate prima di pubblicare, adozione con conferma e avviso per contenuto non verificato, trascinamento e collegamento di sorgenti per title ID. |
| [Sources/NXLibrary/ViewModels/AppViewModel+CloudLibrary.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+CloudLibrary.swift) | Verifica l’ambito senza importare e distingue ID approvato delle sorgenti da disponibilità. Conserva offerte non verificate del riferimento, lega la coda all’eseguibile e Rebuild alla selezione mostrata. Play riprende solo dopo l’installazione. |
| [Sources/NXLibrary/ViewModels/AppViewModel+CloudLibraryMove.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+CloudLibraryMove.swift) | Ricontrolla l'origine approvata, usa una configurazione privata sotto lock e annulla il comando senza perdere il registro. Salva la destinazione per ID solo dopo l'esito verificato. |
| [Sources/NXLibrary/ViewModels/AppViewModel+DriveTool.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+DriveTool.swift) | Spiega rclone e chiede consenso alla ripresa, incluso il percorso esplicito delle sorgenti 0.3.0; coordina download, esito e Cestino della copia propria. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Activity.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Activity.swift) | Ripristina, registra e cancella gli esiti; invia Retry al proprietario del lavoro e conserva l'esito dello spostamento pendente o mostra il percorso del registro illeggibile. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Play.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Play.swift) | Entrata Play comune; prepara il target e il profilo correnti e adatta il percorso nxnative al contratto Core. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Launch.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Launch.swift) | Play nxnative: ripresa dopo scambio cloud, firma dell'icona o conferma VPN con profilo e osservatore iniziali; salvataggi, mod, Home e schermo. |
| [Sources/NXLibrary/ViewModels/NextendoSettings.swift](../../Sources/NXLibrary/ViewModels/NextendoSettings.swift) | Scheda Nextendo in memoria, store del token del profilo, accesso e disconnessione, aggiornamento amici, ultimi dati noti per l'overlay e stato della pubblicazione. |
| [Sources/NXLibrary/ViewModels/AppViewModel+GameActions.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+GameActions.swift) | Azioni su un gioco: Game options, preferito, nascosto, salvataggi cloud, chiusura, rimozione e Mostra nel Finder. |
| [Sources/NXLibrary/ViewModels/AppViewModel+GameFiles.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+GameFiles.swift) | Verifica giochi e percorsi prima della rimozione; passa al catalogo tutte le sorgenti candidate, anche ripetute, e identifica gli originali nell’avviso di errore; selettore Ryujinx e log. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Mods.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Mods.swift) | Crea lo `ModStore`, il valore della riga Mods e gli errori, inclusi nomi condivisi da File e Code mods. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Controller.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Controller.swift) | Sceglie il gioco su cui agiscono i comandi del menu, anche dalla Collection di un profilo. |
| [AppViewModel+PlayersScreen.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+PlayersScreen.swift) | Collega il pannello giocatori al piano, ai profili, al registro delle manette e alle capacità del gioco. |
| [AppViewModel+Players.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Players.swift) | Legge il piano comune e prepara la cache di prove Git e impronte HID per il Play senza attese di rilevamento. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Diagnostics.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Diagnostics.swift) | Raccoglie ambiente, toolchain e ultimo build per il rapporto diagnostico ripulito. |
| [Sources/NXLibrary/ViewModels/AppViewModel+PendingInstall.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+PendingInstall.swift) | Riprende le installazioni differite rispettando i lease, espone il motivo dell'errore e aggiorna il confronto cloud dopo la pubblicazione del bundle. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Porting.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Porting.swift) | Prepara tile, pill e stima del porting; proietta disponibilità locale e remota per il filtro Cloud e i badge senza leggere il disco. |
| [Sources/NXLibrary/ViewModels/AppViewModel+Saves.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Saves.swift) | Risolve contesto e identità se il profilo è leggibile, coordina i lease con motivo di rifiuto e recupera i journal del profilo selezionato. |
| [Sources/NXLibrary/ViewModels/AppViewModel+SteamGridDB.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+SteamGridDB.swift) | Verifica, salva e rimuove la chiave SteamGridDB dell’utente senza registrarne il valore. |
| [Sources/NXLibrary/ViewModels/LibraryRefreshModel.swift](../../Sources/NXLibrary/ViewModels/LibraryRefreshModel.swift) | Il solo aggiornamento della libreria: app, fonti attive e cloud insieme; la scansione locale conserva la richiesta, che Cancel o un nuovo refresh annulla. Parole del messaggio e del centro attività. |
| [Sources/NXLibrary/ViewModels/AppIconModel.swift](../../Sources/NXLibrary/ViewModels/AppIconModel.swift) | Applica o ripristina l’icona senza toccare giochi in esecuzione o in build. Conserva la richiesta Play legata al dialogo durante la firma; Change artwork ne osserva l’avanzamento. |
| [CommandPalette.swift](../../Sources/NXLibrary/ViewModels/CommandPalette.swift) | Stato di Cerca ovunque: voci, gruppi e focus per identità al refresh, senza una sostituzione implicita. |
| [Sources/NXLibrary/ViewModels/CheatsModel.swift](../../Sources/NXLibrary/ViewModels/CheatsModel.swift) | Adatta Core e bundle installato al pannello Cheats, alla riga di stato, alla pagina del gioco e alla diagnostica; chiede a git l'engine dell'app con `prepare(for:)`; raggiunge il coordinatore solo da `app`. |
| [Sources/NXLibrary/ViewModels/GameInboxModel.swift](../../Sources/NXLibrary/ViewModels/GameInboxModel.swift) | Cartella configurabile, lettura con nxnative solo se l’Inbox è attiva e le chiavi sono valide, avviso Game files; verifica del catalogo e Cestino nello stesso turno del main actor. |
| [Sources/NXLibrary/ViewModels/PortingModel.swift](../../Sources/NXLibrary/ViewModels/PortingModel.swift) | Stato di Add Game e del porting: bozza, selezione delle sorgenti e spazio richiesto, chiavi, passo del wizard, stato della build mostrato ed esito. Il lavoro sta nelle estensioni qui sotto; raggiunge il coordinatore solo da `app`. |
| [Sources/NXLibrary/ViewModels/PortingModel+AddGame.swift](../../Sources/NXLibrary/ViewModels/PortingModel+AddGame.swift) | Selettore e preparazione condivisi dei file, scansione e scelta delle sorgenti, passi di Add Game e regole di Back. |
| [Sources/NXLibrary/ViewModels/PortingModel+Build.swift](../../Sources/NXLibrary/ViewModels/PortingModel+Build.swift) | Avvio con gioco chiuso, annullamento del porting o della verifica cache, nuovo tentativo e FIFO persistente. |
| [Sources/NXLibrary/ViewModels/PortingModel+BuildEvents.swift](../../Sources/NXLibrary/ViewModels/PortingModel+BuildEvents.swift) | Eventi del motore, timer, adozione cache in background, diagnosi da log e codice di uscita e salvataggio dell'esito. |
| [Sources/NXLibrary/ViewModels/PortingModel+Failure.swift](../../Sources/NXLibrary/ViewModels/PortingModel+Failure.swift) | Port anyway con override nella singola richiesta, notifica di fine e azioni dell’errore. |
| [Sources/NXLibrary/ViewModels/PortingModel+Folders.swift](../../Sources/NXLibrary/ViewModels/PortingModel+Folders.swift) | Cartelle della build, spazio libero, sorgenti supportate e durata delle fasi finali per la stima. |
| [Sources/NXLibrary/ViewModels/RuntimeSettingsModel.swift](../../Sources/NXLibrary/ViewModels/RuntimeSettingsModel.swift) | Legge e scrive le scelte, anche multigiocatore, per Game Options, More settings e i default dei nuovi giochi. |
| [Sources/NXLibrary/ViewModels/SavePanelModel.swift](../../Sources/NXLibrary/ViewModels/SavePanelModel.swift) | Gestisce backup, anteprime e recupero con un percorso fissato dal lease; rifiuta le azioni se il profilo non si legge. |
| [Sources/NXLibrary/ViewModels/SetupCheckModel.swift](../../Sources/NXLibrary/ViewModels/SetupCheckModel.swift) | Esegue probe e installazioni del Setup, chiede conferma con il percorso per cambiare un checkout e inoltra l’errore di importazione delle chiavi. |
| [Sources/NXLibrary/ViewModels/SetupModel.swift](../../Sources/NXLibrary/ViewModels/SetupModel.swift) | Tiene il Setup Switch: cartella, validità e commit dell'engine, sorgenti che l'engine sa leggere, controllo Upstream e scelta della cartella; chiavi importate (percorso, validità, riepilogo, importazione, errore e selettore); controllo dell'ambiente, compatibilità, override della toolchain non testata, gate e suo riepilogo, Python e Xcode dell'engine, versioni Metal. Ricarica la scelta Newest engine senza effetti durante l'inizializzazione. Raggiunge il coordinatore solo da `app`. |
| [Sources/NXLibrary/ViewModels/SetupModel+NewestEngine.swift](../../Sources/NXLibrary/ViewModels/SetupModel+NewestEngine.swift) | Usa l’engine upstream più nuovo o torna a quello testato dal suo repository, accende l’override e controlla se main è utilizzabile. |
| [Sources/NXLibrary/ViewModels/StoreMetadataModel.swift](../../Sources/NXLibrary/ViewModels/StoreMetadataModel.swift) | Tiene i dati dello store Nintendo, le code per lingua, gli screenshot di ripiego e le scelte di Change metadata; svuotando la cache invalida i risultati in corso. |

## Modelli dello stato applicativo

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Models/AppIconAppearanceMode.swift](../../Sources/NXLibrary/Models/AppIconAppearanceMode.swift) | Espone trama nativa e particelle, conservando i valori salvati. |
| [Sources/NXLibrary/Models/BuildStageItem.swift](../../Sources/NXLibrary/Models/BuildStageItem.swift) | Rappresenta una fase del porting nella lista di avanzamento. |
| [Sources/NXLibrary/Models/BuildState.swift](../../Sources/NXLibrary/Models/BuildState.swift) | Enumera gli esiti e lo stato operativo del porting nella UI. |
| [Sources/NXLibrary/Models/GameDetailsInfo.swift](../../Sources/NXLibrary/Models/GameDetailsInfo.swift) | Ispeziona DLC e salvataggi del bundle e prepara dimensioni localizzate e dettagli del gioco. |
| [Sources/NXLibrary/Models/GamepadType.swift](../../Sources/NXLibrary/Models/GamepadType.swift) | Definisce brand, azioni semantiche, tabelle Oort e Arcane e dati per la guida del controller. |
| [Sources/NXLibrary/Models/LogEntry.swift](../../Sources/NXLibrary/Models/LogEntry.swift) | Rappresenta messaggi, livelli e identità delle righe di log mostrate dall’app. |
| [Sources/NXLibrary/Models/PlayedGame.swift](../../Sources/NXLibrary/Models/PlayedGame.swift) | Gioco nxnative o Steam per schermata di lancio e card di fine sessione. |
| [Sources/NXLibrary/Models/NXLibraryError.swift](../../Sources/NXLibrary/Models/NXLibraryError.swift) | Raggruppa errori applicativi e relative spiegazioni, compresi i rifiuti prima del porting. |
| [Sources/NXLibrary/Models/SelectableGame.swift](../../Sources/NXLibrary/Models/SelectableGame.swift) | Rappresenta le sorgenti selezionabili, la loro dimensione localizzata e l’ordinamento delle versioni nel wizard. |
| [Sources/NXLibrary/Models/UpstreamCheckState.swift](../../Sources/NXLibrary/Models/UpstreamCheckState.swift) | Rappresenta gli stati del controllo del changelog upstream. |

## Integrazione con macOS e servizi applicativi

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Services/AppUpdater.swift](../../Sources/NXLibrary/Services/AppUpdater.swift) | Coordina aggiornamento e riavvio; se il gate blocca l'installazione, conserva lo ZIP verificato per il tentativo successivo. |
| [Sources/NXLibrary/Services/NativeMenuCommands.swift](../../Sources/NXLibrary/Services/NativeMenuCommands.swift) | Coordina tracking, disponibilità nella scena e passaggio differito dai menu macOS alle azioni del launcher. |
| [Sources/NXLibrary/Services/NextendoBrowserSignIn.swift](../../Sources/NXLibrary/Services/NextendoBrowserSignIn.swift) | Apre il browser predefinito e riceve una callback HTTP su loopback, con annullamento e scadenza. |
| [Sources/NXLibrary/Services/ControllerSource.swift](../../Sources/NXLibrary/Services/ControllerSource.swift) | Contratto per connessioni, input, batteria e identificazione esplicita dei pad. |
| [Sources/NXLibrary/Services/ControllerHardwareID.swift](../../Sources/NXLibrary/Services/ControllerHardwareID.swift) | Deriva un HMAC con sale locale dal seriale HID o dall'indirizzo Bluetooth esposto; non salva il valore originale. |
| [Sources/NXLibrary/Services/ControllerRoster.swift](../../Sources/NXLibrary/Services/ControllerRoster.swift) | Assegna ID di connessione e riconcilia gruppi HID/GameController senza attribuire il seriale a un pad per nome. |
| [Sources/NXLibrary/Services/GameControllerService.swift](../../Sources/NXLibrary/Services/GameControllerService.swift) | Pubblica pad, batteria, pressioni e attività. Sorveglia la scadenza HID anche con un pad attivo e filtra le ripetizioni dei tasti di conferma. Giocatori può consumare una pressione prima della navigazione. |
| [Sources/NXLibrary/Services/GCControllerSource.swift](../../Sources/NXLibrary/Services/GCControllerSource.swift) | Osserva i pad GameController e la scelta Home di macOS, legge batteria e simboli e identifica il pad con luce o vibrazione. |
| [Sources/NXLibrary/Services/HIDControllerSource.swift](../../Sources/NXLibrary/Services/HIDControllerSource.swift) | Osserva i pad HID fisici in modalità condivisa; riserva i report Nintendo `0x3F` e `0x30` all'input Nintendo. |
| [Sources/NXLibrary/Services/LaunchReadinessProbe.swift](../../Sources/NXLibrary/Services/LaunchReadinessProbe.swift) | Attende una finestra visibile del gioco (per bundle o, per Steam, per pid) per terminare la schermata di lancio. |
| [Sources/NXLibrary/Services/NotificationService.swift](../../Sources/NXLibrary/Services/NotificationService.swift) | Invia notifiche dei porting e instrada i clic verso il titolo o l’errore interessato. |
| [Sources/NXLibrary/Services/OnlineBackgroundService.swift](../../Sources/NXLibrary/Services/OnlineBackgroundService.swift) | Carica pagine e miniature e scarica wallpaper o video conservando progressi e crediti. |
| [Sources/NXLibrary/Services/RunningGameMonitor.swift](../../Sources/NXLibrary/Services/RunningGameMonitor.swift) | Riconcilia applicazioni e libreria; osserva pausa, ripresa e uscita di `dmhost`, invia Resume e Quit con ripiego SIGTERM. |
| [Sources/NXLibrary/Services/LibraryWindow.swift](../../Sources/NXLibrary/Services/LibraryWindow.swift) | Riporta davanti la finestra di Arcane dopo un gioco nxnative o Steam, mai sopra un gioco della libreria. |
| [Sources/NXLibrary/Services/SoundEffectService.swift](../../Sources/NXLibrary/Services/SoundEffectService.swift) | Riproduce i cue del pacchetto scelto o di Selene, applica attivazione e volume, interrompe l’audio durante il gioco. |
| [Sources/NXLibrary/Services/SystemDetector.swift](../../Sources/NXLibrary/Services/SystemDetector.swift) | Individua checkout nxnative, root personale e possibili percorsi delle chiavi. |

## OortCore · logica portabile

Cartella `Sources/OortCore/`, senza risorse né dipendenze.

| File | Responsabilità |
|---|---|
| [ControllerInput.swift](../../Sources/OortCore/ControllerInput.swift) | Decodifica report Nintendo, calibra stick, calcola transizioni e decide il ripiego HID. |
| [FocusIndex.swift](../../Sources/OortCore/FocusIndex.swift) | Mantiene un indice di focus entro i limiti della lista. |
| [HoldDetector.swift](../../Sources/OortCore/HoldDetector.swift) | Distingue pressione breve, prolungata e annullata. |
| [LineBuffer.swift](../../Sources/OortCore/LineBuffer.swift) | Ricompone righe parziali separate da `\n` o `\r`. |
| [Credits.swift](../../Sources/OortCore/Credits.swift) | Legge `credits.json`: gruppi, ruoli e note legali per sistema e lingua. |
| [MoonlightField.swift](../../Sources/OortCore/MoonlightField.swift) | Genera i dati delle particelle senza Metal; condivide `SplitMix` nel package per il cue Download. |
| [MoveDirection.swift](../../Sources/OortCore/MoveDirection.swift) | Espone le quattro direzioni del focus. |
| [Palette.swift](../../Sources/OortCore/Palette.swift) | Cerca ovunque: confronto tollerante, gruppi, «Vedi tutto», focus e recenti. |
| [ProfileKeypad.swift](../../Sources/OortCore/ProfileKeypad.swift) | Griglia PIN con lunghezza passata dal chiamante e conferma esplicita. |
| [VersionNumber.swift](../../Sources/OortCore/VersionNumber.swift) | Confronta numeri di versione puntati parte per parte. |

## Core · app: aggiornamento, primo avvio, diagnostica e comandi

Cartella `Sources/NXLibraryCore/App/`.

| File | Responsabilità |
|---|---|
| [FileBrowser.swift](../../Sources/NXLibraryCore/App/FileBrowser.swift) | Elenco asincrono dei metadati delle cartelle, luoghi, filtri e risalita del selettore. |
| [Sources/NXLibraryCore/App/AppRouter.swift](../../Sources/NXLibraryCore/App/AppRouter.swift) | Gestisce route, ritorno, Inbox, menu, ricerca, focus e richieste Spotlight. Una bozza sospende l’uscita da Settings; i suoi dialoghi bloccano la palette. |
| [Sources/NXLibraryCore/App/AppRouter.swift](../../Sources/NXLibraryCore/App/AppRouter.swift) | Gestisce route, ritorno, Inbox, menu, ricerca, focus e richieste Spotlight. Una bozza di Settings sospende l'azione prima di lasciare la schermata. ShellBackdropCover definisce la priorità degli strati. |
| [Sources/NXLibraryCore/App/UndoOffers.swift](../../Sources/NXLibraryCore/App/UndoOffers.swift) | L’ultimo gesto reversibile e il modo di annullarlo, una volta: avviso, ⌘Z e centro attività. Un altro profilo lo toglie. |
| [Sources/NXLibraryCore/App/NoticeFocus.swift](../../Sources/NXLibraryCore/App/NoticeFocus.swift) | I tasti dell’avviso a schermo, raggiunti solo su richiesta; la schermata conserva il proprio focus. |
| [Sources/NXLibraryCore/App/Tips.swift](../../Sources/NXLibraryCore/App/Tips.swift) | Due suggerimenti, ciascuno una volta su questo Mac, uno per sessione, mai se sono spenti. |
| [Sources/NXLibraryCore/App/ProfileLayers.swift](../../Sources/NXLibraryCore/App/ProfileLayers.swift) | Strati della schermata profilo (selettore, procedura guidata, domanda di rimozione): solo quella in cima riceve l’input e mostra i suggerimenti; la procedura guidata nasconde il selettore. |
| [Sources/NXLibraryCore/App/FirstRunSetup.swift](../../Sources/NXLibraryCore/App/FirstRunSetup.swift) | Ordine e ripresa del tour, completamento e riapertura; conserva il percorso legacy e il consumo unico della selezione in Your games. |
| [Sources/NXLibraryCore/App/FirstRunFindings.swift](../../Sources/NXLibraryCore/App/FirstRunFindings.swift) | Conta giochi Steam senza modifiche, e le app del modulo con il conteggio che riceve; distingue lettura incompleta da assenza e permette nuove letture annullabili. |
| [Sources/NXLibraryCore/App/ArcaneWelcome.swift](../../Sources/NXLibraryCore/App/ArcaneWelcome.swift) | Decide quando compare il benvenuto in Arcane, l'offerta di Steam, il focus e come ogni uscita lo segna visto. |
| [Sources/NXLibraryCore/App/ReleaseNotesLayout.swift](../../Sources/NXLibraryCore/App/ReleaseNotesLayout.swift) | Divide le note di release in titoli, voci e testo, una riga per volta, per il dialogo degli aggiornamenti. |
| [PaletteAction.swift](../../Sources/NXLibraryCore/App/PaletteAction.swift) | Azioni di Cerca ovunque in cinque sezioni, scorciatoie e recenti per profilo. |
| [Sources/NXLibraryCore/App/BoundedCommand.swift](../../Sources/NXLibraryCore/App/BoundedCommand.swift) | Avvia gruppi isolati per i comandi cloud, legge e scrive pipe non bloccanti, delimita inattività e vita dei figli. |
| [Sources/NXLibraryCore/App/CommandRunner.swift](../../Sources/NXLibraryCore/App/CommandRunner.swift) | Comandi sincroni o streaming senza run loop; per il cloud inoltra input e annullamento all'esecutore con scadenza. |
| [Sources/NXLibraryCore/App/DiagnosticsReport.swift](../../Sources/NXLibraryCore/App/DiagnosticsReport.swift) | Genera il rapporto diagnostico, con i collegamenti dei workspace che non portano a nulla, e rimuove percorso home e valori riconosciuti come chiavi. |
| [Sources/NXLibraryCore/App/AppUpdate.swift](../../Sources/NXLibraryCore/App/AppUpdate.swift) | Definisce repository, versioni, pagina condivisa per le prerelease, verifica del download e sostituzione atomica; riconosce App Translocation. |
| [Sources/NXLibraryCore/App/AppBundleRename.swift](../../Sources/NXLibraryCore/App/AppBundleRename.swift) | Decide se una copia release che si chiama ancora `NX Library.app` diventa `Oort NX.app` alla chiusura, e fa lo spostamento nella stessa cartella. |
| [Sources/NXLibraryCore/App/AppUpdatePresentation.swift](../../Sources/NXLibraryCore/App/AppUpdatePresentation.swift) | Definisce gli stati dell’updater e il gate di installazione per versione e tipo di copia. |
| [Sources/NXLibraryCore/App/AppUpdateDownload.swift](../../Sources/NXLibraryCore/App/AppUpdateDownload.swift) | Scarica gli aggiornamenti con limiti di dimensione, redirect HTTPS vincolati a GitHub e gestione del file temporaneo. |
| [Sources/NXLibraryCore/App/BoundedDownload.swift](../../Sources/NXLibraryCore/App/BoundedDownload.swift) | Lettura HTTP limitata a blocchi e senza redirect, condivisa fra base e modulo per i provider, Steam e Nextendo. |
| [Sources/NXLibraryCore/App/ConnectivityWatcher.swift](../../Sources/NXLibraryCore/App/ConnectivityWatcher.swift) | Avvisa sul main thread quando il Mac torna online, perché il giro delle descrizioni riprenda da solo; la prima lettura non conta. |
| [Sources/NXLibraryCore/App/DisplayNameCache.swift](../../Sources/NXLibraryCore/App/DisplayNameCache.swift) | Nomi visualizzati di cartelle e volumi letti una volta per URL: la pagina si ricostruisce a ogni disegno e un disco esterno in stop bloccherebbe ogni volta. |
| [Sources/NXLibraryCore/App/AppIdentity.swift](../../Sources/NXLibraryCore/App/AppIdentity.swift) | Distingue Oort NX (nome visibile) da Arcane (identità e User-Agent), con vecchio nome, modulo Porting e pagine del progetto e del finanziamento. |
| [Sources/NXLibraryCore/App/Credits+Bundled.swift](../../Sources/NXLibraryCore/App/Credits+Bundled.swift) | I crediti inclusi nell’app. |
| [Sources/NXLibraryCore/App/AppDataProfile.swift](../../Sources/NXLibraryCore/App/AppDataProfile.swift) | Policy di percorsi e preferenze; separa release, Dev, essai 2 e fixture Debug. |
| [Sources/NXLibraryCore/App/LibraryMove.swift](../../Sources/NXLibraryCore/App/LibraryMove.swift) | Copia verificata della libreria precedente; conserva il registro di rimozione come documento inattivo. |
| [Sources/NXLibraryCore/App/LibraryPaths.swift](../../Sources/NXLibraryCore/App/LibraryPaths.swift) | File della libreria con percorsi, nomi dei registri di rimozione e collegamenti morti dei workspace. I percorsi dei log conservano il profilo d'origine. |
| [Sources/NXLibraryCore/App/LibraryPathRepair.swift](../../Sources/NXLibraryCore/App/LibraryPathRepair.swift) | Riparazione ripetibile di una libreria già copiata: isola il registro ereditato, conserva gli originali e sposta i percorsi verificati. |
| [Sources/NXLibraryCore/App/DevelopmentProfileImporter.swift](../../Sources/NXLibraryCore/App/DevelopmentProfileImporter.swift) | Copia selettiva senza modificare la sorgente; per l’essai 2 usa un elenco ristretto senza preferenze. Chiude le sessioni copiate all’ultimo heartbeat. |
| [Sources/NXLibraryCore/App/DowngradeCheckpoint.swift](../../Sources/NXLibraryCore/App/DowngradeCheckpoint.swift) | Copia privata con file essenziali prioritari, SHA-256, gruppi omessi, conferma e rotazione riprendibile senza perdere le due copie precedenti alla pubblicazione. |
| [Sources/NXLibraryCore/App/DevelopmentOperationStore.swift](../../Sources/NXLibraryCore/App/DevelopmentOperationStore.swift) | Autorizzazioni persistenti per le operazioni richieste nella Dev, distinte da quelle importate. |
| [Sources/NXLibraryCore/App/BuildInstallIO.swift](../../Sources/NXLibraryCore/App/BuildInstallIO.swift) | Confine sostituibile per la pubblicazione atomica di un bundle (stesso volume, rinomina o scambio) e il suo errore; lo usano installazione dei giochi e aggiornamento di Arcane. |

## Core · catalogo comune e fonti

Cartella `Sources/NXLibraryCore/Catalog/`.

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Catalog/CatalogGame.swift](../../Sources/NXLibraryCore/Catalog/CatalogGame.swift) | Voce del catalogo attorno al record della sua fonte (`any CatalogSourceRecord`), identità e personalizzazioni con namespace, uguaglianza per tipo e valore; osservazioni delle installazioni Steam; lookup condiviso della prima installazione disponibile, separato dal gate di Play. |
| [Sources/NXLibraryCore/Catalog/CatalogSourceRecord.swift](../../Sources/NXLibraryCore/Catalog/CatalogSourceRecord.swift) | Contratto del record di una fonte, integrazione aperta come stringa e tipi del lettore (`CatalogRecordKinds`, in `userInfo`); Steam e collegamenti Mac sono nella base. |
| [Sources/NXLibraryCore/Catalog/SteamCatalogGame+Record.swift](../../Sources/NXLibraryCore/Catalog/SteamCatalogGame+Record.swift) | Record Steam nel contratto: validazione delle installazioni, presenza, gate di Play e termini di ricerca. |
| [Sources/NXLibraryCore/Catalog/CatalogDocument.swift](../../Sources/NXLibraryCore/Catalog/CatalogDocument.swift) | Schema, revisione, base legacy, fonti e validazione delle identità, inclusa l’unicità dei percorsi dei collegamenti Mac. Conserva intatti i record delle integrazioni sconosciute. |
| [Sources/NXLibraryCore/Catalog/CatalogJSON.swift](../../Sources/NXLibraryCore/Catalog/CatalogJSON.swift) | Valore JSON tenuto com’è stato letto (numeri `Decimal`), per i record e le fonti che il catalogo non conosce e le impostazioni dei moduli; si converte da e verso un tipo `Codable`. |
| [Sources/NXLibraryCore/Catalog/CatalogGamePresentation.swift](../../Sources/NXLibraryCore/Catalog/CatalogGamePresentation.swift) | Contratto comune per presentazione, operazioni supportate e target di avvio; nessuna operazione I/O. |
| [Sources/NXLibraryCore/Catalog/GamePlay.swift](../../Sources/NXLibraryCore/Catalog/GamePlay.swift) | Contratto Play: target e installazione, disponibilità, profilo, risultato e osservazioni; seleziona il connettore per fonte. |
| [Sources/NXLibraryCore/Catalog/CatalogStore.swift](../../Sources/NXLibraryCore/Catalog/CatalogStore.swift) | Conversione legacy con impronta dei byte originali anche se i percorsi cambiano in memoria, letture limitate, revisioni attese, lock, archiviazione dei conflitti e Cestino del volume. |
| [Sources/NXLibraryCore/Catalog/CatalogPublication.swift](../../Sources/NXLibraryCore/Catalog/CatalogPublication.swift) | Staging verificato, creazione esclusiva e sostituzione atomica, con confine di errore controllabile. |
| [Sources/NXLibraryCore/Catalog/CatalogRepository.swift](../../Sources/NXLibraryCore/Catalog/CatalogRepository.swift) | Modifiche tipizzate del catalogo, inclusi i collegamenti Mac; delega la rimozione di file alla transazione dello store. |
| [Sources/NXLibraryCore/Catalog/CatalogStore+Removal.swift](../../Sources/NXLibraryCore/Catalog/CatalogStore+Removal.swift) | Rifiuta le identità ripetute, conserva i registri ereditati senza ripeterli e recupera soltanto le rimozioni della libreria corrente. |
| [Sources/NXLibraryCore/Catalog/MacShortcutRecord.swift](../../Sources/NXLibraryCore/Catalog/MacShortcutRecord.swift) | UUID, percorso canonico, bundle ID e verifica in sola lettura di un’app Mac scelta; ricollega solo la stessa identità. |
| [Sources/NXLibraryCore/Catalog/CatalogRecovery.swift](../../Sources/NXLibraryCore/Catalog/CatalogRecovery.swift) | Offerte di recupero e conflitto legacy con impronte degli input, rivalidate all’accettazione. |
| [Sources/NXLibraryCore/Catalog/CatalogPersonalizations.swift](../../Sources/NXLibraryCore/Catalog/CatalogPersonalizations.swift) | Lookup personali immutabili per identità. |
| [Sources/NXLibraryCore/Catalog/CatalogErrorCopy.swift](../../Sources/NXLibraryCore/Catalog/CatalogErrorCopy.swift) | Errori recuperabili del catalogo nelle sei lingue. |
| [Sources/NXLibraryCore/Catalog/CatalogGameOptions.swift](../../Sources/NXLibraryCore/Catalog/CatalogGameOptions.swift) | Ordine unico delle operazioni comuni della libreria; ciò che una fonte può fare dipende dal suo record (nessuna modifica nxnative su un gioco Steam). |
| [Sources/NXLibraryCore/Catalog/CatalogSourcesModel.swift](../../Sources/NXLibraryCore/Catalog/CatalogSourcesModel.swift) | Opt-in, worker annullabile e stato Steam; discoveryRoot conserva la cartella scelta anche con fonte spenta; pubblica solo documenti salvati dal repository. |
| [Sources/NXLibraryCore/Catalog/CatalogLibraryProjection.swift](../../Sources/NXLibraryCore/Catalog/CatalogLibraryProjection.swift) | Visibilità comune per fonti attive e giochi riconosciuti; nessuna scansione. |
| [Sources/NXLibraryCore/Catalog/SteamCatalogReconciler.swift](../../Sources/NXLibraryCore/Catalog/SteamCatalogReconciler.swift) | Ticket e fusione pura degli snapshot Steam, identità conservate e assenza trattata secondo completezza. |

## Core · libreria, sessioni e spazio

Cartella `Sources/NXLibraryCore/Library/`.

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Library/LibraryFilter.swift](../../Sources/NXLibraryCore/Library/LibraryFilter.swift) | Definisce filtri, storico e query condivisa del catalogo misto; Cloud riceve gli ID solo remoti dal chiamante. `LibraryQueryRecord` è il contratto comune con ricerca e Surprise. |
| [Sources/NXLibraryCore/Library/RecentSearches.swift](../../Sources/NXLibraryCore/Library/RecentSearches.swift) | Le ultime quattro ricerche che hanno portato a un gioco, per profilo e solo su questo Mac; si cancellano. |
| [Sources/NXLibraryCore/Library/LibrarySelectionState.swift](../../Sources/NXLibraryCore/Library/LibrarySelectionState.swift) | Mantiene selezione e spostamento nel risultato filtrato della Collection. |
| [Sources/NXLibraryCore/Library/LibraryPresentation.swift](../../Sources/NXLibraryCore/Library/LibraryPresentation.swift) | Formatta metadati e statistiche temporali per le schermate della libreria: i valori pronti e la strada Steam; quella Switch sta in `ArcanePorting/Library/LibraryPresentation+Porting.swift`. |
| [Sources/NXLibraryCore/Library/PlaySession.swift](../../Sources/NXLibraryCore/Library/PlaySession.swift) | Descrive una sessione persistibile con gioco e riferimenti temporali. |
| [Sources/NXLibraryCore/Library/ActivitySummary.swift](../../Sources/NXLibraryCore/Library/ActivitySummary.swift) | Aggrega sessioni, giorni e tempi della settimana per la scheda Activity. |
| [Sources/NXLibraryCore/Library/ProfilePageCards.swift](../../Sources/NXLibraryCore/Library/ProfilePageCards.swift) | Ordine e visibilità per profilo, gruppi dell’attività e geometria della griglia. |
| [Sources/NXLibraryCore/Library/PlaySessionStore.swift](../../Sources/NXLibraryCore/Library/PlaySessionStore.swift) | Registra avvio, heartbeat e fine; pubblica insieme storico e totali archiviati, importa i file precedenti e unisce i totali Steam con le sessioni successive. |
| [Sources/NXLibraryCore/Library/LocalProfileStore.swift](../../Sources/NXLibraryCore/Library/LocalProfileStore.swift) | Identità, preferiti, scelta della piattaforma, presenza e visibilità, codice e profilo di avvio; protegge l'originale e include lo storico unico nella copia di migrazione. |
| [Sources/NXLibraryCore/Players/PlayerLaunchEnvironment.swift](../../Sources/NXLibraryCore/Players/PlayerLaunchEnvironment.swift) | Calcola le opzioni supportate, rispetta `env.txt` e limita il nickname a offline e locale. |
| [PlayerPlan.swift](../../Sources/NXLibraryCore/Players/PlayerPlan.swift) | Posti, profili protetti, tre modalità e giocatore destinatario facoltativo per la fusione. |
| [PlayerPlanStore.swift](../../Sources/NXLibraryCore/Players/PlayerPlanStore.swift) | Piano JSON v1, formato Codable anche per Settings, lettura dei piani senza destinatario e scrittura atomica del file storico senza perdere i campi sconosciuti. |
| [PlayerControllerResolution.swift](../../Sources/NXLibraryCore/Players/PlayerControllerResolution.swift) | Distingue la conferma per una connessione da un’identità hardware e conserva i posti non attivi durante la fusione. |
| [Sources/NXLibraryCore/Library/ProfileKeypad.swift](../../Sources/NXLibraryCore/Library/ProfileKeypad.swift) | Riesporta `OortCore` e applica la lunghezza del PIN di `LocalProfile` alla tastiera portabile. |
| [Sources/NXLibraryCore/Library/GameFocus.swift](../../Sources/NXLibraryCore/Library/GameFocus.swift) | Quando un gioco che esce riporta Arcane davanti: solo se era l’app in primo piano e nessun altro gioco della libreria è aperto. |
| [Sources/NXLibraryCore/Library/SessionSummary.swift](../../Sources/NXLibraryCore/Library/SessionSummary.swift) | Cosa dice la card di fine sessione: gioco, durata di questa sessione e totale scritto come nelle info del gioco; niente card sotto i dieci secondi. |
| [Sources/NXLibraryCore/Library/RunningAppsTracker.swift](../../Sources/NXLibraryCore/Library/RunningAppsTracker.swift) | Snapshot dei bundle ID delle applicazioni in esecuzione e cosa è partito o finito dall’ultima lettura. |
| [Sources/NXLibraryCore/Library/DirectorySize.swift](../../Sources/NXLibraryCore/Library/DirectorySize.swift) | Misura le cartelle con fts; il modulo Porting può contare anche i file nascosti nelle cartelle cache ignorate. |
| [Sources/NXLibraryCore/App/FileHandle+Chunks.swift](../../Sources/NXLibraryCore/App/FileHandle+Chunks.swift) | Legge a blocchi, rilasciandoli uno alla volta durante il calcolo delle impronte. |
| [Sources/NXLibraryCore/Library/StorageBackend.swift](../../Sources/NXLibraryCore/Library/StorageBackend.swift) | Contratto oggetti remoti: chiavi e impronte serializzabili, trasferimenti, avanzamento e lease condiviso. |
| [Sources/NXLibraryCore/Library/CloudLibraryFailure.swift](../../Sources/NXLibraryCore/Library/CloudLibraryFailure.swift) | Cause e recupero cloud: distingue volume locale pieno, quota Drive e rete; non riporta l'output di rclone. |
| [Sources/NXLibraryCore/Library/RcloneStorageBackend.swift](../../Sources/NXLibraryCore/Library/RcloneStorageBackend.swift) | Usa il binario risolto, verifica ID e nomi originali, rifiuta percorsi ambigui e limita il riferimento all’ID esatto in sola lettura. Prima di scrivere verifica che i due alberi siano disgiunti. |
| [Sources/NXLibraryCore/Library/VolumeSpace.swift](../../Sources/NXLibraryCore/Library/VolumeSpace.swift) | Spazio libero di un disco: dove macOS risponde 0 per l’uso importante (exFAT, FAT32) vale la cifra semplice. |
| [Sources/NXLibraryCore/Library/RcloneDownload.swift](../../Sources/NXLibraryCore/Library/RcloneDownload.swift) | Scarica rclone dopo consenso, verifica origine, dimensione, hash e firma, pubblica la copia con ricevuta e avvia lo snapshot dei byte approvati. |
| [Sources/NXLibraryCore/Library/CloudSetupAssistant.swift](../../Sources/NXLibraryCore/Library/CloudSetupAssistant.swift) | Bozza dell'assistente: passi, selezione, verifica, formato dell'ID client e client Google facoltativo nel plist. |
| [Sources/NXLibraryCore/Selene/CloudSetupAssistantFocus.swift](../../Sources/NXLibraryCore/Selene/CloudSetupAssistantFocus.swift) | Bersagli dell’assistente per tastiera e controller, colonna dei passi e Tab; acceso ciò che serve, mai Cancel. |
| [Sources/NXLibraryCore/Selene/ActionBarOrder.swift](../../Sources/NXLibraryCore/Selene/ActionBarOrder.swift) | Ordine dei tasti di un piede: ritorno a sinistra, azione principale ultima a destra; quale è acceso all’apertura. |
| [Sources/NXLibraryCore/Library/CloudKeptFolders.swift](../../Sources/NXLibraryCore/Library/CloudKeptFolders.swift) | Le due cartelle usate con un account, proposte di nuovo solo allo stesso account. |
| [Sources/NXLibraryCore/Library/RcloneConfiguration.swift](../../Sources/NXLibraryCore/Library/RcloneConfiguration.swift) | Ambito Drive con ID approvati, configurazione privata per le mutazioni ed elenchi senza filtri del proprietario o del Cestino. Cifratura con portachiavi e OAuth senza segreto negli argomenti. |
| [Sources/NXLibraryCore/Library/LibraryRefresh.swift](../../Sources/NXLibraryCore/Library/LibraryRefresh.swift) | Esito per parte di un aggiornamento della libreria: letto, non aggiornato con motivo, annullato; una risposta tardiva non cambia nulla. |
| [Sources/NXLibraryCore/Library/RcloneListing.swift](../../Sources/NXLibraryCore/Library/RcloneListing.swift) | Una lettura di Drive per gli schermi: conto e cartelle provati prima e dopo, cartelle lette per ID, insieme e una sola volta; connessione condivisa finché la configurazione non cambia. |
| [Sources/NXLibraryCore/Library/RcloneRemoteControl.swift](../../Sources/NXLibraryCore/Library/RcloneRemoteControl.swift) | Gestisce demoni locali su socket Unix; distingue cartelle mancanti da operazioni non supportate e passa l'input sensibile OAuth via stdin. |
| [Sources/NXLibraryCore/Library/CollectionRow.swift](../../Sources/NXLibraryCore/Library/CollectionRow.swift) | Definisce proporzioni delle copertine e geometria della riga Collection. |

## Core · Selene: Spotlight, focus, temi e sfondi

Cartella `Sources/NXLibraryCore/Selene/`.

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Selene/BackdropArt.swift](../../Sources/NXLibraryCore/Selene/BackdropArt.swift) | Regola che tiene l’arte del gioco precedente sullo sfondo Spotlight (`BackdropArtRule`) dissolvenza di un layer calcolata sull’orologio (`OpacityFade`) e livelli ormai coperti da togliere (`ArtStack`). |
| [Sources/NXLibraryCore/Selene/TileMotion.swift](../../Sources/NXLibraryCore/Selene/TileMotion.swift) | Curve e campioni dei loop di ring, bagliore e riflesso della tile selezionata, sull'orologio condiviso. |
| [Sources/NXLibraryCore/Selene/DownloadCloudMotion.swift](../../Sources/NXLibraryCore/Selene/DownloadCloudMotion.swift) | Traiettoria smorzata del download, onda calma, assestamento, glifo Oort e bande a dissolvenza. |
| [Sources/NXLibraryCore/Selene/Motion.swift](../../Sources/NXLibraryCore/Selene/Motion.swift) | Curve di focus, rail, schermate, overlay, carte ancorate, toast e progressi con varianti di movimento ridotto. |
| [Sources/NXLibraryCore/Selene/SeleneTokens.swift](../../Sources/NXLibraryCore/Selene/SeleneTokens.swift) | Ruoli Selene generati: testo, spazi, raggi, effetti, colore, durata e riferimento di distanza. |
| [Sources/NXLibraryCore/Selene/SeleneOverlayStyle.swift](../../Sources/NXLibraryCore/Selene/SeleneOverlayStyle.swift) | Associa ogni overlay ai ruoli di velo e sfocatura. |
| [Tests/NXLibraryCoreTests/Selene/MotionTests.swift](../../Tests/NXLibraryCoreTests/Selene/MotionTests.swift) | Verifica che in movimento ridotto restino solo i fonduti previsti. |
| [Sources/NXLibraryCore/Selene/TextScroll.swift](../../Sources/NXLibraryCore/Selene/TextScroll.swift) | Scorrimento della colonna del pannello della mod: altezza della descrizione dopo Read more, limiti, riga a fuoco mostrata intera e passo Su/Giù che legge prima della riga seguente. |
| [Sources/NXLibraryCore/Selene/CursorIdleState.swift](../../Sources/NXLibraryCore/Selene/CursorIdleState.swift) | Politica del ritardo di visibilità del puntatore e reset su mouse o perdita di eleggibilità. |
| [Sources/NXLibraryCore/Selene/OnlineBackgrounds.swift](../../Sources/NXLibraryCore/Selene/OnlineBackgrounds.swift) | Modella sorgenti e risultati e interpreta le risposte dei provider di sfondi fissi e video. |
| [Sources/NXLibraryCore/Selene/SeleneImporter.swift](../../Sources/NXLibraryCore/Selene/SeleneImporter.swift) | Importa suoni e wallpaper dalla cartella Selene dell’utente e risolve cue e fallback. |
| [Sources/NXLibraryCore/Selene/SoundPack.swift](../../Sources/NXLibraryCore/Selene/SoundPack.swift) | Valida manifesti, archivi e audio, sceglie le varianti, pubblica solo copie locali confermate e divide le scelte fra le voci della riga e Other. |
| [Sources/NXLibraryCore/Selene/OortSynth.swift](../../Sources/NXLibraryCore/Selene/OortSynth.swift) | Calcola i suoni delle voci Oort: note, clic, stanza, Sole e sequenze di Compose. |
| [Sources/NXLibraryCore/Selene/OortAmbiance.swift](../../Sources/NXLibraryCore/Selene/OortAmbiance.swift) | Timbri e stanza degli ambienti Frost, Mist e Nucleus e livello allineato alla voce Oort. |
| [Sources/NXLibraryCore/Selene/ButtonPrompts.swift](../../Sources/NXLibraryCore/Selene/ButtonPrompts.swift) | Traduce azioni e direzioni, incluse Su/Giù, in simboli per tastiera e controller Switch, Xbox e PlayStation. |
| [Sources/NXLibraryCore/Selene/InputInHand.swift](../../Sources/NXLibraryCore/Selene/InputInHand.swift) | Decide quale dispositivo è in mano (controller, tastiera o puntatore) senza sfarfallii: stick nella zona morta e piccoli spostamenti non contano. |
| [Sources/NXLibraryCore/Selene/LaunchExit.swift](../../Sources/NXLibraryCore/Selene/LaunchExit.swift) | Dopo quattro secondi dice come uscire dalla schermata di avvio: B o Esc se Oort riceve i tasti, altrimenti il clic. |
| [Sources/NXLibraryCore/Selene/RailScroll.swift](../../Sources/NXLibraryCore/Selene/RailScroll.swift) | Traduce rotella e due dita in passi della riga: un riquadro per riquadro di corsa, uno per scatto. |
| [Sources/NXLibraryCore/Selene/OnScreenKeyboard.swift](../../Sources/NXLibraryCore/Selene/OnScreenKeyboard.swift) | Pagine, tasti, maiuscole e spostamento del focus della tastiera a schermo. |
| [Sources/NXLibraryCore/Selene/MaterialIcon.swift](../../Sources/NXLibraryCore/Selene/MaterialIcon.swift) | Elenca i glifi del font incluso, compresi cancellazione e conferma del PIN. |
| [Sources/NXLibraryCore/Selene/MenuSelectionModel.swift](../../Sources/NXLibraryCore/Selene/MenuSelectionModel.swift) | Gestisce icone, voci delle schede e pillole Power; salta l'Inbox disattivata e lascia il focus sull'icona alla chiusura. |
| [Sources/NXLibraryCore/Selene/MoonlightAppearance.swift](../../Sources/NXLibraryCore/Selene/MoonlightAppearance.swift) | Identità delle superfici classica/Arcane/Flow e campionamento dei colori locali condiviso fra shader e fallback. |
| [Sources/NXLibraryCore/Selene/ScreenshotViewerState.swift](../../Sources/NXLibraryCore/Selene/ScreenshotViewerState.swift) | Mantiene indice e limiti della navigazione nel visualizzatore screenshot. |
| [Sources/NXLibraryCore/Selene/SeleneCanvas.swift](../../Sources/NXLibraryCore/Selene/SeleneCanvas.swift) | Calcola scala uniforme, stage centrato e conversione delle unità del canvas 1920×1080. |
| [Sources/NXLibraryCore/Selene/SelenePalette.swift](../../Sources/NXLibraryCore/Selene/SelenePalette.swift) | Decodifica palette e metadato moonlight; ordina Oort per prima, la usa come fallback e distingue l’ID del blu classico. |
| [Sources/NXLibraryCore/Selene/SpotlightPage.swift](../../Sources/NXLibraryCore/Selene/SpotlightPage.swift) | Calcola estratti delle descrizioni e stati dello scorrimento della pagina Spotlight. |
| [Sources/NXLibraryCore/Selene/SpotlightRow.swift](../../Sources/NXLibraryCore/Selene/SpotlightRow.swift) | Costruisce la sequenza per UUID e salva riordini conservando giochi/fonti/card temporaneamente nascosti; Surprise sceglie fra i giochi visibili di un pool (installati, mai giocati, tutti). |
| [Sources/NXLibraryCore/Selene/SpotlightPlatforms.swift](../../Sources/NXLibraryCore/Selene/SpotlightPlatforms.swift) | Piattaforme presenti, conteggi, combinazione con la query, cursore e scelta stabilizzata. |
| [Sources/NXLibraryCore/Selene/SpotlightRowGeometry.swift](../../Sources/NXLibraryCore/Selene/SpotlightRowGeometry.swift) | Posti delle tessere nella riga, camera unica che la fa scorrere e finestra delle tessere create; posto, scala e camera lungo lo scorrimento dalla posizione continua della selezione. |
| [Sources/NXLibraryCore/Selene/SpotlightState.swift](../../Sources/NXLibraryCore/Selene/SpotlightState.swift) | Gestisce selezione, focus (anche la card Achievements), azioni e spostamento delle tile su Spotlight. |
| [Sources/NXLibraryCore/Selene/SpotlightEntrance.swift](../../Sources/NXLibraryCore/Selene/SpotlightEntrance.swift) | Tempi e partenze del volo delle tessere, dissolvenza oltre il bordo, sfondo, informazioni, hint e fasi della prima entrata di Spotlight, compreso quando accetta input. |
| [Sources/NXLibraryCore/Selene/ThemePicker.swift](../../Sources/NXLibraryCore/Selene/ThemePicker.swift) | Gestisce il focus nella griglia colori, tab Wallpapers/Live e scelta dello sfondo successivo. |
| [Sources/NXLibraryCore/Selene/WallpaperCatalog.swift](../../Sources/NXLibraryCore/Selene/WallpaperCatalog.swift) | Elenca wallpaper e video, gruppi, nomi e file delle risorse incluse o importate. |
| [Sources/NXLibraryCore/Selene/WallpaperPlacement.swift](../../Sources/NXLibraryCore/Selene/WallpaperPlacement.swift) | Decide dove applicare uno sfondo scelto fra schermi principali e Settings. |
| [Sources/NXLibraryCore/Selene/GridListLayout.swift](../../Sources/NXLibraryCore/Selene/GridListLayout.swift) | Geometria di una lista a colonne di righe uguali: altezza, posizione di ogni riga, linee da disegnare, riga da mostrare e riga in vista più vicina. |

## Core · pagina del gioco

Cartella `Sources/NXLibraryCore/Details/`.

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Details/GameDetailPresentation.swift](../../Sources/NXLibraryCore/Details/GameDetailPresentation.swift) | Prepara i dati della pagina Details e compone estratto, testo lungo e crediti per Details e Spotlight; le entrate Steam e Switch sono in estensioni distinte. |
| [Sources/NXLibraryCore/Details/MoreLikeThis.swift](../../Sources/NXLibraryCore/Details/MoreLikeThis.swift) | Ordina i giochi correlati per generi, sviluppatore ed editore, con precedenza alla stessa fonte e ripiego facoltativo. |
| [Sources/NXLibraryCore/Details/DetailsFacts.swift](../../Sources/NXLibraryCore/Details/DetailsFacts.swift) | Sceglie le righe del pannello Details (Steam qui, Switch in `ArcanePorting/Details/DetailsFacts+Porting.swift`): solo i valori presenti, niente identificativi tecnici. |
| [Sources/NXLibraryCore/Details/DetailsFocus.swift](../../Sources/NXLibraryCore/Details/DetailsFocus.swift) | Gestisce zone e spostamenti del focus nei link e nelle bande di Details. |
| [Sources/NXLibraryCore/Details/GameOptionsPresentation.swift](../../Sources/NXLibraryCore/Details/GameOptionsPresentation.swift) | Righe, livelli, focus e titolo Next launch localizzato: Play, rete, azione RomFS in Online e schermo solo per gli host compatibili. |
| [Sources/NXLibraryCore/Details/GameDetailPresentation+Steam.swift](../../Sources/NXLibraryCore/Details/GameDetailPresentation+Steam.swift) | Dati della pagina Steam e generi della testata Spotlight; ignora i dati di altri AppID e dà precedenza ai campi personali. |

## Core · artwork e metadati

Cartella `Sources/NXLibraryCore/Artwork/`.

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Artwork/AutomaticIconResolver.swift](../../Sources/NXLibraryCore/Artwork/AutomaticIconResolver.swift) | Risolve icone automatiche con cache, abbinamento prudente e rispetto delle restrizioni del provider. |
| [Sources/NXLibraryCore/Artwork/ArtworkStore.swift](../../Sources/NXLibraryCore/Artwork/ArtworkStore.swift) | Scarica, ridimensiona e conserva immagini e screenshot nella cache per titolo e tipo. |
| [Sources/NXLibraryCore/Artwork/ArtworkPicker.swift](../../Sources/NXLibraryCore/Artwork/ArtworkPicker.swift) | Aggrega candidati per cover, sfondo, icona e logo (quelli Steam qui, quelli Switch in `ArcanePorting/Store/ArtworkCandidates+Porting.swift`) e conserva le scelte manuali. |
| [Sources/NXLibraryCore/Artwork/MetadataPicker.swift](../../Sources/NXLibraryCore/Artwork/MetadataPicker.swift) | Campi alternativi e override per campo: `MetadataPicks` scrive atomicamente prima di pubblicare la modifica. |
| [Sources/NXLibraryCore/Artwork/GameTitleKey.swift](../../Sources/NXLibraryCore/Artwork/GameTitleKey.swift) | Un titolo come parole da confrontare (minuscole, senza ™ ® © né punteggiatura, "&" come "and"), per le ricerche di artwork online e GameTDB. |
| [Sources/NXLibraryCore/Artwork/HTMLPlainText.swift](../../Sources/NXLibraryCore/Artwork/HTMLPlainText.swift) | Una descrizione HTML (store, Steam, database, mod) come testo semplice: righe ed elenchi tenuti, altri tag tolti, entità decodificate. |
| [Sources/NXLibraryCore/Artwork/OnlineArtworkSources.swift](../../Sources/NXLibraryCore/Artwork/OnlineArtworkSources.swift) | Ricava artwork Steam e loghi da MediaWiki e Wikimedia Commons. |
| [Sources/NXLibraryCore/Artwork/MoreArtworkSources.swift](../../Sources/NXLibraryCore/Artwork/MoreArtworkSources.swift) | Matching dei nomi e sorgenti Xbox, GOG, Nintendo Europe, wiki e altri cataloghi; controllo della variante Nintendo più grande prima del primo download. |
| [Sources/NXLibraryCore/Artwork/ArtworkBrowse.swift](../../Sources/NXLibraryCore/Artwork/ArtworkBrowse.swift) | Sorgenti sfogliabili da Change artwork (LaunchBox, SteamGridDB): nomi cercati e risultati per tutti gli slot. |
| [Sources/NXLibraryCore/Artwork/LaunchBoxArt.swift](../../Sources/NXLibraryCore/Artwork/LaunchBoxArt.swift) | Legge ricerca e pagina gioco di LaunchBox; dal payload Nuxt ricava anteprime, file pieni, tipo, regione e dimensioni; screenshot Gameplay. |
| [Sources/NXLibraryCore/Artwork/SteamGridDBArt.swift](../../Sources/NXLibraryCore/Artwork/SteamGridDBArt.swift) | Conserva la chiave SteamGridDB in un file 0600 e interroga l’API v2 per griglie, hero, loghi e icone statiche accreditate. |
| [Sources/NXLibraryCore/Artwork/LibraryArtworkRole.swift](../../Sources/NXLibraryCore/Artwork/LibraryArtworkRole.swift) | Ruoli di layout delle immagini (copertina, quadrato, sfondo…) separati dal fornitore: un quadrato non chiede né ritaglia mai la copertina verticale. |
| [Sources/NXLibraryCore/Artwork/CriticRating.swift](../../Sources/NXLibraryCore/Artwork/CriticRating.swift) | Identità pubblica del gioco e console (Mac, Switch, Switch 2), voto originale /100, provenienza e riempimento proporzionale delle cinque stelle. |
| [Sources/NXLibraryCore/Artwork/WikidataRatings.swift](../../Sources/NXLibraryCore/Artwork/WikidataRatings.swift) | Abbina titoli esatti e ID Steam; seleziona medie della critica documentate, senza confondere piattaforme o raccomandazioni. L'identità del gioco (`entity`) serve anche alle descrizioni di Wikipedia. |
| [Sources/NXLibraryCore/Artwork/WikipediaDescription.swift](../../Sources/NXLibraryCore/Artwork/WikipediaDescription.swift) | Quando una descrizione non è nella lingua dell'app, sitelink Wikidata e introduzione di Wikipedia in quella lingua (cinese in semplificato); servizio con cache misurabile e svuotabile, host fissi e nessun errore salvato come assenza. |
| [Sources/NXLibraryCore/Artwork/CriticRatingService.swift](../../Sources/NXLibraryCore/Artwork/CriticRatingService.swift) | Preferenza IGDB personale → Wikidata pubblico, cache Wikidata, ripiego offline e pausa dopo errori. |
| [Sources/NXLibraryCore/Artwork/IGDBCredentials.swift](../../Sources/NXLibraryCore/Artwork/IGDBCredentials.swift) | Credenziali Twitch personali in file 0600, validazione e messaggi sicuri senza segreti nei log. |
| [Sources/NXLibraryCore/Artwork/IGDBRatings.swift](../../Sources/NXLibraryCore/Artwork/IGDBRatings.swift) | Abbinamento IGDB esatto o tramite ID Steam, critica preferita e ripiego utenti esplicito, con provenienza distinta da Wikidata. |
| [Sources/NXLibraryCore/Artwork/IGDBRatingService.swift](../../Sources/NXLibraryCore/Artwork/IGDBRatingService.swift) | Cache dei voti, richieste coalescenti e verifica credenziali tramite il client IGDB condiviso. |
| [Sources/NXLibraryCore/Artwork/IGDBClient.swift](../../Sources/NXLibraryCore/Artwork/IGDBClient.swift) | Unico accesso Twitch/IGDB per voti e metadati: token in memoria, coda limitata seriale, host vincolati, rinnovo 401 e annullamento. |
| [Sources/NXLibraryCore/Artwork/IGDBMetadata.swift](../../Sources/NXLibraryCore/Artwork/IGDBMetadata.swift) | Proposte IGDB per campo: identità esatta, ruoli delle aziende e date complete della piattaforma corretta. |
| [Sources/NXLibraryCore/Artwork/IGDBMetadataService.swift](../../Sources/NXLibraryCore/Artwork/IGDBMetadataService.swift) | Ricerca metadati su richiesta, ID Steam verificato, cache separata e ripiego offline; nessuna scrittura delle scelte personali. |
| [Sources/NXLibraryCore/Artwork/DatabaseMetadata.swift](../../Sources/NXLibraryCore/Artwork/DatabaseMetadata.swift) | Proposte LaunchBox/TheGamesDB: identità e piattaforma verificate, campi separati, fonte esplicita e date della versione corretta. |
| [Sources/NXLibraryCore/Artwork/DatabaseMetadataService.swift](../../Sources/NXLibraryCore/Artwork/DatabaseMetadataService.swift) | Letture pubbliche limitate e annullabili, richieste condivise, cache testuale per gioco/piattaforma e recupero offline. |
| [Sources/NXLibraryCore/Artwork/GameGenre.swift](../../Sources/NXLibraryCore/Artwork/GameGenre.swift) | Generi noti tradotti alla presentazione; dati originali e generi personali conservati. |

## Core · achievement

Cartella `Sources/NXLibraryCore/Achievements/`.

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Achievements/AchievementSummary.swift](../../Sources/NXLibraryCore/Achievements/AchievementSummary.swift) | Riepilogo puro per la tile e la schermata: conteggi, percentuale, gioco completato (`isComplete`), righe recenti con icona, conteggi per tier, sbloccati di recente, ultimo sblocco, filtri e ordini; maschera i nascosti ancora bloccati. |
| [Sources/NXLibraryCore/Achievements/AchievementTier.swift](../../Sources/NXLibraryCore/Achievements/AchievementTier.swift) | Tier a cristallo come i trofei PS5: Arcano (viola, al posto del Platino) per il gioco completato, Oro / Argento / Bronzo per rarità Steam (<10%, <30%, il resto); nomi tradotti e PNG nelle risorse del Core; `videoURL` dà il video in loop dell'Arcane (`crystal-arcane.mov`, HEVC con alpha a 384 px). |
| [Sources/NXLibraryCore/Achievements/AchievementsScreenState.swift](../../Sources/NXLibraryCore/Achievements/AchievementsScreenState.swift) | Filtro e selezione della schermata Achievements: due colonne, bordi fermi, LB/RB che girano i filtri. |
| [LocalAchievementPack.swift](../../Sources/NXLibraryCore/Achievements/LocalAchievementPack.swift) | Pack locale, metriche e regole; progressi e primi sblocchi persistenti per gioco e profilo. |

## Core · mod

Cartella `Sources/NXLibraryCore/Mods/`.

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Mods/ModsBandLayout.swift](../../Sources/NXLibraryCore/Mods/ModsBandLayout.swift) | Ordine delle tessere, Search accanto a Manage e movimento nella griglia (sei per riga). |
| [Sources/NXLibraryCore/Mods/LocalMod.swift](../../Sources/NXLibraryCore/Mods/LocalMod.swift) | Una mod locale: cartella, stato e radici `romfs` o `exefs`. |

## Core · impostazioni, lingua e testi

Cartella `Sources/NXLibraryCore/Settings/`. Il catalogo dei testi sta in `Resources/`.

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Settings/AppSettings.swift](../../Sources/NXLibraryCore/Settings/AppSettings.swift) | Impostazioni globali e decodifica compatibile, anche per Inbox, Compilati di recente (attivi per default), Home in gioco e scelta VPN da ZeroTier Automatico. Tiene le chiavi del modulo come JSON e ignora chiavi e card Spotlight sconosciute. |
| [Sources/NXLibraryCore/Settings/AppSettingsStore.swift](../../Sources/NXLibraryCore/Settings/AppSettingsStore.swift) | Separa bozza, anteprime e valori applicati; salva settings.json con lock, sostituzione atomica e rilettura. Conserva un file illeggibile e scrive l'ultima selezione in background. |
| [Sources/NXLibraryCore/Settings/AppSettingsDraft.swift](../../Sources/NXLibraryCore/Settings/AppSettingsDraft.swift) | Confronta ogni campo modificabile con l'originale, espone i cambi e unisce le modifiche senza sovrascrivere un conflitto. |
| [Sources/NXLibraryCore/Settings/SettingsRowAction.swift](../../Sources/NXLibraryCore/Settings/SettingsRowAction.swift) | Identifica azioni e righe Settings, mantenendo una sola azione primaria per riga senza accorpare giochi omonimi. |
| [Sources/NXLibraryCore/Settings/SettingsCatalog.swift](../../Sources/NXLibraryCore/Settings/SettingsCatalog.swift) | Righe fuori da Porting, incluse Play together, Hidden game apps e Home in gioco; ordina, cerca e confronta per identità. |
| [Sources/NXLibraryCore/Settings/SettingsSection.swift](../../Sources/NXLibraryCore/Settings/SettingsSection.swift) | Titoli e icone della barra: General, Library, Porting (con Game folders e Porting storage) e System. |
| [Sources/NXLibraryCore/Settings/SettingsCategory.swift](../../Sources/NXLibraryCore/Settings/SettingsCategory.swift) | Rubriche brevi localizzate e associazione con le sezioni storiche, senza cambiare le rotte. |
| [Sources/NXLibraryCore/Settings/SettingsReset.swift](../../Sources/NXLibraryCore/Settings/SettingsReset.swift) | Reset group per sezione, anche Inbox con Game folders, Compilati di recente con Spotlight, Home in gioco e scelte Play together, non l'ID Nextendo né i percorsi delle cartelle di gioco. |
| [Sources/NXLibraryCore/Settings/OnlinePlayersDisplay.swift](../../Sources/NXLibraryCore/Settings/OnlinePlayersDisplay.swift) | I quattro interruttori di Nextendo players, la conversione delle scelte precedenti e la condizione per leggere il conteggio. |
| [Sources/NXLibraryCore/Settings/AppLocale.swift](../../Sources/NXLibraryCore/Settings/AppLocale.swift) | Sette lingue, risoluzione delle preferenze e regione indipendente; nomi e ricerca delle regioni. |
| [Sources/NXLibraryCore/Settings/AppLocalization.swift](../../Sources/NXLibraryCore/Settings/AppLocalization.swift) | Contesto osservabile, lookup delle risorse, interpolazioni/plurali e nome Oort NX nei testi resi. |
| [Sources/NXLibraryCore/Resources/credits.json](../../Sources/NXLibraryCore/Resources/credits.json) | Copia generata di `design/credits.json`. |
| [Sources/NXLibraryCore/Resources/Localizable.xcstrings](../../Sources/NXLibraryCore/Resources/Localizable.xcstrings) | Testi in sette lingue, inclusi errori di avvio di Python, avvisi del Cestino, recupero degli spostamenti cloud e accessi di Integrations. |

## Core · Steam

Cartella `Sources/NXLibraryCore/Steam/`.

| File | Responsabilità |
|---|---|
| [Sources/NXLibraryCore/Steam/SteamBackgroundLaunch.swift](../../Sources/NXLibraryCore/Steam/SteamBackgroundLaunch.swift) | Attesa di un gioco Steam avviato da Play: pazienza (15 s, 45 s se Play avvia Steam), stato della schermata di lancio, regole di «Keep Steam in the background». |
| [Sources/NXLibraryCore/Steam/SteamKeyValues.swift](../../Sources/NXLibraryCore/Steam/SteamKeyValues.swift) | Parser testuale limitato e lookup condivisi dei lettori: prima chiave, primo valore tipizzato o campo unico, con regole esplicite sui duplicati; nessuna direttiva eseguita. |
| [Sources/NXLibraryCore/Steam/SteamPlaytimeReader.swift](../../Sources/NXLibraryCore/Steam/SteamPlaytimeReader.swift) | Ore e ultima partita dell’account Steam più recente da `localconfig.vdf`; nient’altro del file esce dal tipo. |
| [Sources/NXLibraryCore/Steam/SteamPlaytimeBaselines.swift](../../Sources/NXLibraryCore/Steam/SteamPlaytimeBaselines.swift) | Totali Steam con il momento in cui sono stati visti; nuovo valore o account ripartono; mappa ai giochi del catalogo. |
| [Sources/NXLibraryCore/Steam/SteamReturnFocus.swift](../../Sources/NXLibraryCore/Steam/SteamReturnFocus.swift) | Quando un gioco Steam che esce riporta Arcane davanti: Play premuto qui, gioco in primo piano, nessun altro gioco aperto. |
| [Sources/NXLibraryCore/Steam/SteamLaunchQuestions.swift](../../Sources/NXLibraryCore/Steam/SteamLaunchQuestions.swift) | Domande con cui Steam ferma un avvio, dalle righe `GameAction` di `logs/console_log.txt`. `ShowInterstitials` è avanzamento; le domande contano dopo 1 s. |
| [Sources/NXLibraryCore/Steam/SteamPlaytimeSync.swift](../../Sources/NXLibraryCore/Steam/SteamPlaytimeSync.swift) | Una lettura dei file Steam e cosa fa (pubblica, conserva gli ultimi totali buoni dello stesso account o azzera); coda di una lettura alla volta. |
| [Sources/NXLibraryCore/Steam/InstallationFileSnapshot.swift](../../Sources/NXLibraryCore/Steam/InstallationFileSnapshot.swift) | Letture limitate e non bloccanti di file regolari; verifica dell'identità prima della pubblicazione. |
| [Sources/NXLibraryCore/Steam/InstallationDirectorySnapshot.swift](../../Sources/NXLibraryCore/Steam/InstallationDirectorySnapshot.swift) | Lettura incrementale delle cartelle, budget anche sulle voci nascoste e annullamento durante l'enumerazione. |
| [Sources/NXLibraryCore/Steam/NativeMacApplication.swift](../../Sources/NXLibraryCore/Steam/NativeMacApplication.swift) | Evidenze del bundle Mac e degli header eseguibili, architetture e categoria dichiarata, senza avvio. |
| [Sources/NXLibraryCore/Steam/SteamLibrarySource.swift](../../Sources/NXLibraryCore/Steam/SteamLibrarySource.swift) | Snapshot delle librerie/manifest; omette i percorsi non pubblicabili e segnala una scansione parziale senza modificare il catalogo. |
| [Sources/NXLibraryCore/Steam/SteamPlayState.swift](../../Sources/NXLibraryCore/Steam/SteamPlayState.swift) | Stato di Play per un gioco Steam: processi osservati con i percorsi risolti, passaggio a Steam, sessione solo quando gira l’app di questa installazione, attese e rifiuti. |
| [Sources/NXLibraryCore/Steam/SteamBinaryKeyValues.swift](../../Sources/NXLibraryCore/Steam/SteamBinaryKeyValues.swift) | Lettura limitata del formato KeyValues binario di Steam (`appcache/stats`): tipi noti, profondità, voci e dimensione; qualunque altro byte è un errore. |
| [Sources/NXLibraryCore/Steam/SteamAchievementReader.swift](../../Sources/NXLibraryCore/Steam/SteamAchievementReader.swift) | Achievement di un gioco per l’account corrente: schema (nomi nella lingua dell’app, poi inglese; nascosti; icone) e soli `AchievementTimes` del file delle statistiche; nessun file, account o statistiche: nessun dato. |
| [Sources/NXLibraryCore/Steam/SteamAchievementRarity.swift](../../Sources/NXLibraryCore/Steam/SteamAchievementRarity.swift) | Rarità pubblica (`GetGlobalAchievementPercentagesForApp`, senza chiave) (una percentuale non numerica, «nan» o «inf», si scarta) e indirizzi delle icone sull’host community-assets del CDN di Steam, solo per nomi di file semplici. |
| [Sources/NXLibraryCore/Steam/SteamManifestWatcher.swift](../../Sources/NXLibraryCore/Steam/SteamManifestWatcher.swift) | Uno stream FSEvents sulle cartelle `steamapps` delle librerie dell’ultima scansione; segnala solo i manifest `appmanifest_<AppID>.acf` e l’indice `libraryfolders.vdf` della radice, una volta per gruppo di eventi. |
| [Sources/NXLibraryCore/Steam/SteamMetadata.swift](../../Sources/NXLibraryCore/Steam/SteamMetadata.swift) | Dati store Steam tipizzati, lingua e URL immagini verificati. |
| [Sources/NXLibraryCore/Steam/SteamMetadataService.swift](../../Sources/NXLibraryCore/Steam/SteamMetadataService.swift) | Fino a sei download coalescenti, cache per lingua, ripiego offline (anche in un'altra lingua) e immagini ridimensionate. Legge i tratti dei giochi correlati solo da cache. |
| [Sources/NXLibraryCore/Steam/SteamPersonalizationStore.swift](../../Sources/NXLibraryCore/Steam/SteamPersonalizationStore.swift) | Pubblicazione unica di metadati e riferimenti artwork; fallimenti e Automatic conservano le scelte coerenti. |
| [Sources/NXLibraryCore/Steam/SteamArtworkRequest.swift](../../Sources/NXLibraryCore/Steam/SteamArtworkRequest.swift) | Cosa chiede la tile di un gioco Steam per ogni ruolo: prima la scelta personale, poi per il quadrato l’icona dell’app installata, mai la copertina; gli altri ruoli vanno all’arte dello store. |
| [Sources/NXLibraryCore/Steam/SteamBackdropChoice.swift](../../Sources/NXLibraryCore/Steam/SteamBackdropChoice.swift) | Sfondo automatico di un gioco Steam: arte 16:9 pulita (Xbox, GOG, TheGamesDB, fan art LaunchBox), poi il primo screenshot, per ultimo il banner della libreria ritagliato. |

## Porting · gioco Switch e libreria nxnative

Cartella `Sources/ArcanePorting/`.

| File | Responsabilità |
|---|---|
| [Sources/ArcanePorting/PortedGame.swift](../../Sources/ArcanePorting/PortedGame.swift) | Modello persistente del gioco, anche solo remoto: bundle, sorgenti, posizione remota relativa, impostazioni, build e installazione in attesa. |
| [Sources/ArcanePorting/LibraryFile.swift](../../Sources/ArcanePorting/LibraryFile.swift) | Contenitore versionato del catalogo della libreria. |
| [Sources/ArcanePorting/GameStatus.swift](../../Sources/ArcanePorting/GameStatus.swift) | Enumera disponibilità e stato del gioco rispetto ad app, sorgenti e porting. |
| [Sources/ArcanePorting/TargetPlatform.swift](../../Sources/ArcanePorting/TargetPlatform.swift) | Definisce il target mac-app e le sue etichette per l’interfaccia. |

## Porting · catalogo nxnative

Cartella `Sources/ArcanePorting/Catalog/`.

| File | Responsabilità |
|---|---|
| [Sources/ArcanePorting/Catalog/PortedGame+Catalog.swift](../../Sources/ArcanePorting/Catalog/PortedGame+Catalog.swift) | `PortedGame` nel contratto del catalogo (validazione, presenza, avvio, ricerca), integrazione `.nxnative`, tipi noti dell’app (`CatalogRecordKinds.standard`) ed entrate `nxnativeGame`, `init(nxnative:)`, `updateNXNative`. |
| [Sources/ArcanePorting/Catalog/CatalogPersonalizations+Porting.swift](../../Sources/ArcanePorting/Catalog/CatalogPersonalizations+Porting.swift) | Chiave personale nxnative (title ID o chiave storica) e radice dei dati personali: nxnative alla radice, ogni altra integrazione in `integrations/<nome>`. |
| [Sources/ArcanePorting/Catalog/CatalogStore+Porting.swift](../../Sources/ArcanePorting/Catalog/CatalogStore+Porting.swift) | Store con tutti i tipi noti e import di `library.json`; riconosce le build in attesa della vecchia libreria anche dal percorso del log. |
| [Sources/ArcanePorting/Catalog/CatalogRepository+Porting.swift](../../Sources/ArcanePorting/Catalog/CatalogRepository+Porting.swift) | Modifiche nxnative del catalogo: merge di scansioni, app e build, aggiornamento delle sorgenti da manifest quando mancano tutte le copie locali, esclusioni e proiezione `nxnativeGames`. |
| [Sources/ArcanePorting/Catalog/CatalogBuildRecoveries.swift](../../Sources/ArcanePorting/Catalog/CatalogBuildRecoveries.swift) | Generazioni di build non ancora salvate, selezione del retry e conferma della sola generazione persistita. |

## Porting · libreria, sessioni e spazio

Cartella `Sources/ArcanePorting/Library/`.

| File | Responsabilità |
|---|---|
| [Sources/ArcanePorting/Library/LibraryQuery+Porting.swift](../../Sources/ArcanePorting/Library/LibraryQuery+Porting.swift) | Filtro, ricerca e selezione della home per i giochi Switch: `PortedGame` come `LibraryQueryRecord`, `LibraryQuery.apply(to:history:)`, `reconcile`, `move` e `jump` di `LibrarySelectionState`. |
| [Sources/ArcanePorting/Library/Surprise+Porting.swift](../../Sources/ArcanePorting/Library/Surprise+Porting.swift) | Surprise me sui giochi Switch, sopra la scelta generica di `Surprise`. |
| [Sources/ArcanePorting/Library/PlaySessionStore+Porting.swift](../../Sources/ArcanePorting/Library/PlaySessionStore+Porting.swift) | Avvio della sessione di un gioco portato: title ID (o chiave unica) e bundle ID dell’app. |
| [Sources/ArcanePorting/Library/SessionSummary+Porting.swift](../../Sources/ArcanePorting/Library/SessionSummary+Porting.swift) | Card di fine sessione per un gioco portato. |
| [Sources/ArcanePorting/Library/LibraryPresentation+Porting.swift](../../Sources/ArcanePorting/Library/LibraryPresentation+Porting.swift) | Valori della libreria per un gioco portato (fatti dello store Nintendo, console, sorgenti staccate) e l’entrata per `CatalogGame`, che sceglie la strada Switch o Steam. |
| [Sources/ArcanePorting/Library/RunningGames.swift](../../Sources/ArcanePorting/Library/RunningGames.swift) | Quali giochi portati sono in esecuzione: confronta il bundle ID effettivo con quelli delle app aperte. |
| [Sources/ArcanePorting/Library/StorageManager.swift](../../Sources/ArcanePorting/Library/StorageManager.swift) | Misura app, cache e log per gioco e totali senza duplicare percorsi condivisi; verifica cartelle e sorgenti prima della pulizia selettiva. I backup appartengono al flusso Saves. |
| [Sources/ArcanePorting/Library/GameInbox.swift](../../Sources/ArcanePorting/Library/GameInbox.swift) | Propone nomi e destinazioni delle sorgenti; distingue chiavi mancanti e ambiguità, riusa le verifiche dei duplicati nell'anteprima e ricalcola gli hash prima del Cestino. |
| [Sources/ArcanePorting/Library/CloudArchiveInventory.swift](../../Sources/ArcanePorting/Library/CloudArchiveInventory.swift) | Controlla gerarchia, link, hash e metadati per Apple Archive e i file; condivide le esclusioni di slot, registro e journal storici. |
| [Sources/ArcanePorting/Library/CloudArtifactFiles.swift](../../Sources/ArcanePorting/Library/CloudArtifactFiles.swift) | Valida percorsi, dimensioni e MD5 di un albero v2, confronta l'elenco rclone, ripristina i link e inventaria il contenuto al netto delle firme per l'adozione. |
| [Sources/ArcanePorting/Library/CloudGameArchive.swift](../../Sources/ArcanePorting/Library/CloudGameArchive.swift) | Pubblica e legge le revisioni di app e cache separatamente; distingue manifest non validi ed errori di lettura; riusa la cache compatibile prima di Rebuild completo; ripristino atomico e recupero di Free up space. |
| [Sources/ArcanePorting/Library/CloudGameArchive+Files.swift](../../Sources/ArcanePorting/Library/CloudGameArchive+Files.swift) | Calcola il diff, riprende il download v2 in staging, clona i file uguali, conserva la cache parziale verificata e ripara l'app prima della pubblicazione locale. |
| [Sources/ArcanePorting/Library/CloudManifestCache.swift](../../Sources/ArcanePorting/Library/CloudManifestCache.swift) | Schede cloud già lette, per SHA-256 del nome e MD5 di Drive; solo le letture per gli schermi la usano. |
| [Sources/ArcanePorting/Library/CloudArchiveFingerprintCache.swift](../../Sources/ArcanePorting/Library/CloudArchiveFingerprintCache.swift) | Cache persistente e limitata delle impronte di app e cache, indicizzata da digest. |
| [Sources/ArcanePorting/Library/CloudGameSources.swift](../../Sources/ArcanePorting/Library/CloudGameSources.swift) | Scopre le sorgenti sotto una radice autorizzata, rifiuta ambiguità e collisioni Unicode e riverifica la selezione, lo spazio, le impronte e l'identità NSP al download. |
| [Sources/ArcanePorting/Library/CloudTransferQueue.swift](../../Sources/ArcanePorting/Library/CloudTransferQueue.swift) | Salva azioni, ambito Drive, fornitore, identità dell'eseguibile e selezione di Rebuild; ammette la pausa volontaria solo su un download valido in testa. |
| [PersonalAppReceipt.swift](../../Sources/ArcanePorting/Library/PersonalAppReceipt.swift) | Ricevuta di trasferimento personale, confronto delle copie e controllo delle impronte prima dello scambio. |
| [Sources/ArcanePorting/Library/CloudTransferPresentation.swift](../../Sources/ArcanePorting/Library/CloudTransferPresentation.swift) | Stati, misura esclusiva, annullamento e posizione del comando Cloud library con link di riserva. |
| [Sources/ArcanePorting/Library/CloudDriveFolders.swift](../../Sources/ArcanePorting/Library/CloudDriveFolders.swift) | Elenca, trova e crea cartelle Drive, rifiuta sovrapposizioni con il riferimento, lega l’anteprima di spostamento alla libreria approvata e verifica dipendenze e residui. |
| [Sources/ArcanePorting/Library/CloudDriveReads.swift](../../Sources/ArcanePorting/Library/CloudDriveReads.swift) | Letture condivise per un minuto, solo per lo schermo. |
| [Sources/ArcanePorting/Library/CloudFolderDiscovery.swift](../../Sources/ArcanePorting/Library/CloudFolderDiscovery.swift) | Cosa contiene ogni cartella, quali proporre e perché una è sbagliata. |
| [Sources/ArcanePorting/GameSettings/RemotePlayAdapters.swift](../../Sources/ArcanePorting/GameSettings/RemotePlayAdapters.swift) | Rileva ZeroTier, Tailscale e NetBird da interfacce IPv4 e identità VPN riportata dal sistema; segnala i tunnel ambigui. |
| [Sources/ArcanePorting/Library/BuildQueue.swift](../../Sources/ArcanePorting/Library/BuildQueue.swift) | FIFO delle compilazioni, richiesta serializzabile con scelta della cache locale, deduplica e controllo delle sorgenti al ripristino. |
| [Sources/ArcanePorting/Library/ActivityQueueFile.swift](../../Sources/ArcanePorting/Library/ActivityQueueFile.swift) | Lettura tollerante e scrittura atomica di code ed esiti; la riconferma attende la sincronizzazione del file e della directory. |
| [Sources/ArcanePorting/Library/ActivityHistory.swift](../../Sources/ArcanePorting/Library/ActivityHistory.swift) | Esiti di attività, lock tra processi e registro durevole dello spostamento con identità dell'eseguibile ed esito verificato. |
| [Sources/ArcanePorting/Library/GameStorageUsage.swift](../../Sources/ArcanePorting/Library/GameStorageUsage.swift) | Dimensioni per gioco e totali: distingue assenza e indisponibilità, segnala cache condivise e conserva identità stabili per il focus. |

## Porting · pagina del gioco

Cartella `Sources/ArcanePorting/Details/`.

| File | Responsabilità |
|---|---|
| [Sources/ArcanePorting/Details/GameDetailPresentation+Porting.swift](../../Sources/ArcanePorting/Details/GameDetailPresentation+Porting.swift) | La pagina di un gioco portato: fatti dello store Nintendo, toolchain della build, sorgenti, Rebuild e cartella dei salvataggi. |
| [Sources/ArcanePorting/Details/DetailsFacts+Porting.swift](../../Sources/ArcanePorting/Details/DetailsFacts+Porting.swift) | Le righe Details di un gioco portato: crediti, versione del gioco, data e stato del motore, dimensione e cartella dell’app. |
| [Sources/ArcanePorting/Details/InstalledEngineVersion.swift](../../Sources/ArcanePorting/Details/InstalledEngineVersion.swift) | Legge `DMCommit` dal plist dell'app installata, riusa il confronto d'ascendenza con l'engine selezionato e presenta data e stato localizzati. |
| [Sources/ArcanePorting/Details/GameOptionsPresentation+Porting.swift](../../Sources/ArcanePorting/Details/GameOptionsPresentation+Porting.swift) | Converte `GameSettingsSnapshot` in `GameOptionsBuildSettings`, incluso Play together se la build dichiara modalità di rete. |
| [Sources/ArcanePorting/Details/MoreLikeThis+Porting.swift](../../Sources/ArcanePorting/Details/MoreLikeThis+Porting.swift) | More like this fra giochi portati, con autori e generi dello store Nintendo. |

## Porting · impostazioni e app

Cartelle `Sources/ArcanePorting/Settings/` e `ArcanePorting/App/`.

| File | Responsabilità |
|---|---|
| [Sources/ArcanePorting/Settings/AppSettings+Porting.swift](../../Sources/ArcanePorting/Settings/AppSettings+Porting.swift) | Game defaults, schermo globale e per gioco, Cloud saves, cartella scelta e ID client pubblico Nextendo in `settings.json`; un valore assente o illeggibile è il suo default. |
| [Sources/ArcanePorting/Settings/SettingsReset+Porting.swift](../../Sources/ArcanePorting/Settings/SettingsReset+Porting.swift) | Reset group completo: quello della base più New games (default e scelta globale dello schermo). |
| [Sources/ArcanePorting/App/AppDataProfile+Porting.swift](../../Sources/ArcanePorting/App/AppDataProfile+Porting.swift) | Cartelle temporanee pulite all’avvio: quella del profilo e, nella release non migrata, anche quelle accanto alle app. |
| [Sources/ArcanePorting/App/FirstRunFindings+Porting.swift](../../Sources/ArcanePorting/App/FirstRunFindings+Porting.swift) | Il primo avvio conta le app nxnative della cartella Game apps, nella lettura e nel lettore annullabile. |
| [Sources/ArcanePorting/App/OnboardingInventory.swift](../../Sources/ArcanePorting/App/OnboardingInventory.swift) | Scoperta locale annullabile di app nxnative e file Switch senza chiavi, raggruppamento per titolo e stato già in libreria. |
| [Sources/ArcanePorting/App/DevelopmentProfileImporter+Porting.swift](../../Sources/ArcanePorting/App/DevelopmentProfileImporter+Porting.swift) | I controlli Porting della copia di sviluppo (`library.json`, catalogo con i tipi noti e l’import legacy) e `DevelopmentProfileImporter()` e `AppData.prepare()` con questi. |
| [Sources/ArcanePorting/Settings/SettingsCatalog+Porting.swift](../../Sources/ArcanePorting/Settings/SettingsCatalog+Porting.swift) | Righe Porting (inclusi Inbox e Cestino per le cache), disponibilità Nextendo in Play together e apertura di Cloud → Advanced da Search e Changed. |
| [Sources/ArcanePorting/Settings/IntegrationOverview.swift](../../Sources/ArcanePorting/Settings/IntegrationOverview.swift) | Proietta fatti in righe, con oggetti letti, scritture e destinatari esterni; `open` naviga senza eseguire i controlli. |

## Porting · Setup, motore e chiavi

Cartella `Sources/ArcanePorting/Setup/`.

| File | Responsabilità |
|---|---|
| [Sources/ArcanePorting/Setup/ToolchainRequirements.swift](../../Sources/ArcanePorting/Setup/ToolchainRequirements.swift) | Centralizza requisiti Xcode e asset Metal. |
| [Sources/ArcanePorting/Setup/ToolchainInfo.swift](../../Sources/ArcanePorting/Setup/ToolchainInfo.swift) | Registra provenienza e verifica della toolchain associata a un build. |
| [Sources/ArcanePorting/Setup/ToolchainGateCopy.swift](../../Sources/ArcanePorting/Setup/ToolchainGateCopy.swift) | Traduce il gate in testi distinguendo Metal certificato, precedente e successivo. |
| [Sources/ArcanePorting/Setup/SetupCheck.swift](../../Sources/ArcanePorting/Setup/SetupCheck.swift) | Converte i fatti in schede localizzate, distingue runtime assente e guasto ed esclude i checkout esistenti da Install all. |
| [Sources/ArcanePorting/Setup/GameFoldersCopy.swift](../../Sources/ArcanePorting/Setup/GameFoldersCopy.swift) | Condivide nomi delle cartelle, formati e descrizioni tra Setup, Settings e selettori dei percorsi; indica Game folders per cambiarle. |
| [Sources/ArcanePorting/Setup/SetupGrid.swift](../../Sources/ArcanePorting/Setup/SetupGrid.swift) | Calcola disposizione, centratura e navigazione del focus nella griglia del Setup. |
| [Sources/ArcanePorting/Setup/UpstreamCopy.swift](../../Sources/ArcanePorting/Setup/UpstreamCopy.swift) | Prepara i testi del changelog upstream e dell’adozione degli aggiornamenti tramite Arcane. |
| [Sources/ArcanePorting/Setup/NXNativeEnvironment.swift](../../Sources/ArcanePorting/Setup/NXNativeEnvironment.swift) | Ispeziona strumenti, Python, Xcode e Metal e restituisce uno stato dell’ambiente. |
| [Sources/ArcanePorting/Setup/EngineLocation.swift](../../Sources/ArcanePorting/Setup/EngineLocation.swift) | Risolve checkout predefinito o scelto e produce i candidati per prod.keys. |
| [Sources/ArcanePorting/Setup/EngineToolchain.swift](../../Sources/ArcanePorting/Setup/EngineToolchain.swift) | Individua runtime incluso o venv del checkout e prepara ambiente e PATH dei processi. |
| [Sources/ArcanePorting/Setup/EnginePackageReader.swift](../../Sources/ArcanePorting/Setup/EnginePackageReader.swift) | Legge content meta e capacità del checkout, compresa selezione NUP multiprogramma, senza esporre chiavi. |
| [Sources/ArcanePorting/Setup/NewestEngine.swift](../../Sources/ArcanePorting/Setup/NewestEngine.swift) | Scelta dell’engine più nuovo: testi condivisi, lettura del Metal dal lock di main, cambio di commit con Git senza toccare file modificati; usa il repository del pin per tornare all’engine testato. |
| [Sources/ArcanePorting/Setup/CompatibilityChecker.swift](../../Sources/ArcanePorting/Setup/CompatibilityChecker.swift) | Controlla commit, modifiche del checkout, Metal e opzioni CLI richieste dal frontend. |
| [Sources/ArcanePorting/Setup/SetupProbe.swift](../../Sources/ArcanePorting/Setup/SetupProbe.swift) | Raccoglie i fatti del Setup, compresi runtime attivo e stato del checkout; rilegge il checkout prima di cambiarlo. |
| [Sources/ArcanePorting/Setup/SetupActions.swift](../../Sources/ArcanePorting/Setup/SetupActions.swift) | Legge il pin facoltativo dal plist e costruisce i comandi Git per installare o allineare il motore al pin. |
| [Sources/ArcanePorting/Setup/KeyStore.swift](../../Sources/ArcanePorting/Setup/KeyStore.swift) | Valida `header_key` e pubblica atomicamente gli stessi dati letti con permessi 0600; espone solo il riepilogo. |
| [Sources/ArcanePorting/Setup/KeyCheck.swift](../../Sources/ArcanePorting/Setup/KeyCheck.swift) | Verifica le chiavi contro le intestazioni NCA, con intervalli di lettura limitati dalla dimensione del pacchetto. |
| [Sources/ArcanePorting/Setup/UpstreamChecker.swift](../../Sources/ArcanePorting/Setup/UpstreamChecker.swift) | Consulta i commit upstream tramite HTTP e produce stato e collegamento di confronto. |

## Porting · sorgenti, build e installazione

Cartella `Sources/ArcanePorting/Build/`.

| File | Responsabilità |
|---|---|
| [Sources/ArcanePorting/Build/GameResourceState.swift](../../Sources/ArcanePorting/Build/GameResourceState.swift) | Distingue app mancanti, sorgenti assenti e workspace non compilati; rifiuta gli alias locali nelle selezioni scoperte dal cloud. Una build esistente mantiene Play. |
| [Sources/ArcanePorting/Build/AppSizeCache.swift](../../Sources/ArcanePorting/Build/AppSizeCache.swift) | Conserva dimensioni per percorso e data del bundle e decide lo stato vuoto della libreria. |
| [Sources/ArcanePorting/Build/BuildWarningCopy.swift](../../Sources/ArcanePorting/Build/BuildWarningCopy.swift) | Testo mostrato a fine build per `warn` dell’engine: archivio mancante o pipeline da preparare al primo avvio. |
| [Sources/ArcanePorting/Build/NUPSourceCatalog.swift](../../Sources/ArcanePorting/Build/NUPSourceCatalog.swift) | Legge NUP con base o soli update; tiene distinti programma, applicazione e base DLC tramite il lettore upstream e conserva il default selezionato. |
| [Sources/ArcanePorting/Build/InstallProgress.swift](../../Sources/ArcanePorting/Build/InstallProgress.swift) | Interpreta avanzamento Git, percentuali e byte per le installazioni. |
| [Sources/ArcanePorting/Build/GameFileItem.swift](../../Sources/ArcanePorting/Build/GameFileItem.swift) | Sorgenti salvate con layout, tipo, requisiti e selezione NUP facoltativa, compatibile con i vecchi record e con il manifest cloud. |
| [Sources/ArcanePorting/Build/NUPProgramSelection.swift](../../Sources/ArcanePorting/Build/NUPProgramSelection.swift) | Identità tipizzata del programma NUP, applicazione e base add-on; indice ricavato dal programma, persistito con i sorgenti e portabile nel manifest cloud. |
| [Sources/ArcanePorting/Build/SourceSelection.swift](../../Sources/ArcanePorting/Build/SourceSelection.swift) | Collega un titolo compilabile per ID esatto; scelte dei contenuti, dimensioni e versione di build; verifica coerenza e supporto del programma NUP e ne vincola l’indice nel rebuild. |
| [Sources/ArcanePorting/Build/BuildRecord.swift](../../Sources/ArcanePorting/Build/BuildRecord.swift) | Conserva esito, tempi, log, provenienza, richiesta di Nextendo e descrittori ExeFS. Ordina i giochi visibili per ultima compilazione riuscita. |
| [Sources/ArcanePorting/Build/PipelineArchiveProgress.swift](../../Sources/ArcanePorting/Build/PipelineArchiveProgress.swift) | Legge il log pipeline della build corrente e conta solo i gruppi confermati pronti dal motore. |
| [Sources/ArcanePorting/Build/PortingProgress.swift](../../Sources/ArcanePorting/Build/PortingProgress.swift) | Aggrega eventi del motore in fasi e percentuale complessiva; identifica archivio e prewarm senza dedurre conteggi dal tempo trascorso. |
| [Sources/ArcanePorting/Build/PortingPresentation.swift](../../Sources/ArcanePorting/Build/PortingPresentation.swift) | Definisce fallimento persistito, ETA, attività senza stima del prewarm, aspetto della tile e pill del porting. |
| [Sources/ArcanePorting/Build/PortingFailureReason.swift](../../Sources/ArcanePorting/Build/PortingFailureReason.swift) | Distingue il mancato avvio di Python dagli errori del motore e delle chiavi; classifica anche tabelle shader diverse dal profilo ed errori Nextendo. |
| [Sources/ArcanePorting/Build/PortingNotice.swift](../../Sources/ArcanePorting/Build/PortingNotice.swift) | Decide quando notificare l’esito di un porting e prepara il relativo messaggio. |
| [Sources/ArcanePorting/Build/PendingInstall.swift](../../Sources/ArcanePorting/Build/PendingInstall.swift) | Conserva il bundle pronto e l’identità attesa; un vecchio record senza identità richiede un posto libero o una ricevuta corrispondente. |
| [Sources/ArcanePorting/Build/SourceCatalog.swift](../../Sources/ArcanePorting/Build/SourceCatalog.swift) | Riconosce sorgenti NSP/XCI/NSZ/XCZ e raggruppa titoli, update e DLC; DetectedSource conserva la selezione NUP tipizzata. |
| [Sources/ArcanePorting/Build/ExtractedSourceCatalog.swift](../../Sources/ArcanePorting/Build/ExtractedSourceCatalog.swift) | Verifica il layout di un gioco estratto, legge NPDM e profilo registrato e rileva update e DLC. |
| [Sources/ArcanePorting/Build/WorkspaceManager.swift](../../Sources/ArcanePorting/Build/WorkspaceManager.swift) | Rifiuta collisioni fra sorgenti prima di preparare i collegamenti; lascia intatta la cache e verifica i link interrotti. |
| [Sources/ArcanePorting/Build/BuildScratch.swift](../../Sources/ArcanePorting/Build/BuildScratch.swift) | Sceglie dove stanno workspace e app temporanea (sul volume dell'app quando può ospitarli), riconosce i workspace gestiti e le cartelle temporanee da pulire. |
| [Sources/ArcanePorting/Build/BuildCommand.swift](../../Sources/ArcanePorting/Build/BuildCommand.swift) | Valore con eseguibile, argomenti, ambiente e directory di lavoro del processo di porting. |
| [Sources/ArcanePorting/Build/BuildCommandBuilder.swift](../../Sources/ArcanePorting/Build/BuildCommandBuilder.swift) | Contratto CLI nxnative: Mac, JSON, versione pacchetto, selezione --program esplicita, override toolchain e Nextendo con ID pubblico. |
| [Sources/ArcanePorting/Build/BuildEvent.swift](../../Sources/ArcanePorting/Build/BuildEvent.swift) | Definisce gli eventi di fase, step, avanzamento e log ricevuti dal motore. |
| [Sources/ArcanePorting/Build/BuildEventParser.swift](../../Sources/ArcanePorting/Build/BuildEventParser.swift) | Decodifica eventi JSON e tratta le altre righe come log. |
| [Sources/ArcanePorting/Build/BuildService.swift](../../Sources/ArcanePorting/Build/BuildService.swift) | Gestisce processi, cancellazione, log ed eventi; continua a leggere l’engine se non può scrivere il log. Conserva il bundle valido quando fallisce solo l’installazione. |
| [Sources/ArcanePorting/Build/BuildOutputInstaller.swift](../../Sources/ArcanePorting/Build/BuildOutputInstaller.swift) | Firma ad hoc e verifica; controlla la destinazione attesa, pubblica con rinomina o scambio atomico e riprende tramite ricevuta. |
| [Sources/ArcanePorting/Build/GameAppDestination.swift](../../Sources/ArcanePorting/Build/GameAppDestination.swift) | Risolve la destinazione per build, rebuild e adozione; evita conflitti di nome e rimanda a Game folders se la destinazione non è disponibile. |

## Porting · avvio e icona del gioco

Cartella `Sources/ArcanePorting/Launch/`.

| File | Responsabilità |
|---|---|
| [Sources/ArcanePorting/Launch/ImportService.swift](../../Sources/ArcanePorting/Launch/ImportService.swift) | Identità e scansione dei bundle nxnative; ripara la copia in staging e verifica l'impronta del bundle da sostituire. Firma ad hoc solo se la firma originale non verifica e la politica dei manifest lo consente. |
| [Sources/ArcanePorting/Launch/AppIconProgress.swift](../../Sources/ArcanePorting/Launch/AppIconProgress.swift) | Stati e testi della preparazione icona, con esito informativo aggiunto al log della build conclusa. |
| [Sources/ArcanePorting/Launch/IconLaunchWait.swift](../../Sources/ArcanePorting/Launch/IconLaunchWait.swift) | Conserva una richiesta Play durante la firma dell'icona e la revoca su annullamento, errore o chiusura del dialogo. |
| [Sources/ArcanePorting/Launch/LaunchService.swift](../../Sources/ArcanePorting/Launch/LaunchService.swift) | Scrive le impostazioni runtime su file quando richiesto; avvia con NSWorkspace e ambiente consentito, passa chiavi overlay e Home al processo, rimuove lo snapshot all'uscita o all'errore. |
| [PlayersLaunch.swift](../../Sources/ArcanePorting/Launch/PlayersLaunch.swift) | Limita ordine, fusione, nomi e ritratti al bundle provato e ai valori che il gioco non fissa; conserva la fusione P1 per gli host precedenti. |
| [PlayerPadFingerprint.swift](../../Sources/ArcanePorting/Launch/PlayerPadFingerprint.swift) | Unisce i due usi dello stesso dispositivo HID, rifiuta le identità ambigue e calcola l'impronta di avvio senza conservare numeri di serie. |
| [Sources/ArcanePorting/Launch/HomeMenu.swift](../../Sources/ArcanePorting/Launch/HomeMenu.swift) | Rileva il protocollo Home del bundle, identifica `dmhost` e modella pausa, ripresa e uscita. |
| [Sources/ArcanePorting/Launch/GameOverlayLaunch.swift](../../Sources/ArcanePorting/Launch/GameOverlayLaunch.swift) | Riconosce le chiavi overlay nel `dmhost`; prepara palette, tempo, copertina e snapshot JSON privato con i soli campi visibili. |
| [Sources/ArcanePorting/Launch/InstalledEngineCapabilities.swift](../../Sources/ArcanePorting/Launch/InstalledEngineCapabilities.swift) | Risolve Home, overlay, `DM_SCREEN` e descrittore Z-A dal bundle, con cache Git per le verifiche di ascendenza. |
| [Sources/ArcanePorting/Launch/GameDisplay.swift](../../Sources/ArcanePorting/Launch/GameDisplay.swift) | Associa display a UUID di Core Graphics, risolve la scelta e il ripiego, riconosce `DM_SCREEN` in `env.txt`. |
| [Sources/ArcanePorting/Launch/NextendoLaunch.swift](../../Sources/ArcanePorting/Launch/NextendoLaunch.swift) | Verifica Nextendo nel checkout e nell’host, valida la sessione e compone l’ambiente, inclusi ospite offline e visibilità del gioco. |
| [Sources/ArcanePorting/Launch/NextendoAccountService.swift](../../Sources/ArcanePorting/Launch/NextendoAccountService.swift) | Legge profilo e amici, aggiorna le liste, rinnova la presenza OAuth e risolve ritratti e titoli pubblici senza bearer. Conserva la diagnostica delle letture e distingue le verifiche Discord ed e-mail. |
| [Sources/ArcanePorting/Launch/NextendoOnlineCounts.swift](../../Sources/ArcanePorting/Launch/NextendoOnlineCounts.swift) | Solo con un token e se almeno un posto è attivo, legge e valida il conteggio pubblico per title ID, con download limitato e cache breve. |
| [Sources/ArcanePorting/Launch/NextendoOAuth.swift](../../Sources/ArcanePorting/Launch/NextendoOAuth.swift) | Genera la richiesta PKCE, valida la callback, scambia e ruota i token e legge userinfo. Il trasporto è limitato e registra solo percorso e codice. |
| [Sources/ArcanePorting/Launch/NextendoTokenStore.swift](../../Sources/ArcanePorting/Launch/NextendoTokenStore.swift) | Legge, sostituisce e rimuove il refresh token condiviso sotto il lock nxnative, con permessi privati. |
| [Sources/ArcanePorting/Launch/AppIconWriter.swift](../../Sources/ArcanePorting/Launch/AppIconWriter.swift) | Cambia o ripristina l'icona, rifirma e verifica; conserva le copie e il manifesto se il rollback non riesce. |
| [Sources/ArcanePorting/Launch/NXNativeLibraryMerge.swift](../../Sources/ArcanePorting/Launch/NXNativeLibraryMerge.swift) | Merge nxnative: preserva l'identità di libreria, ma aggiorna la provenienza se il disco restituisce un bundle diverso. |

## Porting · impostazioni del gioco

Cartella `Sources/ArcanePorting/GameSettings/`.

| File | Responsabilità |
|---|---|
| [Sources/ArcanePorting/GameSettings/NXNativeGameSettings.swift](../../Sources/ArcanePorting/GameSettings/NXNativeGameSettings.swift) | Risolve la modalità multigiocatore, le scelte precedenti e le variabili esplicite, e compone l'ambiente VPN di Play. |
| [Sources/ArcanePorting/GameSettings/GameSettingsCopy.swift](../../Sources/ArcanePorting/GameSettings/GameSettingsCopy.swift) | Cosa cambierebbe copiando le impostazioni di un gioco su un altro: solo ciò che entrambe le build offrono, mai la rete; tutto o niente. |
| [Sources/ArcanePorting/GameSettings/GameSettingValues.swift](../../Sources/ArcanePorting/GameSettings/GameSettingValues.swift) | Modalità multigiocatore dichiarate, impostazioni residue di More settings, etichette e passi dei valori. |
| [Sources/ArcanePorting/GameSettings/SavedChoicesStore.swift](../../Sources/ArcanePorting/GameSettings/SavedChoicesStore.swift) | Legge e scrive le scelte salvate launcher.<env> nel dominio preferenze dell’app gioco. |
| [Sources/ArcanePorting/GameSettings/GameRuntimeConfig.swift](../../Sources/ArcanePorting/GameSettings/GameRuntimeConfig.swift) | Persiste opzioni per titolo con preferenze sostituibili, prepara Review e lingua del rebuild, mappa DM_* e unisce env.txt. |
| [Sources/ArcanePorting/GameSettings/LauncherSettings.swift](../../Sources/ArcanePorting/GameSettings/LauncherSettings.swift) | Legge launcher.json e verifica i controlli supportati, con fallback per le build precedenti. |
| [Sources/ArcanePorting/GameSettings/EnvFileEditor.swift](../../Sources/ArcanePorting/GameSettings/EnvFileEditor.swift) | Cambia una sola variabile di un `env.txt` lasciando intatte le altre righe. |

## Porting · cheat

Cartella `Sources/ArcanePorting/Cheats/`.

| File | Responsabilità |
|---|---|
| [Sources/ArcanePorting/Cheats/CheatFile.swift](../../Sources/ArcanePorting/Cheats/CheatFile.swift) | Decodifica cheats, sezioni, metadati e collegamenti dei codici secondo il parser del motore. |
| [Sources/ArcanePorting/Cheats/CheatInstall.swift](../../Sources/ArcanePorting/Cheats/CheatInstall.swift) | Valuta file e cartelle in ingresso rispetto a title ID, build ID e necessità di conferma. |
| [Sources/ArcanePorting/Cheats/CheatLocator.swift](../../Sources/ArcanePorting/Cheats/CheatLocator.swift) | Risolve build ID, title ID e cartella cheats seguendo i file e l’ambiente del launcher. |
| [Sources/ArcanePorting/Cheats/CheatStatus.swift](../../Sources/ArcanePorting/Cheats/CheatStatus.swift) | Valuta il supporto del motore tramite ancestry (git in un task staccato, risposta tenuta per l'avvio) e prepara stato della riga e indicatore attivo. |
| [Sources/ArcanePorting/Cheats/CheatCopy.swift](../../Sources/ArcanePorting/Cheats/CheatCopy.swift) | Centralizza testi di stato, rifiuto, importazione, sostituzione e rimozione dei cheats. |
| [Sources/ArcanePorting/Cheats/CheatStore.swift](../../Sources/ArcanePorting/Cheats/CheatStore.swift) | Legge e modifica cheat, file enabled, master switch e metadati; sostituisce o ripristina l'intero set. |

## Porting · store Nintendo e copertine

Cartella `Sources/ArcanePorting/Store/`.

| File | Responsabilità |
|---|---|
| [Sources/ArcanePorting/Store/BoxArtService.swift](../../Sources/ArcanePorting/Store/BoxArtService.swift) | Trova copertine Switch in GameTDB e ricorda copertine e ricerche senza risultato. |
| [Sources/ArcanePorting/Store/GameTDB.swift](../../Sources/ArcanePorting/Store/GameTDB.swift) | Decodifica il database GameTDB, abbina nomi e regioni e conserva l’indice locale. |
| [Sources/ArcanePorting/Store/ArtworkCandidates+Porting.swift](../../Sources/ArcanePorting/Store/ArtworkCandidates+Porting.swift) | Le immagini del picker per un gioco Switch: Nintendo Europe, GameTDB per regione, Title DB, poi quelle trovate online. |
| [Sources/ArcanePorting/Store/MetadataOptions.swift](../../Sources/ArcanePorting/Store/MetadataOptions.swift) | I valori di Change metadata per un gioco Switch: store Nintendo, Title DB e GameTDB, senza ripetizioni. |
| [Sources/ArcanePorting/Store/MetadataPicks+Porting.swift](../../Sources/ArcanePorting/Store/MetadataPicks+Porting.swift) | Le scelte del giocatore applicate ai metadati dello store Nintendo. |
| [Sources/ArcanePorting/Store/CriticRatingQuery+Porting.swift](../../Sources/ArcanePorting/Store/CriticRatingQuery+Porting.swift) | La ricerca dei voti per un gioco portato, con la console di Details (Switch o Switch 2). |
| [Sources/ArcanePorting/Store/NintendoEuropeCatalog.swift](../../Sources/ArcanePorting/Store/NintendoEuropeCatalog.swift) | Decodifica il catalogo Nintendo Europe e seleziona il prodotto base per ID e console. |
| [Sources/ArcanePorting/Store/NintendoStoreMetadata.swift](../../Sources/ArcanePorting/Store/NintendoStoreMetadata.swift) | Trasporto, ricerca, ripiego Title DB e cache Nintendo Store originali di Arcane. |
| [Sources/ArcanePorting/Store/SwitchGameMetadataService.swift](../../Sources/ArcanePorting/Store/SwitchGameMetadataService.swift) | Conserva i dati Arcane e riempie i vuoti per campo e lingua con Nintendo Europe, Title DB, LaunchBox e l'indice locale GameTDB. |
| [Sources/ArcanePorting/Store/ScreenshotFallback.swift](../../Sources/ArcanePorting/Store/ScreenshotFallback.swift) | Conserva per 30 giorni gli screenshot LaunchBox dei giochi senza screenshot Title DB e li sovrappone ai metadati. |

## Porting · salvataggi, backup e cloud

Cartella `Sources/ArcanePorting/Saves/`.

| File | Responsabilità |
|---|---|
| [Sources/ArcanePorting/Saves/SaveLocation.swift](../../Sources/ArcanePorting/Saves/SaveLocation.swift) | Percorsi storici e separati per profilo, ambiente di avvio, account/device, utenti aggiuntivi, registro e cloud effettivo. |
| [LinksAwakeningAchievements.swift](../../Sources/ArcanePorting/Saves/LinksAwakeningAchievements.swift) | Legge in sola lettura gli slot confermati, controlla versione e CRC ed estrae i progressi Zelda. |
| [Sources/ArcanePorting/Saves/CloudSaves.swift](../../Sources/ArcanePorting/Saves/CloudSaves.swift) | Descrive scelta cloud, cartelle iCloud o personalizzate e passaggi fra le opzioni. |
| [Sources/ArcanePorting/Saves/CloudSavesPreferences.swift](../../Sources/ArcanePorting/Saves/CloudSavesPreferences.swift) | Prepara la cartella e riapplica la scelta cloud ai domini dei giochi prima di ogni avvio, anche Off. |
| [Sources/ArcanePorting/Saves/RyujinxSaveFolder.swift](../../Sources/ArcanePorting/Saves/RyujinxSaveFolder.swift) | Riconosce contenitori Ryujinx, controlla il title ID e seleziona l’intero albero committed 0. |
| [Sources/ArcanePorting/Saves/SaveSnapshot.swift](../../Sources/ArcanePorting/Saves/SaveSnapshot.swift) | Identità, inventario, manifest schema 1/2 e anteprime; rifiuta dichiarazioni storiche con componenti nuovi. |
| [Sources/ArcanePorting/Saves/SavePresentation.swift](../../Sources/ArcanePorting/Saves/SavePresentation.swift) | Riepiloghi e ambito dei restore storici/multiutente, nomi dei componenti e limite cloud a primario/device. |
| [Sources/ArcanePorting/Saves/SaveFileIO.swift](../../Sources/ArcanePorting/Saves/SaveFileIO.swift) | Copie, hash e xattr portabili; inventario di directory e registro regolare limitato, controlli dei percorsi e scritture durevoli. |
| [Sources/ArcanePorting/Saves/SaveSnapshotStore.swift](../../Sources/ArcanePorting/Saves/SaveSnapshotStore.swift) | Backup completi degli utenti locali e registro, formati storici compatibili, staging e import User/Device. |
| [Sources/ArcanePorting/Saves/SaveRestorePreview.swift](../../Sources/ArcanePorting/Saves/SaveRestorePreview.swift) | Staging e validazione dei pezzi registrati nel backup, compreso il file utenti, con rilevamento dei cambiamenti concorrenti. |
| [Sources/ArcanePorting/Saves/SaveTransaction.swift](../../Sources/ArcanePorting/Saves/SaveTransaction.swift) | Sostituzioni e copia fra profili con backup e journal 1/2; staging di rollback ricreabile dopo una copia parziale. |
| [Sources/ArcanePorting/Saves/SaveOperationGate.swift](../../Sources/ArcanePorting/Saves/SaveOperationGate.swift) | Assegna lease attivi per titolo, blocchi di recupero per percorso e un’esclusione globale per l’updater. |
| [Sources/ArcanePorting/Saves/SaveFailure.swift](../../Sources/ArcanePorting/Saves/SaveFailure.swift) | Errori delle operazioni sui salvataggi; localizza anche l’origine della configurazione cloud prima di inserirla nel messaggio. |
| [Sources/ArcanePorting/Saves/SaveFiles.swift](../../Sources/ArcanePorting/Saves/SaveFiles.swift) | Controlli dei percorsi dei salvataggi con lstat: nessun link sostituito e solo cartelle e file normali. |

## Porting · mod RomFS e GameBanana

Cartelle `Sources/ArcanePorting/Mods/` e `ArcanePorting/Mods/GameBanana/`.

| File | Responsabilità |
|---|---|
| [Sources/ArcanePorting/Mods/ModStore.swift](../../Sources/ArcanePorting/Mods/ModStore.swift) | Ordine, overlay, ambiente ExeFS, snapshot, conflitti e Cestino. Rifiuta le scritture con nomi condivisi fra le due radici e tiene spento il gruppo ExeFS noto se la selezione non è risolvibile. |
| [Sources/ArcanePorting/Mods/ModFolderScanner.swift](../../Sources/ArcanePorting/Mods/ModFolderScanner.swift) | Elenca cartelle, archivi e file RomFS; classifica il contenuto come visivo, dati o incerto per il gioco online. |
| [Sources/ArcanePorting/Mods/ModSupport.swift](../../Sources/ArcanePorting/Mods/ModSupport.swift) | Quali file di mod funzionano (solo RomFS), dov'è la loro cartella `romfs`, nomi di cartella sicuri. |
| [Sources/ArcanePorting/Mods/GameBanana/GameBananaAPI.swift](../../Sources/ArcanePorting/Mods/GameBanana/GameBananaAPI.swift) | URL di ricerca e ID dai link, host fidati, risposte GameBanana e testo dalle descrizioni HTML. |
| [Sources/ArcanePorting/Mods/GameBanana/GameBananaClient.swift](../../Sources/ArcanePorting/Mods/GameBanana/GameBananaClient.swift) | Richieste e ricerche GameBanana con User-Agent, limite di 4 alla volta e cache su disco. |
| [Sources/ArcanePorting/Mods/GameBanana/GameBananaImageCache.swift](../../Sources/ArcanePorting/Mods/GameBanana/GameBananaImageCache.swift) | Cache su disco delle immagini delle mod dal CDN di GameBanana. |
| [Sources/ArcanePorting/Mods/GameBanana/GameBananaMatch.swift](../../Sources/ArcanePorting/Mods/GameBanana/GameBananaMatch.swift) | Abbina un gioco alla sua pagina GameBanana per nome e ricorda la scelta. |
| [Sources/ArcanePorting/Mods/GameBanana/AvailableModsFinder.swift](../../Sources/ArcanePorting/Mods/GameBanana/AvailableModsFinder.swift) | Verifica compatibilità da lista, ricerca o link e indica la pagina successiva e gli aggiornamenti. |
| [Sources/ArcanePorting/Mods/GameBanana/ModInstaller.swift](../../Sources/ArcanePorting/Mods/GameBanana/ModInstaller.swift) | Controlla, estrae con `bsdtar` e adotta le radici RomFS ed ExeFS della mod scaricata. |
| [Sources/ArcanePorting/Mods/GameBanana/GameBananaBandModel.swift](../../Sources/ArcanePorting/Mods/GameBanana/GameBananaBandModel.swift) | Stato della fascia Mods: abbinamento, ricerca, paginazione e installazioni. |
| [Sources/ArcanePorting/Mods/GameBanana/ModCatalog.swift](../../Sources/ArcanePorting/Mods/GameBanana/ModCatalog.swift) | Categorie nostre, ordinamenti e sezioni della pagina dello store (altezze fisse). |
| [Sources/ArcanePorting/Mods/GameBanana/ModCatalogSnapshots.swift](../../Sources/ArcanePorting/Mods/GameBanana/ModCatalogSnapshots.swift) | Le mod di ogni gioco salvate su disco, per aprire lo store subito; solo link GameBanana. |
| [Sources/ArcanePorting/Mods/GameBanana/ModStoreModel.swift](../../Sources/ArcanePorting/Mods/GameBanana/ModStoreModel.swift) | Dati dello store: apre dalle copie su disco, aggiorna in background due giochi alla volta, abbina solo se sicuro. |
| [Sources/ArcanePorting/Mods/GameBanana/ModStoreFocus.swift](../../Sources/ArcanePorting/Mods/GameBanana/ModStoreFocus.swift) | Focus nella pagina dello store, ancorato al tipo di sezione; ogni sezione ricorda la sua tessera. |
| [Sources/ArcanePorting/Mods/GameBanana/GameBananaFindModel.swift](../../Sources/ArcanePorting/Mods/GameBanana/GameBananaFindModel.swift) | Stato della ricerca per nome: campo, risultati, None of these. |
| [Sources/ArcanePorting/Mods/GameBanana/ModDownload.swift](../../Sources/ArcanePorting/Mods/GameBanana/ModDownload.swift) | Scarica un file di GameBanana con avanzamento e Cancel, solo da host fidati. |

## UI · Add Game e porting

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/AddGame/AddGameView.swift](../../Sources/NXLibrary/Views/AddGame/AddGameView.swift) | Compone il wizard Choose/Review/Porting, gestisce il rilascio di file e i blocchi cloud; alla chiusura non sovrascrive una selezione Spotlight in attesa. |
| [Sources/NXLibrary/Views/AddGame/AddGameView+Rows.swift](../../Sources/NXLibrary/Views/AddGame/AddGameView+Rows.swift) | Righe e focus del wizard, spiegazione del blocco dell'adozione locale e stato della verifica della cache di compilazione cloud. |
| [Sources/NXLibrary/Views/AddGame/AddGameRows.swift](../../Sources/NXLibrary/Views/AddGame/AddGameRows.swift) | Rende le righe riutilizzabili per sorgenti e azioni di Add Game. |
| [Sources/NXLibrary/Views/AddGame/AddGameAction.swift](../../Sources/NXLibrary/Views/AddGame/AddGameAction.swift) | Identifica le azioni navigabili dei passaggi del wizard. |
| [Sources/NXLibrary/Views/AddGame/AddGameStepThreeView.swift](../../Sources/NXLibrary/Views/AddGame/AddGameStepThreeView.swift) | Mostra progresso, log, annullamento durante la compilazione, fase di installazione ed esito con Retry. |
| [Sources/NXLibrary/Views/Porting/GameInboxView.swift](../../Sources/NXLibrary/Views/Porting/GameInboxView.swift) | Pagina Selene con rilascio file, destinazione nel carattere del corpo, motivo del blocco o azioni singole o in gruppo. |
| [Sources/NXLibrary/Views/Porting/GameInboxView+Input.swift](../../Sources/NXLibrary/Views/Porting/GameInboxView+Input.swift) | Traduce tastiera e controller in focus e azioni dell'Inbox. |

## UI · Spotlight

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Spotlight/SpotlightView.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightView.swift) | Compone home, tessere e pagina; espone la card Inbox solo se attiva, osserva il cloud, collega Profili alla shell e libera il focus di ordinamento all’uscita. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightView+Stage.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightView+Stage.swift) | Palco Spotlight: riga, testate per fonte, azioni cloud, arte hero, overlay, focus di ordinamento e ultime cinque compilazioni. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightView+Hints.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightView+Hints.swift) | Suggerimenti per il focus, incluse le azioni dei collegamenti Mac, Download e X per la cronologia delle compilazioni. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightView+Platforms.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightView+Platforms.swift) | Input, attesa prima di montare le nuove copertine, filtro del profilo e accesso a un gioco fuori filtro. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightView+Selection.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightView+Selection.swift) | Selezione, filtri e libreria; entrando nella pagina si lascia il focus della testata. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightView+Mods.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightView+Mods.swift) | Fascia Mods e store delle mod che si apre da lì. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightView+PageLayout.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightView+PageLayout.swift) | Offset e maschera della pagina, riga Mods a fuoco sempre visibile e cosa mostra About. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightView+PageContent.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightView+PageContent.swift) | Cosa contiene la pagina per un gioco Switch o Steam: About, Details, screenshot e giochi correlati. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightView+Input.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightView+Input.swift) | Traduce input, card, azioni cloud, screenshot e ordinamento. X sulla carta Attività cambia la visibilità delle compilazioni. Le frecce orizzontali nella riga usano solo le tessere. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightView+Entrance.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightView+Entrance.swift) | Coordina l’entrata su moonlight condiviso: coperture e fullscreen, pausa, attesa dell’arte, effetti di volo e dissolvenza, barra in alto e hint per ultimi, atterraggio di sicurezza; nessun input salta l’entrata. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightRowView.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightRowView.swift) | Disegna la riga, il focus e i cue Cloud; mostra le facce scorrevoli della piattaforma e quella della carta Mods (`ModsCardCover`). |
| [Sources/NXLibrary/Views/Spotlight/SpotlightTopBar.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightTopBar.swift) | Disegna Integrations a sinistra, filtri al centro, ritratto e orologio a destra; il menu di ordinamento parte dal prompt in fondo. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightInfoView.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightInfoView.swift) | Mostra logo, Play o Download con fase e byte, Cloud, statistiche e stato di porting. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightCardInfoView.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightCardInfoView.swift) | Mostra informazioni e azioni delle card Spotlight, incluse Inbox e le tessere quadrate con date di compilazione su Attività. |
| [Sources/NXLibrary/Views/Spotlight/SpotlightPageSections.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightPageSections.swift) | Modello della pagina inferiore con dettagli, link e giochi correlati del catalogo; generi e descrizione; la descrizione può venire da Wikipedia (`WikipediaAbout`). |
| [Sources/NXLibrary/Views/Spotlight/SpotlightScreenshotStrip.swift](../../Sources/NXLibrary/Views/Spotlight/SpotlightScreenshotStrip.swift) | Disegna la striscia di screenshot con focus e stile adattabile alle schermate. |
| [Sources/NXLibrary/Views/Spotlight/SeleneArtBackground.swift](../../Sources/NXLibrary/Views/Spotlight/SeleneArtBackground.swift) | Compone wallpaper, sfondo del gioco, transizioni e maschere leggendo la palette dallo snapshot condiviso; l'arte è un `CALayer` che dissolve nel render server (`SeleneArtLayer`) e che l'entrata di Spotlight tiene nascosto (`ArtReveal`). |
| [Sources/NXLibrary/Views/Spotlight/SeleneHeroArt.swift](../../Sources/NXLibrary/Views/Spotlight/SeleneHeroArt.swift) | Coordina il caricamento differito di hero e logo del gioco selezionato; aggiorna l'hero quando arriva l'URL del catalogo. |
| [Sources/NXLibrary/Views/Spotlight/GameArtLoader.swift](../../Sources/NXLibrary/Views/Spotlight/GameArtLoader.swift) | Carica hero e loghi, con le scelte personali prima del catalogo e il vecchio hero disponibile offline. Limita le cache degli sfondi anche per byte decodificato. |
| [Sources/NXLibrary/Views/Spotlight/GameArtLoader+Played.swift](../../Sources/NXLibrary/Views/Spotlight/GameArtLoader+Played.swift) | Hero e logo di un `PlayedGame` per schermata di lancio e card di fine sessione; per Steam le stesse scelte delle sue pagine. |

## UI · Collection e Details

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Collection/CollectionView.swift](../../Sources/NXLibrary/Views/Collection/CollectionView.swift) | Compone copertine e filtro Cloud; distingue configurazione, ricerca, controllo incompleto e inventario verificato senza giochi. |
| [Sources/NXLibrary/Views/Collection/CollectionView+Input.swift](../../Sources/NXLibrary/Views/Collection/CollectionView+Input.swift) | Muove il focus nella barra, nell’elenco o tra le azioni della Collection vuota; inoltra Play, Download e opzioni per fonte, e apre l’ordinamento nella Collection principale. |
| [Sources/NXLibrary/Views/Collection/CollectionCoverRow.swift](../../Sources/NXLibrary/Views/Collection/CollectionCoverRow.swift) | Disegna copertine e scorrimento della riga Collection, con cue Cloud sopra l'arte. |
| [Sources/NXLibrary/Views/Detail/GameDetailView.swift](../../Sources/NXLibrary/Views/Detail/GameDetailView.swift) | Compone Details; coordina focus e suggerimenti e non propone Select per un download passivo. |
| [Sources/NXLibrary/Views/Detail/GameDetailView+Input.swift](../../Sources/NXLibrary/Views/Detail/GameDetailView+Input.swift) | Gestisce azioni, Download, screenshot, navigazione e passaggio ai giochi correlati da Details. |
| [Sources/NXLibrary/Views/Detail/DetailsBackground.swift](../../Sources/NXLibrary/Views/Detail/DetailsBackground.swift) | Compone hero e maschere dello sfondo dedicato alla pagina Details. |
| [Sources/NXLibrary/Views/Detail/DetailsTopBlock.swift](../../Sources/NXLibrary/Views/Detail/DetailsTopBlock.swift) | Mostra logo, prossima azione, luogo dei contenuti, stato o misura non duplicati, statistiche, generi e descrizione. |
| [Sources/NXLibrary/Views/Detail/DetailsBands.swift](../../Sources/NXLibrary/Views/Detail/DetailsBands.swift) | Disegna screenshot, mod e fascia correlati condivisa, con copertine Switch o Steam secondo la fonte. |
| [Sources/NXLibrary/Views/Detail/DetailsPanel.swift](../../Sources/NXLibrary/Views/Detail/DetailsPanel.swift) | Pannello Details uguale per ogni fonte: righe con icona, voto della critica in ultima riga e link in `SeleneActionGrid`; carica solo il voto del gioco mostrato. |
| [Sources/NXLibrary/Views/Detail/CloudLibraryPanel.swift](../../Sources/NXLibrary/Views/Detail/CloudLibraryPanel.swift) | Cloud library: copie, azioni per artefatto, Pause/Resume e app precedente; somma la selezione locale da liberare e distingue verifica e avanzamento. |
| [CloudPersonalAppUpdateRow.swift](../../Sources/NXLibrary/Views/Detail/CloudPersonalAppUpdateRow.swift) | Mostra aggiornamento personale e quantità da scaricare, oppure copie diverse senza invito alla sostituzione. |
| [Sources/NXLibrary/Views/Detail/CriticRatingValue.swift](../../Sources/NXLibrary/Views/Detail/CriticRatingValue.swift) | Valore della riga Critic score: cinque stelle, numero /100 e fonte, senza finestre aggiuntive; caricamento e assenza espliciti. |
| [Sources/NXLibrary/ViewModels/IGDBSettings.swift](../../Sources/NXLibrary/ViewModels/IGDBSettings.swift) | Configurazione IGDB facoltativa: verifica prima del salvataggio, rimozione e invalidazione delle richieste/voti precedenti. |
| [Sources/NXLibrary/Views/Components/IGDBCredentialsDialog.swift](../../Sources/NXLibrary/Views/Components/IGDBCredentialsDialog.swift) | Guida sintetica in cinque passi, Client ID, Client Secret nascosto, verifica/salvataggio e annullamento; input Settings sospeso. |
| [Sources/NXLibrary/Views/Settings/SettingsAPISection.swift](../../Sources/NXLibrary/Views/Settings/SettingsAPISection.swift) | Online services, Play together e Nextendo; conferma le scelte della rete e conserva i titoli risolti per gli amici. Da Integrations attende Check status o Sign in. |
| [Sources/NXLibrary/Views/Settings/SettingsCloudLibrarySection.swift](../../Sources/NXLibrary/Views/Settings/SettingsCloudLibrarySection.swift) | Cloud library: account, biblioteche nel cloud e scelte di questo Mac sempre visibili; rclone, test e biblioteca seguita in Avanzate. Da Integrations ispeziona rclone solo in Avanzate. |
| [Sources/NXLibrary/Views/Settings/CloudSetupAssistant.swift](../../Sources/NXLibrary/Views/Settings/CloudSetupAssistant.swift) | Stato, barra d’azioni e domande dell’assistente cloud in tre passi; il lavoro attivo governa l’attesa della verifica. |
| [Sources/NXLibrary/Views/Settings/CloudSetupAssistant+Input.swift](../../Sources/NXLibrary/Views/Settings/CloudSetupAssistant+Input.swift) | Focus, tastiera, controller e azioni dell’assistente: verifica, attivazione, spostamento. |
| [Sources/NXLibrary/Views/Settings/CloudSetupAssistant+Account.swift](../../Sources/NXLibrary/Views/Settings/CloudSetupAssistant+Account.swift) | Passo 1: tenere l’account, incollare un client Google o crearlo in cinque passi. |
| [Sources/NXLibrary/Views/Settings/CloudSetupAssistant+Folders.swift](../../Sources/NXLibrary/Views/Settings/CloudSetupAssistant+Folders.swift) | Passo 2: una domanda per cartella, creazione dopo conferma e verifica della vecchia cartella legata al ticket e all’ambito Drive. |
| [Sources/NXLibrary/Views/Settings/CloudSetupAssistant+Browser.swift](../../Sources/NXLibrary/Views/Settings/CloudSetupAssistant+Browser.swift) | Selettore Drive: percorso, recenti, cosa contiene ogni cartella; riprende la verifica interrotta al ritorno. |
| [Sources/NXLibrary/Views/Settings/CloudSetupAssistant+Ready.swift](../../Sources/NXLibrary/Views/Settings/CloudSetupAssistant+Ready.swift) | Passo 3: riepilogo e verifica. |
| [Sources/NXLibrary/ViewModels/CloudLibraryModel+KeptFolders.swift](../../Sources/NXLibrary/ViewModels/CloudLibraryModel+KeptFolders.swift) | Ricorda le cartelle prima di lasciare una connessione. |
| [Sources/NXLibrary/ViewModels/CloudRecentFolders.swift](../../Sources/NXLibrary/ViewModels/CloudRecentFolders.swift) | Cartelle Drive scelte di recente per connessione. |
| [Sources/NXLibrary/Views/Settings/SettingsCloudLibrarySection.swift](../../Sources/NXLibrary/Views/Settings/SettingsCloudLibrarySection.swift) | Cloud library: verifica, recupero e configurazione; la scelta esplicita di rclone conserva il collegamento stabile. |
| [Sources/NXLibrary/Views/Settings/CloudSetupAssistant.swift](../../Sources/NXLibrary/Views/Settings/CloudSetupAssistant.swift) | Spiega il diritto Google, sceglie le cartelle, mostra blocchi e indica Collection → Cloud dopo l’attivazione; uno spostamento pendente si riprende da Attività. |
| [Sources/NXLibrary/Views/Settings/CloudSetupAssistant+Input.swift](../../Sources/NXLibrary/Views/Settings/CloudSetupAssistant+Input.swift) | Traduce tastiera e controller in azioni sul bersaglio corrente, lasciando precedenza al menu e alla conferma di uscita. |
| [Sources/NXLibrary/Views/Settings/CloudReferenceDialog.swift](../../Sources/NXLibrary/Views/Settings/CloudReferenceDialog.swift) | Editor del link o ID Drive: spiega sola lettura e assenza di condivisione reciproca; un ID non valido lascia il focus su Cancel. |
| [Sources/NXLibrary/Views/Settings/NextendoClientDialog.swift](../../Sources/NXLibrary/Views/Settings/NextendoClientDialog.swift) | Dialogo Selene per scegliere e validare l’ID client pubblico o riprendere il default della build. |

## UI · Game Options, cheats e salvataggi

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/GameOptions/GameOptionsView.swift](../../Sources/NXLibrary/Views/GameOptions/GameOptionsView.swift) | Opzioni del gioco, Edit details e pannelli; aggiorna capacità dello schermo, adattatori e rischio RomFS. |
| [PlayersScreen.swift](../../Sources/NXLibrary/Views/Players/PlayersScreen.swift) | Otto posti, modalità, profili in linea e dialoghi, composti con le viste Selene. |
| [PlayersScreenModel.swift](../../Sources/NXLibrary/Views/Players/PlayersScreenModel.swift) | Risoluzione dei controller, arrivo, spostamento, aggiornamento del piano, sessione e PIN. |
| [PlayersScreen+Input.swift](../../Sources/NXLibrary/Views/Players/PlayersScreen+Input.swift) | Focus nella griglia, comandi diretti del posto, tastiera e controller nello strato attivo. |
| [PlayersScreenHost.swift](../../Sources/NXLibrary/Views/Players/PlayersScreenHost.swift) | Collega la pagina alle notifiche del genitore, alla cattura delle pressioni, al registro e alla diagnostica. |
| [Sources/NXLibrary/Views/GameOptions/GameOptionsView+Rows.swift](../../Sources/NXLibrary/Views/GameOptions/GameOptionsView+Rows.swift) | Colonna, ciclo Play together con icona a due persone, frecce quando modificabili, percorso di rete, accessibilità e barra Rebuild. |
| [Sources/NXLibrary/Views/GameOptions/GameOptionsView+Confirmation.swift](../../Sources/NXLibrary/Views/GameOptions/GameOptionsView+Confirmation.swift) | Conferma: overlay, testi, richiesta, annullamento ed esecuzione dell’azione confermata. |
| [Sources/NXLibrary/Views/GameOptions/GameOptionsView+Focus.swift](../../Sources/NXLibrary/Views/GameOptions/GameOptionsView+Focus.swift) | Focus: impostazione, spostamento, ingresso e uscita da Edit details. |
| [Sources/NXLibrary/Views/GameOptions/GameOptionsView+Input.swift](../../Sources/NXLibrary/Views/GameOptions/GameOptionsView+Input.swift) | Tastiera, rotella e controller: navigazione, attivazione, indietro o annullamento della verifica Rebuild. |
| [Sources/NXLibrary/Views/GameOptions/GameOptionsView+Actions.swift](../../Sources/NXLibrary/Views/GameOptions/GameOptionsView+Actions.swift) | Azioni delle righe, incluso il ciclo multigiocatore e schermo con focus, la disattivazione RomFS e Rebuild. |
| [Sources/NXLibrary/Views/GameOptions/ChangeArtworkView.swift](../../Sources/NXLibrary/Views/GameOptions/ChangeArtworkView.swift) | Seleziona artwork per titolo da rete o file e indica dove viene usato, con stato ad altezza stabile. Il file tiene stato, geometria, `body`, schede, ricerca, stato e griglia; il resto sta nelle estensioni qui sotto. |
| [Sources/NXLibrary/Views/GameOptions/ChangeArtworkView+Tiles.swift](../../Sources/NXLibrary/Views/GameOptions/ChangeArtworkView+Tiles.swift) | Tile della griglia: anteprima, didascalia e segno dell’artwork in uso. |
| [Sources/NXLibrary/Views/GameOptions/ChangeArtworkView+Loading.swift](../../Sources/NXLibrary/Views/GameOptions/ChangeArtworkView+Loading.swift) | Caricamento: candidati e anteprime della scheda, risultati di una fonte, scelta del giocatore e icona automatica. |
| [Sources/NXLibrary/Views/GameOptions/ChangeArtworkView+Choosing.swift](../../Sources/NXLibrary/Views/GameOptions/ChangeArtworkView+Choosing.swift) | Scelta di una tile o immagine; selettore manuale di file condiviso con i collegamenti Mac. |
| [Sources/NXLibrary/Views/GameOptions/ChangeArtworkView+Browse.swift](../../Sources/NXLibrary/Views/GameOptions/ChangeArtworkView+Browse.swift) | Sfoglia una fonte: apertura, ricerca, chiusura e pagina della fonte. |
| [Sources/NXLibrary/Views/GameOptions/ChangeArtworkView+Input.swift](../../Sources/NXLibrary/Views/GameOptions/ChangeArtworkView+Input.swift) | Input: schede, focus, indietro e chiusura, scelta, controller e monitor dei tasti. |
| [Sources/NXLibrary/Views/GameOptions/ChangeMetadataView.swift](../../Sources/NXLibrary/Views/GameOptions/ChangeMetadataView.swift) | Offre alternative per campo da store, Title DB, GameTDB e IGDB, oppure testo personale; anteprima, scelta, annullamento e retry con lo stesso input. |
| [Sources/NXLibrary/Views/GameOptions/CheatsPanel.swift](../../Sources/NXLibrary/Views/GameOptions/CheatsPanel.swift) | Presenta file, master switch, codici, importazione, rimozione e stato di scrittura dei cheats. |
| [Sources/NXLibrary/Views/GameOptions/ModsPanel.swift](../../Sources/NXLibrary/Views/GameOptions/ModsPanel.swift) | Righe File mods e Code mods, avvisi Online, focus, importazione ExeFS, Rebuild, interruttori, conflitti, ordine e Cestino. |
| [Sources/NXLibrary/Views/Detail/ModDetailPanel.swift](../../Sources/NXLibrary/Views/Detail/ModDetailPanel.swift) | Dettaglio di una mod GameBanana: immagini, autore, versione, descrizione, Install/Update e link. |
| [Sources/NXLibrary/Views/Detail/GameBananaFindPanel.swift](../../Sources/NXLibrary/Views/Detail/GameBananaFindPanel.swift) | Pannelli per trovare il gioco e cercare le sue mod, con lo stesso campo GameBanana. |
| [Sources/NXLibrary/ViewModels/ModStoreHost.swift](../../Sources/NXLibrary/ViewModels/ModStoreHost.swift) | Store della card Mods: mantiene la cover fra schermate, rivalida abbinamenti e snapshot; rilegge i badge a ogni apertura e scarta i risultati di generazioni precedenti. |
| [Sources/NXLibrary/Views/Store/ModStorePage.swift](../../Sources/NXLibrary/Views/Store/ModStorePage.swift) | Pagina dello store: barra di ordinamento, banner Featured, righe di tessere; disegna solo le sezioni vicine al focus. |
| [Sources/NXLibrary/Views/Store/GameBananaBlur.swift](../../Sources/NXLibrary/Views/Store/GameBananaBlur.swift) | Arte di una mod rimpicciolita e sfocata una volta, fuori dal main thread, e tenuta in memoria: sfondo del Featured. |
| [Sources/NXLibrary/ViewModels/ModsBandHost.swift](../../Sources/NXLibrary/ViewModels/ModsBandHost.swift) | Fascia Mods condivisa da Spotlight e Details. Legge mod installate, coordina GameBanana e pannelli, svuota i dati del gioco precedente sulla riga Spotlight. |
| [Sources/NXLibrary/ViewModels/GameBananaServices.swift](../../Sources/NXLibrary/ViewModels/GameBananaServices.swift) | Client, cache delle immagini e abbinamenti GameBanana condivisi da tutta l'app. |
| [Sources/NXLibrary/Views/GameOptions/SavesPanel.swift](../../Sources/NXLibrary/Views/GameOptions/SavesPanel.swift) | Azioni, anteprime ed esiti dei salvataggi; la scelta del profilo parte da Annulla a destra e mostra il suo aiuto. |
| [Sources/NXLibrary/Views/GameOptions/GameSettingsScreen.swift](../../Sources/NXLibrary/Views/GameOptions/GameSettingsScreen.swift) | Pagina completa raggiunta da All settings per Switch e Steam; barra, focus, input e ritorno al pannello rapido. |
| [Sources/NXLibrary/Views/GameOptions/GameOptionsView+FullSettings.swift](../../Sources/NXLibrary/Views/GameOptions/GameOptionsView+FullSettings.swift) | Traduce i gruppi del catalogo e le azioni esistenti del gioco Switch in righe; riusa Mods, Cheats e Saves. |
| [Sources/NXLibrary/Views/GameOptions/MoreSettingsPanel.swift](../../Sources/NXLibrary/Views/GameOptions/MoreSettingsPanel.swift) | Mostra le impostazioni del launcher.json senza riga dedicata: interruttori, scelte e intervalli; le righe fissate da env.txt restano attenuate. |
| [Sources/NXLibrary/Views/GameOptions/CopySettingsPanel.swift](../../Sources/NXLibrary/Views/GameOptions/CopySettingsPanel.swift) | Gli altri giochi a cui copiare le impostazioni; A mostra cosa cambia prima di scrivere. |
| [Sources/NXLibrary/Views/GameOptions/SaveImportDetails.swift](../../Sources/NXLibrary/Views/GameOptions/SaveImportDetails.swift) | Disegna percorsi From/To centrati, riquadri leggeri e freccia con riflesso direzionale. |

## UI · Settings

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Settings/SettingsView.swift](../../Sources/NXLibrary/Views/Settings/SettingsView.swift) | Coordina sezioni, bozza e dialoghi; comunica al router quando un sottopannello possiede l’input. |
| [Sources/NXLibrary/Views/OortUI/ControllerShape.swift](../../Sources/NXLibrary/Views/OortUI/ControllerShape.swift) | Sagoma e posti dei tasti di ogni tipo di controller. |
| [Sources/NXLibrary/Views/OortUI/OortSettingsShell.swift](../../Sources/NXLibrary/Views/OortUI/OortSettingsShell.swift) | Layout riusabile: barra, titolo, pila di pagine, ritorno, collegamenti e campo di ricerca. |
| [Sources/NXLibrary/Views/OortUI/OortAssistantPanel.swift](../../Sources/NXLibrary/Views/OortUI/OortAssistantPanel.swift) | Pannello a passi e scheda di una cartella. |
| [Sources/NXLibrary/Views/OortUI/OortActionBar.swift](../../Sources/NXLibrary/Views/OortUI/OortActionBar.swift) | Piede di pannelli e domande: ritorno a sinistra, azione principale a destra. |
| [Sources/NXLibrary/Views/Settings/SettingsDraftFields.swift](../../Sources/NXLibrary/Views/Settings/SettingsDraftFields.swift) | Elenca le chiavi di Settings, distingue anteprima e applicazione differita e descrive i cambi in ordine di importanza. |
| [Sources/NXLibrary/Views/Settings/SettingsSidebar.swift](../../Sources/NXLibrary/Views/Settings/SettingsSidebar.swift) | Associa le pagine alle rubriche, al campo di ricerca e ai filtri; mantiene i collegamenti diretti alle sezioni. |
| [Sources/NXLibrary/Views/Settings/SettingsSectionContent.swift](../../Sources/NXLibrary/Views/Settings/SettingsSectionContent.swift) | Instrada le sezioni, distingue Play together da Online services, passa gli ingressi cloud e mostra le azioni del blocco profilo. Usa un trattino se manca il commit del motore. |
| [Sources/NXLibrary/Views/Settings/SettingsSearchSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsSearchSection.swift) | Presenta risultati e valori modificati filtrati dal campo nella barra; ciascun risultato apre la riga nella sua pagina. |
| [Sources/NXLibrary/Views/Settings/SettingsStartUpSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsStartUpSection.swift) | Espone il profilo all’avvio, schermata iniziale, animazione e aggiornamenti; `SettingsProfileCardsSection` ordina e attiva le schede del profilo. |
| [Sources/NXLibrary/Views/Settings/SettingsProfileIdentitySection.swift](../../Sources/NXLibrary/Views/Settings/SettingsProfileIdentitySection.swift) | Identità del profilo attivo: nome, illustrazione e immagine personale. |
| [Sources/NXLibrary/Views/Settings/SettingsNavigationSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsNavigationSection.swift) | Espone le preferenze di navigazione e dei suggerimenti dei tasti. |
| [Sources/NXLibrary/Views/Settings/SettingsSpotlightSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsSpotlightSection.swift) | Espone card, ordine e preferenze della home Spotlight. |
| [Sources/NXLibrary/Views/Settings/SettingsSoundSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsSoundSection.swift) | Espone volume, scelta e anteprima sonora; mostra la licenza prima di importare e rimuove solo la copia; mantiene l’import Selene storico. |
| [Sources/NXLibrary/Views/Settings/SettingsLookSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsLookSection.swift) | Separa palette, sfondi e adattamento del profilo da luminosità, movimento e icona di Look. |
| [Sources/NXLibrary/Views/Settings/SettingsGamesSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsGamesSection.swift) | Porting → New games: default dei nuovi giochi, vibrazione e schermo globale applicato al Play. |
| [Sources/NXLibrary/Views/Settings/SettingsLibraryGamesSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsLibraryGamesSection.swift) | Library → Games: schermata di lancio, Surprise me, card della sessione e app di gioco portate nascoste. |
| [Sources/NXLibrary/Views/Settings/SettingsCloudSavesSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsCloudSavesSection.swift) | Porting → Cloud saves: scelta e cartella; chiarisce che sincronizzano solo primario e device. |
| [Sources/NXLibrary/Views/Settings/SettingsControllersSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsControllersSection.swift) | Espone disposizione del profilo, riepilogo dei tasti, sostituzioni Home di macOS, zona morta, Players e tre scelte per Home in gioco. |
| [Sources/NXLibrary/Views/Settings/SettingsLibrarySection.swift](../../Sources/NXLibrary/Views/Settings/SettingsLibrarySection.swift) | Porting → Game folders: cartelle, interruttore Inbox, scansione e notifiche dei porting. |
| [Sources/NXLibrary/Views/Settings/SettingsStorageSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsStorageSection.swift) | Library → Storage: spazio occupato, log, cache di metadati e artwork, cartella comune dei backup verificati. |
| [Sources/NXLibrary/Views/Settings/SettingsPortingStorageSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsPortingStorageSection.swift) | Porting → Porting storage: dimensioni e conferma per spostare nel Cestino la cache di uno o di tutti i giochi. |
| [Sources/NXLibrary/Views/Settings/SettingsConsoleSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsConsoleSection.swift) | System → Console: apre la console dei log di build e avvio. |
| [Sources/NXLibrary/Views/Settings/SettingsEngineSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsEngineSection.swift) | Porting → Setup and engine: checkout, pin, gate, conferme per cambio motore e override, runtime, changelog upstream e Setup; l'arrivo da Integrations non avvia controlli né importa chiavi. |
| [Sources/NXLibrary/Views/Settings/SettingsKeysSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsKeysSection.swift) | Porting → Keys: stato, importazione, sostituzione e rilevamento di prod.keys. |
| [Sources/NXLibrary/Views/Settings/SettingsAboutSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsAboutSection.swift) | Mostra versione, aggiornamenti, guida online, diagnostica, sostegno volontario e i crediti di `design/credits.json` in schede comuni. I due titoli dei crediti usano lo scrim nelle palette chiare. |
| [Sources/NXLibrary/Views/Settings/SettingsAboutSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsAboutSection.swift) | Mostra versione, aggiornamenti, guida online, diagnostica, collegamenti distinti al sostegno di Bium23 e al finanziamento di Oort NX, e crediti di `design/credits.json`. |
| [Sources/NXLibrary/Views/Settings/LocalePicker.swift](../../Sources/NXLibrary/Views/Settings/LocalePicker.swift) | Scelta diretta della lingua e ricerca dei formati regionali, con focus tastiera/controller e codici stabili. |

## UI · Setup, avvio, ricerca e console

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Setup/SetupCheckView.swift](../../Sources/NXLibrary/Views/Setup/SetupCheckView.swift) | Schede dei requisiti, errore chiavi, progressi e conferme distinte per Metal e motore; continua senza installare. |
| [Sources/NXLibrary/Views/Setup/OnboardingView.swift](../../Sources/NXLibrary/Views/Setup/OnboardingView.swift) | Pagine e input del tour locale, inventario, importazione selettiva e rinvii ai servizi e alla modifica profilo. |
| [Sources/NXLibrary/Views/Setup/OnboardingScreen.swift](../../Sources/NXLibrary/Views/Setup/OnboardingScreen.swift) | Composizione Selene del tour, novità della 0.4.0 e conferma della copia locale. |
| [Sources/NXLibrary/Views/Setup/SetupCheckView+Input.swift](../../Sources/NXLibrary/Views/Setup/SetupCheckView+Input.swift) | Gestisce focus iniziale, navigazione della griglia, attivazione delle schede Setup e B verso `found` durante il primo avvio. |
| [Sources/NXLibrary/Views/Setup/ArcaneWelcomeView.swift](../../Sources/NXLibrary/Views/Setup/ArcaneWelcomeView.swift) | Disegna il benvenuto in Arcane: nome nuovo, novità, offerta Steam dalla cartella scelta, Add / Not now e Open library. |
| [Sources/NXLibrary/Views/Setup/ArcaneWelcomeView+Input.swift](../../Sources/NXLibrary/Views/Setup/ArcaneWelcomeView+Input.swift) | Gestisce focus, mouse, tastiera e controller del benvenuto. |
| [Sources/NXLibrary/Views/Setup/FoundGamesSetupView.swift](../../Sources/NXLibrary/Views/Setup/FoundGamesSetupView.swift) | Prima pagina del Setup: Steam con scelta salvata o attivazione esistente, Retry, app portate e card Porting; condivide il solo disegno con la fixture. |
| [Sources/NXLibrary/Views/Setup/FoundGamesSetupView+Input.swift](../../Sources/NXLibrary/Views/Setup/FoundGamesSetupView+Input.swift) | Focus, mouse, tastiera e controller di found; Retry della lettura Steam e uscita che annulla la richiesta prima di aprire la libreria. |
| [Sources/NXLibrary/Views/Setup/YourGamesSetupView.swift](../../Sources/NXLibrary/Views/Setup/YourGamesSetupView.swift) | Disegna scelta cartella, primo gioco, apertura libreria e Skip; contiene l'indicatore localizzato dei passi e `SetupCardRow`, la riga condivisa con `found`. |
| [Sources/NXLibrary/Views/Launch/LaunchScreenView.swift](../../Sources/NXLibrary/Views/Launch/LaunchScreenView.swift) | Mostra artwork e logo per nxnative e Steam. Il pulsante per chiudere la schermata inattiva resta visibile con i suggerimenti spenti. |
| [Sources/NXLibrary/Views/Launch/LaunchMotion.swift](../../Sources/NXLibrary/Views/Launch/LaunchMotion.swift) | Movimento della schermata di lancio in Core Animation: artwork che si avvicina e logo del gioco che sale una volta. Con Riduci movimento resta la dissolvenza del logo. |
| [Sources/NXLibrary/Views/Launch/LaunchCoverWindow.swift](../../Sources/NXLibrary/Views/Launch/LaunchCoverWindow.swift) | Ordina la finestra d’attesa sopra ogni app e Space e avvisa il coordinatore dopo aver inviato il pannello al server delle finestre. |
| [Sources/NXLibrary/Views/Search/FindGameView.swift](../../Sources/NXLibrary/Views/Search/FindGameView.swift) | Presenta ricerca nella libreria e risultati navigabili e inoltra il gioco scelto alla home. |
| [CommandPaletteView.swift](../../Sources/NXLibrary/Views/Search/CommandPaletteView.swift) | Cerca ovunque: campo, gruppi, righe con scorciatoia, annunci VoiceOver e ritorno del focus. |
| [CommandPaletteProbe.swift](../../Sources/NXLibrary/Views/Search/CommandPaletteProbe.swift) | Tasti, pulsanti, aggiornamenti del focus e catture Debug con voci sintetiche. |
| [CommandPaletteView.swift](../../Sources/NXLibrary/Views/Search/CommandPaletteView.swift) | Cerca ovunque: campo, gruppi, righe con scorciatoia, annunci VoiceOver su nome e azione della riga attiva, ritorno del focus. |
| [CommandPaletteProbe.swift](../../Sources/NXLibrary/Views/Search/CommandPaletteProbe.swift) | Controllo Debug di tasti e pulsanti e catture di ogni stato, senza finestra e con voci sintetiche. |
| [Sources/NXLibrary/Views/Console/ConsoleView.swift](../../Sources/NXLibrary/Views/Console/ConsoleView.swift) | Mostra log e stato corrente e offre copia di log e diagnostica. |
| [Sources/NXLibrary/Views/ControlsView.swift](../../Sources/NXLibrary/Views/ControlsView.swift) | Guida Selene separata fra Library e In game; stato controller, rilevamento e scorrimento delle righe con tastiera/controller. |

## UI · componenti condivisi

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Components/WikipediaAbout.swift](../../Sources/NXLibrary/Views/Components/WikipediaAbout.swift) | Richiesta dell'introduzione di Wikipedia per About this game (Spotlight e Details), chiesta solo quando la risposta dello store nella lingua dell'app è definitiva, valida solo per lo stesso gioco e lingua, e credito con link alla voce. |
| [Sources/NXLibrary/Views/Components/GameIconProvider.swift](../../Sources/NXLibrary/Views/Components/GameIconProvider.swift) | Fornisce e conserva l’icona estratta dai bundle dei giochi; ricorda anche quando manca. |
| [Sources/NXLibrary/Views/Components/PortingArtLook.swift](../../Sources/NXLibrary/Views/Components/PortingArtLook.swift) | Desatura la tile; mantiene la linea, la barra di avanzamento del porting e il riempimento lineare degli invii. |
| [Sources/NXLibrary/Views/Components/DownloadCloudOverlay.swift](../../Sources/NXLibrary/Views/Components/DownloadCloudOverlay.swift) | Proiezione del trasferimento, campioni Core Animation su tessere visibili, maschera di colore e ritaglio del titolo. |
| [Sources/NXLibrary/Views/Components/ScreenshotViewer.swift](../../Sources/NXLibrary/Views/Components/ScreenshotViewer.swift) | Mostra screenshot a schermo pieno e navigazione fra le immagini. |
| [Sources/NXLibrary/Views/Components/SeleneBottomScrim.swift](../../Sources/NXLibrary/Views/Components/SeleneBottomScrim.swift) | Definisce sfumatura inferiore, posizione condivisa dei comandi (32 unità dal fondo) e fascia libera dai contenuti. |
| [Sources/NXLibrary/Views/OortUI/OortPage.swift](../../Sources/NXLibrary/Views/OortUI/OortPage.swift) | Pagina con sfondo opaco o Selene storico, scroll e focus, intestazione di sezione e stato vuoto. |
| [OortFilePicker.swift](../../Sources/NXLibrary/Views/OortUI/OortFilePicker.swift) | Selettore in-app, navigazione e passaggio facoltativo al selettore di macOS. |
| [OortFilePickerProbe.swift](../../Sources/NXLibrary/Views/OortUI/OortFilePickerProbe.swift) | Catture Debug larghe e strette in francese, con cartelle sintetiche. |
| [Sources/NXLibrary/Views/OortUI/OortActionBar.swift](../../Sources/NXLibrary/Views/OortUI/OortActionBar.swift) | Piede comune di pannelli e domande: ritorno a sinistra, principale ultima a destra, distruttivo staccato; due righe se manca spazio. |
| [Sources/NXLibrary/Views/OortUI/OortControls.swift](../../Sources/NXLibrary/Views/OortUI/OortControls.swift) | Preset per righe, azioni e stati, e riga con cursore. |
| [Sources/NXLibrary/Views/OortUI/OortItemActions.swift](../../Sources/NXLibrary/Views/OortUI/OortItemActions.swift) | Azioni che l'indizio annuncia, anche sullo schermo e nel clic destro, dagli stessi HintItem. |
| [Sources/NXLibrary/Views/OortUI/OortLink.swift](../../Sources/NXLibrary/Views/OortUI/OortLink.swift) | Collegamento tra i campi di un dialogo: clic, oppure Tab e Invio. |
| [Sources/NXLibrary/Views/OortUI/OortGameTile.swift](../../Sources/NXLibrary/Views/OortUI/OortGameTile.swift) | Tessera con preset Spotlight e Collection, input e accessibilità; l'arte resta al chiamante. |
| [Sources/NXLibrary/Views/OortUI/OortSecondaryClick.swift](../../Sources/NXLibrary/Views/OortUI/OortSecondaryClick.swift) | Clic destro (o Ctrl-clic) su un riquadro: le stesse opzioni di +; ogni altro evento passa al riquadro. |
| [Sources/NXLibrary/Views/OortUI/OortWebPage.swift](../../Sources/NXLibrary/Views/OortUI/OortWebPage.swift) | Apre una pagina nel browser; dal controller chiede prima, perché nulla riporta a Oort. |
| [Sources/NXLibrary/Views/OortUI/OortKeyboard.swift](../../Sources/NXLibrary/Views/OortUI/OortKeyboard.swift) | Tastiera a schermo unica: segue campo e periferica senza cambiare il primo responder. |
| [Sources/NXLibrary/Views/OortUI/OortKeyboardProbe.swift](../../Sources/NXLibrary/Views/OortUI/OortKeyboardProbe.swift) | Prova Debug fuori schermo: scrittura e cambio di periferica in un campo corto e in uno lungo. |
| [Sources/NXLibrary/Views/OortUI/PlayerSlot.swift](../../Sources/NXLibrary/Views/OortUI/PlayerSlot.swift) | Posto giocatore ad altezza stabile con ritratto, stato e valore accessibile. |
| [DESIGN.md](../../DESIGN.md) | Sistema di design: token, pezzi, regole. |
| [PRODUCT.md](../../PRODUCT.md) | Per chi è Oort, cosa promette e cosa evita. |
| [Sources/NXLibrary/Services/ControllerLive.swift](../../Sources/NXLibrary/Services/ControllerLive.swift) | Stato vivo del controller attivo (tasti tenuti, stick), separato dal servizio per non ridisegnare le altre viste. |
| [Sources/NXLibrary/Views/OortUI/OortControllerView.swift](../../Sources/NXLibrary/Views/OortUI/OortControllerView.swift) | Controller disegnato a punti, con gli ingressi reali accesi, e la sua mappa dei comandi. |
| [Sources/NXLibrary/Views/OortUI/OortMeter.swift](../../Sources/NXLibrary/Views/OortUI/OortMeter.swift) | Barra di avanzamento, misurata o indeterminata. |
| [Sources/NXLibrary/Views/OortUI/OortSearchField.swift](../../Sources/NXLibrary/Views/OortUI/OortSearchField.swift) | Campo di ricerca condiviso. |
| [Sources/NXLibrary/Views/OortUI/OortSetupCard.swift](../../Sources/NXLibrary/Views/OortUI/OortSetupCard.swift) | Scheda di scelta della prima configurazione. |
| [Sources/NXLibrary/Views/OortUI/OortTabs.swift](../../Sources/NXLibrary/Views/OortUI/OortTabs.swift) | Schede condivise: scelta, focus, conteggio. |
| [Sources/NXLibrary/Views/OortUI/OortTag.swift](../../Sources/NXLibrary/Views/OortUI/OortTag.swift) | Etichetta breve: genere, versione, stato. |
| [Sources/NXLibrary/Views/OortUI/OortCreditCard.swift](../../Sources/NXLibrary/Views/OortUI/OortCreditCard.swift) | Scheda di un credito e gruppo di schede: griglia piena, di altezza uguale, o lista. |
| [Tests/NXLibraryCoreTests/PaletteContrastTests.swift](../../Tests/NXLibraryCoreTests/PaletteContrastTests.swift) | Contrasto di testo, focus e simboli in ogni palette. |
| [Sources/NXLibrary/Views/OortUI/OortUIGallery.swift](../../Sources/NXLibrary/Views/OortUI/OortUIGallery.swift) | Esempi sintetici Debug delle primitive OortUI e catture senza finestre su tre palette. |
| [Sources/NXLibrary/Views/OortUI/SeleneConfirmDialog.swift](../../Sources/NXLibrary/Views/OortUI/SeleneConfirmDialog.swift) | Card e aiuto condivisi, annullamento a sinistra e conferma a destra con `OortActionBar`, scelte multiple con testo a larghezza definita e note, SeleneSuccessNotice. |
| [Sources/NXLibrary/Views/OortUI/SeleneConfirmDialog.swift](../../Sources/NXLibrary/Views/OortUI/SeleneConfirmDialog.swift) | Card e aiuto condivisi, conferma a sinistra e annullamento a destra, scelte multiple con testo a larghezza definita e note, SeleneSuccessNotice. |
| [Sources/NXLibrary/Views/OortUI/OortActionBar.swift](../../Sources/NXLibrary/Views/OortUI/OortActionBar.swift) | Barra e domanda con Annulla a sinistra, azione principale a destra e azione distruttiva su una riga separata. |
| [Sources/NXLibraryCore/Selene/ActionBarOrder.swift](../../Sources/NXLibraryCore/Selene/ActionBarOrder.swift), [test](../../Tests/NXLibraryCoreTests/ActionBarOrderTests.swift) | Ordine e focus iniziale delle azioni secondo il ruolo, in comune fra disegno e input. |
| [Sources/NXLibrary/Views/Components/AppUpdateDialog.swift](../../Sources/NXLibrary/Views/Components/AppUpdateDialog.swift) | Presenta controllo aggiornamenti, note di release, errori e progresso nel dialogo dell’app. |
| [Sources/NXLibrary/Views/OortUI/SeleneHintsBar.swift](../../Sources/NXLibrary/Views/OortUI/SeleneHintsBar.swift) | Disegna i suggerimenti contestuali: ogni voce ha un glifo o un'etichetta di tasto; ⌘F appare senza manetta. |
| [Sources/NXLibrary/Views/Components/SeleneHomeChrome.swift](../../Sources/NXLibrary/Views/Components/SeleneHomeChrome.swift) | Rende elementi condivisi della cornice e dei controlli della home Selene; trattiene gli hint durante l’entrata. |
| [Sources/NXLibrary/Views/OortUI/SeleneOptionRow.swift](../../Sources/NXLibrary/Views/OortUI/SeleneOptionRow.swift) | Disegna righe di opzioni con icona, titolo, descrizione con carattere configurabile, focus e contenuto laterale. |
| [Sources/NXLibrary/Views/Components/SeleneExpandableText.swift](../../Sources/NXLibrary/Views/Components/SeleneExpandableText.swift) | Rivela la descrizione completa animando l'altezza fra due layout di testo stabili; usato solo dalle righe dei metadati. |
| [Sources/NXLibrary/Views/OortUI/SelenePillButton.swift](../../Sources/NXLibrary/Views/OortUI/SelenePillButton.swift) | Disegna il pulsante condiviso, il contorno come anello pieno, la larghezza piena in una colonna e il riempimento mascherato di Download. |
| [Sources/NXLibrary/Views/OortUI/SeleneStepper.swift](../../Sources/NXLibrary/Views/OortUI/SeleneStepper.swift) | Indicatore di passo e superficie dei campi per l'assistente Selene. |
| [Sources/NXLibrary/Views/OortUI/SelenePromptBadge.swift](../../Sources/NXLibrary/Views/OortUI/SelenePromptBadge.swift) | Rende simbolo o etichetta del controller e della tastiera, compresa la croce direzionale a contrasto. |
| [Sources/NXLibrary/Views/Components/GlideGroup.swift](../../Sources/NXLibrary/Views/Components/GlideGroup.swift) | Usa `geometryGroup` per spostare un blocco come un pezzo unico. `RailCamera` limita la posizione interpolata dei rail Spotlight e Collection alla lunghezza corrente. |
| [Sources/NXLibrary/Views/Components/SeleneReveal.swift](../../Sources/NXLibrary/Views/Components/SeleneReveal.swift) | Applica l’animazione di comparsa Selene rispettando la preferenza Riduci movimento. |
| [Sources/NXLibrary/Views/OortUI/SeleneSettingsRow.swift](../../Sources/NXLibrary/Views/OortUI/SeleneSettingsRow.swift) | Righe delle impostazioni e ciclo di valore condiviso da Settings e Game Options. |
| [Sources/NXLibrary/Views/OortUI/SeleneStatsRow.swift](../../Sources/NXLibrary/Views/OortUI/SeleneStatsRow.swift) | Disegna le statistiche compatte del gioco nella libreria. |
| [Sources/NXLibrary/Views/Components/SeleneSwitch.swift](../../Sources/NXLibrary/Views/Components/SeleneSwitch.swift) | Disegna lo switch coerente con il tema. |
| [Sources/NXLibrary/Views/OortUI/SeleneTileRing.swift](../../Sources/NXLibrary/Views/OortUI/SeleneTileRing.swift) | Ring e riflesso della tile selezionata; con Reduce motion il ring fermo disegnato da SwiftUI. |
| [Sources/NXLibrary/Views/Components/TileMotionLayers.swift](../../Sources/NXLibrary/Views/Components/TileMotionLayers.swift) | Ring e riflesso come layer Core Animation in loop: nessun ridisegno dell'app tra un frame e l'altro. |
| [Sources/NXLibrary/Views/OortUI/SeleneValueChip.swift](../../Sources/NXLibrary/Views/OortUI/SeleneValueChip.swift) | Rende valori e badge compatti nel linguaggio visivo Selene. |
| [Sources/NXLibrary/Views/Components/NextendoOnlineBadge.swift](../../Sources/NXLibrary/Views/Components/NextendoOnlineBadge.swift) | Punto e numero sulla copertina; tiene i valori d’ambiente con i conteggi e gli interruttori. |
| [Sources/NXLibrary/Views/OortUI/SeleneStatusDot.swift](../../Sources/NXLibrary/Views/OortUI/SeleneStatusDot.swift) | Punto decorativo di 7 unità per testo o badge; l'alone Core Animation facoltativo può comparire senza punto e rispetta Riduci movimento e finestra attiva. |
| [Sources/NXLibrary/Views/Components/SpotlightTileArtwork.swift](../../Sources/NXLibrary/Views/Components/SpotlightTileArtwork.swift) | Disegna subito l’icona nxnative già decodificata; cache condivisa `TileArtMemo` con fonte e revisione delle scelte, caricamento annullabile e segnale `TileArtPendingKey`. |
| [Sources/NXLibrary/Views/Components/SwitchBoxArtCover.swift](../../Sources/NXLibrary/Views/Components/SwitchBoxArtCover.swift) | Disegna la copertina Switch dalle immagini in cache o compone il ripiego e fornisce i limiti del titolo. |
| [Sources/NXLibrary/Views/Components/SteamGridDBKeyDialog.swift](../../Sources/NXLibrary/Views/Components/SteamGridDBKeyDialog.swift) | Popup per incollare e verificare la chiave SteamGridDB da Settings → Look e da Change artwork. |
| [Sources/NXLibrary/Views/OortUI/PlatformLabel.swift](../../Sources/NXLibrary/Views/OortUI/PlatformLabel.swift) | Etichetta condivisa: simbolo monocromatico, nome e indicatore Switch 2. |
| [Sources/NXLibrary/Views/Components/GameLogoArea.swift](../../Sources/NXLibrary/Views/Components/GameLogoArea.swift) | Area del logo del gioco con la geometria condivisa da Spotlight e Collection; caricamento e impostazioni restano fuori. |
| [Sources/NXLibrary/Views/Components/GamePrimaryActions.swift](../../Sources/NXLibrary/Views/Components/GamePrimaryActions.swift) | Azioni principali con avanzamento di Download, Options, pillola Cloud e preferito con bersagli di input stabili. |
| [Sources/NXLibrary/Views/Components/SessionCard.swift](../../Sources/NXLibrary/Views/Components/SessionCard.swift) | Card di fine sessione e toast degli obiettivi con titolo plurale: aspettano che Arcane sia davanti, compaiono 1,8 s dopo per 8 s e si azzerano al cambio di profilo. |
| [Sources/NXLibrary/Views/Components/UndoNotice.swift](../../Sources/NXLibrary/Views/Components/UndoNotice.swift) | Avviso con Undo e avviso di un suggerimento, nell’angolo della card di fine sessione; prendono il focus solo su richiesta. |

## UI · temi, rendering e sfondi

| File | Responsabilità |
|---|---|
| [Sources/NXLibrary/Views/Theme/ThemeStore.swift](../../Sources/NXLibrary/Views/Theme/ThemeStore.swift) | Mantiene palette attiva, wallpaper inclusi e importati e operazioni sulle scelte dell’utente. |
| [Sources/NXLibrary/Views/Theme/SeleneTheme.swift](../../Sources/NXLibrary/Views/Theme/SeleneTheme.swift) | Espone colori, stili, curve di animazione, focus e ambiente Selene; solo il blu classico usa inchiostro tenue per i glifi delle righe. |
| [Sources/NXLibrary/Views/Theme/SeleneFonts.swift](../../Sources/NXLibrary/Views/Theme/SeleneFonts.swift) | Registra il font incluso e definisce MaterialIconView. |
| [Sources/NXLibrary/Views/Theme/SeleneCanvasEnvironment.swift](../../Sources/NXLibrary/Views/Theme/SeleneCanvasEnvironment.swift) | Pubblica il canvas, scala unità e font e applica le sfumature sui bordi orizzontali richiesti. |
| [Sources/NXLibrary/Views/Theme/SeleneBackdrop.swift](../../Sources/NXLibrary/Views/Theme/SeleneBackdrop.swift) | Nella shell dichiara la richiesta di sfondo condiviso, fuori dalla shell disegna; consuma lo snapshot completo della palette e compone gradiente, wallpaper e Moonlight a particelle morbide; conserva le immagini decodificate e il fallback statico. |
| [Sources/NXLibrary/Views/Theme/MoonlightRenderer.swift](../../Sources/NXLibrary/Views/Theme/MoonlightRenderer.swift) | Gestisce Metal, il `CAMetalDisplayLink` e il rendering live/statico. Disegna solo il link, anche il frame fermo, e il primo drawable presentato sblocca `LaunchReveal`; nella Dev registra creazione e prima presentazione. |
| [Sources/NXLibrary/Views/Theme/MoonlightShaders.swift](../../Sources/NXLibrary/Views/Theme/MoonlightShaders.swift) | Contiene gli shader Metal del Moonlight, superfici analitiche Arcane/Flow, filamenti sottili antialias piegati da onde viaggianti e particelle morbide, compilati a runtime. |
| [Sources/NXLibrary/Views/Theme/LiveBackdrop.swift](../../Sources/NXLibrary/Views/Theme/LiveBackdrop.swift) | Integra video AVFoundation in loop e adatta riproduzione e frame alla visibilità della finestra. |
| [Sources/NXLibrary/Views/Theme/OnlineBrowsePanel.swift](../../Sources/NXLibrary/Views/Theme/OnlineBrowsePanel.swift) | Mantiene stato di ricerca e download e presenta griglia e miniature degli sfondi online. |
| [Sources/NXLibrary/Views/Theme/ThemePickerView.swift](../../Sources/NXLibrary/Views/Theme/ThemePickerView.swift) | Presenta i colori con anteprima viva nel primo passo; sfondi, provider e destinazione nel passo successivo. Il file tiene stato, `body`, transizioni, intestazione, griglia, `TileFocus` e `WallpaperThumb`; il resto sta nelle estensioni qui sotto. |
| [Sources/NXLibrary/Views/Theme/ThemePickerView+ThemeStep.swift](../../Sources/NXLibrary/Views/Theme/ThemePickerView+ThemeStep.swift) | Passo dei temi: campioni delle palette con scrim di lettura per quelle chiare, colori e sfondo di anteprima. |
| [Sources/NXLibrary/Views/Theme/ThemePickerView+BackgroundStep.swift](../../Sources/NXLibrary/Views/Theme/ThemePickerView+BackgroundStep.swift) | Passo degli sfondi: schede, tile degli sfondi e delle fonti, anteprime, crediti ed etichette. |
| [Sources/NXLibrary/Views/Theme/ThemePickerView+Input.swift](../../Sources/NXLibrary/Views/Theme/ThemePickerView+Input.swift) | Input: apertura, schede, controller, focus, tocchi, conferma e indietro. |
| [Sources/NXLibrary/Views/Theme/ThemePickerView+Online.swift](../../Sources/NXLibrary/Views/Theme/ThemePickerView+Online.swift) | Sfondi online: apertura di una fonte, suo input, categorie, ricerca e uso dell’immagine scelta. |
| [Sources/NXLibrary/Views/Theme/ThemePickerView+Placement.swift](../../Sources/NXLibrary/Views/Theme/ThemePickerView+Placement.swift) | Collocazione: chiede come lo sfondo scelto riempie lo schermo e applica la risposta. |
| [Sources/NXLibrary/Views/Theme/ThemePickerView+OwnWallpapers.swift](../../Sources/NXLibrary/Views/Theme/ThemePickerView+OwnWallpapers.swift) | Sfondi del giocatore: aggiunta da file e rimozione dopo conferma. |
| [Sources/NXLibrary/Views/Theme/ThemePreview.swift](../../Sources/NXLibrary/Views/Theme/ThemePreview.swift) | Disegna un’anteprima della home con palette, sfondo e particelle morbide; il movimento segue le preferenze. |
| [Sources/NXLibrary/Views/Theme/AppLocaleEnvironment.swift](../../Sources/NXLibrary/Views/Theme/AppLocaleEnvironment.swift) | Contesto della lingua reattivo per le viste; conserva identità, selezione e focus. |

## UI · fonti, Steam e libreria mista

| File | Responsabilità |
|---|---|
| [AppViewModel+Catalog.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Catalog.swift) | Salvataggio e retry del risultato di build senza libreria di ripiego; aggiorna il confronto cloud per l’app installata. |
| [CatalogPersonalizationsEnvironment.swift](../../Sources/NXLibrary/Views/Theme/CatalogPersonalizationsEnvironment.swift) | Dipendenza SwiftUI esplicita per le chiavi personali stabili. |
| [AppViewModel+Sources.swift](../../Sources/NXLibrary/ViewModels/AppViewModel+Sources.swift) | Proiezione visibile, selezione comune e modifiche personali tipizzate. |
| [SettingsSourcesSection.swift](../../Sources/NXLibrary/Views/Settings/SettingsSourcesSection.swift) | Aggiunta manuale di un’app Mac; attivazione, refresh, cartella e controllo della fonte Steam. |
| [CatalogNativeArtwork.swift](../../Sources/NXLibrary/Views/Catalog/CatalogNativeArtwork.swift) | Icona nativa in sola lettura; testata dei collegamenti Mac e immagine scelta localmente. |
| [MacShortcutAdapter.swift](../../Sources/NXLibrary/Services/MacShortcutAdapter.swift) | Selettore, esito del trascinamento, ricollegamento e opzioni della tessera; Play consegna a macOS senza osservare sessioni. |
| [CatalogSteamInfo.swift](../../Sources/NXLibrary/Views/Catalog/CatalogSteamInfo.swift) | Intestazione condivisa nelle due librerie: Play/Riprendi/Annulla/Riprova, Opzioni e preferito, con la nota di stato. |
| [SteamPlayCoordinator.swift](../../Sources/NXLibrary/Services/SteamPlayCoordinator.swift) | Play tramite il client verificato; distingue consegna e apertura, e registra sessioni dal processo dell’app installata. La fonte spenta lascia finire le sessioni, senza aprirne altre. |
| [SteamPlaytimeCoordinator.swift](../../Sources/NXLibrary/Services/SteamPlaytimeCoordinator.swift) | Aggiorna le ore Steam fuori dal thread principale; conserva il totale se una sessione Steam appartiene a un profilo secondario. |
| [SteamOptionsView.swift](../../Sources/NXLibrary/Views/GameOptions/SteamOptionsView.swift) | Opzioni di un gioco Steam con l’aspetto e l’input di Game options: Play, Edit details, Move, preferito, nascosto, Finder. |
| [PersonalizationSubject.swift](../../Sources/NXLibrary/Views/GameOptions/PersonalizationSubject.swift) | Il gioco che Change artwork e Change metadata personalizzano: scelte nxnative o archivio personale Steam, senza icona Mac per Steam. |
| [SteamGamePage.swift](../../Sources/NXLibrary/Views/Catalog/SteamGamePage.swift) | Dati store Steam dei giochi a schermo, una copia condivisa da Spotlight e Collection, per AppID e lingua; una risposta per un gioco o una lingua non più chiesti si scarta; offline mostra il testo di un'altra lingua con l'avviso. |
| [SteamArtwork.swift](../../Sources/NXLibrary/Views/Catalog/SteamArtwork.swift) | Immagini Steam con cache disponibile prima del task, identità di richiesta/build e ripiego in colore Selene; rivalidazione dei file, scelte personali, annullamento e `TileArtPendingKey`. |
| [SteamPersonalizations.swift](../../Sources/NXLibrary/Views/Catalog/SteamPersonalizations.swift) | Archivio delle scelte personali Steam (metadati e artwork), modificate da Change artwork e Change metadata. |

## UI · achievement

| File | Responsabilità |
|---|---|
| [SteamAchievementsStore.swift](../../Sources/NXLibrary/Services/SteamAchievementsStore.swift) | Legge gli achievement fuori dal thread principale (selezione, apertura della schermata e, per il gioco selezionato, fine di una sessione Steam: subito e dopo un minuto), uno per AppID alla volta; tiene gli ultimi 16 giochi e aggiunge la rarità quando arriva. |
| [ArcaneOrbVideo.swift](../../Sources/NXLibrary/Views/Spotlight/ArcaneOrbVideo.swift) | L'Arcane della card come video: grigio e fermo a riposo, a colori e in movimento con hover o focus, si ferma sul suo fotogramma e riparte da lì; colore, luce e scala animati da Core Animation. Usato anche, grande e sempre attivo, in testa alla schermata Achievements quando l'Arcane è conquistato. |
| [DetailsAchievementsCard.swift](../../Sources/NXLibrary/Views/Detail/DetailsAchievementsCard.swift) | Card Achievements sopra Details; prende il focus e apre la schermata. Definisce la barra misurata con colore di riempimento configurabile. |
| [AchievementIcon.swift](../../Sources/NXLibrary/Views/Detail/AchievementIcon.swift) | Icona di un achievement dalla cache di `SteamMetadataService`, decodificata fuori dal thread principale e tenuta in memoria (niente lampo quando una riga torna in vista), con un riquadro neutro finché manca; un segreto non sbloccato è sfocato sotto un lucchetto. |
| [AchievementsScreen.swift](../../Sources/NXLibrary/Views/Spotlight/AchievementsScreen.swift) | Obiettivi Selene: logo e sbloccati a sinistra, cristalli o medaglione a destra, lista con offset proprio. LB/RB affiancano i filtri; nel dettaglio aperto i suggerimenti passano nella barra in basso. |
| [AchievementDetail.swift](../../Sources/NXLibrary/Views/Spotlight/AchievementDetail.swift) | Dettaglio di un obiettivo come medaglione (A sulla riga o clic sulla riga in focus): icona grande con il cristallo della tier come piccolo distintivo sull’angolo, nome e descrizione interi centrati, percentuale dei giocatori, data di sblocco; le frecce scorrono la lista, A/B o un clic fuori chiudono. |
| [TierCrystal.swift](../../Sources/NXLibrary/Views/Spotlight/TierCrystal.swift) | Il cristallo di una tier dalle risorse del Core, decodificato una volta; non ancora ottenuto, tenue con una traccia del suo colore, così oro, argento e bronzo restano distinguibili. |
| [AchievementsScreenModel.swift](../../Sources/NXLibrary/ViewModels/AchievementsScreenModel.swift) | Selezione, filtro e scroll di Achievements; LB/RB cambiano filtro o scorrono i dettagli aperti. Dopo la rotella la prima freccia riporta il focus in vista. |
| [ListScroll.swift](../../Sources/NXLibrary/ViewModels/ListScroll.swift) | Offset di una lista (`TextScroll`) con la planata del pannello delle mod: rotella, trackpad e frecce muovono lo stesso valore. |

## Contributi, skill e controlli di architettura

| File | Responsabilità |
|---|---|
| [scripts/ci_changed_areas.py](../../scripts/ci_changed_areas.py) | Decide quali aree della CI girano secondo i percorsi modificati; una cartella assente lascia l’area spenta. |
| [scripts/check_module_boundaries.py](../../scripts/check_module_boundaries.py) | Verifica l’ordine dei moduli, Foundation soltanto in OortCore e la lista di base degli import d’interfaccia nel core. |
| [Tests/CIChecks/test_changed_areas.py](../../Tests/CIChecks/test_changed_areas.py) | Verifica quali aree si accendono per documentazione, core, workflow e cartelle mancanti. |
| [Tests/ModuleChecks/test_module_boundaries.py](../../Tests/ModuleChecks/test_module_boundaries.py) | Verifica i confini dei moduli con fixture sintetiche e sul repository. |
| [Tests/SkillChecks/test_skills.py](../../Tests/SkillChecks/test_skills.py) | Verifica formato, tre casi per skill, link e assenza di percorsi personali nelle skill pubbliche. |
| [docs/working-on-it/architecture-map.md](architecture-map.md) | Carta dei cinque sistemi, livelli d’import e dove mettere il codice. |
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
| [FileBrowserTests.swift](../../Tests/NXLibraryCoreTests/FileBrowserTests.swift) | Filtri, ordine, collegamenti, permessi, volume non disponibile e cartella con 2.000 file sintetici. |
| [Tests/NXLibraryCoreTests/SettingsRowActionTests.swift](../../Tests/NXLibraryCoreTests/SettingsRowActionTests.swift) | Regressioni per giochi omonimi e azioni secondarie della medesima riga. |
| [Tests/ArcanePortingTests/ScreenshotFallbackTests.swift](../../Tests/ArcanePortingTests/ScreenshotFallbackTests.swift) | Screenshot LaunchBox cercati una volta e conservati, precedenza di quelli propri e dimensione piena della scelta. |
| [Tests/NXLibraryCoreTests/SteamGridDBArtTests.swift](../../Tests/NXLibraryCoreTests/SteamGridDBArtTests.swift) | Chiave privata, richieste con la chiave solo a SteamGridDB, crediti, anteprime e ricerca da Browse online. |
| [Tests/PublicationChecks/test_publication.py](../../Tests/PublicationChecks/test_publication.py) | Esegue il controllo in repository temporanee: file vietati, chiavi sintetiche redatte, runtime non conforme e testi o sorgenti mancanti o alterati. |
| [Tests/PublicationChecks/test_release_target.py](../../Tests/PublicationChecks/test_release_target.py) | Verifica senza rete i controlli, la destinazione unica di tag e release e il ripiego DMG mantenendo il nome dell'asset, attraverso repository locali e comandi sostitutivi. |
| [Tests/PublicationChecks/test_update_archive.py](../../Tests/PublicationChecks/test_update_archive.py) | Verifica il controllo ZIP reale con bundle sintetici, symlink, percorsi non sicuri, collisioni Unicode, header incoerenti e dimensioni eccessive. |

| File | Responsabilità |
|---|---|
| [Tests/NXLibraryCoreTests/ActivitySummaryTests.swift](../../Tests/NXLibraryCoreTests/ActivitySummaryTests.swift) | Totali settimanali, distribuzione giornaliera, sessioni aperte e passaggi di mezzanotte. |
| [Tests/NXLibraryCoreTests/ProfilePageCardsTests.swift](../../Tests/NXLibraryCoreTests/ProfilePageCardsTests.swift) | Ordine persistente, visibilità senza conto, geometria adattiva e isolamento delle sessioni. |
| [Tests/NXLibraryCoreTests/AppBundleRenameTests.swift](../../Tests/NXLibraryCoreTests/AppBundleRenameTests.swift) | Rinomina alla chiusura: solo `NX Library.app`, verso `Oort NX.app` se libero e scrivibile; `Arcane.app` resta al suo posto. |
| [Tests/NXLibraryCoreTests/AppRouterTests.swift](../../Tests/NXLibraryCoreTests/AppRouterTests.swift) | Route, overlay, precedenza degli input, tasti e ritorno del control center; i dialoghi di Settings impediscono ⌘K. |
| [Tests/NXLibraryCoreTests/ActionBarOrderTests.swift](../../Tests/NXLibraryCoreTests/ActionBarOrderTests.swift) | Ordine della barra, elenco verticale, domande e focus iniziale. |
| [Tests/NXLibraryCoreTests/AppRouterTests.swift](../../Tests/NXLibraryCoreTests/AppRouterTests.swift) | Route, overlay, precedenza fullscreen, tasti di ogni sottomenu e navigazione LB/RB del control center, focus senza Inbox, navigazione del centro attività e ritorno distinto dal clic fuori. |
| [Tests/NXLibraryCoreTests/UndoOffersTests.swift](../../Tests/NXLibraryCoreTests/UndoOffersTests.swift) | Annullare una volta, l’ultimo gesto soltanto, anche dal centro attività. |
| [Tests/NXLibraryCoreTests/TipsTests.swift](../../Tests/NXLibraryCoreTests/TipsTests.swift) | Un suggerimento una volta, uno per sessione, nessuno da spenti. |
| [Tests/NXLibraryCoreTests/RecentSearchesTests.swift](../../Tests/NXLibraryCoreTests/RecentSearchesTests.swift) | Ricerche recenti per profilo; errori e schermate vuote dicono cosa fare nelle sette lingue. |
| [Tests/ArcanePortingTests/AppSettingsStoreTests.swift](../../Tests/ArcanePortingTests/AppSettingsStoreTests.swift) | Default e reset di Inbox, errori, recupero, nomi e ordine delle sezioni, chiavi correnti e del modulo, card Spotlight rimosse, ultima selezione in background e alla chiusura. |
| [Tests/NXLibraryCoreTests/AppSettingsDraftTests.swift](../../Tests/NXLibraryCoreTests/AppSettingsDraftTests.swift) | Anteprima, scarto, ordine nel riepilogo, merge senza perdita, conflitto, file illeggibile e interruzione prima della sostituzione. |
| [Tests/NXLibraryCoreTests/OnlinePlayersDisplayTests.swift](../../Tests/NXLibraryCoreTests/OnlinePlayersDisplayTests.swift) | Sedici combinazioni, migrazione delle quattro scelte precedenti, default, reset e catalogo. |
| [Tests/ArcanePortingTests/AppSizeCacheTests.swift](../../Tests/ArcanePortingTests/AppSizeCacheTests.swift) | Riuso delle dimensioni, invalidazione sui bundle modificati e scansione senza falso stato vuoto. |
| [Tests/NXLibraryCoreTests/AppUpdateTests.swift](../../Tests/NXLibraryCoreTests/AppUpdateTests.swift) | Versioni, pagina mista per le prerelease, asset, requisiti, digest, identità del bundle e guasti di copia, scambio e Cestino. |
| [Tests/NXLibraryCoreTests/AppUpdatePresentationTests.swift](../../Tests/NXLibraryCoreTests/AppUpdatePresentationTests.swift) | Verifica che i controlli manuali non permettano sostituzioni di copie di sviluppo, in sola lettura o con una versione uguale/più recente. |
| [Tests/NXLibraryCoreTests/ArcaneWelcomeTests.swift](../../Tests/NXLibraryCoreTests/ArcaneWelcomeTests.swift) | Una volta dopo l'aggiornamento, mai dopo un primo Setup né con un recupero in corso, decodifica di un file vecchio, offerta di Steam, focus e uscite. |
| [Tests/NXLibraryCoreTests/ShellOverlayInputTests.swift](../../Tests/NXLibraryCoreTests/ShellOverlayInputTests.swift) | Ogni monitor della tastiera che cede all'offerta di aggiornamento cede anche al benvenuto, così Invio non arriva alla schermata sotto. Sotto il centro di controllo e la schermata profilo, schermata, Aggiungi gioco e console nascondono i propri suggerimenti. |
| [Tests/NXLibraryCoreTests/ArcaneNameTests.swift](../../Tests/NXLibraryCoreTests/ArcaneNameTests.swift) | Nessun testo del catalogo, in nessuna lingua, mostra il vecchio nome; User-Agent con il nome Arcane e nessuna sorgente con il vecchio. |
| [Tests/NXLibraryCoreTests/ArtworkPickerFocusTests.swift](../../Tests/NXLibraryCoreTests/ArtworkPickerFocusTests.swift) | Spostamenti nella griglia dei candidati e passaggi fra slot di artwork. |
| [Tests/ArcanePortingTests/ArtworkPickerTests.swift](../../Tests/ArcanePortingTests/ArtworkPickerTests.swift) | Decodifica Title DB, candidati per slot e scelte manuali. |
| [Tests/NXLibraryCoreTests/AutomaticIconTests.swift](../../Tests/NXLibraryCoreTests/AutomaticIconTests.swift) | Priorità delle fonti, ambiguità, edizioni, cache offline, immagini invalide e opt-out del sito. |
| [Tests/NXLibraryCoreTests/ArtworkStoreTests.swift](../../Tests/NXLibraryCoreTests/ArtworkStoreTests.swift) | Cache, download, immagini trasparenti, ridimensionamento e fallback. |
| [Tests/ArcanePortingTests/BoxArtServiceTests.swift](../../Tests/ArcanePortingTests/BoxArtServiceTests.swift) | Matching GameTDB, regioni e durata delle ricerche senza risultato. |
| [Tests/ArcanePortingTests/BuildCommandBuilderTests.swift](../../Tests/ArcanePortingTests/BuildCommandBuilderTests.swift) | Contratto CLI, override Metal, flag e ambiente Nextendo e compatibilità dei record precedenti. |
| [Tests/ArcanePortingTests/BuildEventParserTests.swift](../../Tests/ArcanePortingTests/BuildEventParserTests.swift) | Eventi JSON, fasi, percentuali e righe ordinarie di log. |
| [Tests/ArcanePortingTests/BuildOutputInstallerTests.swift](../../Tests/ArcanePortingTests/BuildOutputInstallerTests.swift) | Pubblicazione atomica, interruzioni, tentativi ripetuti, copie fra volumi e conservazione dei bundle in caso di errore. |
| [Tests/ArcanePortingTests/BuildScratchTests.swift](../../Tests/ArcanePortingTests/BuildScratchTests.swift) | Posto dei file di build per Mac, disco esterno, exFAT e workspaces spostati; workspace gestiti e cartelle temporanee. |
| [Tests/ArcanePortingTests/BuildServiceTests.swift](../../Tests/ArcanePortingTests/BuildServiceTests.swift) | Processi, eventi, cancellazione, lease e conservazione della build dopo un errore d’installazione o profili illeggibili, con retry senza nuova esecuzione del motore. |
| [Tests/NXLibraryCoreTests/SystemCommandRunnerTests.swift](../../Tests/NXLibraryCoreTests/SystemCommandRunnerTests.swift) | Un comando atteso, sincrono o in streaming, non fa girare il run loop mentre aspetta. |
| [Tests/NXLibraryCoreTests/CommandRunnerTests.swift](../../Tests/NXLibraryCoreTests/CommandRunnerTests.swift) | Verifica stdout, stderr, attesa senza run loop, annullamento con pipe ereditate, scadenze e progresso reale. |
| [Tests/NXLibraryCoreTests/RcloneListingTests.swift](../../Tests/NXLibraryCoreTests/RcloneListingTests.swift) | Letture raggruppate e uniche, ambito prima e dopo, ambiguità, annullamento, rclone meno recenti, rifiuto di ogni scrittura. |
| [Tests/NXLibraryCoreTests/LibraryRefreshTests.swift](../../Tests/NXLibraryCoreTests/LibraryRefreshTests.swift) | Esiti, parti non aggiornate, risposte tardive e posizione della riga. |
| [Tests/NXLibraryCoreTests/RcloneStorageBackendTests.swift](../../Tests/NXLibraryCoreTests/RcloneStorageBackendTests.swift) | Binario, oggetti, impronte, avanzamento e annullamento; prefissi assenti o vuoti; Drive configurato e ID esatto per il riferimento in sola lettura. |
| [VolumeSpaceTests.swift](../../Tests/NXLibraryCoreTests/VolumeSpaceTests.swift) | Ripiego per lo zero di exFAT, cartella non ancora creata e disco reale facoltativo. |
| [Tests/NXLibraryCoreTests/RcloneDownloadTests.swift](../../Tests/NXLibraryCoreTests/RcloneDownloadTests.swift) | Trasporto locale e archivi sintetici: rifiuti, annullamento, firma, pubblicazione atomica e protezione delle copie altrui. |
| [Tests/NXLibraryCoreTests/RcloneConfigurationTests.swift](../../Tests/NXLibraryCoreTests/RcloneConfigurationTests.swift) | Preferenze, comandi OAuth, cifratura e recuperi tipizzati con runner finto; prova stdin su una configurazione rclone temporanea; senza configurazione o portachiavi reali. |
| [Tests/NXLibraryCoreTests/CloudSetupAssistantTests.swift](../../Tests/NXLibraryCoreTests/CloudSetupAssistantTests.swift) | Bozza, verifica, formato dell’ID client, focus iniziale, colonna dei passi e Tab. |
| [Tests/NXLibraryCoreTests/ActionBarOrderTests.swift](../../Tests/NXLibraryCoreTests/ActionBarOrderTests.swift) | Ordine dei tasti e tasto acceso. |
| [Tests/ArcanePortingTests/CloudGameArchiveTests.swift](../../Tests/ArcanePortingTests/CloudGameArchiveTests.swift) | App firmata sintetica e cache con rclone finto o locale: invio incrementale, manifest intermedio visibile dal riferimento, annullamento, riuso della cache locale, migrazione `.aar` e importazione con conflitti nei percorsi dichiarati. |
| [Tests/ArcanePortingTests/CloudReadingTests.swift](../../Tests/ArcanePortingTests/CloudReadingTests.swift) | Numero di richieste per 1 e 40 giochi, schede conservate, sostituite o danneggiate, interruzioni; una lettura non decide e non scrive. |
| [Tests/ArcanePortingTests/CloudArchiveListingTests.swift](../../Tests/ArcanePortingTests/CloudArchiveListingTests.swift) | Doppioni Drive con ID distinti, varianti di maiuscole e Unicode, rifiuto prima di Send o lettura e importazione senza falsi assenti. |
| [Tests/ArcanePortingTests/GameAppDestinationTests.swift](../../Tests/ArcanePortingTests/GameAppDestinationTests.swift) | Installazione e scoperta nella cartella scelta, rebuild dopo il cambio cartella, conflitti di nome, sorgenti protette e cartelle non disponibili o di sola lettura. |
| [Tests/NXLibraryCoreTests/ButtonPromptsTests.swift](../../Tests/NXLibraryCoreTests/ButtonPromptsTests.swift) | Etichette e simboli per tastiera, controller e scelte esplicite dell’utente. |
| [Tests/NXLibraryCoreTests/InputInHandTests.swift](../../Tests/NXLibraryCoreTests/InputInHandTests.swift) | Ultimo dispositivo usato, urti del mouse, movimento reale e attesa dopo un tasto. |
| [Tests/NXLibraryCoreTests/LaunchExitTests.swift](../../Tests/NXLibraryCoreTests/LaunchExitTests.swift) | Attesa, azione accettata e precedenza della schermata di avvio. |
| [Tests/NXLibraryCoreTests/ClickableHintsTests.swift](../../Tests/NXLibraryCoreTests/ClickableHintsTests.swift) | Suggerimenti cliccabili nelle schermate iniziali, nello spostamento e nelle catture. |
| [Tests/NXLibraryCoreTests/RailScrollTests.swift](../../Tests/NXLibraryCoreTests/RailScrollTests.swift) | Passi, direzione, scatti, pausa e asse della rotella sulle righe. |
| [Tests/NXLibraryCoreTests/SafeDefaultsTests.swift](../../Tests/NXLibraryCoreTests/SafeDefaultsTests.swift) | Schermate che si aprono da sole: Indietro nel primo avvio e scelta iniziale dell'aggiornamento. |
| [Tests/NXLibraryCoreTests/VocabularyTests.swift](../../Tests/NXLibraryCoreTests/VocabularyTests.swift) | Parole del contratto: Rimuovi e Elimina, Spotlight, compilazione. |
| [Tests/NXLibraryCoreTests/OnScreenKeyboardTests.swift](../../Tests/NXLibraryCoreTests/OnScreenKeyboardTests.swift) | Caratteri disponibili, maiuscole, focus e cambio pagina della tastiera a schermo. |
| [Tests/NXLibraryCoreTests/SettingsResetQuestionTests.swift](../../Tests/NXLibraryCoreTests/SettingsResetQuestionTests.swift) | Domanda prima di ogni ripristino di gruppo e suo testo. |
| [Tests/OortCoreTests/ControllerInputTests.swift](../../Tests/OortCoreTests/ControllerInputTests.swift) | Report Nintendo sintetici, calibrazione, transizioni e precedenza di GameController. |
| [Tests/ArcanePortingTests/CheatCopyTests.swift](../../Tests/ArcanePortingTests/CheatCopyTests.swift) | Testi di intestazione, rifiuto, conferma e rimozione dei cheats. |
| [Tests/ArcanePortingTests/CheatFileTests.swift](../../Tests/ArcanePortingTests/CheatFileTests.swift) | Parsing dei codici secondo il motore, sezioni, metadati, nomi duplicati e codici non validi. |
| [Tests/ArcanePortingTests/CheatInstallTests.swift](../../Tests/ArcanePortingTests/CheatInstallTests.swift) | Build ID, title ID, file senza nome, cartelle e decisioni di installazione. |
| [Tests/ArcanePortingTests/CheatLocatorTests.swift](../../Tests/ArcanePortingTests/CheatLocatorTests.swift) | Identità nel bundle e precedenza dei percorsi cheats e delle variabili del launcher. |
| [Tests/ArcanePortingTests/CheatStatusTests.swift](../../Tests/ArcanePortingTests/CheatStatusTests.swift) | Ancestry del motore, necessità di rebuild, valore della riga e indicatore attivo. |
| [Tests/ArcanePortingTests/CheatStoreTests.swift](../../Tests/ArcanePortingTests/CheatStoreTests.swift) | Installazione, enabled, master switch, sostituzione e ripristino se il Cestino rifiuta il set. |
| [Tests/ArcanePortingTests/ModStoreTests.swift](../../Tests/ArcanePortingTests/ModStoreTests.swift) | Overlay (anche dopo errore di scrittura), conflitti, omonimi fra RomFS ed ExeFS, Cestino e gruppo ExeFS escluso in Online o con selezione illeggibile. |
| [Tests/ArcanePortingTests/ModFolderScannerTests.swift](../../Tests/ArcanePortingTests/ModFolderScannerTests.swift) | Voci della cartella mods, layout `romfs`/Atmosphère, symlink, file relativi e file nascosti. |
| [Tests/ArcanePortingTests/EnvFileEditorTests.swift](../../Tests/ArcanePortingTests/EnvFileEditorTests.swift) | Modifica di una chiave dell'`env.txt`: commenti, duplicati, CRLF, merge al lancio. |
| [Tests/ArcanePortingTests/GameBananaAPITests.swift](../../Tests/ArcanePortingTests/GameBananaAPITests.swift) | Decodifica tollerante delle risposte, URL, host fidati, contenuto degli archivi e testo dalle descrizioni. |
| [Tests/ArcanePortingTests/GameBananaClientTests.swift](../../Tests/ArcanePortingTests/GameBananaClientTests.swift) | User-Agent, durata della cache, rete assente, errori del server, limite di richieste e cache immagini. |
| [Tests/ArcanePortingTests/GameBananaBandModelTests.swift](../../Tests/ArcanePortingTests/GameBananaBandModelTests.swift) | Cambio di gioco, avanzi di installazione, ricerca per nome con controller, mod in due gruppi con l'arte pronta. |
| [Tests/NXLibraryCoreTests/TextScrollTests.swift](../../Tests/NXLibraryCoreTests/TextScrollTests.swift) | Descrizione dopo Read more, limiti dello scorrimento, riga mostrata intera e passo Su/Giù tra le righe. |
| [Tests/ArcanePortingTests/GameBananaMatchTests.swift](../../Tests/ArcanePortingTests/GameBananaMatchTests.swift) | Abbinamento per nome, voci per piattaforma e memoria della scelta. |
| [Tests/ArcanePortingTests/ModSupportTests.swift](../../Tests/ArcanePortingTests/ModSupportTests.swift) | Quali archivi funzionano, radice `romfs`, title ID, visibilità e nomi di cartella. |
| [Tests/ArcanePortingTests/AvailableModsFinderTests.swift](../../Tests/ArcanePortingTests/AvailableModsFinderTests.swift) | Mod che funzionano in ordine, limiti di ricerca, rete assente e aggiornamenti. |
| [Tests/ArcanePortingTests/ModInstallerTests.swift](../../Tests/ArcanePortingTests/ModInstallerTests.swift) | Installazione con archivi veri: MD5, percorsi pericolosi, mod di codice, errori, gioco aperto, spazio, nomi, aggiornamenti. |
| [Tests/ArcanePortingTests/CloudSavesTests.swift](../../Tests/ArcanePortingTests/CloudSavesTests.swift) | Cartelle cloud, preferenze per gioco e decodifica delle impostazioni precedenti. |
| [Tests/ArcanePortingTests/CompatibilityCheckerTests.swift](../../Tests/ArcanePortingTests/CompatibilityCheckerTests.swift) | Commit, modifiche ammesse nel checkout, Metal, CLI e override del gate. |
| [Tests/NXLibraryCoreTests/ConnectivityWatcherTests.swift](../../Tests/NXLibraryCoreTests/ConnectivityWatcherTests.swift) | Solo il passaggio da offline a online conta come ritorno della connessione; la prima lettura no. |
| [Tests/NXLibraryCoreTests/DetailsFocusTests.swift](../../Tests/NXLibraryCoreTests/DetailsFocusTests.swift) | Spostamento nelle bande di Details, limiti e sezioni vuote. |
| [Tests/NXLibraryCoreTests/DirectorySizeTests.swift](../../Tests/NXLibraryCoreTests/DirectorySizeTests.swift) | Somma dei file regolari ignorando nascosti e collegamenti; cartella mancante a zero. |
| [Tests/NXLibraryCoreTests/DiagnosticsReportTests.swift](../../Tests/NXLibraryCoreTests/DiagnosticsReportTests.swift) | Rimozione di percorsi personali e chiavi e contenuto delle sezioni diagnostiche. |
| [Tests/NXLibraryCoreTests/LibraryPathsTests.swift](../../Tests/NXLibraryCoreTests/LibraryPathsTests.swift) | Copia e riparazione dei percorsi su cartelle sintetiche: URL, accenti composti e decomposti, altro account, lock, interruzioni, rimozione in sospeso e collegamenti morti. |
| [Tests/NXLibraryCoreTests/DowngradeCheckpointTests.swift](../../Tests/NXLibraryCoreTests/DowngradeCheckpointTests.swift) | Prova avviso singolo, verifica, rotazione, conservazione dei file essenziali al limite, link rifiutati e dati esclusi. |
| [Tests/ArcanePortingTests/EngineLocationTests.swift](../../Tests/ArcanePortingTests/EngineLocationTests.swift) | Percorso predefinito, cartella scelta e fallback quando scompare. |
| [Tests/ArcanePortingTests/EngineToolchainTests.swift](../../Tests/ArcanePortingTests/EngineToolchainTests.swift) | Rilevamento del runtime incluso e fallback a Python e strumenti del checkout. |
| [Tests/ArcanePortingTests/EnvironmentTests.swift](../../Tests/ArcanePortingTests/EnvironmentTests.swift) | Parsing di Metal e controlli dell’ambiente mediante runner sintetico. |
| [Tests/OortCoreTests/FocusIndexTests.swift](../../Tests/OortCoreTests/FocusIndexTests.swift) | Movimento limitato agli elementi della lista e liste vuote. |
| [Tests/ArcanePortingTests/GameDetailPresentationTests.swift](../../Tests/ArcanePortingTests/GameDetailPresentationTests.swift) | Disponibilità di build e sorgenti e formattazione di metadati e azioni Details. |
| [Tests/ArcanePortingTests/GameResourceStateTests.swift](../../Tests/ArcanePortingTests/GameResourceStateTests.swift) | App spostata e ripristinata, input assenti, Play senza sorgenti e conservazione di workspace e build attive durante Refresh. |
| [Tests/ArcanePortingTests/GameOptionsPresentationTests.swift](../../Tests/ArcanePortingTests/GameOptionsPresentationTests.swift) | Ordine, focus e capacità della build, incluse le righe multigiocatore e RomFS. |
| [Tests/ArcanePortingTests/GameRuntimeConfigTests.swift](../../Tests/ArcanePortingTests/GameRuntimeConfigTests.swift) | Review di giochi nuovi ed esistenti, persistenza con plist temporaneo, lingua del rebuild e conversione DM_* con merge di env.txt. |
| [Tests/ArcanePortingTests/GameTDBTests.swift](../../Tests/ArcanePortingTests/GameTDBTests.swift) | Database, normalizzazione dei nomi, regioni e matching delle copertine. |
| [Tests/OortCoreTests/HoldDetectorTests.swift](../../Tests/OortCoreTests/HoldDetectorTests.swift) | Soglia temporale e distinzione fra pressione breve e prolungata. |
| [Tests/ArcanePortingTests/ImportServiceTests.swift](../../Tests/ArcanePortingTests/ImportServiceTests.swift) | Identità, firma originale o di ripiego senza cloud, spazio, riparazione, rifiuto di sidecar non sicuri, conflitto, modifica dopo l'anteprima e rollback. |
| [Tests/NXLibraryCoreTests/CursorIdleTests.swift](../../Tests/NXLibraryCoreTests/CursorIdleTests.swift) | Ritardo del cursore, ripristino e ripartenza dopo interruzione o attività del mouse. |
| [Tests/ArcanePortingTests/InstallProgressTests.swift](../../Tests/ArcanePortingTests/InstallProgressTests.swift) | Fasi Git, percentuali e byte. |
| [Tests/OortCoreTests/LineBufferTests.swift](../../Tests/OortCoreTests/LineBufferTests.swift) | Ricomposizione delle righe parziali e separatori dei progressi. |
| [Tests/OortCoreTests/CreditsTests.swift](../../Tests/OortCoreTests/CreditsTests.swift) | Autori, gruppi per sistema, lingue e immagini permesse dei crediti. |
| [Tests/ArcanePortingTests/KeyCheckTests.swift](../../Tests/ArcanePortingTests/KeyCheckTests.swift) | Cifratura e lettura di intestazioni sintetiche, intervalli troncati e chiavi richieste dalle sorgenti. |
| [Tests/ArcanePortingTests/KeyStoreTests.swift](../../Tests/ArcanePortingTests/KeyStoreTests.swift) | Importazione e sostituzione atomica, conservazione della copia precedente anche con header malformato, permessi 0600 e riepilogo. |
| [Tests/ArcanePortingTests/LaunchServiceTests.swift](../../Tests/ArcanePortingTests/LaunchServiceTests.swift) | Processo fittizio, impostazioni runtime e profilo, ambiente ereditato senza segreti, Home e overlay, permessi e pulizia dello snapshot; capacità, ripiego e override dello schermo. |
| [Tests/ArcanePortingTests/HomeQuitTextTests.swift](../../Tests/ArcanePortingTests/HomeQuitTextTests.swift) | Domanda di uscita del gioco nella lingua del giocatore, riga per riga. |
| [PlayersLaunchTests.swift](../../Tests/ArcanePortingTests/PlayersLaunchTests.swift) | Bundle sintetici per prove motore, precedenze, fusione P1/P2–P8, ordine e profili di gioco. |
| [Tests/ArcanePortingTests/HomeMenuTests.swift](../../Tests/ArcanePortingTests/HomeMenuTests.swift) | Capacità e ambiente del bundle, stati e segnale al solo figlio sintetico. |
| [Tests/ArcanePortingTests/LauncherSettingsTests.swift](../../Tests/ArcanePortingTests/LauncherSettingsTests.swift) | Metadati launcher.json e fallback dei controlli per build precedenti. |
| [Tests/NXLibraryCoreTests/LaunchBoxArtTests.swift](../../Tests/NXLibraryCoreTests/LaunchBoxArtTests.swift) | Risultati di ricerca, scelta della voce Switch/Switch 2, payload Nuxt con file pieni e screenshot. |
| [Tests/ArcanePortingTests/LibraryPresentationTests.swift](../../Tests/ArcanePortingTests/LibraryPresentationTests.swift) | Formattazione dei metadati e delle statistiche della libreria. |
| [Tests/ArcanePortingTests/LibraryQueryTests.swift](../../Tests/ArcanePortingTests/LibraryQueryTests.swift) | Filtri, ricerca, ordinamento e rapporto con la cronologia di gioco. |
| [Tests/ArcanePortingTests/NXNativeCatalogPersistenceTests.swift](../../Tests/ArcanePortingTests/NXNativeCatalogPersistenceTests.swift) | Persistenza e merge nxnative, ripresa e copia senza eseguire rimozioni o build ereditate; staging esterno preservato e nuova build ancora in coda. |
| [Tests/NXLibraryCoreTests/MaterialIconTests.swift](../../Tests/NXLibraryCoreTests/MaterialIconTests.swift) | Integrità dei glifi e del font delle icone. |
| [Tests/ArcanePortingTests/MetadataPickerTests.swift](../../Tests/ArcanePortingTests/MetadataPickerTests.swift) | Alternative per campo, override persistiti e applicazione ai metadati del gioco. |
| [Tests/OortCoreTests/MoonlightFieldTests.swift](../../Tests/OortCoreTests/MoonlightFieldTests.swift) | Generazione deterministica e limiti dei dati delle particelle. |
| [MoonlightAppearanceTests.swift](../../Tests/ArcanePortingTests/MoonlightAppearanceTests.swift) | Ignora la preferenza storica delle particelle senza perdere altri valori; continuità del ciclo e bordi della griglia colori. |
| [Tests/ArcanePortingTests/MoreArtworkSourcesTests.swift](../../Tests/ArcanePortingTests/MoreArtworkSourcesTests.swift) | Matching dei titoli e risposte delle sorgenti artwork aggiuntive. |
| [Tests/ArcanePortingTests/MoreLikeThisTests.swift](../../Tests/ArcanePortingTests/MoreLikeThisTests.swift) | Ranking condiviso, precedenza Steam e ripiego Switch, giochi nascosti e metadati incompleti. |
| [Tests/ArcanePortingTests/NintendoStoreMetadataTests.swift](../../Tests/ArcanePortingTests/NintendoStoreMetadataTests.swift) | Decodifica store e Title DB, cache, screenshot e risposte incomplete della fonte Arcane. |
| [Tests/ArcanePortingTests/SwitchGameMetadataServiceTests.swift](../../Tests/ArcanePortingTests/SwitchGameMetadataServiceTests.swift) | Priorità Arcane per campo, richiesta pubblica Europe, prodotto base, lingue, cache e ripieghi. |
| [Tests/NXLibraryCoreTests/ReleaseNotesLayoutTests.swift](../../Tests/NXLibraryCoreTests/ReleaseNotesLayoutTests.swift) | Titoli, voci e righe vuote delle note di release, una voce per riga. |
| [Tests/ArcanePortingTests/NewestEngineTests.swift](../../Tests/ArcanePortingTests/NewestEngineTests.swift) | Lock e Metal di main, validità della scelta, comandi git del cambio, gate Newest engine, scheda Setup e frase. |
| [Tests/ArcanePortingTests/NUPSourceCatalogTests.swift](../../Tests/ArcanePortingTests/NUPSourceCatalogTests.swift) | NUP storici, multiprogramma e soli update; identità DLC, JSON, capacità checkout, programma zero nei vecchi record e argv coerenti. |
| [Tests/ArcanePortingTests/NXNativeGameSettingsTests.swift](../../Tests/ArcanePortingTests/NXNativeGameSettingsTests.swift) | Migrazione da un plist temporaneo, precedenza di `env.txt`, scelta VPN, ripiego locale e tutte le scelte runtime macOS con ambiente filtrato. |
| [Tests/ArcanePortingTests/NextendoLaunchTests.swift](../../Tests/ArcanePortingTests/NextendoLaunchTests.swift) | Online solo per build compatibili, ordine e focus di Play, presenza di Favorite, Search e blocco senza sessione. |
| [Tests/ArcanePortingTests/NextendoAccountServiceTests.swift](../../Tests/ArcanePortingTests/NextendoAccountServiceTests.swift) | Account, liste, stati di presenza e rinnovo OAuth con trasporto finto, messaggi diagnostici, verifiche Discord ed e-mail e annullamento. |
| [Tests/ArcanePortingTests/NextendoOnlineCountsTests.swift](../../Tests/ArcanePortingTests/NextendoOnlineCountsTests.swift) | Verifica assenza di richieste senza token o con tutti gli interruttori spenti, normalizzazione, collisioni, zeri e forma del conteggio. |
| [Tests/ArcanePortingTests/NextendoOAuthTests.swift](../../Tests/ArcanePortingTests/NextendoOAuthTests.swift) | PKCE RFC 7636, callback, scambio e rotazione sintetici, scadenza ed errore temporaneo. |
| [Tests/ArcanePortingTests/NextendoTokenStoreTests.swift](../../Tests/ArcanePortingTests/NextendoTokenStoreTests.swift) | Permessi, sostituzione atomica, flock POSIX, annullamento, disconnessione e link rifiutati. |
| [Tests/ArcanePortingTests/OnlineArtworkSourcesTests.swift](../../Tests/ArcanePortingTests/OnlineArtworkSourcesTests.swift) | Ricerca Steam e loghi MediaWiki/Commons con risposte sintetiche. |
| [Tests/NXLibraryCoreTests/OnlineBackgroundsTests.swift](../../Tests/NXLibraryCoreTests/OnlineBackgroundsTests.swift) | Parser degli sfondi fissi, risoluzioni, crediti e nomi dei download. |
| [Tests/NXLibraryCoreTests/OnlineLiveSourcesTests.swift](../../Tests/NXLibraryCoreTests/OnlineLiveSourcesTests.swift) | Parser e indirizzi dei provider di sfondi video. |
| [Tests/ArcanePortingTests/PendingInstallTests.swift](../../Tests/ArcanePortingTests/PendingInstallTests.swift) | Staging, rifiuto di un bundle estraneo con record vecchio, ripresa a destinazione libera e riconoscimento dopo pubblicazione. |
| [Tests/ArcanePortingTests/LibraryPathsPortingTests.swift](../../Tests/ArcanePortingTests/LibraryPathsPortingTests.swift) | Riparazione e prima conversione di una libreria copiata: percorsi aggiornati, input legacy principale o di backup intatto e catalogo riapribile. |
| [Tests/ArcanePortingTests/PlaySessionStoreTests.swift](../../Tests/ArcanePortingTests/PlaySessionStoreTests.swift) | Persistenza atomica di storico e totali, import dei file precedenti senza sovrascriverli, conservazione dei dati illeggibili, durata, heartbeat, riconciliazione e bundle ID. |
| [Tests/NXLibraryCoreTests/LocalProfileStoreTests.swift](../../Tests/NXLibraryCoreTests/LocalProfileStoreTests.swift) | Migrazione, profilo corrente, protezione del profilo originale, dati illeggibili e attribuzione al profilo che avvia il gioco. |
| [Tests/NXLibraryCoreTests/PlayerPlanTests.swift](../../Tests/NXLibraryCoreTests/PlayerPlanTests.swift) | Posti, accesso ai profili, identità ambigue e conferme dei controller. |
| [Tests/NXLibraryCoreTests/PlayerPlanStoreTests.swift](../../Tests/NXLibraryCoreTests/PlayerPlanStoreTests.swift) | Persistenza e conservazione dei campi sconosciuti; rifiuto dei documenti non validi. |
| [Tests/NXLibraryCoreTests/PlayerLaunchEnvironmentTests.swift](../../Tests/NXLibraryCoreTests/PlayerLaunchEnvironmentTests.swift) | Modalità di lancio, capacità dichiarate, precedenza di `env.txt` e limiti del nickname. |
| [Tests/OortCoreTests/ProfileKeypadTests.swift](../../Tests/OortCoreTests/ProfileKeypadTests.swift) | Navigazione, cancellazione, zero iniziale e lunghezza del PIN fornita dal chiamante. |
| [Tests/OortCoreTests/PaletteTests.swift](../../Tests/OortCoreTests/PaletteTests.swift) | Accenti, errori, ordine, gruppi, focus e recenti di Cerca ovunque. |
| [Tests/NXLibraryCoreTests/PaletteActionTests.swift](../../Tests/NXLibraryCoreTests/PaletteActionTests.swift) | Sezioni, scorciatoie, traduzioni e recenti per profilo di Cerca ovunque. |
| [Tests/NXLibraryCoreTests/ProfileLayersTests.swift](../../Tests/NXLibraryCoreTests/ProfileLayersTests.swift) | In ogni stato un solo strato della schermata profilo riceve l’input e mostra i suggerimenti; la procedura guidata sostituisce il selettore. |
| [Tests/ArcanePortingTests/PortedGameTests.swift](../../Tests/ArcanePortingTests/PortedGameTests.swift) | Modello del gioco, compatibilità dei record, disponibilità dell’app e selezione delle ultime compilazioni riuscite. |
| [Tests/ArcanePortingTests/PortingFailureReasonTests.swift](../../Tests/ArcanePortingTests/PortingFailureReasonTests.swift) | Classificazione dei fallimenti, distinzione fra avvio di Python e chiavi, e corrispondenza con i messaggi del pin (anche con NX_TEST_ENGINE_REPO). |
| [Tests/ArcanePortingTests/PortingNoticeTests.swift](../../Tests/ArcanePortingTests/PortingNoticeTests.swift) | Condizioni e testi delle notifiche di esito del porting. |
| [Tests/ArcanePortingTests/PortingPresentationTests.swift](../../Tests/ArcanePortingTests/PortingPresentationTests.swift) | ETA, prewarm, tile, fallimenti del porting e posizione e focus della pill Cloud. |
| [Tests/ArcanePortingTests/CloudGameSourcesTests.swift](../../Tests/ArcanePortingTests/CloudGameSourcesTests.swift) | Scoperta con solo metadati, radici isolate, errori e rifiuti; voci solo remote, esclusioni, Unfollow, spazio, conflitti, lease e Cestino sintetico. |
| [Tests/ArcanePortingTests/CloudTransferQueueTests.swift](../../Tests/ArcanePortingTests/CloudTransferQueueTests.swift) | Persistenza, ordine, vecchie richieste con `offer`, errori di scrittura e marcatore di pausa volontaria valido solo in testa. |
| [PersonalAppReceiptTests.swift](../../Tests/ArcanePortingTests/PersonalAppReceiptTests.swift) | Ricevuta personale, origine, revisione, cambiamenti nell’app e stima dei byte. |
| [Tests/ArcanePortingTests/CloudTransferPresentationTests.swift](../../Tests/ArcanePortingTests/CloudTransferPresentationTests.swift) | Stati e azioni, misura esclusiva per superficie, movimento ridotto e punto d'ingresso unico. |
| [Tests/ArcanePortingTests/BuildQueueTests.swift](../../Tests/ArcanePortingTests/BuildQueueTests.swift) | FIFO, ripristino, voci non valide, sorgenti mancanti, persistenza degli esiti e retry. |
| [Tests/ArcanePortingTests/CloudDriveFoldersTests.swift](../../Tests/ArcanePortingTests/CloudDriveFoldersTests.swift) | Manifest e archivi su file temporanei: residui prima e dopo lo spostamento, identità cambiate, concorrenza e ripresa dopo risposte perse. |
| [Tests/ArcanePortingTests/CloudDriveReadsTests.swift](../../Tests/ArcanePortingTests/CloudDriveReadsTests.swift) | Letture condivise, annullamento, e rifiuto di ogni scrittura. |
| [Tests/ArcanePortingTests/CloudFolderDiscoveryTests.swift](../../Tests/ArcanePortingTests/CloudFolderDiscoveryTests.swift) | Cartelle trovate, tenute, proposte, spiegate e create. |
| [Tests/ArcanePortingTests/CloudAssistantNetworkTests.swift](../../Tests/ArcanePortingTests/CloudAssistantNetworkTests.swift) | Misura dell’assistente su un Drive sintetico lento, solo su richiesta. |
| [Tests/ArcanePortingTests/AppIconPreferenceTests.swift](../../Tests/ArcanePortingTests/AppIconPreferenceTests.swift) | Ambito dell’icona: scelta esplicita, vecchie librerie, scansioni, persistenza e rebuild. |
| [Tests/ArcanePortingTests/AppIconProgressTests.swift](../../Tests/ArcanePortingTests/AppIconProgressTests.swift) | Verifica che l'esito di un'icona mancante non sovrascriva il log o segnali una build fallita. |
| [Tests/ArcanePortingTests/IconLaunchWaitTests.swift](../../Tests/ArcanePortingTests/IconLaunchWaitTests.swift) | Attesa Play: successo, errore, annullamento, gioco diverso e nuova firma in coda. |
| [Tests/ArcanePortingTests/PipelineArchiveProgressTests.swift](../../Tests/ArcanePortingTests/PipelineArchiveProgressTests.swift) | Log obsoleti, righe incomplete, cache riusata, gruppi paralleli e GPU diverse. |
| [Tests/ArcanePortingTests/PortingProgressTests.swift](../../Tests/ArcanePortingTests/PortingProgressTests.swift) | Aggregazione delle fasi, avanzamento monotono, peso degli shader e avvisi di archivio/prewarm. |
| [Tests/ArcanePortingTests/ProdKeysLocationsTests.swift](../../Tests/ArcanePortingTests/ProdKeysLocationsTests.swift) | Selezione e validazione dei possibili percorsi delle chiavi. |
| [Tests/ArcanePortingTests/RunningGamesTests.swift](../../Tests/ArcanePortingTests/RunningGamesTests.swift) | Associazione bundle ID, applicazioni aperte e voci della libreria. |
| [Tests/ArcanePortingTests/RyujinxSaveImportTests.swift](../../Tests/ArcanePortingTests/RyujinxSaveImportTests.swift) | Contenitori e slot Ryujinx, identità del titolo e importazioni con strutture e destinazioni differenti. |
| [Tests/ArcanePortingTests/SaveLocationTests.swift](../../Tests/ArcanePortingTests/SaveLocationTests.swift) | Identificativi, percorsi sicuri, precedenze dell’ambiente e cloud effettivo. |
| [Tests/ArcanePortingTests/SaveOperationGateTests.swift](../../Tests/ArcanePortingTests/SaveOperationGateTests.swift) | Lease per titolo, esclusione updater, isolamento dei blocchi di recupero a I/O concluso. |
| [Tests/ArcanePortingTests/SavePresentationTests.swift](../../Tests/ArcanePortingTests/SavePresentationTests.swift) | Azioni e messaggi del pannello; distingue backup storico/completo e limite cloud. |
| [Tests/ArcanePortingTests/SaveSnapshotStoreTests.swift](../../Tests/ArcanePortingTests/SaveSnapshotStoreTests.swift) | Inventari, xattr, integrità dei backup, staging e selezione dei backup datati. |
| [MultiuserSaveTests.swift](../../Tests/ArcanePortingTests/MultiuserSaveTests.swift) | Backup e restore utenti/registro, compatibilità storica, import circoscritti, fault injection e conservazione di dati cambiati da fuori. |
| [Tests/ArcanePortingTests/SaveTestHome.swift](../../Tests/ArcanePortingTests/SaveTestHome.swift) | Fixture condivisa che crea una home e un bundle sintetici in una directory temporanea dedicata. |
| [Tests/ArcanePortingTests/SaveTransactionTests.swift](../../Tests/ArcanePortingTests/SaveTransactionTests.swift) | Sostituzioni, interruzioni, rollback, modifiche esterne e compatibilità dei journal precedenti. |
| [Tests/NXLibraryCoreTests/ScreenshotViewerStateTests.swift](../../Tests/NXLibraryCoreTests/ScreenshotViewerStateTests.swift) | Indice, avanzamento e limiti del visualizzatore screenshot. |
| [Tests/NXLibraryCoreTests/SeleneCanvasTests.swift](../../Tests/NXLibraryCoreTests/SeleneCanvasTests.swift) | Scala, centratura e conversione delle unità del canvas. |
| [Tests/NXLibraryCoreTests/SeleneImporterTests.swift](../../Tests/NXLibraryCoreTests/SeleneImporterTests.swift) | Copia delle risorse Selene e risoluzione dei cue sonori. |
| [Tests/NXLibraryCoreTests/SelenePaletteTests.swift](../../Tests/NXLibraryCoreTests/SelenePaletteTests.swift) | Lettura delle 26 palette, valori RGB di Oort e blu, alternative Crystal/Flow, persistenza ID, ordine e fallback. |
| [Tests/ArcanePortingTests/SettingsCatalogTests.swift](../../Tests/ArcanePortingTests/SettingsCatalogTests.swift) | Ordine, ricerca (anche Hidden game apps, Home in gioco e Inbox), Advanced, Changed e reset, compresa la migrazione della preferenza ZeroTier. |
| [Tests/ArcanePortingTests/IntegrationOverviewTests.swift](../../Tests/ArcanePortingTests/IntegrationOverviewTests.swift) | Distingue scansione vuota, lavoro e panne; controlla destinazioni esistenti, identità e ritorno del focus. |
| [Tests/ArcanePortingTests/SetupActionsTests.swift](../../Tests/ArcanePortingTests/SetupActionsTests.swift) | Pin facoltativo nel plist, comandi Git del Setup upstream e del fork, rispetto delle modifiche locali. |
| [Tests/ArcanePortingTests/SetupCheckTests.swift](../../Tests/ArcanePortingTests/SetupCheckTests.swift) | Stati e condizioni di riapertura del Setup, runtime con o senza bundle, errori chiavi ed esclusione dei checkout da Install all. |
| [Tests/ArcanePortingTests/SetupGridTests.swift](../../Tests/ArcanePortingTests/SetupGridTests.swift) | Bilanciamento delle righe e spostamento del focus fra le schede. |
| [Tests/ArcanePortingTests/FirstRunSetupTests.swift](../../Tests/ArcanePortingTests/FirstRunSetupTests.swift) | Pagina iniziale, Porting, scelta Steam acceso/spento dopo interruzione, completamento e pulizia della scelta salvata, focus, scansione e ripresa. |
| [Tests/ArcanePortingTests/FirstRunFindingsTests.swift](../../Tests/ArcanePortingTests/FirstRunFindingsTests.swift) | Steam assente, solo giochi Mac pronti, zero giochi, errore/parziale distinto da assenza, annullamento, app portate contate e conteggio ricevuto. |
| [Tests/NXLibraryCoreTests/SmokeTests.swift](../../Tests/NXLibraryCoreTests/SmokeTests.swift) | Importabilità e versione nominale del modulo Core. |
| [Tests/NXLibraryCoreTests/WikipediaDescriptionTests.swift](../../Tests/NXLibraryCoreTests/WikipediaDescriptionTests.swift) | Quando cercare Wikipedia (lingua dal testo, scelta del giocatore, scrittura cinese, testi corti), sitelink dell'entità giusta, introduzione e link, host rifiutati, cache ed errori di rete non salvati. |
| [Tests/NXLibraryCoreTests/CriticRatingTests.swift](../../Tests/NXLibraryCoreTests/CriticRatingTests.swift) | Abbinamenti esatti, metriche e piattaforme, stelle proporzionali, cache offline, richieste seriali/condivise, errori e annullamento delle valutazioni. |
| [Tests/ArcanePortingTests/IGDBRatingTests.swift](../../Tests/ArcanePortingTests/IGDBRatingTests.swift) | Credenziali 0600 sintetiche, isolamento degli host, voti critica/utenti, rinnovo accesso, annullamento, cache offline e ripiego Wikidata. |
| [Tests/NXLibraryCoreTests/IGDBMetadataTests.swift](../../Tests/NXLibraryCoreTests/IGDBMetadataTests.swift) | Identità, ruoli, date precise per piattaforma, Steam, cache offline, retry, annullamento e token/coda condivisi. |
| [Tests/NXLibraryCoreTests/DatabaseMetadataTests.swift](../../Tests/NXLibraryCoreTests/DatabaseMetadataTests.swift) | Parser pubblici, identità/ambiguità, date, conteggio richieste, letture concorrenti, cache, annullamento, risposte errate e retry. |
| [Tests/ArcanePortingTests/SourceCatalogTests.swift](../../Tests/ArcanePortingTests/SourceCatalogTests.swift) | Fixture PFS0/CNMT e riconoscimento di base, aggiornamenti e DLC. |
| [Tests/ArcanePortingTests/GameInboxTests.swift](../../Tests/ArcanePortingTests/GameInboxTests.swift) | Nomi, chiavi mancanti, metadati ambigui, collisioni, duplicati, copia interrotta, ritrovamento e Cestino simulato. |
| [Tests/ArcanePortingTests/EngineUpgradeSourcesTests.swift](../../Tests/ArcanePortingTests/EngineUpgradeSourcesTests.swift) | Cartelle estratte, pacchetti multipli, collegamento per ID esatto, persistenza, bridge Python e restaging senza perdita di originali. |
| [Tests/NXLibraryCoreTests/SpotlightPageTests.swift](../../Tests/NXLibraryCoreTests/SpotlightPageTests.swift) | Estratti, precedenza e crediti del testo nella lingua del giocatore, e stati dello scorrimento. |
| [Tests/ArcanePortingTests/SpotlightRowTests.swift](../../Tests/ArcanePortingTests/SpotlightRowTests.swift) | Ordine, card, riordino delle tile, gioco avviato primo nell’ordine salvato e selezione Surprise. |
| [Tests/NXLibraryCoreTests/SpotlightStateTests.swift](../../Tests/NXLibraryCoreTests/SpotlightStateTests.swift) | Focus, selezione, filtri, azioni e spostamento delle tile Spotlight. |
| [Tests/NXLibraryCoreTests/SpotlightPlatformsTests.swift](../../Tests/NXLibraryCoreTests/SpotlightPlatformsTests.swift) | Conteggi, filtri, ordine, rimozione di piattaforme e cursore dell’anteprima. |
| [Tests/NXLibraryCoreTests/SpotlightEntranceTests.swift](../../Tests/NXLibraryCoreTests/SpotlightEntranceTests.swift) | Partenze, tempi di volo e dissolvenza, bordi, durata, messaggio vuoto, avanzamento degli effetti e fasi dell’entrata; interruttore e Riduci movimento. |
| [Tests/ArcanePortingTests/StorageManagerTests.swift](../../Tests/ArcanePortingTests/StorageManagerTests.swift) | Misure per gioco, cache condivise e nascoste, pulizia selettiva, protezione di app/sorgenti/symlink, file incoerenti e volumi/cartelle non disponibili. |
| [Tests/NXLibraryCoreTests/ThemePickerTests.swift](../../Tests/NXLibraryCoreTests/ThemePickerTests.swift) | Navigazione della griglia, tab e selezione degli sfondi. |
| [Tests/ArcanePortingTests/ToolchainGateCopyTests.swift](../../Tests/ArcanePortingTests/ToolchainGateCopyTests.swift) | Testi del gate per Metal certificato, precedente, successivo e altre cause di blocco. |
| [Tests/ArcanePortingTests/ToolchainRequirementsTests.swift](../../Tests/ArcanePortingTests/ToolchainRequirementsTests.swift) | Versioni minime e identificativi degli asset Metal da scaricare. |
| [Tests/OortCoreTests/VersionNumberTests.swift](../../Tests/OortCoreTests/VersionNumberTests.swift) | Confronto numerico delle versioni. |
| [Tests/ArcanePortingTests/UpstreamCheckerTests.swift](../../Tests/ArcanePortingTests/UpstreamCheckerTests.swift) | Changelog HTTP, cache e gestione degli errori del provider. |
| [Tests/ArcanePortingTests/UpstreamCopyTests.swift](../../Tests/ArcanePortingTests/UpstreamCopyTests.swift) | Testi della riga upstream e adozione dei commit attraverso gli aggiornamenti dell’app. |
| [Tests/NXLibraryCoreTests/WallpaperBrightnessTests.swift](../../Tests/NXLibraryCoreTests/WallpaperBrightnessTests.swift) | Maschere e livelli di luminosità dello sfondo. |
| [Tests/NXLibraryCoreTests/WallpaperCatalogTests.swift](../../Tests/NXLibraryCoreTests/WallpaperCatalogTests.swift) | Catalogo dei file inclusi/importati, gruppi e tipi immagine/video. |
| [Tests/NXLibraryCoreTests/WallpaperPlacementTests.swift](../../Tests/NXLibraryCoreTests/WallpaperPlacementTests.swift) | Destinazione dello sfondo fra home e impostazioni. |
| [Tests/ArcanePortingTests/WorkspaceManagerTests.swift](../../Tests/ArcanePortingTests/WorkspaceManagerTests.swift) | Collegamenti simbolici, collisioni fra sorgenti, cache conservata e link interrotti. |
| [Tests/ArcanePortingTests/AppIconWriterTests.swift](../../Tests/ArcanePortingTests/AppIconWriterTests.swift) | Icona scelta scritta e ripristinata, originale ricordato anche se assente, ricostruzione dell’app, firma fallita senza modifiche, icona rifilata e opaca. |
| [Tests/NXLibraryCoreTests/BackdropArtTests.swift](../../Tests/NXLibraryCoreTests/BackdropArtTests.swift) | Arte tenuta fra un gioco e l’altro e mai fra card e gioco, dissolvenze sull’orologio come Core Animation, livelli coperti tolti e scorrimento rapido. |
| [Tests/NXLibraryCoreTests/BoundedDownloadTests.swift](../../Tests/NXLibraryCoreTests/BoundedDownloadTests.swift) | Blocchi raccolti fino al limite, corpo o lunghezza dichiarata oltre il limite rifiutati, nessun redirect, annullamento della lettura. |
| [Tests/ArcanePortingTests/DetailsFactsTests.swift](../../Tests/ArcanePortingTests/DetailsFactsTests.swift) | Righe Details per Switch e Steam: ordine, valori mancanti o vuoti nascosti, mai la versione Steam, solo crediti durante il download, simboli. |
| [Tests/ArcanePortingTests/InstalledEngineVersionTests.swift](../../Tests/ArcanePortingTests/InstalledEngineVersionTests.swift) | Plist e checkout sintetici: motore attuale, anteriore, successivo o ignoto; app mancante, file di gioco e precedenza del badge. |
| [Tests/ArcanePortingTests/DetailsReviewFixTests.swift](../../Tests/ArcanePortingTests/DetailsReviewFixTests.swift) | Play costruisce un gioco non ancora costruito con le sorgenti; nome di cartella o volume letto una volta per URL. |
| [Tests/NXLibraryCoreTests/EngineRuntimeRequirementsTests.swift](../../Tests/NXLibraryCoreTests/EngineRuntimeRequirementsTests.swift) | Il runtime incluso porta ogni pacchetto Python che il motore fissato chiede (riga `pip install` del README e `tools.txt`). |
| [Tests/NXLibraryCoreTests/GameFocusTests.swift](../../Tests/NXLibraryCoreTests/GameFocusTests.swift) | Ritorno della libreria davanti solo per il gioco in primo piano, mai con un altro gioco aperto, uscita contata una volta. |
| [Tests/ArcanePortingTests/ModStoreModelTests.swift](../../Tests/ArcanePortingTests/ModStoreModelTests.swift) | Store delle mod da copia fresca o vecchia, abbinamenti incerti o sicuri, ordine della libreria, copie di un altro gioco, chiusura senza perdite. |
| [Tests/ArcanePortingTests/SessionSummaryTests.swift](../../Tests/ArcanePortingTests/SessionSummaryTests.swift) | Card di fine sessione: gioco, sessione e totale, meno di un minuto, sessioni troppo brevi o in corso, altri giochi, giochi Steam. |
| [Tests/NXLibraryCoreTests/SettingsRowButtonsTests.swift](../../Tests/NXLibraryCoreTests/SettingsRowButtonsTests.swift) | Riga con due pulsanti: Sinistra/Destra fra i pulsanti, uscita dalla riga, riga con un solo pulsante, A preme quello in focus. |
| [Tests/NXLibraryCoreTests/SpotlightRowGeometryTests.swift](../../Tests/NXLibraryCoreTests/SpotlightRowGeometryTests.swift) | Posto a schermo = camera più posto nella riga, tessere che restano ferme durante lo scorrimento, distanze costanti e quattro tessere di riserva ai bordi. |
| [Tests/NXLibraryCoreTests/TileMotionTests.swift](../../Tests/NXLibraryCoreTests/TileMotionTests.swift) | Curve di bagliore, ring e riflesso; continuità a 60 Hz tra raffiche, pausa, verifica, riavvio e movimento ridotto. |
| [Tests/ArcanePortingTests/AppLocaleTests.swift](../../Tests/ArcanePortingTests/AppLocaleTests.swift) | Preferenze, formati, traduzioni e nome Oort NX senza cambiare trofeo, argomenti o User-Agent. |
| [Tests/PublicationChecks/test_check_guides.py](../../Tests/PublicationChecks/test_check_guides.py) | Le guide pubblicate passano; ogni regola rifiuta il suo errore. |
| [Tests/PublicationChecks/test_localizations.py](../../Tests/PublicationChecks/test_localizations.py) | Rifiuto di cataloghi incompleti e bundle senza risorse. |
| [Tests/PublicationChecks/test_vocabulary.py](../../Tests/PublicationChecks/test_vocabulary.py) | Prova le regole del vocabolario, il registro che può solo ridursi e le fonti lette per sistema. |
| [DevelopmentProfileTests.swift](../../Tests/ArcanePortingTests/DevelopmentProfileTests.swift) | Identità separate, copie e filtro dell’essai 2, sorgente intatta, symlink, sovrascrittura, sessioni e totali. |
| [DevelopmentProfileEffectTests.swift](../../Tests/ArcanePortingTests/DevelopmentProfileEffectTests.swift) | Isolamento Dev, staging e richieste esplicite. Verifica anche che la riconciliazione delle mod conservi record e overlay dopo un errore di lettura. |
| [test_profile_boundaries.py](../../Tests/PublicationChecks/test_profile_boundaries.py) | Guardia contro percorsi/defaults del launcher non centralizzati. |
| [SteamKeyValuesTests.swift](../../Tests/NXLibraryCoreTests/SteamKeyValuesTests.swift) | Formato, escape, Unicode, duplicati, input troncati e limiti del parser. |
| [SteamPlaytimeReaderTests.swift](../../Tests/NXLibraryCoreTests/SteamPlaytimeReaderTests.swift) | Campi letti, ultima partita, scelta dell’account, duplicati e tipi errati di blocchi/scalari, file grandi, malformati o non sicuri. |
| [SteamPlaytimeBaselinesTests.swift](../../Tests/ArcanePortingTests/SteamPlaytimeBaselinesTests.swift) | Base mantenuta o ripartita, minuto conservato, cambio account, salvataggio e mappatura sul catalogo. |
| [SteamReturnFocusTests.swift](../../Tests/NXLibraryCoreTests/SteamReturnFocusTests.swift) | Ritorno ad Arcane solo per Play premuto qui, gioco davanti e nessun altro gioco aperto. |
| [SteamLaunchQuestionsTests.swift](../../Tests/NXLibraryCoreTests/SteamLaunchQuestionsTests.swift) | Fase `ShowInterstitials` a freddo, domande aperte o risposte subito, log per righe intere e sostituzione del file. |
| [SteamPlaytimeSyncTests.swift](../../Tests/NXLibraryCoreTests/SteamPlaytimeSyncTests.swift) | Letture con o senza account, file illeggibili, file invariato, regole di pubblicazione e coda delle letture. |
| [NativeMacApplicationTests.swift](../../Tests/NXLibraryCoreTests/NativeMacApplicationTests.swift) | Fixture native, classificazione, traversal/link, metadata non regolari e header invalidi. |
| [SoundPackTests.swift](../../Tests/NXLibraryCoreTests/SoundPackTests.swift) | Verifica manifesti, ZIP, limiti, link, copia controllata, eventi mancanti e persistenza della scelta. |
| [OortAmbianceTests.swift](../../Tests/NXLibraryCoreTests/OortAmbianceTests.swift) | Copertura degli eventi, nomi nelle sette lingue, livello e picco, assenza di clic, carattere dei tre ambienti e note di Compose. |
| [SteamLibrarySourceTests.swift](../../Tests/NXLibraryCoreTests/SteamLibrarySourceTests.swift) | Più fonti, dischi assenti, identità, manifest/path con campi duplicati o di tipo errato, file cambiati, limiti e assenza di scritture. |
| [SteamDiscoveryConsistencyTests.swift](../../Tests/NXLibraryCoreTests/SteamDiscoveryConsistencyTests.swift) | Mutazioni reali di inventario e app durante scan, indice inizialmente assente, budget e propagazione dell'annullamento. |
| [SteamTestSupport.swift](../../Tests/NXLibraryCoreTests/SteamTestSupport.swift) | Genera solo metadati e header sintetici nelle directory temporanee dei test. |
| [Tests/ArcanePortingTests/SteamTestSupport.swift](../../Tests/ArcanePortingTests/SteamTestSupport.swift) | Collegamento simbolico a `NXLibraryCoreTests/SteamTestSupport.swift`: i test del modulo usano la stessa fixture Steam, da un solo file. |
| [SteamPlayStateTests.swift](../../Tests/NXLibraryCoreTests/SteamPlayStateTests.swift) | Symlink, passaggio senza sessione, Play doppi e risposte tardive, rifiuti e timeout, giochi già aperti, argomenti silenziosi, pazienza di Steam a freddo e schermata di lancio. |
| [SteamBinaryKeyValuesTests.swift](../../Tests/NXLibraryCoreTests/SteamBinaryKeyValuesTests.swift) | Tipi, annidamento, fine dei dati, input troncati, tipi ignoti e limiti del parser binario. |
| [SteamAchievementReaderTests.swift](../../Tests/NXLibraryCoreTests/SteamAchievementReaderTests.swift) | Percorsi, account e file mancanti/non sicuri, lingue con ripiego anche su stringhe vuote duplicate, primo valore tipizzato, nascosti, icone, ordine numerico e file corrotti. |
| [SteamAchievementRarityTests.swift](../../Tests/NXLibraryCoreTests/SteamAchievementRarityTests.swift) | Percentuali numeriche o testuali (non numeriche scartate), host e percorso ammessi, cache di un giorno, cache vecchia offline, icone in cache, coda oltre sei download con annullamento, errore recente senza attesa e file che non sono immagini. |
| [AchievementSummaryTests.swift](../../Tests/NXLibraryCoreTests/AchievementSummaryTests.swift) | Conteggi, gioco completato, ordini dei filtri, rarità sconosciute in fondo, soglia del raro, maschera dei nascosti e icone recenti (segreti compresi). |
| [LocalAchievementTests.swift](../../Tests/ArcanePortingTests/LocalAchievementTests.swift) | Fixture Zelda, soglie, versione e CRC, nessuna scrittura sul salvataggio, percorso `DM_SAVE`, persistenza per profilo con plist temporaneo e formato overlay. |
| [AchievementsScreenStateTests.swift](../../Tests/NXLibraryCoreTests/AchievementsScreenStateTests.swift) | Movimento in due colonne, bordi, liste vuote, cambio filtro e liste che si accorciano. |
| [GridListLayoutTests.swift](../../Tests/NXLibraryCoreTests/GridListLayoutTests.swift) | Linee, altezza, posizione delle righe, spazio da mostrare, linee visibili e riga in vista più vicina dopo la rotella. |
| [AchievementTierTests.swift](../../Tests/NXLibraryCoreTests/AchievementTierTests.swift) | Soglie, tier dalla percentuale mostrata, ordine dal più raro, conteggi per tier, Arcane solo al 100% e mai senza achievement, miglior tier ottenuto, rarità sconosciuta. |
| [SteamManifestWatcherTests.swift](../../Tests/NXLibraryCoreTests/SteamManifestWatcherTests.swift) | Filtri e durata dello stream; eventi reali da librerie tornate disponibili, da sole o accanto a una già osservata, inclusa la normalizzazione `/private`. |
| [CatalogPreservationTests.swift](../../Tests/ArcanePortingTests/CatalogPreservationTests.swift) | Giochi e fonti di un’integrazione sconosciuta: letti, invisibili, riscritti uguali, controlli di forma e duplicati, catalogo noto scritto come prima. |
| [CatalogModelTests.swift](../../Tests/ArcanePortingTests/CatalogModelTests.swift) | Conservazione del record precedente, proprietà comuni e separazione delle azioni per integrazione. |
| [CatalogStoreTests.swift](../../Tests/ArcanePortingTests/CatalogStoreTests.swift) | Conversione, backup, corruzione, versioni, input cambiati, scrittori concorrenti, guasti di pubblicazione e tipi noti disattivati in un nuovo profilo. |
| [MacShortcutTests.swift](../../Tests/NXLibraryCoreTests/MacShortcutTests.swift) | Aggiunta e deduplicazione, persistenza, app spostate o sostituite, ricollegamento e rimozione con bundle sintetici compilati. |
| [MacShortcutProbe.swift](../../Tests/CatalogAppChecks/MacShortcutProbe.swift) | Sorgenti, libreria e dialoghi EN/FR fuori schermo; Play mediante Launch Services della sola fixture compilata, senza sessioni né modifiche al bundle. |
| [ControllerIdentityProbe.swift](../../Tests/CatalogAppChecks/ControllerIdentityProbe.swift) | Twin, duplicati HID/GameController, pressioni, identificazione, sospensione e riconnessione con sorgenti sintetiche; ripiego HID senza refresh manuale. |
| [Beta4InputScreens.swift](../../Tests/CatalogAppChecks/Beta4InputScreens.swift) | Sonda fuori schermo per annunci della ricerca, pulsante di chiusura dell'avvio e attività del cursore in finestra. |
| [run_beta4_input_screens.py](../../Tests/CatalogAppChecks/run_beta4_input_screens.py) | Esegue le sonde schermate e cattura il pulsante di chiusura del lancio inattivo. |
| [run_beta4_input_routing.py](../../Tests/CatalogAppChecks/run_beta4_input_routing.py) | Verifica i tasti della shell e il riavvio di prova con monitor e processo fittizi. |
| [SteamCatalogReconcilerTests.swift](../../Tests/ArcanePortingTests/SteamCatalogReconcilerTests.swift) | Identità, aggiornamenti, installazioni ambigue, fonti assenti e scansioni obsolete/parziali. |
| [CatalogTestSupport.swift](../../Tests/ArcanePortingTests/CatalogTestSupport.swift) | Record legacy sintetico completo e scrittura di fixture; nessun contenuto di gioco. |
| [CatalogRepositoryTests.swift](../../Tests/ArcanePortingTests/CatalogRepositoryTests.swift) | Modifiche concorrenti, confini per integrazione, campi build, conservazione Steam/legacy e import cloud del programma NUP esatto. |
| [CatalogRecoveryTests.swift](../../Tests/ArcanePortingTests/CatalogRecoveryTests.swift) | Recupero esplicito, conflitto legacy senza fusione, archivi, offerte obsolete, guasti di pubblicazione, restore point e importazione Dev. |
| [CatalogPersonalizationTests.swift](../../Tests/ArcanePortingTests/CatalogPersonalizationTests.swift) | Rinomina senza perdita del lookup e isolamento di chiavi uguali tra fonti. |
| [CatalogBuildRecoveryTests.swift](../../Tests/ArcanePortingTests/CatalogBuildRecoveryTests.swift) | Vecchia build persistita e nuova conservata, sospensione automatica e conferme obsolete. |
| [run_notices.py](../../Tests/CatalogAppChecks/run_notices.py) | Esegue il modello e i metodi reali degli avvisi e del ponte legacy senza finestre, dopo swift test. |
| [run_onscreen_keyboard.py](../../Tests/CatalogAppChecks/run_onscreen_keyboard.py) | Avvia la prova della tastiera a schermo su una home isolata. |
| [run_update_wait.py](../../Tests/CatalogAppChecks/run_update_wait.py) | Bundle di prova: conserva l'aggiornamento verificato mentre un gioco o un lease blocca; riprende dallo ZIP senza rete e rifiuta modifiche. |
| [run_review.py](../../Tests/CatalogAppChecks/run_review.py) | Verifica senza finestre achievement, loghi, focus, input del centro e di Integrations, badge mod in Online, priorità dei dialoghi e Steam durante Play. |
| [audit_probe_host.py](../../Tests/CatalogAppChecks/audit_probe_host.py) | Collega sonde headless al binario di debug e le isola con home temporanea e senza rete. |
| [run_platform_cards.py](../../Tests/CatalogAppChecks/run_platform_cards.py) | Lancia Spotlight isolato e conserva i PNG e, con ffmpeg, lo scorrimento video. |
| [run_credits.py](../../Tests/CatalogAppChecks/run_credits.py) | Apre About isolata, conserva i PNG e prova i crediti con il controller. |
| [CreditsProbe.swift](../../Tests/CatalogAppChecks/CreditsProbe.swift) | Host della prova di About: tre lingue, tutte le schede, ordine delle righe e destinazione localizzata del finanziamento con browser simulato. |
| [PlatformCardsProbe.swift](../../Tests/CatalogAppChecks/PlatformCardsProbe.swift) | Verifica input, filtro, chiusura e recupero su tre fonti, una fonte e libreria vuota; rende Spotlight in francese con sfondo chiaro. |
| [run_steam_disabled_tracking.py](../../Tests/CatalogAppChecks/run_steam_disabled_tracking.py) | Disattiva una fonte Steam sintetica, chiude una sessione già aperta e rifiuta una nuova osservazione. |
| [run_steam_scoped_playtime.py](../../Tests/CatalogAppChecks/run_steam_scoped_playtime.py) | Aggiorna le ore Steam dopo sessioni Switch secondarie, anche archiviate, e congela dopo una sessione Steam secondaria. |
| [run_keymap_screens.py](../../Tests/CatalogAppChecks/run_keymap_screens.py) | Verifica tabelle Oort e Arcane, suggerimenti e glifi; rende le barre Selene senza aprire finestre. |
| [run_inbox_screens.py](../../Tests/CatalogAppChecks/run_inbox_screens.py) | Verifica e rende Inbox, menu e card; controlla Inbox disattivata, riletture, duplicati e sorgenti collegate durante il triage con preferenze e Cestino simulati. |
| [run_cloud_screens.py](../../Tests/CatalogAppChecks/run_cloud_screens.py) | Verifica Cloud, coda, accesso Google, scoperta delle sorgenti, spostamento, glifi, Play together e schermo su fixture locali. Separa schermate, trasferimenti, giochi solo cloud e risultati incompleti in processi con directory e preferenze proprie. Condivide l’isolamento dell’avvio nelle copie di test. Verifica anche il fornitore e la selezione di Rebuild. `--compare-with-5047557` confronta la scheda con Riduci movimento. |
| [run_cloud_assistant.py](../../Tests/CatalogAppChecks/run_cloud_assistant.py) | Disegna impostazioni e assistente in finestre nascoste, poi va dall’account ai giochi con la sola tastiera, il solo puntatore e il solo controller. |
| [CloudAssistantProbe.swift](../../Tests/CatalogAppChecks/CloudAssistantProbe.swift) | La sonda: schermate, percorsi completi, riconnessione, nomi per VoiceOver. |
| [fake_rclone.py](../../Tests/CatalogAppChecks/fake_rclone.py) | rclone sintetico: una cartella risponde come Drive, con attesa e conteggio. |
| [run_library_refresh.py](../../Tests/CatalogAppChecks/run_library_refresh.py) | Aggiornamento sul modello reale: cloud spento, fuori rete, ripetuto, annullato (catalogo intatto, scansione indipendente riuscita), interrotto, cartella sostituita; catture facoltative in francese e inglese. |
| [fake_drive_rclone.py](../../Tests/CatalogAppChecks/fake_drive_rclone.py) | Finto rclone con `rcd` su socket Unix e un Drive in un file JSON. |
| [run_download_cloud.py](../../Tests/CatalogAppChecks/run_download_cloud.py) | Con una destinazione esplicita, verifica pixel, contrasto e compositing del download; video facoltativo a 60 Hz e tabella dei livelli reali e visivi. |
| [run_cloud_queue_pause.py](../../Tests/CatalogAppChecks/run_cloud_queue_pause.py) | Riapre una coda sintetica con pausa registrata e confronta le righe Attività in francese prima e dopo, senza backend. |
| [run_cloud_pause.py](../../Tests/CatalogAppChecks/run_cloud_pause.py) | Verifica la pausa e la ripresa esplicita dopo riavvio, ordine e controlli in Cloud e Attività con un backend sintetico. |
| [run_cloud_shelf.py](../../Tests/CatalogAppChecks/run_cloud_shelf.py) | Rende lo scaffale Cloud in francese e verifica gli stati vuoti, i titoli importati e il recupero nell’assistente con fixture. |
| [run_cloud_reference.py](../../Tests/CatalogAppChecks/run_cloud_reference.py) | Rende il dialogo del riferimento e la riga con accesso, senza accesso e in controllo, usando dati sintetici. |
| [run_cloud_free_space.py](../../Tests/CatalogAppChecks/run_cloud_free_space.py) | Rende la conferma di liberazione con selezioni e lo stato di verifica, senza toccare il Cestino. |
| [run_store_next_step.py](../../Tests/CatalogAppChecks/run_store_next_step.py) | Rende le prossime azioni e gli stati passivi di Details in francese su dati sintetici. |
| [StoreNextStepOCR.swift](../../Tests/CatalogAppChecks/StoreNextStepOCR.swift) | Legge i PNG della sonda Details e verifica testi, origine e assenza di misure ripetute. |
| [run_cloud_personal_update.py](../../Tests/CatalogAppChecks/run_cloud_personal_update.py) | Esercita l’offerta personale, la conferma e le copie sostituite o conservate tramite un cloud e bundle sintetici. |
| [run_settings_confirmations.py](../../Tests/CatalogAppChecks/run_settings_confirmations.py) | Lancia la sonda di Settings con dati, selettore rclone e preferenze sintetici. |
| [SettingsConfirmationProbe.swift](../../Tests/CatalogAppChecks/SettingsConfirmationProbe.swift) | Prova bozza, conferme, collegamento rclone, blocco di ⌘K e avvisi di avvio fuori schermo. |
| [run_settings_confirmations.py](../../Tests/CatalogAppChecks/run_settings_confirmations.py) | Lancia la sonda delle conferme in un processo con dati e preferenze propri, in francese e senza servizi reali. |
| [SettingsConfirmationProbe.swift](../../Tests/CatalogAppChecks/SettingsConfirmationProbe.swift) | Verifica la bozza e le conferme separate di Cloud/rclone/motore e rende Settings con sfondo e riepilogo in una finestra non mostrata. |
| [AttentionsProbe.swift](../../Tests/CatalogAppChecks/AttentionsProbe.swift) | Undo, ricerche recenti, ripristino di una riga, copia delle impostazioni e suggerimenti in fr, de, en; solo questa parte con `OORT_ATTENTIONS_ONLY=1` in `run_settings_confirmations.py`. |
| [run_integration_contract.py](../../Tests/CatalogAppChecks/run_integration_contract.py) | Controlla il collegamento di Integrations alle viste reali senza aprirle. |
| [run_profiles.py](../../Tests/CatalogAppChecks/run_profiles.py) | Rende profili, raccolte, impostazioni, primo avvio e PIN. Verifica focus da Integrations, alone, moto ridotto, salvataggi e ripresa di Play dopo scambio cloud, firma o conferma VPN. Prova i collegamenti Mac su richiesta, sempre con preferenze temporanee. |
| [run_startup_recovery.py](../../Tests/CatalogAppChecks/run_startup_recovery.py) | Coordinatore di avvio reale su profili sintetici: avviso prima della scrittura, copia non valida, prosecuzione solo per l’avvio corrente, conflitto legacy e Retry; nessuna finestra. |
| [run_downgrade.py](../../Tests/CatalogAppChecks/run_downgrade.py) | Con un checkout 0.3.0 e una destinazione espliciti, collega i binari Debug, confronta letture e riscritture e ripristina entrambe le versioni su dati sintetici; rende l’avviso su richiesta. |
| [DowngradeProbe.swift](../../Tests/CatalogAppChecks/DowngradeProbe.swift) | Verifica i lettori e gli scrittori effettivi su sessioni, impostazioni, profili, catalogo, integrazioni, coda e stato cloud e immagini. |
| [run_source_access.py](../../Tests/CatalogAppChecks/run_source_access.py) | Esegue avvio, observer, selettori e preparazione dei file in Add Game: scansione limitata, cartella ricordata e riconoscimento del percorso estratto. |
| [run_catalog_removal.py](../../Tests/CatalogAppChecks/run_catalog_removal.py) | Prova il Cestino con arresti, concorrenza, file sostituiti e alias. Due avvii del profilo 0.3.0 sintetico verificano anche la coda cloud e la build in attesa. |
| [run_onboarding.py](../../Tests/CatalogAppChecks/run_onboarding.py) | Prova ripresa e chiusura del tour oltre ai casi legacy di Steam, modali e notifiche; può rendere le viste in francese su due taglie. |
| [run_artwork_return.py](../../Tests/CatalogAppChecks/run_artwork_return.py) | Viste, task e host Mods reali su fixture: primo body con arte warm, scelte personali, aggiornamenti Steam nello stesso percorso, badge dopo rimozione, cambi abbinamento e snapshot completato fuori ordine; nessuna finestra o rendering. |
| [run_nested_bundles.py](../../Tests/CatalogAppChecks/run_nested_bundles.py) | App sintetiche con bundle dati annidati e firme reali: installazione, icona, rollback, copia forzata, ripresa e rifiuto di dati alterati; nessuna UI. |
| [run_nup_programs.py](../../Tests/CatalogAppChecks/run_nup_programs.py) | Esegue il probe NUP opzionale su snapshot sintetico, convertitori UI reali, persistenza e argv del rebuild. |
| [run_add_game_back.py](../../Tests/CatalogAppChecks/run_add_game_back.py) | Esegue le regole di Back e verifica che poco spazio per compilare non blocchi l'aggiunta alla libreria. Nessuna finestra. |
| [run_build_cache_thread.py](../../Tests/CatalogAppChecks/run_build_cache_thread.py) | Verifica che l’adozione della cache a fine porting non venga eseguita sul thread dell’interfaccia. |
| [run_build_gates.py](../../Tests/CatalogAppChecks/run_build_gates.py) | Verifica il cambio motore e i limiti di annullamento per installazione e spostamento nel centro attività. |
| [run_controller_identity.py](../../Tests/CatalogAppChecks/run_controller_identity.py) | Compila la verifica dei pad con il servizio effettivo e senza periferiche fisiche. |
| [run_players_screen.py](../../Tests/CatalogAppChecks/run_players_screen.py) | Prova focus e stati con controller sintetici; rende anche Giocatori aperto da Impostazioni e Opzioni con sfondi a contrasto. |
| [run_build_queue_engine.py](../../Tests/CatalogAppChecks/run_build_queue_engine.py) | Verifica il collegamento tra la fine del cambio motore e il risveglio della coda, anche quando il clone non produce un motore valido. |
| [run_guest_quit.py](../../Tests/CatalogAppChecks/run_guest_quit.py) | Esegue il veto durante l’adozione della cache, la conferma ospite e l’uscita con esiti sintetici. |
| [run_profile_collection_game.py](../../Tests/CatalogAppChecks/run_profile_collection_game.py) | Verifica la selezione dei giochi Switch e Steam nel menu nativo della Collection di un profilo. |
| [run_logo_cancellation.py](../../Tests/CatalogAppChecks/run_logo_cancellation.py) | Verifica il recupero del logo tornando prima che la ricerca annullata finisca, senza rete. |
| [run_metadata_preload.py](../../Tests/CatalogAppChecks/run_metadata_preload.py) | Verifica le letture fuori dal main thread, la pubblicazione sul main thread e lo scarto dei risultati dopo lo svuotamento (EN/FR). |
| [run_spotlight_notification_select.py](../../Tests/CatalogAppChecks/run_spotlight_notification_select.py) | Verifica la selezione da una notifica, anche chiudendo Add Game mentre è in corso un altro porting. |
| [run_sort_native_menu.py](../../Tests/CatalogAppChecks/run_sort_native_menu.py) | Verifica disponibilità e consegna di Gioca dal menu nativo con l’ordinamento aperto. |
| [run_empty_collection_input.py](../../Tests/CatalogAppChecks/run_empty_collection_input.py) | Invia comandi di navigazione alla Collection vuota e verifica Aggiungi gioco e Importa build esistenti. |
| [run_hero_cache_budget.py](../../Tests/CatalogAppChecks/run_hero_cache_budget.py) | Verifica che le cache degli sfondi ricevano i byte decodificati e abbiano un limite di costo. |
| [run_collection_query_count.py](../../Tests/CatalogAppChecks/run_collection_query_count.py) | Conta le valutazioni della query di Collection con una selezione Switch su 300 giochi sintetici. |
| [run_save_restart.py](../../Tests/CatalogAppChecks/run_save_restart.py) | Arresti reali e nuovi processi nei checkpoint di transazione, recovery e pulizia; verifica tutti gli utenti, registro e integrità dei backup su fixture temporanee. |
| [run_save_profile_isolation.py](../../Tests/CatalogAppChecks/run_save_profile_isolation.py) | Un recupero fallito in un profilo non impedisce a un altro di giocare allo stesso titolo. |
| [run_save_unreadable_profile.py](../../Tests/CatalogAppChecks/run_save_unreadable_profile.py) | Profili illeggibili: rifiuta contesto, backup, apertura cartella e recupero dei salvataggi originali. |
| [run_install_profiles_wiring.py](../../Tests/CatalogAppChecks/run_install_profiles_wiring.py) | Verifica che il rifiuto dei profili raggiunga worker, retry e dialogo d'installazione. |
| [run_entrance.py](../../Tests/CatalogAppChecks/run_entrance.py) | Esegue i metodi reali di input e readiness: nessun comando agisce o salta l’entrata prima dell’atterraggio, clic su Profili, precedenza delle coperture, drawable mancante e presentazione su entrambi i percorsi. Nessuna finestra o GPU reale. |
| [run_icon_cache.py](../../Tests/CatalogAppChecks/run_icon_cache.py) | Esegue il vero `GameIconProvider`: un gioco senza icona non si rilegge dal disco a ogni disegno; dopo `forget` o la build si legge di nuovo. |
| [run_theme.py](../../Tests/CatalogAppChecks/run_theme.py) | Regressioni delle richieste condivise (precedenza, frame mantenuto e pausa) e del cambio palette a wallpaper/card invariati con snapshot e apply reali, ordine Look e input del selettore; shader Metal fuori schermo, colori locali GPU/Core, profilo sottile, deformazione delle onde, superfici distinte, frame fermo e uniform Mods. |
| [run_achievement_scroll.py](../../Tests/CatalogAppChecks/run_achievement_scroll.py) | Verifica fuori schermo lista, LB/RB in filtri e dettagli, riaperture rapide, ridimensionamento e Riduci movimento. |
| [run_mods_band_scroll.py](../../Tests/CatalogAppChecks/run_mods_band_scroll.py) | Verifica fuori schermo che la riga Mods a fuoco resti intera in Spotlight e Details e che la rotella raggiunga l’ultima riga. |
| [run_online_players.py](../../Tests/CatalogAppChecks/run_online_players.py) | Rende fuori schermo Spotlight, Collection, scheda e Settings con giochi e conteggi sintetici: default, tutto acceso e tutto spento. |
| [run_game_header.py](../../Tests/CatalogAppChecks/run_game_header.py) | Esegue i corpi reali di logo e azioni condivisi senza finestra né store applicativi, per entrambi i layout. |
| [NoticeHost.swift](../../Tests/CatalogAppChecks/NoticeHost.swift) | Host minimo per Retry, annullamento e ordine delle scelte Rebuild, con storage reale e dati sintetici temporanei. |
| [SharedGamePresentationTests.swift](../../Tests/ArcanePortingTests/SharedGamePresentationTests.swift) | Presentazione Steam con identità, personalizzazioni e cronologia; prima installazione disponibile coerente per artwork e dettagli, con Play bloccato se ambiguo; confine nxnative e opzioni comuni. |
| [Tests/NXLibraryCoreTests/GamePlayTests.swift](../../Tests/NXLibraryCoreTests/GamePlayTests.swift) | Registra un terzo connettore finto senza modificare il chiamante e verifica target, profilo, disponibilità e risultati distinti. |
| [CatalogSourcesRepositoryTests.swift](../../Tests/ArcanePortingTests/CatalogSourcesRepositoryTests.swift) | Compatibilità generazioni, cambi fonte, preferenze concorrenti e adozione NX esplicita. |
| [CatalogSourcesModelTests.swift](../../Tests/ArcanePortingTests/CatalogSourcesModelTests.swift) | Opt-in, annullamento, cambio radice, recupero errori e intervallo tra riscansioni, misurato dagli avvii pubblicati dal modello. |
| [CatalogLibraryQueryTests.swift](../../Tests/ArcanePortingTests/CatalogLibraryQueryTests.swift) | Visibilità, ricerca/filtri misti e selezione per UUID senza sessioni simulate. |
| [SteamOptionsTests.swift](../../Tests/ArcanePortingTests/SteamOptionsTests.swift) | Righe delle opzioni Steam come quelle comuni nxnative, niente di nxnative, Play e Finder spenti senza installazione, artwork e impostazione «Keep Steam in the background». |
| [SteamMetadataTests.swift](../../Tests/NXLibraryCoreTests/SteamMetadataTests.swift) | Identità, lingue, offline, URL, concorrenza, tratti correlati in cache ed esito del salvataggio. |
| [SteamArtworkRequestTests.swift](../../Tests/NXLibraryCoreTests/SteamArtworkRequestTests.swift) | Quadrato dall’icona originale e mai dalla copertina, scelta personale prima, link che escono dal bundle ignorati, icona automatica solo senza app. |
| [SteamAutomaticIconTests.swift](../../Tests/NXLibraryCoreTests/SteamAutomaticIconTests.swift) | Quadrato LaunchBox della voce PC preso intero, scaricato una volta e conservato; nessun quadrato non si richiede di nuovo nella sessione. |
| [SteamBackdropChoiceTests.swift](../../Tests/NXLibraryCoreTests/SteamBackdropChoiceTests.swift) | Solo arte in formato schermo, ordine store → screenshot → banner, fan art LaunchBox fra store e screenshot, ripiego sulla prima immagine che si carica. |
| [test_app_bundle.py](../../Tests/PublicationChecks/test_app_bundle.py) | Verifica Game Mode, iniezione della coppia OAuth nel plist solo se completa e rifiuto delle variabili in pubblicazione. |

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
| [Tests/PublicationChecks/test_oort_tokens.py](../../Tests/PublicationChecks/test_oort_tokens.py) | Prova generazione stabile, output obsoleti e contrasto insufficiente. |
| [scripts/check_oort_core.py](../../scripts/check_oort_core.py) | Verifica manifest e import del target portabile; può preparare un pacchetto minimo per Linux. |
| [scripts/generate_credits.py](../../scripts/generate_credits.py) | Copia i crediti in app, NOTICE e sito; le voci `noticeOnly` restano solo nel NOTICE. Fallisce se manca un credito o una copia differisce. |
| [scripts/selene-token-debt.json](../../scripts/selene-token-debt.json) | Occorrenze letterali preesistenti per file e firma, escluse le misure già migrate ai token; le voci obsolete fanno fallire il controllo. |
| [Tests/PublicationChecks/test_selene_tokens.py](../../Tests/PublicationChecks/test_selene_tokens.py) | Prova argomenti multilinea, valori scalati ed esclusioni. |
| [scripts/check_ui_rules.py](../../scripts/check_ui_rules.py) | Misura menu, profondità, testi senza traduzione, misure e forme locali, nomi di accessibilità, ordine dei pulsanti, focus iniziale pericoloso e percorsi da tastiera e mouse; blocca il nuovo. |
| [scripts/ui-rules.json](../../scripts/ui-rules.json) | Superfici contate, valori, righe di pulsanti note, percorsi dichiarati di mouse e tastiera, parti non misurate e debito che può solo diminuire. |
| [Tests/UIRulesChecks/test_ui_rules.py](../../Tests/UIRulesChecks/test_ui_rules.py) | Prove negative di ogni regola e coerenza fra controllo, criteri e skill. |
| [Tests/PublicationChecks/test_credits.py](../../Tests/PublicationChecks/test_credits.py) | Prova che una dipendenza senza credito, un NOTICE o un sito diversi falliscono. |
| [scripts/check_metadata_text_layout.swift](../../scripts/check_metadata_text_layout.swift) | Verifica fuori schermo il layout delle descrizioni e la destinazione dello scroll dopo cambi di focus, anche rapidi e con Riduci movimento. |
| [check_app_profile.swift](../../scripts/check_app_profile.swift) | Prova senza UI di identità, accesso reale alle preferenze e percorsi nel pacchetto prodotto dalla build; non importa né scrive dati. |

## Risorse incluse

| File | Responsabilità aggiuntiva |
|---|---|
| [Resources/IconArtwork.png](../../Resources/IconArtwork.png) | Master quadrato originale dell’icona (cristallo nella sfera di vetro), fornito dall’utente e creato con AI. |
| [Resources/IconArtwork.md](../../Resources/IconArtwork.md) | Riproduzione delle icone native e Dock, e provenienza del cristallo originale. |
| [crystal-arcane.png](../../Sources/NXLibraryCore/Resources/crystal-arcane.png) | Immagine ferma del trofeo Arcane, anche come ripiego del video. |
| [crystal-arcane.mov](../../Sources/NXLibraryCore/Resources/crystal-arcane.mov) | Animazione con alpha del trofeo Arcane. |
| [achievements-01006BB00C6F0000.json](../../Sources/NXLibraryCore/Resources/achievements-01006BB00C6F0000.json) | Pack degli obiettivi locali di Link’s Awakening in sette lingue. |
| [crystal-gold.png](../../Sources/NXLibraryCore/Resources/crystal-gold.png) | Immagine del trofeo Oro. |
| [crystal-silver.png](../../Sources/NXLibraryCore/Resources/crystal-silver.png) | Immagine del trofeo Argento. |
| [crystal-bronze.png](../../Sources/NXLibraryCore/Resources/crystal-bronze.png) | Immagine del trofeo Bronzo. |

| File | Responsabilità |
|---|---|
| [Resources/AppIcon.icon/icon.json](../../Resources/AppIcon.icon/icon.json) | Icona Icon Composer a trama: sfondo, livelli e colori. |
| [Resources/AppIcon.icon/Assets/glyph.svg](../../Resources/AppIcon.icon/Assets/glyph.svg) | Livello vettoriale della trama. |
| [Resources/AppIcon.icon/Assets/sun.svg](../../Resources/AppIcon.icon/Assets/sun.svg) | Livello vettoriale del Sole. |
| [Resources/AppIconParticles.icon/icon.json](../../Resources/AppIconParticles.icon/icon.json) | Sorgente Icon Composer per le immagini del Dock a particelle. |
| [Resources/AppIconParticles.icon/Assets/glyph.svg](../../Resources/AppIconParticles.icon/Assets/glyph.svg) | Livello vettoriale delle particelle. |
| [Resources/AppIconParticles.icon/Assets/sun.svg](../../Resources/AppIconParticles.icon/Assets/sun.svg) | Livello vettoriale del Sole nella variante a particelle. |
| [Resources/AppIcon.icns](../../Resources/AppIcon.icns) | Ripiego `.icns` della trama. |
| [Resources/AppIcon-Light.png](../../Resources/AppIcon-Light.png) | Anteprima chiara della trama nel README. |
| [Resources/AppIcon-Particles-Dark.png](../../Resources/AppIcon-Particles-Dark.png) | Icona Dock a particelle scura. |
| [Resources/AppIcon-Particles-Light.png](../../Resources/AppIcon-Particles-Light.png) | Icona Dock a particelle chiara. |
| [Resources/Selene/palettes.json](../../Resources/Selene/palettes.json) | Catalogo delle 26 palette: Oort predefinito, blu classico Arcane e superfici opzionali Crystal e Flow. |
| [Resources/Selene/Fonts/MaterialIcons-Regular.ttf](../../Resources/Selene/Fonts/MaterialIcons-Regular.ttf) | Font dei glifi Material Icons disegnati dalla UI. |
| [Resources/Selene/Fonts/MaterialIcons-LICENSE.txt](../../Resources/Selene/Fonts/MaterialIcons-LICENSE.txt) | Licenza del font Material Icons incluso. |
| [Resources/Selene/NOTICE.txt](../../Resources/Selene/NOTICE.txt) | Attribuzioni delle risorse Selene incluse. |
| [Resources/Brands/Platforms/LICENSE-Lucide.txt](../../Resources/Brands/Platforms/LICENSE-Lucide.txt) | Licenza ISC e nota Feather MIT. |
| [Resources/Brands/Credits/arcane.png](../../Resources/Brands/Credits/arcane.png) | Icona di Arcane, dal suo deposito MIT, solo per il credito. |
| [Resources/Brands/Credits/playnite.png](../../Resources/Brands/Credits/playnite.png) | Icona di Playnite, dal suo deposito MIT, solo per il credito. |
| [Resources/Brands/Credits/selene.png](../../Resources/Brands/Credits/selene.png) | Icona di Selene, dal suo deposito MIT, solo per il credito. |
| [Buy Me a Coffee.svg](../../Resources/Brands/Platforms/Marks/Buy%20Me%20a%20Coffee.svg) | Simbolo piattaforma revisionato; fonte e impronta nel manifesto licenze. |
| [CrossOver.svg](../../Resources/Brands/Platforms/Marks/CrossOver.svg) | Simbolo piattaforma revisionato; fonte e impronta nel manifesto licenze. |
| [Epic Games.svg](../../Resources/Brands/Platforms/Marks/Epic%20Games.svg) | Simbolo piattaforma revisionato; fonte e impronta nel manifesto licenze. |
| [GOG.svg](../../Resources/Brands/Platforms/Marks/GOG.svg) | Simbolo piattaforma revisionato; fonte e impronta nel manifesto licenze. |
| [Google Drive.svg](../../Resources/Brands/Platforms/Marks/Google%20Drive.svg) | Simbolo piattaforma revisionato; fonte e impronta nel manifesto licenze. |
| [Nintendo Switch 2.svg](../../Resources/Brands/Platforms/Marks/Nintendo%20Switch%202.svg) | Simbolo piattaforma revisionato; fonte e impronta nel manifesto licenze. |
| [Nintendo Switch.svg](../../Resources/Brands/Platforms/Marks/Nintendo%20Switch.svg) | Simbolo piattaforma revisionato; fonte e impronta nel manifesto licenze. |
| [Steam.svg](../../Resources/Brands/Platforms/Marks/Steam.svg) | Simbolo piattaforma revisionato; fonte e impronta nel manifesto licenze. |
| [Resources/Brands/Platforms/NOTICE.txt](../../Resources/Brands/Platforms/NOTICE.txt) | Provenienza e nota sui marchi. |
| [Resources/Brands/Platforms/arrow-left-right.svg](../../Resources/Brands/Platforms/arrow-left-right.svg) | Simbolo generico CrossOver. |
| [Resources/Brands/Platforms/boxes.svg](../../Resources/Brands/Platforms/boxes.svg) | Simbolo generico Minecraft. |
| [Resources/Brands/Platforms/cloud.svg](../../Resources/Brands/Platforms/cloud.svg) | Simbolo Lucide per i salvataggi iCloud. |
| [Resources/Brands/Platforms/image.svg](../../Resources/Brands/Platforms/image.svg) | Simbolo Lucide per immagini e valutazioni. |
| [Resources/Brands/Platforms/network.svg](../../Resources/Brands/Platforms/network.svg) | Simbolo Lucide per Nextendo. |
| [Resources/Brands/Platforms/coffee.svg](../../Resources/Brands/Platforms/coffee.svg) | Tazza generica per il collegamento di sostegno. |
| [Resources/Brands/Platforms/disc-3.svg](../../Resources/Brands/Platforms/disc-3.svg) | Simbolo generico Steam. |
| [Resources/Brands/Platforms/gamepad-2.svg](../../Resources/Brands/Platforms/gamepad-2.svg) | Simbolo generico Switch e base del segno Switch 2. |
| [Resources/Brands/Platforms/hard-drive.svg](../../Resources/Brands/Platforms/hard-drive.svg) | Simbolo generico Google Drive. |
| [Resources/Brands/Platforms/laptop.svg](../../Resources/Brands/Platforms/laptop.svg) | Simbolo generico dei collegamenti alle app Mac. |
| [Resources/Brands/Platforms/package.svg](../../Resources/Brands/Platforms/package.svg) | Simbolo generico GOG. |
| [Resources/Brands/Platforms/shield.svg](../../Resources/Brands/Platforms/shield.svg) | Simbolo generico Epic Games. |
| [Resources/Selene/NOTICE-palettes.txt](../../Resources/Selene/NOTICE-palettes.txt) | Attribuzioni delle palette incluse con esse. |
| [Resources/ThirdPartyLicenses/omarchy-LICENSE.txt](../../Resources/ThirdPartyLicenses/omarchy-LICENSE.txt) | Testo MIT di Omarchy per le palette derivate. |
| [Resources/ThirdPartyLicenses/python-LICENSES.txt](../../Resources/ThirdPartyLicenses/python-LICENSES.txt) | Licenze delle dipendenze native di CPython, Tcl/Tk e delle estensioni. |
| [Resources/ThirdPartyLicenses/rclone-LICENSES.txt](../../Resources/ThirdPartyLicenses/rclone-LICENSES.txt) | Licenze e avvisi di rclone, delle dipendenze Go incluse e della libreria standard. |
| [Resources/ThirdPartyLicenses/wheel-NOTICES.txt](../../Resources/ThirdPartyLicenses/wheel-NOTICES.txt) | Avvisi aggiuntivi per il codice incorporato nelle wheel Python. |
| [Resources/Selene/Sounds/Boot.wav](../../Resources/Selene/Sounds/Boot.wav) | Cue sonoro incluso per l’avvio. |
| [Resources/Selene/Sounds/Key.wav](../../Resources/Selene/Sounds/Key.wav) | Cue sonoro incluso per la pressione dei tasti. |
| [Resources/Selene/Sounds/Success.wav](../../Resources/Selene/Sounds/Success.wav) | Cue sonoro incluso per il completamento di un’azione. |
| [Resources/Selene/Sounds/navigation.wav](../../Resources/Selene/Sounds/navigation.wav) | Cue sonoro incluso per la navigazione. |
| [Resources/SoundPacks/oort.oortsound](../../Resources/SoundPacks/oort.oortsound) | Manifesto CC0 e dieci cue WAV originali; firma punto/risposta al ritorno. |
| [Resources/SoundPacks/pollen.oortsound](../../Resources/SoundPacks/pollen.oortsound) | Manifesto CC0 e dodici cue WAV chiari e brevi. |
| [Resources/SoundPacks/umbra.oortsound](../../Resources/SoundPacks/umbra.oortsound) | Manifesto CC0 e dodici cue WAV morbidi. |
| [Resources/SoundPacks/impulsion.oortsound](../../Resources/SoundPacks/impulsion.oortsound) | Manifesto CC0 e dodici cue WAV elettronici. |

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

## Aggiornare questo catalogo

Quando si aggiunge, rinomina o rimuove un file versionato, aggiornare la sua riga nella sezione della sua area e il totale iniziale; una funzione nuova non apre una sezione in fondo al catalogo. Le regole complete sono in [conventions.md](conventions.md#10-documentazione). Quando cambia un flusso o una responsabilità, aggiornare anche la sezione corrispondente della guida tecnica. Le descrizioni dei test indicano l’ambito dei controlli, mentre l’esito di esecuzione appartiene ai rapporti di verifica.
