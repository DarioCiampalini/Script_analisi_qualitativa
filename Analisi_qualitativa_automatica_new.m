%% CLASSIFICATORE AUTOMATICO DI ACCUMULI DETRITICI - STRATEGIA A AVANZATA (MATLAB R2026a)
clear; clc; close all;

%% ==================== CONFIGURAZIONE UTENTE ====================
ESEGUI_CALIBRAZIONE = true; 
percorsoCalibrazione = "E:\Script qualitativo new\dataset_detrito_50"; 

% Percorsi per collegarsi all'output del Python (Dataset 2012 - 50cm)
percorsoInput = "E:\Script qualitativo new\Ritagli_2012_50cm_50x50";
percorsoOutputBase = "E:\RISULTATI_FINALI\Qualitativa\50cm";

fileModelloCalibrato = "ModelloCalibrazioneDetrito.mat";
nomeFileTabella = "Risultati_Classificazione_Detrito_50.csv"; 

% --- PARAMETRI GEOMETRICI ADATTATIVI ---
risoluzionePixelMetro = 0.50;  % 0.50 m per 2012 e 0.20 per il 2024
dimFinestraMetri = 20;        % Dimensione cella (10x10m 2024 e 20x20 2012)
tolleranzaNaN = 0.30;         

% --- OTTIMIZZAZIONI CALIBRAZIONE E SPETTRALI ---
BIAS_CLASSE_2 = 1;         % Coefficiente per espandere la Classe 2 (1.0 = nessun bias, >1.0 favorisce la Cl2)
SOGLIA_NEVE_PCT = 20.0;       % Se più del 20% del cerchio è neve/bianco puro, scatta l'alert di affidabilità

dimFinestraPixel = round(dimFinestraMetri / risoluzionePixelMetro);
%% ===============================================================

%% Fase 1: Calibrazione Multiformato (PNG, JPG, TIF + MAT)
if ESEGUI_CALIBRAZIONE
    fprintf('=== FASE 1: Calibrazione Multiformato ===\n');
    elencoClassi = ["Classe0", "Classe1", "Classe2", "Classe3"];
    X_train = []; Y_train = [];
    
    for c = 1:numel(elencoClassi)
        nomeClasse = elencoClassi(c);
        cartellaClasse = fullfile(percorsoCalibrazione, nomeClasse);
        if ~exist(cartellaClasse, 'dir'), continue; end
        
        fileImmagini = [dir(fullfile(cartellaClasse, '*.png')); ...
                        dir(fullfile(cartellaClasse, '*.jpg')); ...
                        dir(fullfile(cartellaClasse, '*.tif')); ...
                        dir(fullfile(cartellaClasse, '*.mat'))];
                    
        for f = 1:numel(fileImmagini)
            percorsoFileCompleto = fullfile(fileImmagini(f).folder, fileImmagini(f).name);
            [~, ~, est] = fileparts(fileImmagini(f).name);
            try
                if strcmpi(est, '.mat')
                    datiMat = load(percorsoFileCompleto);
                    campi = fieldnames(datiMat);
                    img = datiMat.(campi{1});
                else
                    img = imread(percorsoFileCompleto);
                end
                [feats, ~, ~, ~] = estraiCaratteristicheMorfologiche(img);
                X_train = [X_train; feats];
                Y_train = [Y_train; categorical(nomeClasse)];
            catch
                fprintf('Avviso: Impossibile leggere il file: %s\n', fileImmagini(f).name);
            end
        end
    end
    template = templateTree('MaxNumSplits', 25);
    modelloClassificatore = fitcensemble(X_train, Y_train, 'Method', 'Bag', 'NumLearningCycles', 100, 'Learners', template);
    save(fileModelloCalibrato, 'modelloClassificatore');
else
    load(fileModelloCalibrato, 'modelloClassificatore');
end

%% Fase 2: Analisi Eterogenea Adattativa
fprintf('=== FASE 2: Analisi spaziale con ottimizzazioni ===\n');
elencoFile = dir(fullfile(percorsoInput, '*.mat'));
numFile = numel(elencoFile);

if ~exist(percorsoOutputBase, 'dir'), mkdir(percorsoOutputBase); end

idFileElaborato = zeros(numFile, 1);
nomiFileMat = cell(numFile, 1);
classiDominanti = zeros(numFile, 1);
raggiInteriMetri = zeros(numFile, 1);
pctClasse0 = zeros(numFile, 1);
pctClasse1 = zeros(numFile, 1);
pctClasse2 = zeros(numFile, 1);
pctClasse3 = zeros(numFile, 1);
affidabilitaAnalisi = cell(numFile, 1);

