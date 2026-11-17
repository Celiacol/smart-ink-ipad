@echo off
chcp 65001 >nul
title Compilazione Automatica iOS (.ipa) su GitHub Cloud
echo ======================================================================
echo   INVIO PROGETTO A GITHUB PER COMPILARE L'APP NATIVA iPAD (.IPA)
echo ======================================================================
echo.
echo Prima di continuare:
echo 1. Vai su https://github.com/new (accedi o registrati gratis)
echo 2. Scrivi come Repository name: smart-ink-ipad
echo 3. Scegli "Public" (cosi i minuti di compilazione Mac su GitHub sono infiniti e gratuiti)
echo 4. Clicca "Create repository" in basso (NON spuntare "Add a README")
echo.
set /p REPO_URL="Incolla qui l'indirizzo del tuo repository (es. https://github.com/tuonome/smart-ink-ipad.git) e premi INVIO: "

if "%REPO_URL%"=="" (
    echo Nessun indirizzo inserito. Riprova!
    pause
    exit /b
)

cd /d "%~dp0"
git remote remove origin 2>nul
git remote add origin %REPO_URL%
git branch -M main
echo.
echo Invio del codice a GitHub in corso...
git push -u origin main

echo.
echo ======================================================================
echo   FATTO! ORA SCARICA IL FILE .IPA DALLA SCHEDA "ACTIONS" DI GITHUB
echo ======================================================================
echo 1. Apri la pagina del tuo repository su GitHub e clicca in alto su "Actions"
echo 2. Vedrai partire "Compila SmartInkNotebook.ipa per iPad (macOS Cloud)"
echo 3. Dopo circa 6-8 minuti (pallino verde), cliccaci sopra e in basso sotto
echo    "Artifacts" clicca su "SmartInkNotebook-iPad-IPA" per scaricare il file!
echo ======================================================================
pause
