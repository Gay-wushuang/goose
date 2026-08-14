@echo off
setlocal EnableExtensions
set "SUPPORT=%~dp0.."
if /I "%~1"=="e4b" goto e4b
if /I "%~1"=="26b" goto 26b
echo Usage: %~nx0 e4b ^| 26b
exit /b 2

:e4b
if defined GOOSE_E4B_MODEL (set "MODEL=%GOOSE_E4B_MODEL%") else (set "MODEL=%SUPPORT%\models\gemma-4-E4B-it-UD-Q4_K_XL.gguf")
set "ALIAS=gemma-4-e4b-q4"
set "NGL=99"
set "CTX=32768"
set "PARALLEL=1"
set "PREDICT=-1"
goto start

:26b
if defined GOOSE_A4B_MODEL (set "MODEL=%GOOSE_A4B_MODEL%") else (set "MODEL=%SUPPORT%\models\gemma-4-26B-A4B-it-UD-Q4_K_M.gguf")
set "ALIAS=gemma-4-26b-a4b-q4"
set "NGL=24"
if not "%~2"=="" set "NGL=%~2"
set "CTX=32768"
if not "%~3"=="" set "CTX=%~3"
set "PARALLEL=1"
set "PREDICT=-1"

:start
if not exist "%MODEL%" (
  echo ERROR: GGUF model does not exist: %MODEL%
  echo Set GOOSE_E4B_MODEL or GOOSE_A4B_MODEL, or place the model under "%SUPPORT%\models".
  exit /b 3
)
if not exist "%SUPPORT%\llama.cpp\bin\llama-server.exe" (
  echo ERROR: llama-server.exe does not exist: %SUPPORT%\llama.cpp\bin\llama-server.exe
  exit /b 4
)
if not exist "%SUPPORT%\logs" mkdir "%SUPPORT%\logs"
for /f "tokens=5" %%P in ('netstat -ano ^| findstr "127.0.0.1:8080" ^| findstr "LISTENING"') do taskkill /PID %%P /F >nul 2>nul
ping 127.0.0.1 -n 3 >nul
powershell.exe -NoProfile -Command "$a=@('-m','%MODEL%','--alias','%ALIAS%','--host','127.0.0.1','--port','8080','-ngl','%NGL%','-c','%CTX%','--parallel','%PARALLEL%','-n','%PREDICT%','--jinja','--reasoning','off','--no-context-shift'); Start-Process -FilePath '%SUPPORT%\llama.cpp\bin\llama-server.exe' -ArgumentList $a -WindowStyle Minimized -RedirectStandardOutput '%SUPPORT%\logs\%ALIAS%.out.log' -RedirectStandardError '%SUPPORT%\logs\%ALIAS%.err.log'"
for /L %%I in (1,1,180) do (
  curl.exe -fsS http://127.0.0.1:8080/v1/models 2>nul | findstr /C:"%ALIAS%" >nul && (
    echo READY: %ALIAS%
    exit /b 0
  )
  ping 127.0.0.1 -n 2 >nul
)
echo ERROR: model server did not become ready within 180 seconds.
exit /b 1
