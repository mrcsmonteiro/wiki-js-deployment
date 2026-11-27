#!/usr/bin/env bash
# Resolves container image tags to digests and checks each has a linux/arm64
# build. Prints lines ready to paste into packer/*.pkrvars.hcl.
#
#   scripts/pin-images.sh ghcr.io/requarks/wiki:3.0.1 postgres:17-alpine
#
# Needs Docker with buildx (Docker Desktop has it).
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <image:tag> [<image:tag> ...]" >&2
  exit 2
fi

status=0
for ref in "$@"; do
  digest=$(docker buildx imagetools inspect "$ref" --format '{{json .Manifest}}' |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["digest"])')
  platforms=$(docker buildx imagetools inspect "$ref" --format '{{json .Manifest}}' |
    python3 -c 'import json,sys; m=json.load(sys.stdin); print(" ".join(sorted({p["platform"]["os"]+"/"+p["platform"]["architecture"] for p in m.get("manifests", []) if "platform" in p})))')

  if [[ " $platforms " == *" linux/arm64 "* ]]; then
    echo "${ref}@${digest}   # platforms: ${platforms}"
  else
    echo "NO linux/arm64 build: ${ref} (platforms: ${platforms:-single-arch image})" >&2
    status=1
  fi
done
exit $status
