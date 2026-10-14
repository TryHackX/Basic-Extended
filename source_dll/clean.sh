#!/bin/sh
# A copy made on Windows has Windows line ends: they are taken out here and the script starts again (the # at the
# end of the next two lines keeps their own CR in a comment). ./build.sh cannot start such a copy at all - sh can.
cr=$(printf '\r') #
case $(head -n 1 "$0" 2>/dev/null) in *"$cr") sed -i "s/$cr\$//" "$0" && exec sh "$0" "$@";; esac #
# Removes compiler output and test builds (build/). The library in the script folder stays.
cd "$(dirname "$0")" || exit 1
rm -rf build
echo "Removed build/"
