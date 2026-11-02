@echo off
rem INICIAR_ANTIBLOQUEO.bat detecta esta ventana por su titulo: no lo cambies.
title Mantener PC Activo
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0MANTENER_DESPIERTO.ps1"
