@echo off
setlocal EnableExtensions EnableDelayedExpansion
title failguard

rem ============================================================
rem  failguard v3.2.6 - failed-logon shutdown guard + duress account
rem ============================================================

rem ====================== CONFIG ======================
set "THRESHOLD=2"
set "WINDOW=100"
set "POLL=5"
set "GRACE=2"
set "TYPES=2,7,10"
set "DURESS=1"
set "DURESS_DELAY=3"
set "DRYRUN=0"
set "SHUTDOWN_MODE=normal"
set "BSOD_MAX=3"
set "BSOD_WINDOW=240"
set "LOCKDOWN=1"
rem ====================================================

set "DEST=%ProgramData%\failguard"
set "PSFILE=%DEST%\failguard.ps1"
set "LOGF=%DEST%\failguard.log"
set "NAMESF=%DEST%\duress.names"
set "TASK=failguard"
rem Locale-independent GUID for the "Logon" audit subcategory
set "AUDIT_LOGON={0CCE9215-69AE-11D9-BED3-505054503030}"

rem ---- needs admin: self-elevate ----
whoami /groups | findstr /C:"S-1-16-12288" >nul 2>&1
if errorlevel 1 (
    echo Administrator rights are needed - requesting elevation...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

call :du_load
call :mode_load

:menu
call :du_load
call :mode_load
cls
echo ============== failguard v3.2.6 ==============
echo   failsafe : %THRESHOLD% failures / %WINDOW% min / grace %GRACE%s / types %TYPES%
set "DULINE=off"
if "%DURESS%"=="1" set "DULINE=ON  - names: %DURESS_NAMES%"
if "%DURESS%"=="1" if not defined DURESS_NAMES set "DULINE=ON  - NO NAMES CONFIGURED - inactive"
echo   action   : %SHUTDOWN_MODE%
echo   duress   : %DULINE%
if /i "%SHUTDOWN_MODE%"=="bsod" echo   [!] BSOD MODE: triggers cause an intentional crash, NOT a clean shutdown.
if /i "%SHUTDOWN_MODE%"=="bsod" echo       Crash dumps are auto-disabled at trigger time. See option 9.
echo ----------------------------------------------
echo   1. Install / update (apply config + start)
echo   2. Status
echo   3. Recent failed logons
echo   4. Open log
echo   5. Enable / disable
echo   6. Uninstall
echo   7. Duress settings
echo   8. Exit
echo   9. Shutdown action
echo ==============================================
set "CHOICE="
set /p "CHOICE=Select [1-9]: "
if "%CHOICE%"=="1" goto :install
if "%CHOICE%"=="2" goto :status
if "%CHOICE%"=="3" goto :recent
if "%CHOICE%"=="4" goto :openlog
if "%CHOICE%"=="5" goto :toggle
if "%CHOICE%"=="6" goto :uninstall
if "%CHOICE%"=="7" goto :duress
if "%CHOICE%"=="8" exit /b
if "%CHOICE%"=="9" goto :actionmenu
goto :menu

rem ------------------ ACTION SETTINGS ------------------
:actionmenu
call :mode_load
cls
echo ============== shutdown action ==============
echo   current : %SHUTDOWN_MODE%
echo ----------------------------------------------
echo   n. normal - orderly shutdown (default, FDE-safe)
echo   b. bsod   - intentional kernel crash
echo   t. test BSOD now (CRASHES this machine - use in a VM)
echo   x. back
echo ----------------------------------------------
echo   WARNING: BSOD is a crash, not a clean shutdown.
echo   - Crash dumps are DISABLED automatically at trigger time (FDE
echo       precaution) and stay off afterwards.
echo   - With FDE (VeraCrypt/BitLocker) keys may stay in RAM until
echo         power is cut - verify that is acceptable for you.
echo   - Set auto-reboot to OFF if you want the screen to stay up.
echo   - Loop guard: at most %BSOD_MAX% bugchecks per %BSOD_WINDOW% min;
echo       after that triggers fall back to a normal shutdown.
echo ==============================================
set "ACH="
set /p "ACH=Select [n/b/t/x]: "
if /i "%ACH%"=="n" goto :action_normal
if /i "%ACH%"=="b" goto :action_bsod
if /i "%ACH%"=="t" goto :action_test
if /i "%ACH%"=="x" goto :menu
goto :actionmenu

:action_test
echo(
echo   This crashes the machine IMMEDIATELY (after disabling crash
echo   dumps). Unsaved work is lost. Intended for VM verification of
echo   the BSOD mechanism - identical code path to a real trigger.
set "TCF="
set /p "TCF=Type TEST to continue, anything else cancels: "
if /i not "%TCF%"=="TEST" goto :actionmenu
call :mkdest
powershell -NoProfile -Command "(Get-Content '%~f0') | Where-Object { $_ -match '^\#PST:' } | ForEach-Object { $_ -replace '^\#PST:', '' } | Set-Content '%DEST%\bsod_test.ps1'"
powershell -NoProfile -ExecutionPolicy Bypass -File "%DEST%\bsod_test.ps1"
if errorlevel 2 echo   [!] Loop protection refused: too many bugchecks in the last 240 min.
echo   Returned WITHOUT a BSOD - see the messages above.
pause
goto :actionmenu

:action_normal
call :mode_save normal
echo   [+] Shutdown action set to normal. Run option 1 to apply.
pause
goto :menu

:action_bsod
echo(
echo   This replaces the orderly shutdown with a deliberate BSOD.
echo   At trigger time the watcher will first disable crash dumps
echo   (FDE precaution) and keep them off, then raise the bugcheck.
echo   With VeraCrypt/BitLocker, keys can remain in RAM until the
echo   machine powers off - confirm that risk is acceptable.
echo   Loop guard: at most %BSOD_MAX% bugchecks per %BSOD_WINDOW% min,
echo   then triggers fall back to a normal shutdown.
set "CFM="
set /p "CFM=Enable BSOD mode? [y/N]: "
if /i not "%CFM%"=="y" goto :actionmenu
call :mode_save bsod
echo   [+] Shutdown action set to bsod.
echo   IMPORTANT: run option 1 (Install / update) NOW - the setting
echo   only takes effect when the watcher script is rewritten.
pause
goto :menu


:install
call :mkdest
call :du_load
call :mode_load
call :killwatcher

rem Write PS Configuration Variables safely
ver >nul
> "%PSFILE%" echo $threshold    = %THRESHOLD%
if errorlevel 1 (
    echo   [WARN] Cannot write %PSFILE% - install aborted.
    pause
    goto :menu
)
>>"%PSFILE%" echo $windowMin    = %WINDOW%
>>"%PSFILE%" echo $poll         = %POLL%
>>"%PSFILE%" echo $grace        = %GRACE%
>>"%PSFILE%" echo $types        = @(%TYPES%)
if "%DURESS%"=="1" (>>"%PSFILE%" echo $duress = $true) else (>>"%PSFILE%" echo $duress = $false)
>>"%PSFILE%" echo $duressNames  = '%DURESS_NAMES%'.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries)
>>"%PSFILE%" echo $duressDelay  = %DURESS_DELAY%
if "%DRYRUN%"=="1" (>>"%PSFILE%" echo $dry = $true) else (>>"%PSFILE%" echo $dry = $false)
>>"%PSFILE%" echo $mode         = '%SHUTDOWN_MODE%'
>>"%PSFILE%" echo $bsodMax      = %BSOD_MAX%
>>"%PSFILE%" echo $bsodWindowMin = %BSOD_WINDOW%
>>"%PSFILE%" echo $log          = '%LOGF%'

rem Extract embedded PowerShell script safely without delims issue
powershell -NoProfile -Command "(Get-Content '%~f0') | Where-Object { $_ -match '^\#PS:' } | ForEach-Object { $_ -replace '^\#PS:', '' } | Add-Content '%PSFILE%'"

rem Enable both Failure and Success Audit for Logon (GUID = works on any Windows language)
auditpol /set /subcategory:"%AUDIT_LOGON%" /failure:enable /success:enable >nul 2>&1
if errorlevel 1 echo   [WARN] Could not set Logon auditing - check Group Policy / run option 2.

rem Success auditing grows the Security log faster - make sure it is at least 128 MB
powershell -NoProfile -Command "try { $l = Get-WinEvent -ListLog Security -ErrorAction Stop; if ($l.MaximumSizeInBytes -lt 134217728) { $l.MaximumSizeInBytes = 134217728; $l.SaveChanges() } } catch {}" >nul 2>&1

rem Register the task with explicit settings: no 72h time limit, runs on battery, auto-restart
powershell -NoProfile -Command "$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ' + [char]34 + $env:PSFILE + [char]34); $t = New-ScheduledTaskTrigger -AtStartup; $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew; $p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest; Register-ScheduledTask -TaskName '%TASK%' -Action $a -Trigger $t -Settings $s -Principal $p -Force -ErrorAction Stop | Out-Null"
if errorlevel 1 (
    echo   [WARN] Could not register the scheduled task.
    pause
    goto :menu
)
schtasks /run /tn "%TASK%" >nul 2>&1
ping -n 4 127.0.0.1 >nul
echo(
echo   [+] Installed. Watcher runs at every boot as SYSTEM and is running now.
call :mode_load
if /i not "%SHUTDOWN_MODE%"=="bsod" goto :install_mode_done
echo   [!] BSOD MODE IS ACTIVE - a trigger now causes an intentional
echo       kernel crash instead of a clean shutdown. Crash dumps are
echo       disabled automatically at trigger time and stay off. With
echo       VeraCrypt/BitLocker, keys may remain in RAM until power off.
echo       Loop guard: max %BSOD_MAX% bugchecks per %BSOD_WINDOW% min, then
echo       triggers use a normal shutdown instead of crashing.
echo       Check the startup line below ends with: action bsod
:install_mode_done
if "%DURESS%"=="1" if not defined DURESS_NAMES (
    echo   [WARN] duress is ON but NO duress usernames are configured.
    echo       The duress feature does NOTHING in this state. Add names
    echo       via option 7, then re-run this option.
)
echo(
echo   Watcher startup line - duress names must appear in parentheses:
powershell -NoProfile -Command "if (Test-Path '%LOGF%') { Get-Content -Path '%LOGF%' -Tail 2 }"
echo(
echo   Log: %LOGF%
pause
goto :menu

rem ------------------ STATUS ------------------
:status
call :du_load
cls
echo ================= failguard status =================
schtasks /query /tn "%TASK%" >nul 2>&1
if errorlevel 1 (
    echo   task      : NOT installed - run option 1 first.
    echo(
    pause
    goto :menu
)
echo   task      : installed
call :mode_load
echo   action    : %SHUTDOWN_MODE%
set "DEPLOYED="
if exist "%PSFILE%" for /f "usebackq tokens=3 delims= " %%M in (`findstr /B "$mode" "%PSFILE%" 2^>nul`) do set "DEPLOYED=%%M"
if defined DEPLOYED echo   deployed : %DEPLOYED%
if defined DEPLOYED if /i not "%DEPLOYED%"=="'%SHUTDOWN_MODE%'" (
    echo   [WARN] configured action is %SHUTDOWN_MODE% but the RUNNING
    echo         watcher was installed with %DEPLOYED%. Run option 1 to apply.
)
if /i not "%SHUTDOWN_MODE%"=="bsod" goto :status_mode_done
echo   [!] BSOD MODE - trigger causes an intentional kernel crash.
echo       Crash dumps are disabled at trigger time (FDE precaution)
echo       and stay off. Keys may remain in RAM until power is cut.
:status_mode_done
schtasks /query /tn "%TASK%" /xml 2>nul | findstr /C:"<Enabled>false" >nul
if errorlevel 1 (echo   task state: ENABLED) else echo   task state: disabled
powershell -NoProfile -Command "$p = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*failguard.ps1*' -and $_.ProcessId -ne $PID }; if ($p) { '   watcher  : RUNNING' } else { '   watcher  : not running' }"
if "%DURESS%"=="1" goto :status_duress_on
echo   duress    : off
goto :status_duress_done
:status_duress_on
echo   duress    : ON - delay %DURESS_DELAY%s after trigger
if not defined DURESS_NAMES (
    echo   duress names: NONE - duress layer inactive. Use option 7.
    goto :status_duress_done
)
echo   duress names: %DURESS_NAMES%
powershell -NoProfile -Command "$names = @('%DURESS_NAMES%'.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }); foreach ($n in $names) { try { $u = Get-LocalUser -Name $n -ErrorAction Stop; Write-Output ('   ' + $n + ' : account exists') } catch { Write-Output ('   ' + $n + ' : NO Windows account with this name') } }"
:status_duress_done
echo   logon auditing (effective policy - Group Policy may override auditpol):
auditpol /get /subcategory:"%AUDIT_LOGON%" 2>nul
echo(
powershell -NoProfile -Command "$types=@(%TYPES%); $since=(Get-Date).AddMinutes(-%WINDOW%); try { $f=[datetime]::ParseExact((Get-Content '%DEST%\failguard.state' -Raw).Trim(),'s',[System.Globalization.CultureInfo]::InvariantCulture); if ($f -gt $since) { $since=$f } } catch {}; $n=0; try { $evs = Get-WinEvent -FilterHashtable @{LogName='Security';Id=4625;StartTime=$since} -ErrorAction Stop; foreach ($e in $evs) { $x=[xml]$e.ToXml(); $t=($x.Event.EventData.Data | Where-Object { $_.Name -eq 'LogonType' }).'#text'; if ($t -and ($types -contains [int]$t)) { $n++ } } } catch {}; '   failed logons since floor: ' + $n + '   (shutdown at ' + %THRESHOLD% + ')'"
echo =====================================================
pause
goto :menu

rem ------------------ RECENT FAILURES ------------------
:recent
cls
echo Recent failed logons (newest first, up to 15):
echo(
powershell -NoProfile -Command "Get-WinEvent -FilterHashtable @{LogName='Security';Id=4625} -MaxEvents 15 -ErrorAction SilentlyContinue | ForEach-Object { $x=[xml]$_.ToXml(); $u=($x.Event.EventData.Data | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'; $t=($x.Event.EventData.Data | Where-Object { $_.Name -eq 'LogonType' }).'#text'; '{0,-22}  type {1,-3}  {2}' -f $_.TimeCreated, $t, $u }"
echo(
echo type 2 = login screen, 7 = unlock, 10 = RDP, 3 = network share etc.
pause
goto :menu

:openlog
if exist "%LOGF%" (start "" notepad "%LOGF%") else echo   No log yet.
pause
goto :menu

rem ------------------ TOGGLE ------------------
:toggle
schtasks /query /tn "%TASK%" >nul 2>&1
if errorlevel 1 (
    echo   Not installed yet - run option 1 first.
    pause
    goto :menu
)
schtasks /query /tn "%TASK%" /xml 2>nul | findstr /C:"<Enabled>false" >nul
if errorlevel 1 (
    schtasks /change /tn "%TASK%" /disable >nul
    call :killwatcher
    echo   [-] failguard DISABLED - watcher stopped, boots dormant until re-enabled
) else (
    schtasks /change /tn "%TASK%" /enable >nul
    schtasks /run /tn "%TASK%" >nul 2>&1
    echo   [+] failguard ENABLED - watcher running again
)
pause
goto :menu

rem ------------------ DURESS SETTINGS ------------------
:duress
call :mkdest
call :du_load
cls
echo ================ duress settings ================
echo   enabled : %DURESS%
echo   names   : %DURESS_NAMES%
echo   delay   : %DURESS_DELAY%s after trigger
echo --------------------------------------------------
echo   a. Add duress username
echo   c. Clear duress usernames
echo   t. Toggle enable / disable
echo   n. Create matching Windows account (auto-registers)
echo   b. Back
echo ==================================================
set "DCH="
set /p "DCH=Select [a/c/t/n/b]: "
if /i "%DCH%"=="a" goto :du_add
if /i "%DCH%"=="c" goto :du_clear
if /i "%DCH%"=="t" goto :du_toggle
if /i "%DCH%"=="n" goto :du_account
if /i "%DCH%"=="b" goto :menu
goto :duress

:du_add
set "DN="
set /p "DN=Duress username: "
if not defined DN goto :duress
call :validname DN
if errorlevel 1 (
    echo   [WARN] Use 1-20 characters: letters, digits, dot, underscore, hyphen,
    echo       and inner spaces only.
    pause
    goto :duress
)
if exist "%NAMESF%" findstr /X /I /C:"%DN%" "%NAMESF%" >nul 2>&1 && (
    echo   [i] Already registered.
    pause
    goto :duress
)
>>"%NAMESF%" echo %DN%
> "%DEST%\duress.enabled" echo 1
call :du_load
echo   [+] added: %DN%
echo       Any logon attempt on this name - correct OR wrong password -
echo       now triggers shutdown. Run option 1 to apply.
pause
goto :duress

:du_clear
del "%NAMESF%" >nul 2>&1
call :du_load
echo   [-] cleared. Run option 1 to apply.
pause
goto :duress

:du_toggle
set "NEWV=1"
if "%DURESS%"=="1" set "NEWV=0"
> "%DEST%\duress.enabled" echo %NEWV%
call :du_load
if "%DURESS%"=="%NEWV%" (
    echo   [+] duress flag is now %DURESS% - 1 = on, 0 = off. Run option 1 to apply.
) else (
    echo   [WARN] Could not change the duress flag - the setting is NOT changed.
)
pause
goto :duress

:du_account
echo(
echo Creates a real local account AND registers it as a duress name.
echo Its tile appears on the login screen. Give away ITS password
echo under pressure - any logon attempt on it shuts the machine down.
echo(
set "AN="
set /p "AN=Username: "
if not defined AN goto :duress
call :validname AN
if errorlevel 1 (
    echo   [WARN] Use 1-20 characters: letters, digits, dot, underscore, hyphen,
    echo       and inner spaces only.
    pause
    goto :duress
)
rem Password is read hidden inside PowerShell and never appears on a command line
powershell -NoProfile -Command "$p = Read-Host 'Password (hidden)' -AsSecureString; try { New-LocalUser -Name $env:AN -Password $p -PasswordNeverExpires -AccountNeverExpires -ErrorAction Stop | Out-Null; Add-LocalGroupMember -SID S-1-5-32-545 -Member $env:AN -ErrorAction Stop; exit 0 } catch { Write-Host ('   ' + $_.Exception.Message); exit 1 }"
if errorlevel 1 (
    echo   [WARN] Could not create the account - it may already exist or
    echo       the name/password failed policy. If it already exists,
    echo       just register it with option a instead.
) else (
    >>"%NAMESF%" echo %AN%
    > "%DEST%\duress.enabled" echo 1
    call :du_load
    echo   [+] Account created and registered as duress name: %AN%
    echo       Run option 1 - Install - to apply.
)
pause
goto :duress

rem ------------------ UNINSTALL ------------------
:uninstall
echo(
echo This removes the watcher, task, log and duress settings.
echo Duress ACCOUNTS created via the menu are left alone - remove
echo them yourself with:  net user NAME /delete
set "CFM="
set /p "CFM=Continue? [y/N]: "
if /i not "%CFM%"=="y" goto :menu
call :killwatcher
schtasks /delete /tn "%TASK%" /f >nul 2>&1
if exist "%DEST%\crashdump.bak" (
    powershell -NoProfile -Command "try { $v = (Get-Content '%DEST%\crashdump.bak' -Raw).Trim(); Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name CrashDumpEnabled -Value ([int]$v) -Type DWord -ErrorAction Stop; Write-Host ('   crash dumps restored to CrashDumpEnabled=' + $v) } catch { Write-Host ('   [WARN] could not restore crash dump setting: ' + $_.Exception.Message) }"
) else (
    echo   Crash dump setting left as-is ^(BSOD mode never disabled it here^).
)
echo   NOTE: the Logon audit policy and the enlarged Security log size
echo         are left in place - undo manually if you want them reverted.
rd /s /q "%DEST%" >nul 2>&1
echo   Removed.
pause
goto :menu

rem ---------------------- HELPERS ----------------------
:mkdest
if not exist "%DEST%" md "%DEST%"
set "ACLLOG=%TEMP%\failguard_acl.txt"
> "%ACLLOG%" echo ACL step log
if not "%LOCKDOWN%"=="1" goto :mkdest_test
rem Self-healing: take ownership first (we are admin) so a broken ACL from an earlier run can always be repaired
takeown /f "%DEST%" /a /r /d y >>"%ACLLOG%" 2>&1
rem Grant FIRST, then drop inheritance, so the folder is never left without an allow entry
icacls "%DEST%" /grant:r "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-544:(OI)(CI)F" >>"%ACLLOG%" 2>&1
icacls "%DEST%" /inheritance:r >>"%ACLLOG%" 2>&1
rem Existing files: reset to inherit from the folder (never use /T with the grant above - it left files with an empty ACL)
icacls "%DEST%\*" /reset /C >>"%ACLLOG%" 2>&1
:mkdest_test
type nul > "%DEST%\.wtest" 2>nul
if exist "%DEST%\.wtest" (
    del "%DEST%\.wtest" >nul 2>&1
) else (
    echo   [WARN] Cannot write to %DEST%
    echo   Output of the permission step:
    type "%ACLLOG%"
    echo   Current permissions:
    icacls "%DEST%"
)
goto :eof

:validname
rem usage: call :validname VARNAME   (checks the env var directly, so no cmd metacharacter can leak)
powershell -NoProfile -Command "$v = [Environment]::GetEnvironmentVariable('%~1'); if ($v -match '^[A-Za-z0-9._-]([A-Za-z0-9._ -]{0,18}[A-Za-z0-9._-])?$') { exit 0 } else { exit 1 }"
goto :eof

:du_load
set "DURESS_NAMES="
if exist "%NAMESF%" for /f "usebackq delims=" %%N in ("%NAMESF%") do (
    if defined DURESS_NAMES (
        set "DURESS_NAMES=!DURESS_NAMES!,%%N"
    ) else (
        set "DURESS_NAMES=%%N"
    )
)
if exist "%DEST%\duress.enabled" (
    set "DURESS="
    set /p DURESS=<"%DEST%\duress.enabled"
)
if not defined DURESS set "DURESS=1"
goto :eof

:mode_load
set "SHUTDOWN_MODE=normal"
if exist "%DEST%\shutdown.mode" (
    set "SHUTDOWN_MODE="
    set /p SHUTDOWN_MODE=<"%DEST%\shutdown.mode"
)
if not defined SHUTDOWN_MODE set "SHUTDOWN_MODE=normal"
if /i not "%SHUTDOWN_MODE%"=="bsod" set "SHUTDOWN_MODE=normal"
goto :eof

:mode_save
call :mkdest
> "%DEST%\shutdown.mode" echo %~1
set "SHUTDOWN_MODE=%~1"
goto :eof

:killwatcher
schtasks /end /tn "%TASK%" >nul 2>&1
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*failguard.ps1*' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1
goto :eof

rem ---------------- PowerShell watcher body (extracted at install) ----------------
#PS:$state  = Join-Path (Split-Path $log) 'failguard.state'
#PS:function L($m) { Add-Content -Path $log -Value ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) }
#PS:function NormalShutdown($t, $why) {
#PS:    $out = (shutdown.exe /s /f /t $t /c $banner 2>&1 | Out-String).Trim()
#PS:    L ('shutdown({0}): rc={1} {2}' -f $why, $LASTEXITCODE, $out)
#PS:    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1190) { $script:sdFails = $script:sdFails + 1 } else { $script:sdFails = 0 }
#PS:    if ($script:sdFails -ge 3) { L ('shutdown keeps failing - forcing immediate power-off'); Stop-Computer -Force }
#PS:}
#PS:function BugCheck {
#PS:    # FDE precaution: never intentionally create a crash dump that could
#PS:    # contain encryption keys. Default Windows has dumps ON (value 7), so
#PS:    # disabling them here at trigger time is the expected path, not an error.
#PS:    try {
#PS:        $ccKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
#PS:        $cc = Get-ItemProperty -Path $ccKey -ErrorAction Stop
#PS:        if ($cc.CrashDumpEnabled -ne 0) {
#PS:            # remember the original value once so uninstall can restore it
#PS:            $bak = Join-Path (Split-Path $log) 'crashdump.bak'
#PS:            if (-not (Test-Path $bak)) { try { $cc.CrashDumpEnabled | Set-Content -Path $bak } catch {} }
#PS:            Set-ItemProperty -Path $ccKey -Name CrashDumpEnabled -Value 0 -Type DWord -ErrorAction Stop
#PS:            L ('FDE precaution: crash dumps were enabled ({0}) - disabled before bugcheck' -f $cc.CrashDumpEnabled)
#PS:        }
#PS:    } catch {
#PS:        # Cannot verify or disable dump policy - fail closed to a normal shutdown.
#PS:        L ('BSOD aborted: cannot verify/disable crash dump policy ({0}); using normal shutdown' -f $_.Exception.Message)
#PS:        NormalShutdown 0 'bsod-unverified'
#PS:        return
#PS:    }
#PS:    # Loop protection: a bugcheck reboots the machine and the watcher
#PS:    # restarts at boot - without this guard a persistent trigger source
#PS:    # (e.g. ongoing brute force, auto-reboot) could crash it every cycle.
#PS:    $crashFile = Join-Path (Split-Path $log) 'failguard.crashes'
#PS:    # UTC timestamps so clock changes / DST cannot skew the loop-guard window
#PS:    $now = (Get-Date).ToUniversalTime()
#PS:    $hist = @()
#PS:    try {
#PS:        if (Test-Path $crashFile) {
#PS:            foreach ($ln in @(Get-Content $crashFile -ErrorAction Stop)) {
#PS:                try { $t2 = [datetime]::ParseExact($ln.Trim(), 'u', [System.Globalization.CultureInfo]::InvariantCulture); if ($t2 -gt $now.AddMinutes(-$bsodWindowMin)) { $hist += $t2 } } catch {}
#PS:            }
#PS:        }
#PS:    } catch { $hist = @() }
#PS:    if ($hist.Count -ge $bsodMax) {
#PS:        L ('BSOD LOOP PROTECTION: {0} bugchecks already issued within {1} min - using normal shutdown instead' -f $hist.Count, $bsodWindowMin)
#PS:        NormalShutdown 0 'bsod-loop-guard'
#PS:        return
#PS:    }
#PS:    try { @($hist | ForEach-Object { $_.ToUniversalTime().ToString('u') }) + @($now.ToString('u')) | Set-Content -Path $crashFile -ErrorAction Stop } catch { L ('WARN: cannot write crash counter ({0})' -f $_.Exception.Message) }
#PS:    L ('bugcheck #{0} within the last {1} min (max {2})' -f ($hist.Count + 1), $bsodWindowMin, $bsodMax)
#PS:    # NtRaiseHardError with OptionShutdownSystem forces a kernel bugcheck.
#PS:    # This intentionally does NOT write or alter any disk encryption settings.
#PS:    if (-not $nativeOk) {
#PS:        L ('BSOD aborted: bugcheck stub not loaded (see startup log) - using normal shutdown')
#PS:        NormalShutdown 0 'bsod-native-missing'
#PS:        return
#PS:    }
#PS:    $wasEnabled = $false
#PS:    # 19 = SeShutdownPrivilege - required for the hard-error shutdown option.
#PS:    $rc = [FailGuard_Native]::RtlAdjustPrivilege(19, $true, $false, [ref]$wasEnabled)
#PS:    $handled = 0
#PS:    # 0xC0000022 = STATUS_ACCESS_DENIED; option 6 = OptionShutdownSystem (kernel bugcheck).
#PS:    # NOTE: written as decimal - PowerShell parses hex literals >= 0x80000000 as NEGATIVE
#PS:    # Int32, which cannot be converted to the uint parameter and throws.
#PS:    $hr = [FailGuard_Native]::NtRaiseHardError([uint32]3221225506, 0, 0, [IntPtr]::Zero, 6, [ref]$handled)
#PS:    L ('bugcheck: privilege rc={0} hardError rc={1} handled={2}' -f $rc, $hr, $handled)
#PS:    # If the bugcheck did not take effect, do not hang: fall back to a forced power-off.
#PS:    Start-Sleep -Seconds 5
#PS:    Stop-Computer -Force
#PS:}
#PS:function SD($t, $why) {
#PS:    if ($mode -eq 'bsod') {
#PS:        if ($t -gt 0) { Start-Sleep -Seconds $t }
#PS:        L ('BSOD TRIGGER: {0} - raising hard error' -f $why)
#PS:        BugCheck
#PS:    } else {
#PS:        # Let shutdown.exe own the countdown so the machine still goes down
#PS:        # even if this watcher process dies during the delay.
#PS:        NormalShutdown $t $why
#PS:    }
#PS:}
#PS:$start = Get-Date
#PS:$floor = $start
#PS:if (Test-Path $state) { try { $floor = [datetime]::ParseExact((Get-Content $state -Raw).Trim(), 's', [System.Globalization.CultureInfo]::InvariantCulture) } catch { $floor = $start } }
#PS:# consistent floor rule: never count events from before the current boot
#PS:if ($floor -lt $start) { $floor = $start }
#PS:$last = 0
#PS:try { $last = (Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625 } -MaxEvents 1 -ErrorAction Stop).RecordId } catch { $last = 0 }
#PS:$duressList = @($duressNames | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
#PS:$sdFails = 0
#PS:$lastErr = ''
#PS:function Hold($sec) { for ($i = 0; $i -lt $sec; $i++) { $script:floor = Get-Date; $script:floor.ToString('s') | Set-Content -Path $state; Start-Sleep -Seconds 1 } }
#PS:$banner = 'failguard: too many failed sign-in attempts'
#PS:$typeQ = '(' + (($types | ForEach-Object { "Data[@Name='LogonType']='$_'" }) -join ' or ') + ')'
#PS:$nativeOk = $false
#PS:if ($mode -eq 'bsod') {
#PS:    # Compile the bugcheck stub ONCE at startup so a compile failure
#PS:    # (constrained language mode, no temp access, AV) shows in the log
#PS:    # at install/boot time - not silently during an actual trigger.
#PS:    try {
#PS:        if (-not ('FailGuard_Native' -as [type])) {
#PS:            Add-Type -TypeDefinition @'
#PS:using System;
#PS:using System.Runtime.InteropServices;
#PS:public static class FailGuard_Native {
#PS:    [DllImport("ntdll.dll")] public static extern uint RtlAdjustPrivilege(int privilege, bool enable, bool currentThread, out bool enabled);
#PS:    [DllImport("ntdll.dll")] public static extern uint NtRaiseHardError(uint status, uint args, uint mask, IntPtr ptr, uint option, out uint handled);
#PS:}
#PS:'@
#PS:        }
#PS:        $nativeOk = $true
#PS:        L ('bugcheck stub compiled and ready')
#PS:    } catch { L ('ERROR: bugcheck stub failed to compile ({0}) - BSOD triggers will use a normal shutdown' -f $_.Exception.Message) }
#PS:}
#PS:L ('watcher started; ignoring events before {0}; threshold {1}/{2}min types ({3}); duress {4} names ({5}) delay {6}s dry {7}; action {8}' -f $floor, $threshold, $windowMin, ($types -join ','), $duress, ($duressList -join ','), $duressDelay, $dry, $mode)
#PS:while ($true) {
#PS:    $now = Get-Date
#PS:    $since = $now.AddMinutes(-$windowMin)
#PS:    if ($floor -gt $since) { $since = $floor }
#PS:    $n = 0
#PS:    $duressHit = ''
#PS:    # Filter by event id, age and logon type inside the event log service (cheap) instead of parsing everything
#PS:    $ms = [int][Math]::Max(1000, ($now - $since).TotalMilliseconds + 2000)
#PS:    $q = "*[System[(EventID=4624 or EventID=4625) and TimeCreated[timediff(@SystemTime) <= $ms]]] and *[EventData[$typeQ]]"
#PS:    try { $evs = @(Get-WinEvent -LogName Security -FilterXPath $q -ErrorAction Stop | Sort-Object TimeCreated); $lastErr = '' } catch { $evs = @(); if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*' -and $_.Exception.Message -ne $lastErr) { $lastErr = $_.Exception.Message; L ('event query failed: ' + $lastErr) } }
#PS:    foreach ($e in $evs) {
#PS:        if ($e.TimeCreated -lt $since) { continue }
#PS:        $x = [xml]$e.ToXml()
#PS:        $u = ($x.Event.EventData.Data | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
#PS:        $t = ($x.Event.EventData.Data | Where-Object { $_.Name -eq 'LogonType' }).'#text'
#PS:        $uLow = ''
#PS:        if ($u) { $uLow = $u.Trim().ToLower() }
#PS:        $tOk = $t -and ($types -contains [int]$t)
#PS:        if ($e.Id -eq 4625) {
#PS:            if ($e.RecordId -and ($e.RecordId -gt $last)) {
#PS:                $last = $e.RecordId
#PS:                if ($e.TimeCreated -ge $start) { L ('failed logon: account {0}, type {1}' -f $u, $t) }
#PS:            }
#PS:            if ($tOk) { $n = $n + 1 }
#PS:        }
#PS:        if ($duress -and $tOk -and $uLow -and ($duressList -contains $uLow)) { $duressHit = $uLow }
#PS:    }
#PS:    if ($duressHit) {
#PS:        # Move the floor forward so these events are never counted again (works for dry run and aborted shutdowns)
#PS:        $floor = Get-Date
#PS:        $floor.ToString('s') | Set-Content -Path $state
#PS:        L ('DURESS TRIGGER: account {0} - shutdown in {1}s' -f $duressHit, $duressDelay)
#PS:        if ($dry) { L '(dry run - no shutdown issued)' } else { SD $duressDelay 'duress' }
#PS:        Hold 15
#PS:    } elseif ($n -ge $threshold) {
#PS:        $floor = Get-Date
#PS:        $floor.ToString('s') | Set-Content -Path $state
#PS:        L ('TRIGGER: {0} failed logons within window - shutting down in {1}s' -f $n, $grace)
#PS:        if ($dry) { L '(dry run - no shutdown issued)' } else { SD $grace 'threshold' }
#PS:        Hold ($grace + 10)
#PS:    } else {
#PS:        Start-Sleep -Seconds $poll
#PS:    }
#PS:}

rem ---------------- BSOD test body (extracted by option 9 - t) ----------------
#PST:$ccKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl'
#PST:# Loop protection - same rule as the watcher: max 3 bugchecks per 240 min.
#PST:$crashFile = Join-Path $PSScriptRoot 'failguard.crashes'
#PST:$now = (Get-Date).ToUniversalTime()
#PST:$hist = @()
#PST:try {
#PST:    if (Test-Path $crashFile) {
#PST:        foreach ($ln in @(Get-Content $crashFile -ErrorAction Stop)) {
#PST:            try { $t2 = [datetime]::ParseExact($ln.Trim(), 'u', [System.Globalization.CultureInfo]::InvariantCulture); if ($t2 -gt $now.AddMinutes(-240)) { $hist += $t2 } } catch {}
#PST:        }
#PST:    }
#PST:} catch { $hist = @() }
#PST:if ($hist.Count -ge 3) {
#PST:    Write-Host ('REFUSED: ' + $hist.Count + ' bugchecks already issued within 240 min - loop protection. Normal shutdown instead.')
#PST:    exit 2
#PST:}
#PST:try { @($hist | ForEach-Object { $_.ToUniversalTime().ToString('u') }) + @($now.ToString('u')) | Set-Content -Path $crashFile -ErrorAction Stop } catch { Write-Host ('WARN: cannot write crash counter: ' + $_.Exception.Message) }
#PST:try {
#PST:    $cc = Get-ItemProperty -Path $ccKey -ErrorAction Stop
#PST:    if ($cc.CrashDumpEnabled -ne 0) {
#PST:        $bak = Join-Path $PSScriptRoot 'crashdump.bak'
#PST:        if (-not (Test-Path $bak)) { try { $cc.CrashDumpEnabled | Set-Content -Path $bak } catch {} }
#PST:        Set-ItemProperty -Path $ccKey -Name CrashDumpEnabled -Value 0 -Type DWord -ErrorAction Stop
#PST:        Write-Host 'crash dumps were enabled - disabled before test bugcheck'
#PST:    }
#PST:} catch {
#PST:    Write-Host ('ABORTED: cannot disable crash dumps: ' + $_.Exception.Message)
#PST:    exit 1
#PST:}
#PST:Add-Type -TypeDefinition @'
#PST:using System;
#PST:using System.Runtime.InteropServices;
#PST:public static class FailGuard_Test {
#PST:    [DllImport("ntdll.dll")] public static extern uint RtlAdjustPrivilege(int privilege, bool enable, bool currentThread, out bool enabled);
#PST:    [DllImport("ntdll.dll")] public static extern uint NtRaiseHardError(uint status, uint args, uint mask, IntPtr ptr, uint option, out uint handled);
#PST:}
#PST:'@
#PST:$wasEnabled = $false
#PST:$rc = [FailGuard_Test]::RtlAdjustPrivilege(19, $true, $false, [ref]$wasEnabled)
#PST:$handled = 0
#PST:# 0xC0000022 = STATUS_ACCESS_DENIED as decimal (hex literals parse as negative Int32 in PS)
#PST:$hr = [FailGuard_Test]::NtRaiseHardError([uint32]3221225506, 0, 0, [IntPtr]::Zero, 6, [ref]$handled)
#PST:Write-Host ('privilege rc={0} hardError rc={1} handled={2} - if no BSOD follows, the hard error was ignored' -f $rc, $hr, $handled)
#PST:Start-Sleep -Seconds 15
#PST:Write-Host 'NO BSOD within 15s - NtRaiseHardError did not bugcheck on this system.'
#PST:Write-Host 'The watcher would fall back to a forced power-off in this situation.'
