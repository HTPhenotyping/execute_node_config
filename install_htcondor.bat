@echo off
setlocal

rem Check the number of arguments
set nargs=0
for %%x in (%*) do set /a nargs+=1
if not %nargs% equ 3 (
    echo Invalid number of arguments %nargs%
    call :usage
    exit /b 1
)

rem Set arguments
set %1 > nul 2> nul
set %2 > nul 2> nul
set %3 > nul 2> nul

rem Check arguments
if not defined CM (
    echo Central Manager is undefined
    call :usage
    exit /b 1
)
if not defined DSN (
    echo Data Source Name is undefined
    call :usage
    exit /b 1
)
if not defined DSD (
    echo Data Source Directory is undefined
    call :usage
    exit /b 1
)

rem Check for the Data Source Directory
if not exist "%DSD%" (
    echo %DSD% does not exist, attempting to create it
    mkdir "%DSD%"
)

rem Check for persistent data storage locations and files
if not exist "%LOCALAPPDATA%\HTPhenotyping" (
    mkdir "%LOCALAPPDATA%\HTPhenotyping"
)

echo %DSD%>"%LOCALAPPDATA%\HTPhenotyping\data_source_directory"

if not exist "%LOCALAPPDATA%\HTPhenotyping\config.d" (
    mkdir "%LOCALAPPDATA%\HTPhenotyping\config.d"
)

if not exist "%LOCALAPPDATA%\HTPhenotyping\tokens.d" (
    mkdir "%LOCALAPPDATA%\HTPhenotyping\tokens.d"
)

rem Check for the Docker batch script
if not exist "%LOCALAPPDATA%\HTPhenotyping\run_htcondor_docker.bat" (
    call :write_docker_script
)

rem Run Docker batch script in initialization mode
call "%LOCALAPPDATA%\HTPhenotyping\run_htcondor_docker.bat" i "CM=%CM%" "DSD=%DSD%"

exit /b %errorlevel%

:usage
echo Usage: install_htcondor.bat "CM=<Central Manager>" "DSN=<Data Source Name>" "DSD=<Data Source Directory>"
exit /b 0

:write_docker_script
(
    echo ^@echo off
    echo setlocal
    echo.
    echo echo Downloading latest version of HTCondor on Docker (if needed^)...
    echo docker pull -q htphenotyping/execute:8.9.7-el7 ^> nul
    echo echo.
    echo set /p DSD=^<"%%LOCALAPPDATA%%\HTPhenotyping\data_source_directory"
    echo echo Running HTCondor on Docker, serving data out of %%DSD%%...
    echo echo To stop HTCondor on Docker at any time, hit Ctrl+C
    echo echo.
    echo if "%%1%%" == "i" (
    echo     set %%2%%
    echo     set %%3%%
    echo     docker run --rm -it --name htcondor --mount type=bind,source="%%DSD%%",target="/mnt/data" --mount type=bind,source="%%LOCALAPPDATA%%\HTPhenotyping\tokens.d",target="/etc/condor/tokens.d" --mount type=bind,source="%%LOCALAPPDATA%%\HTPhenotyping\config.d",target="/etc/condor/config.d" htphenotyping/execute:8.9.7-el7 -i -c "%%CM%%" -n "%%DSN%%"
    echo ^) else (
    echo     docker run --rm -it --name htcondor --mount type=bind,source="%%DSD%%",target="/mnt/data" --mount type=bind,source="%%LOCALAPPDATA%%\HTPhenotyping\tokens.d",target="/etc/condor/tokens.d" --mount type=bind,source="%%LOCALAPPDATA%%\HTPhenotyping\config.d",target="/etc/condor/config.d" htphenotyping/execute:8.9.7-el7
    echo ^)
) > "%LOCALAPPDATA%\HTPhenotyping\run_htcondor_docker.bat"
exit /b 0