for i = 1:numFile
    nomeFileCorrente = elencoFile(i).name;
    datiCaricati = load(fullfile(percorsoInput, nomeFileCorrente));
    imgOriginale = datiCaricati.rgb_grezzo;
    
    [H, W, C] = size(imgOriginale);
    [~, nomeSenzaEst, ~] = fileparts(nomeFileCorrente);
    fidStr = regexp(nomeSenzaEst, '\d+', 'match');
    if ~isempty(fidStr), idFileElaborato(i) = str2double(fidStr{1}); else, idFileElaborato(i) = i - 1; end
    nomiFileMat{i} = nomeFileCorrente;

    % 1. Calcolo geometrico raggio
    mascheraValidiTotale = ~any(isnan(imgOriginale), 3);
    areaPixel = sum(mascheraValidiTotale(:));
    areaMetriQuadri = areaPixel * (risoluzionePixelMetro^2);
    raggiInteriMetri(i) = round(sqrt(areaMetriQuadri / pi));

    % 2. FILTRO SPETTRALE NEVE (Analisi dei pixel bianchi/saturi)
    % La neve riflette fortemente su RGB (assumiamo valori vicini al massimo spettrale)
    valMaxSoglia = max(imgOriginale(:)); 
    if valMaxSoglia > 1.0, sogliaBianco = 230; else, sogliaBianco = 0.90; end % Adattivo se float o uint8
    
    mascheraNeve = (imgOriginale(:,:,1) > sogliaBianco) & ...
                   (imgOriginale(:,:,2) > sogliaBianco) & ...
                   (imgOriginale(:,:,3) > sogliaBianco) & mascheraValidiTotale;
               
    pctNeveRilevata = (sum(mascheraNeve(:)) / areaPixel) * 100;
    
    if pctNeveRilevata >= SOGLIA_NEVE_PCT
        affidabilitaAnalisi{i} = "BASSA (Presenza Neve)";
    else
        affidabilitaAnalisi{i} = "ALTA";
    end

    % 3. Griglia mobile
    mappaClassiChiuse = NaN(H, W);
    rigaStep = 1:dimFinestraPixel:H; colStep = 1:dimFinestraPixel:W;
    listaPredizioniLocali = [];
    
    % Recuperiamo le etichette delle classi per mappare correttamente i bias
    nomiClassiModello = modelloClassificatore.ClassNames;
    idxClasse2 = find(string(nomiClassiModello) == "Classe 2");
    
    for r = 1:numel(rigaStep)
        for c = 1:numel(colStep)
            rStart = rigaStep(r); rEnd = min(rStart + dimFinestraPixel - 1, H);
            cStart = colStep(c); cEnd = min(cStart + dimFinestraPixel - 1, W);
            
            subImg = imgOriginale(rStart:rEnd, cStart:cEnd, :);
            mascheraNaN_sub = any(isnan(subImg), 3);
            quotaNaN = sum(mascheraNaN_sub(:)) / numel(mascheraNaN_sub);
            
            if quotaNaN <= tolleranzaNaN && (rEnd-rStart+1 == dimFinestraPixel) && (cEnd-cStart+1 == dimFinestraPixel)
                [featsSub, ~, ~, ~] = estraiCaratteristicheMorfologiche(subImg);
                
                % Otteniamo le probabilità posteriori del modello per gestire il Bias
                [~, score] = predict(modelloClassificatore, featsSub);
                
                % Applichiamo il Bias per espandere la Classe 2
                if ~isempty(idxClasse2)
                    score(idxClasse2) = score(idxClasse2) * BIAS_CLASSE_2;
                end
                
                [~, maxIdx] = max(score);
                classePredetta = string(nomiClassiModello(maxIdx));
                numClasseSub = str2double(regexp(classePredetta, '\d+', 'match'));
                
                if ~isnan(numClasseSub)
                    listaPredizioniLocali = [listaPredizioniLocali; numClasseSub];
                    mappaClassiChiuse(rStart:rEnd, cStart:cEnd) = numClasseSub;
                end
            end
        end
    end
    
    % Recupero globale se vuoto
    if isempty(listaPredizioniLocali) && any(mascheraValidiTotale(:))
        [featsGlobal, ~, ~, ~] = estraiCaratteristicheMorfologiche(imgOriginale);
        [~, score] = predict(modelloClassificatore, featsGlobal);
        if ~isempty(idxClasse2), score(idxClasse2) = score(idxClasse2) * BIAS_CLASSE_2; end
        [~, maxIdx] = max(score);
        numClasseGlobal = str2double(regexp(string(nomiClassiModello(maxIdx)), '\d+', 'match'));
        if ~isnan(numClasseGlobal)
            listaPredizioniLocali = numClasseGlobal;
            mappaClassiChiuse(mascheraValidiTotale) = numClasseGlobal;
        end
    end
    
    if ~isempty(listaPredizioniLocali)
        classiDominanti(i) = mode(listaPredizioniLocali);
        pctClasse0(i) = (sum(listaPredizioniLocali == 0) / numel(listaPredizioniLocali)) * 100;
        pctClasse1(i) = (sum(listaPredizioniLocali == 1) / numel(listaPredizioniLocali)) * 100;
        pctClasse2(i) = (sum(listaPredizioniLocali == 2) / numel(listaPredizioniLocali)) * 100;
        pctClasse3(i) = (sum(listaPredizioniLocali == 3) / numel(listaPredizioniLocali)) * 100;
    else
        classiDominanti(i) = NaN;
    end
    
    fprintf('FID %d (%s) -> Cl. Dominante: %d (C2=%.1f%%)\n', ...
        idFileElaborato(i), affidabilitaAnalisi{i}, classiDominanti(i), pctClasse2(i));
    
    indiceZeroBased = i - 1; 
    nuovoNomeFile = sprintf('%d_%s_MappaClasse_%d.png', indiceZeroBased, nomeSenzaEst, classiDominanti(i));
    percorsoSalvataggioElab = fullfile(percorsoOutputBase, nuovoNomeFile);
    
    salvaOutputMappato(imgOriginale, mappaClassiChiuse, classiDominanti(i), raggiInteriMetri(i), ...
                       pctClasse0(i), pctClasse1(i), pctClasse2(i), pctClasse3(i), ...
                       affidabilitaAnalisi{i}, pctNeveRilevata, percorsoSalvataggioElab);
