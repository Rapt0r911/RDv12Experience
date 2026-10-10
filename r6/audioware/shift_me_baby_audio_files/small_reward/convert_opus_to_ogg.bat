@echo off
title Opus to OGG Converter
echo.
echo  Converting all .opus files in this folder to .ogg ...
echo.

for %%f in (*.opus) do (
    echo Converting: %%f
    ffmpeg -i "%%f" -c:a libvorbis -q:a 5 "%%~nf.ogg" -y
)

echo.
echo  Done!
echo  Press any key to close...
pause >nul