#!/bin/sh
# Gives the app unique identifiers so Apple accepts your free signing.
# Usage (on a Mac, inside the AyahLock folder):   sh rename.sh yourname
# Use letters and numbers only, e.g.  sh rename.sh mdruhul
set -e
if [ -z "$1" ]; then
  echo "Usage: sh rename.sh yourname"; exit 1
fi
for f in project.yml Shared/SharedStore.swift; do
  sed -i '' "s/com\.example/com.$1/g" "$f"
done
echo "Identifiers now use com.$1. Next: xcodegen generate"
