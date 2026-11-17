@echo off
rem Resultados de ayer hasta el projector (skill resultados-ayer).
rem Doble clic: cuadre previo; si falta algo, extrae de Flashscore, carga y comprueba Mongo.
rem Admite los mismos argumentos: resultados-ayer.cmd [AAAA-MM-DD] [--solo-csv] [--forzar]
call "%~dp0basket.cmd" resultados-ayer %*
set RC=%ERRORLEVEL%
echo.
if %RC%==0 (echo Resultados de ayer: OK) else (echo Resultados de ayer: FALLO codigo %RC%)
pause
exit /b %RC%