end 

%% Fase 3: Esportazione Tabella
fprintf('=== FASE 3: Esportazione Tabella Dati ===\n');
tabellaRisultati = table(idFileElaborato, string(nomiFileMat), raggiInteriMetri, classiDominanti, ...
    pctClasse0, pctClasse1, pctClasse2, pctClasse3, string(affidabilitaAnalisi), ...
    'VariableNames', {'FID', 'NomeFileOrig', 'Raggio_m', 'ClasseDominante_Moda', 'Pct_Classe_0', 'Pct_Classe_1', 'Pct_Classe_2', 'Pct_Classe_3', 'Affidabilita'});

percorsoTabellaOutput = fullfile(percorsoOutputBase, nomeFileTabella);
writetable(tabellaRisultati, percorsoTabellaOutput, 'Delimiter', ',');
fprintf('Processo completato con successo.\n');


%% ==============================================================================
%%                               FUNZIONI LOCALI
%% ==============================================================================

function [features, E, DoG, Sintesi] = estraiCaratteristicheMorfologiche(img)
    if size(img, 3) == 3
        grayImg = mean(img, 3, 'omitnan');
        mascheraNaN = any(isnan(img), 3); grayImg(mascheraNaN) = NaN;
    else
        grayImg = img;
    end
    mascheraValidi = ~isnan(grayImg);
    if ~any(mascheraValidi(:))
        E = grayImg; DoG = grayImg; Sintesi = grayImg; features = zeros(1, 5); return;
    end
    minReale = min(grayImg(mascheraValidi)); maxReale = max(grayImg(mascheraValidi));
    if maxReale > minReale, grayImgNorm = (grayImg - minReale) / (maxReale - minReale); else, grayImgNorm = zeros(size(grayImg)); end
    valoreRiempimento = mean(grayImgNorm(mascheraValidi));
    grayImgSenzaNaN = grayImgNorm; grayImgSenzaNaN(~mascheraValidi) = valoreRiempimento;
    E_raw = entropyfilt(grayImgSenzaNaN); 
    DoG_raw = imabsdiff(imgaussfilt(grayImgSenzaNaN, 1.0), imgaussfilt(grayImgSenzaNaN, 3.0));
    E = E_raw; E(~mascheraValidi) = NaN; DoG = DoG_raw; DoG(~mascheraValidi) = NaN;
    Sintesi = (mat2gray(E) * 0.4) + (mat2gray(DoG) * 0.6); Sintesi(~mascheraValidi) = NaN;
    meanE = mean(E(:), 'omitnan'); stdE = std(E(:), 'omitnan');
    varDoG = var(DoG(:), 'omitnan'); varSintesi = var(Sintesi(:), 'omitnan');
    valoriDoGValidi = DoG(mascheraValidi);
    if ~isempty(valoriDoGValidi), pctDoG = prctile(abs(valoriDoGValidi), 95); else, pctDoG = 0; end
    features = [meanE, stdE, varDoG, varSintesi, pctDoG];
