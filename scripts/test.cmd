:: Main entry point
@setlocal
@if defined CI echo on
@if defined CI set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"

@set ERRORS=0
@set BUILDS_LOG="%TEMP%\bugsalot-builds-list.txt"
@echo Channel    Config     Platform   Result>%BUILDS_LOG%
@echo ---------------------------------------->>%BUILDS_LOG%
@call :build %*
@if "%ERRORS%" == "0" goto :all-builds-succeeded
@goto :some-builds-failed

:all-builds-succeeded
@echo.
@echo.
@type %BUILDS_LOG%
@echo.
@echo.
@echo Build succeeded!
@echo.
@echo.
@endlocal && exit /b 0

:some-builds-failed
@echo.
@echo.
@type %BUILDS_LOG%
@echo.
@echo.
@echo Build failed!
@echo.
@echo.
@endlocal && exit /b 1



:build
@setlocal

:: Parameters

@set "CHANNEL=%~1"
:: stable
:: beta
:: nightly
@if not defined CHANNEL set CHANNEL=*

@set "CONFIG=%~2"
:: debug
:: release
@if not defined CONFIG set CONFIG=*

@set "PLATFORM=%~3"
:: windows
:: android
:: linux (WSL)
:: wasm
@if not defined PLATFORM set PLATFORM=*

:: Handle wildcards

@if not "%CHANNEL%" == "*" goto :skip-channel-wildcard
  @call :build stable  "%CONFIG%" "%PLATFORM%"
  @call :build beta    "%CONFIG%" "%PLATFORM%"
  @call :build nightly "%CONFIG%" "%PLATFORM%"
  @endlocal && set ERRORS=%ERRORS%&& exit /b 0
:skip-channel-wildcard

@if not "%CONFIG%" == "*" goto :skip-config-wildcard
  @call :build "%CHANNEL%" debug   "%PLATFORM%"
  @call :build "%CHANNEL%" release "%PLATFORM%"
  @endlocal && set ERRORS=%ERRORS%&& exit /b 0
:skip-config-wildcard

@if not "%PLATFORM%" == "*" goto :skip-platform-wildcard
  @call :build "%CHANNEL%" "%CONFIG%" windows
  @call :build "%CHANNEL%" "%CONFIG%" linux
  @call :build "%CHANNEL%" "%CONFIG%" wasm
  @call :build "%CHANNEL%" "%CONFIG%" android
  @endlocal && set ERRORS=%ERRORS%&& exit /b 0
:skip-platform-wildcard

:: If we got this far, CHANNEL, CONFIG, and PLATFORM are all non-wildcards.

@set "PAD=                      "
@set "PAD_CHANNEL=%CHANNEL%%PAD%"
@set "PAD_CONFIG=%CONFIG%%PAD%"
@set "PAD_PLATFORM=%PLATFORM%%PAD%"
@set "PAD_CHANNEL=%PAD_CHANNEL:~0,10%"
@set "PAD_CONFIG=%PAD_CONFIG:~0,10%"
@set "PAD_PLATFORM=%PAD_PLATFORM:~0,10%"

:: Skip some builds due to earlier errors, non-bugsalot bugs, being too lazy to install the beta toolchain, etc.

@if not "%ERRORS%" == "0" goto :build-one-skipped
@if /I "%CHANNEL%"  == "beta"                echo Skipping %CHANNEL% %CONFIG% %PLATFORM%: Beta toolchain&& goto :build-one-skipped
@if /I "%PLATFORM%" == "linux" if defined CI echo Skipping %CHANNEL% %CONFIG% %PLATFORM%: Appveyor doesn't have WSL installed&& goto :build-one-skipped

:: Parameters -> Settings

@set CARGO_FLAGS= 
@if /i "%CONFIG%" == "release"   set CARGO_FLAGS=%CARGO_FLAGS% --release



:: Build

@if /i "%PLATFORM%" == "windows" cargo +%CHANNEL% test --all %CARGO_FLAGS% || goto :build-one-error
@if /i "%PLATFORM%" == "windows" goto :build-one-successful



