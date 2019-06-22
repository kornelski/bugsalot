@setlocal
@set ERRORS=0
@where rustup >NUL 2>NUL && goto :skip-install-rustup
@where curl >NUL 2>NUL || goto :cannot-auto-install-rustup
curl -sSf -o %TEMP%\rustup-init.exe https://win.rustup.rs
%TEMP%\rustup-init.exe --default-toolchain stable -y
@set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"
:skip-install-rustup

                  rustup toolchain install stable                                 || set ERRORS=1
                  rustup toolchain install nightly                                || set ERRORS=1
if not defined CI rustup target add --toolchain stable i686-pc-windows-msvc       || set ERRORS=1
if not defined CI rustup target add --toolchain stable x86_64-pc-windows-msvc     || set ERRORS=1
                  rustup target add --toolchain stable wasm32-unknown-unknown     || set ERRORS=1
                  rustup target add --toolchain stable i686-linux-android         || set ERRORS=1
if not defined CI rustup target add --toolchain nightly i686-pc-windows-msvc      || set ERRORS=1
if not defined CI rustup target add --toolchain nightly x86_64-pc-windows-msvc    || set ERRORS=1
                  rustup target add --toolchain nightly wasm32-unknown-unknown    || set ERRORS=1
                  rustup target add --toolchain nightly i686-linux-android        || set ERRORS=1

if defined CI wslconfig /setdefault ubuntu
wsl curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o rustup-init.sh   || set ERRORS=1
wsl sh rustup-init.sh --default-toolchain stable -y                               || set ERRORS=1
wsl rustup toolchain install stable'                                              || set ERRORS=1
wsl rustup toolchain install nightly'                                             || set ERRORS=1

@echo.
@echo.
@if     "%ERRORS%" == "0" echo Installed tools with no errors.
@if not "%ERRORS%" == "0" echo INSTALLATION ERRORS
@echo.
@echo.
@endlocal && set "PATH=%PATH%" && exit /b %ERRORS%



:cannot-auto-install-rustup
@echo.
@echo.
@echo INSTALLATION ERRORS:
@echo curl not found in %%PATH%%, cannot auto-install rustup.
@echo.
@echo.
@endlocal && exit /b 1
