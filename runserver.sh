#!/bin/bash
function abs_path {
  (cd "$1" &>/dev/null && printf "%s" "$PWD")
}

sa_apps_repo="$(python -c "from openquakeplatform_server.settings import STANDALONE_APPS ; print('\n'.join(STANDALONE_APPS))" | sed 's/openquakeplatform_/oq-platform-/g' )"
IFS='
'
for i in oq-hazardlib oq-engine oq-platform-standalone $sa_apps_repo; do
    abs="$(abs_path "${PWD}/../${i}")"
    if [ ! -d "$abs" ]; then
        continue
    fi
    if ! (echo "$PYTHONPATH" | grep -q ":\?${abs}:\?" ); then
        export PYTHONPATH="${PYTHONPATH}:${abs}"
    fi
done
echo $PYTHONPATH
python openquakeplatform_server/bin/openquakeplatform_srv.py runserver 0.0.0.0:8000 >>runserver.log 2>&1
