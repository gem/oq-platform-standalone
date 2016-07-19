#!/bin/bash
function abs_path {
  (cd "$1" &>/dev/null && printf "%s" "$PWD")
}

IFS='
'
for i in hazardlib engine platform-standalone platform-ipt platform-taxtweb; do
    abs="$(abs_path "${PWD}/../oq-${i}")"
    if [ ! -d "$abs" ]; then
        continue
    fi
    if ! (echo "$PYTHONPATH" | grep -q ":\?${abs}:\?" ); then
        export PYTHONPATH="${PYTHONPATH}:${abs}"
    fi
done
echo $PYTHONPATH
python openquakeplatform_server/bin/openquakeplatform_srv.py runserver 0.0.0.0:8000
