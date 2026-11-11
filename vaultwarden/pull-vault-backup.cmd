@echo off
rem pull-vault-backup.cmd - copy the latest Vaultwarden backup from G7 to this PC.
rem Uses the read-only key %USERPROFILE%\.ssh\vault-backup (it can only download latest.tar.gz).
set DEST=D:\VaultBackups
if not exist "%DEST%" mkdir "%DEST%"
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd"') do set TODAY=%%i
"C:\Windows\System32\OpenSSH\ssh.exe" -T -i "%USERPROFILE%\.ssh\vault-backup" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15 -p 3333 buttmud@192.168.0.6 > "%DEST%\vault-%TODAY%.tar.gz"
if errorlevel 1 (del "%DEST%\vault-%TODAY%.tar.gz" 2>nul & echo Pull failed - is G7 reachable? & exit /b 1)
for %%F in ("%DEST%\vault-%TODAY%.tar.gz") do if %%~zF LSS 1000 (del "%%F" & echo Backup looked empty & exit /b 1)
forfiles /p "%DEST%" /m vault-*.tar.gz /d -60 /c "cmd /c del @path" 2>nul
echo Saved %DEST%\vault-%TODAY%.tar.gz
