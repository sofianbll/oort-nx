# OortUI · inventario dei componenti

`Sources/NXLibrary/Views/OortUI` contiene le implementazioni Selene condivise.
I tipi con prefisso `Selene` restano disponibili per la migrazione.

| Componente | Scopo e uso | Preset / stati | Usare · evitare |
|---|---|---|---|
| `OortPage` | Pagina con titolo, scorrimento, ritorno e suggerimenti | `standard` opaco; `legacyBackdrop` solo per preservare pagine precedenti | Passare l'identità del focus · non aggiungere una seconda barra. |
| `OortSettingsShell`, `OortSettingsSidebar`, `OortSettingsLink` | Barra di categorie e dettaglio con titolo e ritorno | Selezione separata dal focus, secondo livello per argomenti autonomi | Passare il contenuto; non definire lo stile nella schermata. |
| `OortSection` | Raggruppare righe sotto un titolo | Standard | Usare quando cambia il gruppo · non simulare un titolo con colore e dimensione. |
| `OortRow` | Aprire una pagina o descrivere una funzione | Navigazione, informazione; focus, stato scritto | Un'azione per riga · non annidare pulsanti. |
| `SeleneValueRow`, `SeleneCycleRow`, `SeleneToggleRow`, `SeleneButtonRow`, `OortSliderRow` | Mostrare/modificare un valore nelle impostazioni | Valore, scelta, interruttore, azione, cursore | Conservare valore e azione distinti · non attivare al focus. |
| `OortCard` (`SelenePanel`) | Superficie condivisa per informazioni o controlli correlati | Titolo e info facoltativi | Comporre righe · non annidare schede per creare margini. |
| `OortGameTile` | Tessera con arte fornita dal chiamante | `spotlight`, `collection`; selezionata o no | Separare selezione da attivazione · non aggiungere un secondo anello. |
| `oortSecondaryClick` | Clic destro o Ctrl-clic: le opzioni del pezzo | Azione o nessuna | Raddoppia un comando già visibile · mai l'unica via. |
| `OortButton` | Azione isolata nella pillola Selene | `action`, `compact`; pronto, bloccato, in corso, focus | Dare un verbo al titolo · non attivare un lavoro già in corso. |
| `SeleneConfirmDialog`, `SeleneChoiceDialog`, `SeleneSuccessNotice` | Conferma, scelta o messaggio | Conferma, lista di scelte, messaggio | Azione primaria a sinistra, focus iniziale sicuro · nascondere l'aiuto sottostante. |
| `OortActionBar`, `OortQuestion` | Piede di un pannello o di una domanda | Ruoli `destructive`, `back`, `secondary`, `primary` | Dare il ruolo, non la posizione: ritorno a sinistra, azione principale ultima a destra · per ora solo l'assistente cloud. |
| `OortAssistantPanel`, `OortFolderCard` | Compito in pochi passi; una cartella con domanda, percorso e contenuto | Passo fatto, corrente, futuro | Un compito lungo · non una semplice domanda. |
| `SeleneValueChip`, `OortStatus` | Valore breve o stato scritto | Testo/simbolo; neutro, in corso, attenzione, pronto | Scrivere lo stato · non affidarlo a colore o animazione. |
| `PlatformLabel`, `PlatformMark` | Nome leggibile e marchio piattaforma | Intestazione, riga, riepilogo, didascalia, setup, elenco | Usare il marchio con il nome · non aggiungere un secondo disegno. |
| `OortField` (`SeleneFieldSurface`) | Applicare al campo la superficie Selene | Focus o riposo | Passare il focus del campo · non ridefinire il contorno. |
| `OortFilePicker`, `OortFormatBadges` | Navigare il disco e spiegare i formati | Cartella, file Switch, prod.keys | Passare tipi accettati e callback; il selettore non legge il contenuto dei file. |
| `OortEmptyState` | Spiegare l'assenza di contenuto | Standard | Nominare ciò che manca · non confondere vuoto e caricamento. |
| `SeleneHintsBar` | Mostrare le azioni del livello attivo | Tastiera e layout manetta; coperta, visibile | Legare gli hint alle azioni reali · non duplicare il ritorno. |
| `OortPlayerSlot` | Una posizione di gioco, con ritratto e controller | Vuota o occupata; focus, selezione, indicatore | Conservare l'altezza e il nome accessibile · non ridimensionare la griglia al cambio di controller. |
| `OortSegmented` | Scelta esclusiva e immediata | `compact`, `modeBar`; scelta e focus distinti | Muovere il focus senza cambiare modalità · attivare solo su conferma. |
| `OortSearchField` | Cercare in una pagina o in una lista | `page`, `list`; focus, testo da cancellare | Un campo per schermata · non disegnare un'altra lente. |
| `OortKeyboard`, `OortKeyboardLayer` | Scrivere col controller in qualunque campo di testo | Lettere, simboli, accenti; maiuscole; campo segreto | Nessun codice nel campo: usare un `TextField` con `focused` · non disegnare altri tasti. |
| `OortTabs` | Passare tra viste sorelle | Scelta, focus, conteggio, simbolo | La scelta resta piena, il focus è un anello · non usarle per un'azione. |
| `OortTag` | Un fatto breve | `quiet`, `panel`, `art`; tono con la sua parola | Mai un pulsante · mai il colore da solo. |
| `OortMeter` | Avanzamento | Misurato o indeterminato | Accompagnarlo con il testo dello stato. |
| `OortControllerView` | Mostrare il controller e ciò che preme | `ControllerShape.Kind` (Xbox, PlayStation, Switch Pro, Joy-Con), ingressi vivi, movimento ridotto | Dentro un pannello · non un elemento interattivo. |
| `OortControllerMap` | Dire a ogni tasto cosa fa, con una linea | Tipo, voci (tasto, nome, azione, tenuta) | Pagina Comandi e guide · le linee non si incrociano. |
| `OortCreditCard`, `OortCreditGroup`, `OortCreditGrid` | Un progetto citato: segno, nome, autore e licenza, ruolo, freccia | Immagine, piattaforma o segno; focus | Dati solo da `design/credits.json` · mai un link colorato nel testo. |
| `oortPanel`, `oortWell`, `oortRing` | Superficie, incavo e anello di focus condivisi | Sollevato, fluttuante; contrasto aumentato | Nessuna forma disegnata a mano in una schermata. |

Per verificare una composizione usare la [galleria Debug](development.md#debug-configuration)
e `python3 scripts/check_selene_tokens.py --base HEAD`. Le voci esistenti del
debito possono essere rimosse con `--prune`, mai aumentate.
