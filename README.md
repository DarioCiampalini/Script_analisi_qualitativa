# Script_analisi_qualitativa

Script MATLAB per l'analisi qualitativa di immagini/maschere volte all'estrazione di parametri granulometrici e morfometrici. Il codice esegue preprocessing, segmentazione semiautomatica/automatica, pulizia delle maschere e calcolo di metriche sintetiche per supportare valutazioni descrittive.

## Requisiti
- MATLAB (consigliato R2019b o successivo)
- Image Processing Toolbox (obbligatorio)
- (Opzionale) Computer Vision Toolbox se il workflow utilizza funzioni di visione avanzata

## Installazione / setup
1. Clonare il repository:
   git clone https://github.com/DarioCiampalini/Script_analisi_qualitativa.git
2. Aprire MATLAB e aggiungere la cartella del progetto al path:
   addpath(genpath('percorso/Script_analisi_qualitativa'))

## Uso
  1. Aprire MATLAB.
  2. Impostare la cartella corrente su quella del progetto.
  3. Lanciare lo script:
     `analisi_qualitativa`

## Input
- Cartella di immagini (formati supportati: JPG, PNG, TIFF) o file singolo.
- Eventuali parametri di configurazione (soglie, filtri, risoluzione) possono essere definiti in un file `config.m` o passati come argomenti.

## Output
- Maschere pulite (cartella `masks/`).
- File CSV/Excel con le metriche calcolate per ciascun oggetto (es. area, perimetro, diametro equivalente, circolarità).
- Log sintetico dell'esecuzione (`log.txt`).

## Parametri principali (da adattare)
- inputFolder: percorso delle immagini di ingresso
- outputFolder: percorso per salvare risultati
- threshold: soglia per la segmentazione
- minArea: area minima per considerare un oggetto
- cleanMorph: flag per applicare operazioni morfologiche di pulizia

## Esempio minimo
1. Impostare le variabili in `config.m`:
   - inputFolder = 'data/images'
   - outputFolder = 'results'
2. Eseguire:
   - `analisi_qualitativa`

## Buone pratiche
- Lavorare su immagini con scala nota per calcolare metriche dimensionali reali.
- Validare la segmentazione su un campione prima di processare interi dataset.
- Versionare i parametri usati per ogni batch (es. salvando `config_used.mat`).

## Licenza
Uso accademico o di ricerca.
