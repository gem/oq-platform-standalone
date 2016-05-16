#!/bin/bash
if ! (echo "$PYTHONPATH" | grep -q ":\?${PWD}:\?" ); then
    export PYTHONPATH="${PYTHONPATH}:${PWD}"
fi
python openquakeplatform_server/bin/openquakeplatform_srv.py runserver 0.0.0.0:8000
