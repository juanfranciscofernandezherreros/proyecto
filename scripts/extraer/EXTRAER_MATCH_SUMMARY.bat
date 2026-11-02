@echo off
rem Uso: EXTRAER_MATCH_SUMMARY.bat [pais] [competicion] [limite]
call "%~dp0EXTRAER_DATASET.bat" MATCH_SUMMARY score_summary.csv %*
exit /b %ERRORLEVEL%
