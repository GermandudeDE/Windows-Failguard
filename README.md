# Windows-Failguard
failguard installs a small watcher that runs as SYSTEM at every boot. It shuts the PC down when: THRESHOLD failed sign-ins within WINDOW minutes after GRACE seconds. OR: any logon attempt on a registered duress username, with a right or wrong password, causes a shutdown after DURESS_DELAY seconds.
