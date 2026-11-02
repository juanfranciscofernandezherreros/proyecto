@echo off
rem Uso: EXTRAER_TEAM_STATS.bat [pais] [competicion] [limite]
call "%~dp0EXTRAER_DATASET.bat" TEAM_STATS stats_all_periods.csv %*
exit /b %ERRORLEVEL%
