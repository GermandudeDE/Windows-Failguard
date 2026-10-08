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

:menu
call :du_load
cls
echo ============== failguard v3.2.6 ==============
echo   failsafe : %THRESHOLD% failures / %WINDOW% min / grace %GRACE%s / types %TYPES%
set "DULINE=off"
if "%DURESS%"=="1" set "DULINE=ON  - names: %DURESS_NAMES%"
if "%DURESS%"=="1" if not defined DURESS_NAMES set "DULINE=ON  - NO NAMES CONFIGURED - inactive"
echo   duress   : %DULINE%
echo ----------------------------------------------
echo   1. Install / update (apply config + start)
echo   2. Status
echo   3. Recent failed logons
echo   4. Open log
echo   5. Enable / disable
echo   6. Uninstall
echo   7. Duress settings
echo   8. Exit
echo ==============================================
set "CHOICE="
set /p "CHOICE=Select [1-8]: "
if "%CHOICE%"=="1" goto :install
if "%CHOICE%"=="2" goto :status
if "%CHOICE%"=="3" goto :recent
if "%CHOICE%"=="4" goto :openlog
if "%CHOICE%"=="5" goto :toggle
if "%CHOICE%"=="6" goto :uninstall
if "%CHOICE%"=="7" goto :duress
if "%CHOICE%"=="8" exit /b
goto :menu

rem ------------------ INSTALL ------------------
:install
call :mkdest
call :du_load
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
powershell -NoProfile -Command "$types=@(%TYPES%); $since=(Get-Date).AddMinutes(-%WINDOW%); $n=0; try { $evs = Get-WinEvent -FilterHashtable @{LogName='Security';Id=4625;StartTime=$since} -ErrorAction Stop; foreach ($e in $evs) { $x=[xml]$e.ToXml(); $t=($x.Event.EventData.Data | Where-Object { $_.Name -eq 'LogonType' }).'#text'; if ($t -and ($types -contains [int]$t)) { $n++ } } } catch {}; '   failed logons in last %WINDOW% min: ' + $n + '   (shutdown at ' + %THRESHOLD% + ')'"
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

:killwatcher
schtasks /end /tn "%TASK%" >nul 2>&1
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*failguard.ps1*' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1
goto :eof

rem ---------------- PowerShell watcher body (extracted at install) ----------------
#PS:$state  = Join-Path (Split-Path $log) 'failguard.state'
#PS:function L($m) { Add-Content -Path $log -Value ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) }
#PS:function SD($t, $why) {
#PS:    $out = (shutdown.exe /s /f /t $t /c $banner 2>&1 | Out-String).Trim()
#PS:    L ('shutdown({0}): rc={1} {2}' -f $why, $LASTEXITCODE, $out)
#PS:    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1190) { $script:sdFails = $script:sdFails + 1 } else { $script:sdFails = 0 }
#PS:    if ($script:sdFails -ge 3) { L ('shutdown keeps failing - forcing immediate power-off'); Stop-Computer -Force }
#PS:}
#PS:$start = Get-Date
#PS:$floor = $start
#PS:if (Test-Path $state) { try { $floor = [datetime]::Parse((Get-Content $state -Raw)) } catch { $floor = $start } }
#PS:$last = 0
#PS:try { $last = (Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625 } -MaxEvents 1 -ErrorAction Stop).RecordId } catch { $last = 0 }
#PS:$duressList = @($duressNames | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
#PS:$sdFails = 0
#PS:$lastErr = ''
#PS:function Hold($sec) { for ($i = 0; $i -lt $sec; $i++) { $script:floor = Get-Date; $script:floor.ToString('o') | Set-Content -Path $state; Start-Sleep -Seconds 1 } }
#PS:$banner = 'failguard: too many failed sign-in attempts'
#PS:$typeQ = '(' + (($types | ForEach-Object { "Data[@Name='LogonType']='$_'" }) -join ' or ') + ')'
#PS:L ('watcher started; ignoring events before {0}; threshold {1}/{2}min types ({3}); duress {4} names ({5}) delay {6}s dry {7}' -f $floor, $threshold, $windowMin, ($types -join ','), $duress, ($duressList -join ','), $duressDelay, $dry)
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
#PS:        $floor.ToString('o') | Set-Content -Path $state
#PS:        L ('DURESS TRIGGER: account {0} - shutdown in {1}s' -f $duressHit, $duressDelay)
#PS:        if ($dry) { L '(dry run - no shutdown issued)' } else { SD $duressDelay 'duress' }
#PS:        Hold 15
#PS:    } elseif ($n -ge $threshold) {
#PS:        $floor = Get-Date
#PS:        $floor.ToString('o') | Set-Content -Path $state
#PS:        L ('TRIGGER: {0} failed logons within window - shutting down in {1}s' -f $n, $grace)
#PS:        if ($dry) { L '(dry run - no shutdown issued)' } else { SD $grace 'threshold' }
#PS:        Hold ($grace + 10)
#PS:    } else {
#PS:        Start-Sleep -Seconds $poll
#PS:    }
#PS:}
