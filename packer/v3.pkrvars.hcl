# Wiki.js 3 image build:
#   packer build -var-file=packer/v3.pkrvars.hcl packer
#
# Pin both images by digest before building: scripts/pin-images.sh prints the
# digest and fails if an image has no linux/arm64 build (the host is Graviton).

ami_name_prefix = "wiki-js-v3"
wikijs_major    = "3.x"

# Pinned with scripts/pin-images.sh on 2026-11-24 (both have linux/arm64 builds).
wikijs_image   = "ghcr.io/requarks/wiki:3.0.1@sha256:6e9987cc7f0f583f73591fbdf318fe94c6ba76616913e6c8f833b7a1960cd31d"
# Wiki.js 3 needs PostgreSQL 17 or 18 (ltree and pg_trgm ship with the image).
postgres_image = "postgres:17-alpine@sha256:f9cf3e1f0066f0eb0c48707d864f0ac5941e9ff454a072077d97a4d278d07d73"

# t4g.medium has 4 GiB. Wiki.js 3 runs Puppeteer (headless Chromium) for page
# rendering and the MCP write tools.
wikijs_mem_limit   = "2g"
postgres_mem_limit = "768m"
