@echo off
rem 双击即可：拉源码 + 打补丁 + 编译 Windows 便携版
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
pause
