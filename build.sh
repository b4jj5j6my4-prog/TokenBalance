#!/bin/sh
set -eu
: "${APELIN_PACKAGE_DIR:?run this through apelin_project_build}"
: "${APELIN_PROJECT_ROOT:?}" "${APELIN_BOOTSTRAP:?}" "${APELIN_ARCHITECTURE:?}"
: "${APELIN_BUILD_ID:?}" "${TMPDIR:?}"
: "${APELIN_PREFIX?}"

if [ "${APELIN_BOOTSTRAP}" != "roothide" ]; then
    echo "This project currently supports roothide only." >&2
    exit 1
fi

THEOS="${THEOS:-/var/mobile/theos}"
export THEOS
export APELIN_BUILD_ID

make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide THEOS_PACKAGE_DIR="${APELIN_PACKAGE_DIR:?}"

count="$(find "${APELIN_PACKAGE_DIR:?}" -maxdepth 1 -type f -name '*.deb' | wc -l | tr -d ' ')"
if [ "$count" != "1" ]; then
    echo "Expected exactly one package, found $count." >&2
    exit 1
fi
