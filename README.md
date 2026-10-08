# Windows-Failguard
failguard installs a small watcher that runs as SYSTEM at every boot. It shuts the PC down when: THRESHOLD failed sign-ins within WINDOW minutes after GRACE seconds. OR: any logon attempt on a registered duress username, with a right or wrong password, causes a shutdown after DURESS_DELAY seconds.

The batch file is the control panel. It installs the watcher, registers the scheduled task, and lets you check status and the log.

Why?
If someone guesses passwords at your lock screen, or pressures you to unlock the machine, a shutdown puts it back into a cold, locked state. The duress account is a decoy you can hand over: using it looks normal but powers the machine off. This only protects you if the disk is encrypted (e.g. Veracrypt) and the machine isn't left in a hibernated or unlocked state.

How to edit it correctly
Settings: change values in the CONFIG block at the top of the .bat (THRESHOLD, WINDOW, GRACE, TYPES, DRYRUN, and so on). Then run option 1. The watcher reads a generated file in C:\ProgramData\failguard, not the .bat, so nothing takes effect until you reinstall (with option 1 within the command prompt).
Duress names: use option 7, then option 1. Names may use letters, digits, ., _, -, and inner spaces, up to 20 characters.
Test before going live: set DRYRUN=1, reinstall, trigger it, and check the log (option 4). Then set DRYRUN=0 and reinstall.
Don't edit the generated failguard.ps1. It gets overwritten on every install. Change the #PS: lines in the .bat instead, and keep the #PS: prefix on every one.
File format: keep the file ASCII with CRLF line endings. Avoid ! in echo text because delayed expansion eats it. Leave LOCKDOWN=1, and don't add /T to the icacls lines, since that's what emptied the file permissions earlier.
Uninstall: option 6 removes the task and the folder. Duress accounts you created stay until you delete them with net user NAME /delete.

Type 10 counts RDP attempts, so anyone who can reach port 3389 could shut the machine down.
