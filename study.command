#!/bin/bash
# Serves this folder on localhost and opens Song Study in Chrome.
# The app needs a real origin (not file://) to hold write permission on your .md
# files between sessions. Double-click this file to start.
cd "$(dirname "$0")" || exit 1
PORT=8788
if ! curl -sf -o /dev/null "http://127.0.0.1:$PORT/index.html"; then
  nohup python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
  disown
  sleep 1
fi
open -a "Google Chrome" "http://127.0.0.1:$PORT/index.html"
