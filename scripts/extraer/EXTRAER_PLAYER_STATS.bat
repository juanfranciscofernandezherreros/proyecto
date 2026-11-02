@echo off
rem Uso: EXTRAER_PLAYER_STATS.bat [pais] [competicion] [limite]
call "%~dp0EXTRAER_DATASET.bat" PLAYER_STATS player_stats.csv %*
exit /b %ERRORLEVEL%
