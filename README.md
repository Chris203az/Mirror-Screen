# MirrorScreen

App per macOS che mostra in tempo reale lo schermo di un iPad collegato via cavo USB. Usa lo stesso meccanismo di QuickTime Player (CoreMediaIO + AVFoundation), quindi sull'iPad non serve installare niente. Niente audio e niente registrazione su disco.

## Requisiti

- macOS 14 o successivo, Xcode 16 o successivo
- iPad sbloccato, collegato via USB, che abbia già autorizzato questo Mac («Autorizza questo computer»)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) per generare il progetto Xcode

## Compilare ed eseguire

```sh
brew install xcodegen
xcodegen generate
open MirrorScreen.xcodeproj
```

In Xcode premi Run (⌘R). Al primo avvio macOS chiede l'accesso alla Fotocamera: serve perché il sistema tratta l'iPad come una sorgente video. Se vuoi una firma stabile (così il permesso non viene richiesto a ogni build), scegli il tuo Apple ID in *Signing & Capabilities*.

In alternativa, ogni build su GitHub Actions produce un artefatto `MirrorScreen.zip` con l'app firmata ad hoc. Dopo averla scaricata: `xattr -dr com.apple.quarantine MirrorScreen.app`, poi aprila.

## Funzioni

Tutte le funzioni extra si possono spegnere dal menu Mirroring o dalle Impostazioni (⌘,), così è facile decidere quali tenere.

| Funzione | Dove | Scorciatoia |
| --- | --- | --- |
| Mirroring automatico al collegamento | sempre attivo | |
| Avviso di blocco o scollegamento, ripresa automatica | sempre attivo | |
| Finestra in proporzione con l'iPad, anche dopo una rotazione | sempre attivo | |
| Dimensione finestra: 50%, 75%, reale, adatta allo schermo | Mirroring › Dimensione finestra | ⌘1, ⌘2 |
| Schermo intero | Mirroring / Vista | ⌃⌘F |
| Modalità presentazione: niente barra del titolo, finestra trascinabile dall'immagine | Mirroring, Impostazioni › Generale | ⇧⌘P |
| Sempre in primo piano | Mirroring | ⇧⌘T |
| Zoom nell'immagine: pizzico sul trackpad, ⌥ + scroll, trascina o scrolla per spostarti, doppio clic per tornare al 100% | Mirroring | ⌘=, ⌘-, ⌘0 |
| Congela immagine (l'iPad continua, la finestra resta ferma) | Mirroring, barra dei menu | spazio |
| Copia schermata negli appunti (niente su disco) | Mirroring | ⇧⌘C |
| Ispettore pixel: coordinate in pixel e punti, colore esadecimale, clic per copiarlo | Mirroring | ⌥⌘I |
| Griglia sovrapposta: terzi o griglia da 8 pt | Mirroring, Impostazioni › Aspetto | |
| Angoli arrotondati come l'iPad | Mirroring, Impostazioni › Aspetto | |
| Statistiche: risoluzione, formato, fps, frame persi | Mirroring, Impostazioni › Avanzate | ⌘I |
| Riconnetti e scelta del dispositivo | Mirroring | ⌘R |
| Sfondo nero, grigio scuro o bianco | Impostazioni › Aspetto | |
| Opacità della finestra | Impostazioni › Aspetto | |
| Cursore che si nasconde quando è fermo sull'immagine | Impostazioni › Aspetto | |
| Impedisce lo stop dello schermo durante il mirroring | Impostazioni › Generale | |
| Icona nella barra dei menu (chiudendo la finestra l'app resta attiva) | Impostazioni › Generale | |
| Avvio al login | Impostazioni › Generale | |
| Notifiche di collegamento e scollegamento quando l'app è in secondo piano | Impostazioni › Generale | |
| Motore di visualizzazione alternativo e formato pixel (per i test) | Impostazioni › Avanzate | |
| Soglia per l'avviso di blocco | Impostazioni › Avanzate | |

## Come funziona

1. All'avvio l'app imposta `kCMIOHardwarePropertyAllowScreenCaptureDevices`, così l'iPad compare come dispositivo di cattura esterno.
2. `DeviceMonitor` osserva collegamenti e scollegamenti.
3. `CaptureController` apre una `AVCaptureSession` con solo l'uscita video, alla risoluzione più alta disponibile.
4. `FrameHub` passa ogni frame a un `AVSampleBufferDisplayLayer` (mostrato subito, senza code) e tiene il conto dei frame.
5. `MirrorStateMachine` decide cosa mostrare: attesa, connessione, diretta, bloccato, scollegato, errore. Se per qualche secondo non arrivano frame, l'app segnala che l'iPad potrebbe essere bloccato.

Il piano tecnico completo è nel documento del progetto.

## Da verificare nei test

- [ ] L'iPad compare dopo il collegamento e la risoluzione nelle statistiche è quella nativa (iPad Air 4: 1640×2360)
- [ ] Latenza paragonabile a QuickTime
- [ ] Testo nitido in Dimensione reale (⌘1)
- [ ] Rotazione: la finestra cambia proporzioni senza deformare l'immagine
- [ ] Blocco dell'iPad: compare l'avviso, e allo sblocco riprende da solo
- [ ] Con una schermata ferma (niente animazioni) l'avviso di blocco non compare per sbaglio; se compare, alzare la soglia o disattivarlo nelle Impostazioni
- [ ] Scollegamento e ricollegamento del cavo
- [ ] Confronto tra i due motori e i due formati pixel nelle Impostazioni
- [ ] Zoom: resta nitido ingrandendo, si sposta bene con trackpad e mouse
- [ ] Ispettore pixel: coordinate e colore corrispondono a quanto c'è sull'iPad
- [ ] Modalità presentazione: la finestra si trascina dall'immagine, ⌘W la chiude
- [ ] Per ogni funzione extra: tenerla o toglierla?
