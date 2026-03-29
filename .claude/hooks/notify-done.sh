#!/bin/bash
# Stop/Notification hook — Windows 토스트 알림 (작업 완료 시)
powershell.exe -NoProfile -Command "
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Media
\$n = New-Object System.Windows.Forms.NotifyIcon
\$n.Icon = [System.Drawing.SystemIcons]::Information
\$n.Visible = \$true
\$n.ShowBalloonTip(3000, 'Claude Code', '블로그 작업이 완료되었습니다', [System.Windows.Forms.ToolTipIcon]::Info)
[System.Media.SystemSounds]::Asterisk.Play()
Start-Sleep 4
\$n.Dispose()
" 2>/dev/null
