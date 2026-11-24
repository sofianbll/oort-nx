# OortUI · inventario dei componenti

`Sources/NXLibrary/Views/OortUI` contiene le implementazioni Selene condivise.
I tipi con prefisso `Selene` restano disponibili per la migrazione.

| Componente | Scopo e uso | Preset / stati | Usare · evitare |
|---|---|---|---|
| `OortPage` | Pagina con titolo, scorrimento, ritorno e suggerimenti | `standard` opaco; `legacyBackdrop` solo per preservare pagine precedenti | Passare l'identità del focus · non aggiungere una seconda barra. |
| `OortSection` | Raggruppare righe sotto un titolo | Standard | Usare quando cambia il gruppo · non simulare un titolo con colore e dimensione. |
| `OortRow` | Aprire una pagina o descrivere una funzione | Navigazione, informazione; focus, stato scritto | Un'azione per riga · non annidare pulsanti. |
| `SeleneValueRow`, `SeleneCycleRow`, `SeleneToggleRow`, `SeleneButtonRow`, `OortSliderRow` | Mostrare/modificare un valore nelle impostazioni | Valore, scelta, interruttore, azione, cursore | Conservare valore e azione distinti · non attivare al focus. |
| `OortCard` (`SelenePanel`) | Superficie condivisa per informazioni o controlli correlati | Titolo e info facoltativi | Comporre righe · non annidare schede per creare margini. |
| `OortGameTile` | Tessera con arte fornita dal chiamante | `spotlight`, `collection`; selezionata o no | Separare selezione da attivazione · non aggiungere un secondo anello. |
| `OortButton` | Azione isolata nella pillola Selene | `action`, `compact`; pronto, bloccato, in corso, focus | Dare un verbo al titolo · non attivare un lavoro già in corso. |
| `SeleneConfirmDialog`, `SeleneChoiceDialog`, `SeleneSuccessNotice` | Conferma, scelta o messaggio | Conferma, lista di scelte, messaggio | Azione primaria a sinistra, focus iniziale sicuro · nascondere l'aiuto sottostante. |
| `SeleneValueChip`, `OortStatus` | Valore breve o stato scritto | Testo/simbolo; neutro, in corso, attenzione, pronto | Scrivere lo stato · non affidarlo a colore o animazione. |
| `PlatformLabel`, `PlatformMark` | Nome leggibile e marchio piattaforma | Intestazione, riga, riepilogo, didascalia, setup, elenco | Usare il marchio con il nome · non aggiungere un secondo disegno. |
| `OortField` (`SeleneFieldSurface`) | Applicare al campo la superficie Selene | Focus o riposo | Passare il focus del campo · non ridefinire il contorno. |
| `OortEmptyState` | Spiegare l'assenza di contenuto | Standard | Nominare ciò che manca · non confondere vuoto e caricamento. |
| `SeleneHintsBar` | Mostrare le azioni del livello attivo | Tastiera e layout manetta; coperta, visibile | Legare gli hint alle azioni reali · non duplicare il ritorno. |
| `OortPlayerSlot` | Una posizione di gioco, con ritratto e controller | Vuota o occupata; focus, selezione, indicatore | Conservare l'altezza e il nome accessibile · non ridimensionare la griglia al cambio di controller. |
| `OortSegmented` | Scelta esclusiva e immediata | `compact`, `modeBar`; scelta e focus distinti | Muovere il focus senza cambiare modalità · attivare solo su conferma. |

Per verificare una composizione usare la [galleria Debug](development.md#debug-configuration)
e `python3 scripts/check_selene_tokens.py --base HEAD`. Le voci esistenti del
debito possono essere rimosse con `--prune`, mai aumentate.
