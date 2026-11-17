@echo off
title Smart Ink Notebook - Server per iPad & Tablet
echo ========================================================
echo   SMART INK NOTEBOOK - TEST SU IPAD / TABLET ANDROID
echo ========================================================
echo.
echo Assicurati che il tuo iPad sia collegato allo stesso Wi-Fi del PC.
echo Apri Safari sull'iPad e vai all'indirizzo:
echo.
echo     http://192.168.0.126:8080
echo.
echo Per installarla come App a tutto schermo sull'iPad:
echo 1. Premi l'icona "Condividi" (quadrato con freccia in alto) in Safari
echo 2. Scegli "Aggiungi alla schermata Home"
echo ========================================================
echo.
cd /d "%~dp0web_preview"
"C:\Users\lupui\AppData\Local\Programs\Python\Python313\python.exe" -m http.server 8080 --bind 0.0.0.0
pause
