#!/bin/sh
# Run grabd's tests (Python, no PipeWire needed) and the widget's QML tests
# (qmltestrunner, offscreen). Exits non-zero if any fail.
#   tests/run.sh            all
#   tests/run.sh grabd      grabd only
#   tests/run.sh qml        widget only
set -u
cd "$(dirname "$0")"
what=${1:-all}
status=0

if [ "$what" = all ] || [ "$what" = grabd ]; then
    echo "== grabd"
    # dbus-next's own deprecation warnings are not ours
    PYTHONDONTWRITEBYTECODE=1 python3 -W "ignore::DeprecationWarning:dbus_next.service" \
        -m unittest discover -s grabd -t grabd || status=1
fi

if [ "$what" = all ] || [ "$what" = qml ]; then
    echo "== widget"
    # Qt 6 (/usr/bin/qmltestrunner may be the Qt 5 one, which loads nothing)
    runner=/usr/lib/qt6/bin/qmltestrunner
    [ -x "$runner" ] || runner=$(command -v qmltestrunner6 || command -v qmltestrunner-qt6 || echo qmltestrunner)
    log=$(mktemp)
    QT_QPA_PLATFORM=offscreen "$runner" -input qml >"$log" 2>&1 || status=1
    grep -E "^(FAIL|   Loc|   Actual|   Expected|Totals)" "$log"   # the rest: "$log" kept on failure
    if [ $status = 0 ]; then rm -f "$log"; else echo "full output: $log"; fi
fi

exit $status