@if /i not "%PLATFORM%" == "android" goto :skip-platform-android
@set ANDROID_AVD_NAME=Nexus_5X_API_29_x86
@set JAVA_HOME=%ProgramFiles%\Android\Android Studio\jre\
@set PATH=%LOCALAPPDATA%\Android\Sdk\platform-tools\;%PATH%
@set PATH=%LOCALAPPDATA%\Android\Sdk\ndk-bundle\toolchains\llvm\prebuilt\windows-x86_64\bin;%PATH%
adb start-server
start "" /B "%LOCALAPPDATA%\Android\Sdk\emulator\emulator" -no-audio -no-window -no-snapshot -no-boot-anim @%ANDROID_AVD_NAME%
:: -no-snapshot:  loading one would speed things up, but this can cause problems in terminated emulators.  Saving is undesired too.
adb wait-for-local-device
@for /f "tokens=1" %%d in ('adb devices ^| findstr emulator-') do @set EMULATOR_DEVICE=%%d
@adb -s %EMULATOR_DEVICE% shell getprop ro.product.cpu.abi | findstr x86_64 && set "NATIVE_ARCH=x86_64" || set "NATIVE_ARCH=i686"
@pushd "%~dp0windows-android"
@set ANDROID_ERROR=0
cargo +%CHANNEL% build --all --tests %CARGO_FLAGS% --target=%NATIVE_ARCH%-linux-android || set ANDROID_ERROR=1
@popd
@if not "%ANDROID_ERROR%" == "0" goto :build-one-error
@pushd "%~dp0..\target\%NATIVE_ARCH%-linux-android\%CONFIG%"
@set ANDROID_TEST_NAME=
@for /f "" %%n in ('dir /OD /B bugsalot-* ^| findstr /v \.d') do @set "ANDROID_TEST_NAME=%%n"
@if not defined ANDROID_TEST_NAME set ANDROID_TEST_NAME=could_not_find_android_test
adb -s %EMULATOR_DEVICE% push "%ANDROID_TEST_NAME%" /data/local/tmp/bugsalot_unit_tests || set ANDROID_ERROR=1
@popd
adb -s %EMULATOR_DEVICE% shell chmod 755 /data/local/tmp/bugsalot_unit_tests || set ANDROID_ERROR=1
adb -s %EMULATOR_DEVICE% shell /data/local/tmp/bugsalot_unit_tests || set ANDROID_ERROR=1
@taskkill /FI "WINDOWTITLE eq Android Emulator - %ANDROID_AVD_NAME%:*" 2>NUL
::@taskkill /F /IM "emulator.exe"
@if not "%ANDROID_ERROR%" == "0" goto :build-one-error
@goto :build-one-successful
:skip-platform-android



@if /i "%PLATFORM%" == "linux" "%WINDIR%\System32\bash" --login -c 'cargo +%CHANNEL% test             %CARGO_FLAGS%' || goto :build-one-error
@if /i "%PLATFORM%" == "linux" "%WINDIR%\System32\bash" --login -c 'cargo +%CHANNEL% build --examples %CARGO_FLAGS%' || goto :build-one-error
@if /i "%PLATFORM%" == "linux" goto :build-one-successful



@if /i "%PLATFORM%" == "wasm" call :install-cargo-web                                                  || goto :build-one-error
@if /i "%PLATFORM%" == "wasm" call :add-chrome-to-path                                                 || goto :build-one-error
@if /i "%PLATFORM%" == "wasm" cargo +%CHANNEL% web build --target=wasm32-unknown-unknown %CARGO_FLAGS% || goto :build-one-error
@if /i "%PLATFORM%" == "wasm" goto :build-one-successful



@echo Unrecognized %%PLATFORM%%: %PLATFORM%
@goto :build-one-error

:: Exit from :build
:build-one-skipped
@echo %PAD_CHANNEL% %PAD_CONFIG% %PAD_PLATFORM% skipped>>%BUILDS_LOG%
@endlocal && set ERRORS=%ERRORS%&& exit /b 0

:build-one-successful
@echo %PAD_CHANNEL% %PAD_CONFIG% %PAD_PLATFORM% ok>>%BUILDS_LOG%
@endlocal && set ERRORS=%ERRORS%&& exit /b 0

:build-one-error
@echo %PAD_CHANNEL% %PAD_CONFIG% %PAD_PLATFORM% ERRORS>>%BUILDS_LOG%
@endlocal && set /A ERRORS=%ERRORS% + 1&& exit /b 1



:: Utilities
:add-chrome-to-path
@where chrome >NUL 2>NUL && exit /b 0
@if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "PATH=%ProgramFiles(x86)%\Google\Chrome\Application\;%PATH%" && exit /b 0
@if exist      "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set      "PATH=%ProgramFiles%\Google\Chrome\Application\;%PATH%" && exit /b 0
@echo ERROR: Cannot find chrome.exe
@exit /b 1

:install-cargo-web
@where cargo-web >NUL 2>NUL && exit /b 0
cargo install cargo-web && exit /b 0
@echo ERROR: Cannot find nor install cargo-web
@exit /b 1