end

function salvaOutputMappato(img, mappaClassi, clDominante, raggio, p0, p1, p2, p3, affidabilita, pctNeve, percorsoOutput)
    switch clDominante
        case 0, descr = "DOMINANTE CLASSE 0: Tessitura fine uniforme, blocchi non distinguibili.";
        case 1, descr = "DOMINANTE CLASSE 1: Tessitura rugosa, si distinguono solo rari blocchi isolati.";
        case 2, descr = "DOMINANTE CLASSE 2: Distribuzione mista, si distingue chiaramente tra il 50% e il 70% dei blocchi.";
        case 3, descr = "DOMINANTE CLASSE 3: Accumulo massivo, la quasi totalità dei singoli blocchi è definita.";
        otherwise, descr = "Area non classificabile.";
    end
    
    stringaRiepilogoCompito = sprintf('Geometria: Raggio = %d m | C0=%.1f%% | C1=%.1f%% | C2=%.1f%% | C3=%.1f%%', raggio, p0, p1, p2, p3);

    hFig = figure('Visible', 'off', 'Color', [1 1 1], 'Position', [50, 50, 1600, 540]);

    % Titolo Principale
    annotation('textbox', [0.02, 0.93, 0.96, 0.05], 'String', 'ANALISI MORFOLOGICA SPAZIALE AD ALTA RISOLUZIONE (STRATEGIA A)', 'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'FontSize', 13, 'FontWeight', 'bold');
    
    % Box descrittivo standard
    annotation('textbox', [0.02, 0.84, 0.96, 0.07], 'String', {descr, stringaRiepilogoCompito}, 'EdgeColor', [0.7 0.7 0.7], 'HorizontalAlignment', 'center', 'BackgroundColor', [0.98 0.98 0.98], 'FontSize', 10);

    % ALERT NEVE VISIVO: Se l'affidabilità è bassa stampiamo un banner vistoso sopra i grafici
    if strcmpi(affidabilita, "BASSA (Presenza Neve)")
        annotation('textbox', [0.02, 0.76, 0.96, 0.05], 'String', sprintf('ATTENZIONE: DATI POCO AFFIDABILI - RILEVATA NEVE AL %.1f%% DELLA SUPERFICIE', pctNeve), ...
            'EdgeColor', 'none', 'HorizontalAlignment', 'center', 'FontSize', 11, 'FontWeight', 'bold', 'Color', [0.8 0.1 0.1]);
    end

    vMin = min(img(:), [], 'omitnan'); vMax = max(img(:), [], 'omitnan');
    if vMax > vMin, imgNorm = (img - vMin) / (vMax - vMin); else, imgNorm = zeros(size(img)); end

    t = tiledlayout(hFig, 1, 3, 'Units', 'normalized', 'OuterPosition', [0.01, 0.01, 0.98, 0.74]);
    t.TileSpacing = 'compact'; t.Padding = 'compact';
    
    mappaColoriClassi = [0.2 0.4 0.8; 0.2 0.7 0.3; 0.9 0.6 0.1; 0.8 0.1 0.1];
    
    nexttile; imshow(imgNorm); title('A) Ortofoto Originale', 'FontWeight', 'bold');
    
    axB = nexttile; imagesc(mappaClassi, 'AlphaData', ~isnan(mappaClassi)); axis image; axis off;
    title('B) Griglia delle Classi (10x10m)', 'FontWeight', 'bold');
    colormap(axB, mappaColoriClassi); caxis(axB, [0 3]);
    
    axC = nexttile; imshow(imgNorm); hold(axC, 'on');
    mascheraTrasparenza = ~isnan(mappaClassi) * 0.40; 
    imagesc(mappaClassi, 'AlphaData', mascheraTrasparenza); axis image; axis off;
    title('C) Sovrapposizione (Trasparenza 60%)', 'FontWeight', 'bold');
    colormap(axC, mappaColoriClassi); caxis(axC, [0 3]); hold(axC, 'off');
    
    cb = colorbar(axC, 'Location', 'eastoutside', 'Ticks', 0:3, 'TickLabels', {'Classe 0', 'Classe 1', 'Classe 2', 'Classe 3'});
    cb.FontWeight = 'bold'; cb.Position = [0.94, 0.10, 0.015, 0.58];

    exportgraphics(hFig, percorsoOutput, 'Resolution', 300);
    close(hFig);
end