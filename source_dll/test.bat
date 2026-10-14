@echo off
rem Builds and runs the tests (build\test): the store and the writer on their own, then the
rem library itself (build\win32\basicext_dll.dll, so run build.bat first).
setlocal
cd /d "%~dp0"

set "FPC=fpc"
if exist "C:\FPC\3.2.2\bin\i386-win32\fpc.exe" set "FPC=C:\FPC\3.2.2\bin\i386-win32\fpc.exe"
if not exist build\test mkdir build\test

"%FPC%" -B -Pi386 -Twin32 -Mobjfpc -Sh -O1 -gl -Cr -Co -Ci -dBE_CHECKS -Fu. -FUbuild\test -FEbuild\test tests\test_store.pas
if errorlevel 1 exit /b 1
"%FPC%" -B -Pi386 -Twin32 -Mobjfpc -Sh -O1 -gl -Cr -Co -Ci -dBE_CHECKS -Fu. -FUbuild\test -FEbuild\test tests\test_dll.pas
if errorlevel 1 exit /b 1
"%FPC%" -B -Pi386 -Twin32 -Mobjfpc -Sh -O1 -gl -Cr -Co -Ci -dBE_CHECKS -Fu. -FUbuild\test -FEbuild\test tests\test_engine.pas
if errorlevel 1 exit /b 1
"%FPC%" -B -Pi386 -Twin32 -Mobjfpc -Sh -O1 -gl -Cr -Co -Ci -dBE_CHECKS -Fu. -FUbuild\test -FEbuild\test tests\test_bridge.pas
if errorlevel 1 exit /b 1
"%FPC%" -B -Pi386 -Twin32 -Mobjfpc -Sh -O1 -gl -Cr -Co -Ci -dBE_CHECKS -Fu. -FUbuild\test -FEbuild\test tests\test_ammo.pas
if errorlevel 1 exit /b 1
"%FPC%" -B -Pi386 -Twin32 -Mobjfpc -Sh -O1 -gl -Cr -Co -Ci -dBE_CHECKS -Fu. -FUbuild\test -FEbuild\test tests\test_rocket.pas
if errorlevel 1 exit /b 1
"%FPC%" -B -Pi386 -Twin32 -Mobjfpc -Sh -O1 -gl -Cr -Co -Ci -dBE_CHECKS -Fu. -FUbuild\test -FEbuild\test tests\test_tk.pas
if errorlevel 1 exit /b 1
"%FPC%" -B -Pi386 -Twin32 -Mobjfpc -Sh -O1 -gl -Cr -Co -Ci -dBE_CHECKS -Fu. -FUbuild\test -FEbuild\test tests\test_mine.pas
if errorlevel 1 exit /b 1
"%FPC%" -B -Pi386 -Twin32 -Mobjfpc -Sh -O1 -gl -Cr -Co -Ci -dBE_CHECKS -Fu. -FUbuild\test -FEbuild\test tests\test_body.pas
if errorlevel 1 exit /b 1
"%FPC%" -B -Pi386 -Twin32 -Mobjfpc -Sh -O1 -gl -Cr -Co -Ci -dBE_CHECKS -Fu. -FUbuild\test -FEbuild\test tests\test_names.pas
if errorlevel 1 exit /b 1
"%FPC%" -B -Pi386 -Twin32 -Mobjfpc -Sh -O1 -gl -Cr -Co -Ci -dBE_CHECKS -Fu. -FUbuild\test -FEbuild\test tests\test_shop.pas
if errorlevel 1 exit /b 1
"%FPC%" -B -Pi386 -Twin32 -Mobjfpc -Sh -O1 -gl -Cr -Co -Ci -dBE_CHECKS -Fu. -FUbuild\test -FEbuild\test tests\test_sprite.pas
if errorlevel 1 exit /b 1
"%FPC%" -B -Pi386 -Twin32 -Mobjfpc -Sh -O1 -gl -Cr -Co -Ci -dBE_CHECKS -Fu. -FUbuild\test -FEbuild\test tests\test_spawn.pas
if errorlevel 1 exit /b 1

build\test\test_store.exe build\test
if errorlevel 1 exit /b 1
build\test\test_dll.exe build\win32\basicext_dll.dll build\test
if errorlevel 1 exit /b 1
build\test\test_engine.exe build\test
if errorlevel 1 exit /b 1
build\test\test_bridge.exe
if errorlevel 1 exit /b 1
build\test\test_ammo.exe
if errorlevel 1 exit /b 1
build\test\test_tk.exe
if errorlevel 1 exit /b 1
build\test\test_mine.exe
if errorlevel 1 exit /b 1
build\test\test_body.exe
if errorlevel 1 exit /b 1
build\test\test_names.exe
if errorlevel 1 exit /b 1
build\test\test_sprite.exe
if errorlevel 1 exit /b 1
rem [Spawns]: the old Respawns-Control's layouts and a map of the server are used when this folder is in its
rem scripts folder (each one is left out when it is not there); the /recompile talks to a stand-in on 127.0.0.1
build\test\test_spawn.exe ..\..\Respawns-Control\data ..\..\..\maps\ctf_Ash.pms
if errorlevel 1 exit /b 1
rem the shop's helpers on a map of the server (when this folder is in its scripts folder)
if exist ..\..\..\maps\ctf_Ash.pms (
  build\test\test_shop.exe ..\..\..\maps\ctf_Ash.pms
  if errorlevel 1 exit /b 1
)
rem the guided rockets on a map of the server (when this folder is in its scripts folder)
if exist ..\..\..\maps\ctf_Ash.pms (
  build\test\test_rocket.exe ..\..\..\maps\ctf_Ash.pms build\test\rocket_ctf_Ash.txt 40 1 1
  if errorlevel 1 exit /b 1
)
echo All tests passed.

