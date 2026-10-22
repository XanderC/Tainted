#!/bin/sh
# Runs the Tainted World server. On `docker stop` (SIGTERM) it asks the server to stop properly
# (tainted-admin shutdown: everyone told, every account written) and waits for it, instead of the
# server being killed with up to a couple of seconds of saves unwritten.
mkdir -p /tmp/tainted-admin
godot --headless --main-pack /game/tainted.pck -- --server --name="$TAINTED_NAME" --max="$TAINTED_MAX" \
  --data=/data --admin=/tmp/tainted-admin ${TAINTED_AUTH:+--auth=$TAINTED_AUTH} \
  ${TAINTED_UPDATE:+"--update=$TAINTED_UPDATE"} ${TAINTED_BOT_KEY:+"--bot-key=$TAINTED_BOT_KEY"} &
pid=$!
trap 'echo "Asked to stop: shutting down in ${TAINTED_STOP_WARNING:-10}s"; tainted-admin shutdown "${TAINTED_STOP_WARNING:-10}" >/dev/null 2>&1' TERM INT
wait "$pid"   # returns early when the signal comes...
wait "$pid"   # ...then waits for the server to have saved and stopped
