#!/bin/sh
# A copy made on Windows has Windows line ends: they are taken out here and the script starts again (the # at the
# end of the next two lines keeps their own CR in a comment). ./build.sh cannot start such a copy at all - sh can.
cr=$(printf '\r') #
case $(head -n 1 "$0" 2>/dev/null) in *"$cr") sed -i "s/$cr\$//" "$0" && exec sh "$0" "$@";; esac #
# Builds basicext_dll.so for the 32-bit Soldat server on Linux.
# Compiler output stays in build/i386-linux; only the finished library is copied to the
# script folder (one level up), which is where main.pas loads it from.
#
# It needs Free Pascal 3.2.2 for i386-linux, the linker and the 32-bit C library files. On a
# 64-bit Debian or Ubuntu, the official release has everything:
#   sudo apt-get install binutils libc6-dev-i386
#   wget https://downloads.sourceforge.net/project/freepascal/Linux/3.2.2/fpc-3.2.2.i386-linux.tar
#   tar xf fpc-3.2.2.i386-linux.tar && cd fpc-3.2.2.i386-linux && sudo ./install.sh
#
#   sh build.sh          the library for the server
#   sh build.sh debug    with range, overflow and object checks and line numbers (slower)
#   FPCUNITS=/usr/local/lib/fpc/3.2.2/units/i386-linux sh build.sh
#                        reads the units from that folder, whatever fpc.cfg says
set -e
cd "$(dirname "$0")"

FPC=${FPC:-fpc}
# the units of the compiler that will run: <prefix>/lib/fpc/<version>/ppc386 has them in
# <prefix>/lib/fpc/<version>/units/i386-linux
if [ -z "$FPCUNITS" ]; then
  ppc=$("$FPC" -Pi386 -PB 2>/dev/null | head -n 1) || ppc=
  case $ppc in
    /*) ;;
    ?*) ppc=$(command -v "$ppc" 2>/dev/null) || ppc= ;;
  esac
  if [ -n "$ppc" ]; then
    ppc=$(readlink -f "$ppc" 2>/dev/null) || ppc=
    if [ -n "$ppc" ] && [ -d "${ppc%/*}/units/i386-linux/rtl-objpas" ]; then
      FPCUNITS=${ppc%/*}/units/i386-linux
      echo "build.sh: units from $FPCUNITS"
    fi
  fi
fi
UNITPATH=${FPCUNITS:+-Fu$FPCUNITS/*}
OPTS="-O2 -Xs -XX -CX"
if [ "$1" = "debug" ]; then
  OPTS="-O1 -gl -gw -Cr -Co -Ci -dBE_CHECKS -CX"
fi
OUT=build/i386-linux
mkdir -p "$OUT"

"$FPC" -B -Pi386 -Tlinux -Mobjfpc -Sh $OPTS ${UNITPATH:+"$UNITPATH"} -FU"$OUT" -FE"$OUT" -obasicext_dll.so be_main.pas
cp -f "$OUT/basicext_dll.so" ../basicext_dll.so
chmod 755 ../basicext_dll.so
echo "Built ../basicext_dll.so"
