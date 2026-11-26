# Wiki.js 3 image build:
#   packer build -var-file=packer/v3.pkrvars.hcl packer
#
# Pin both images by digest before building: scripts/pin-images.sh prints the
# digest and fails if an image has no linux/arm64 build (the host is Graviton).

ami_name_prefix = "wiki-js-v3"
wikijs_major    = "3.x"

# Pinned with scripts/pin-images.sh on 2026-11-27 (both have linux/arm64 builds;
# postgres:17-alpine digest unchanged since 2026-11-24).
wikijs_image = "ghcr.io/requarks/wiki:3.6.1@sha256:bd4819960f2f9d35ef016653b97abf5fc0cd93a941d3baf34d2e79e4c9059169"
# Wiki.js 3 needs PostgreSQL 17 or 18 (ltree and pg_trgm ship with the image).
postgres_image = "postgres:17-alpine@sha256:f9cf3e1f0066f0eb0c48707d864f0ac5941e9ff454a072077d97a4d278d07d73"

# t4g.medium has 4 GiB. Wiki.js 3 runs Puppeteer (headless Chromium) for page
# rendering and the MCP write tools.
wikijs_mem_limit   = "2g"
postgres_mem_limit = "768m"

# Wiki.js 3 serves "/" from a root page that does not exist here; the home
# page is /index, as in 2.x. nginx redirects "/" there.
wikijs_root_redirect = "/index"
