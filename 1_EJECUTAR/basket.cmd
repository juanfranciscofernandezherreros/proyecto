@echo off
rem basket - CLI unico del proyecto. Doble clic = menu; o: basket.cmd <comando> [args]
rem Comandos: basket.cmd ayuda
python "%~dp0..\scripts\py\basket.py" %*
exit /b %ERRORLEVEL%
