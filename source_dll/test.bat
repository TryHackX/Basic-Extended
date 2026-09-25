@echo off
rem Builds and runs the tests (build\test): the store and the writer on their own, then the
rem library itself (build\win32\basicext_dll.dll, so run build.bat first).
setlocal
cd /d "%~dp0"

set "FPC=fpc"
if exist "C:\FPC\3.2.2\bin\i386-win32\fpc.exe" set "FPC=C:\FPC\3.2.2\bin\i386-win32\fpc.exe"
if not exist build\test mkdir build\test

"%FPC%" -B -Pi386 -Twin32 -Mobjfpc -Sh -O1 -gl -Cr -Co -Ci -Fu. -FUbuild\test -FEbuild\test tests\test_store.pas
if errorlevel 1 exit /b 1
"%FPC%" -B -Pi386 -Twin32 -Mobjfpc -Sh -O1 -gl -Cr -Co -Ci -Fu. -FUbuild\test -FEbuild\test tests\test_dll.pas
if errorlevel 1 exit /b 1
"%FPC%" -B -Pi386 -Twin32 -Mobjfpc -Sh -O1 -gl -Cr -Co -Ci -Fu. -FUbuild\test -FEbuild\test tests\test_engine.pas
if errorlevel 1 exit /b 1

build\test\test_store.exe build\test
if errorlevel 1 exit /b 1
build\test\test_dll.exe build\win32\basicext_dll.dll build\test
if errorlevel 1 exit /b 1
build\test\test_engine.exe build\test
if errorlevel 1 exit /b 1
echo All tests passed.
