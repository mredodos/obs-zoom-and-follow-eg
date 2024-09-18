# OBS - Zoom and Follow Mouse EG

## Descrizione

Questo script per OBS Studio crea un effetto di zoom dinamico e segue il movimento del mouse su una sorgente video selezionata. È particolarmente utile per evidenziare parti specifiche dello schermo durante registrazioni o streaming live, con supporto per configurazioni multi-monitor.

## Caratteristiche

- Zoom dinamico su qualsiasi sorgente video valida
- Movimento fluido che segue il mouse
- Supporto multi-piattaforma (Windows, Linux, macOS)
- Supporto multi-monitor
- Velocità di zoom e di inseguimento personalizzabili
- Attivazione tramite tasti di scelta rapida
- Gestione automatica dei cambi di scena
- Transizioni fluide durante il cambio di scena

## Requisiti

- OBS Studio (versione 27.0.0 o superiore)
- Lua 5.1 o superiore

## Installazione

1. Scarica il file `obs-zoom-and-follow-mouse-eg.lua`
2. In OBS Studio, vai su Strumenti > Script
3. Clicca sul pulsante "+" e seleziona il file scaricato
4. Configura le impostazioni dello script secondo le tue preferenze

## Configurazione

Lo script offre diverse opzioni di configurazione:

- Valore Zoom: Imposta il livello massimo di zoom (da 1.1 a 5.0)
- Velocità Zoom: Regola la velocità dell'effetto zoom (da 0.01 a 1.0)
- Velocità Inseguimento: Regola la velocità dell'effetto di inseguimento (da 0.01 a 1.0)

## Utilizzo

1. Configura lo script nelle impostazioni di OBS Studio
2. Imposta i tasti di scelta rapida per attivare/disattivare lo zoom e l'inseguimento
3. Durante la registrazione o lo streaming live, usa i tasti di scelta rapida per controllare gli effetti di zoom e inseguimento

## Funzioni Principali

- Zoom dinamico sulla sorgente selezionata con animazione fluida
- Inseguimento del movimento del mouse con smussatura personalizzabile
- Gestione automatica dei cambi di scena e rimozione della sorgente
- Supporto per configurazioni multi-monitor
- Transizioni fluide durante il cambio di scena mentre si è in modalità zoom

## Risoluzione dei problemi

Se incontri problemi con lo script, prova a:

1. Verificare che ci sia una sorgente video valida nella scena corrente
2. Riavviare OBS Studio
3. Controllare i log di OBS per eventuali messaggi di errore
4. Assicurarti che la tua versione di OBS Studio sia compatibile

## Supporto

Per segnalare bug o richiedere nuove funzionalità, apri un issue su GitHub o contatta l'autore dello script.

## Licenza

Questo script è rilasciato sotto la GNU General Public License v3.0. Vedi il file LICENSE per maggiori dettagli.

## Versione

Versione corrente: 1.1

## Autore

Edoardo Guzzi

## Ringraziamenti

Un ringraziamento speciale alla comunità di OBS Studio per il loro supporto e feedback.

## Ispirazione

Questo script è ispirato a vari script di zoom e inseguimento nella comunità OBS, con funzionalità aggiuntive e miglioramenti per il supporto multi-monitor e transizioni fluide.
