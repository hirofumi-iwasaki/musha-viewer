# musha-viewer development

This repository is independent of musha-edit. The current release branch is `release/0.2.0`. For Linux development in the managed workspace, use the viewer-only `musha-viewer-dev` container and `scripts/cloud-run`; setup and isolation details are in [docs/CLOUD_ENVIRONMENT.md](docs/CLOUD_ENVIRONMENT.md). Do not use the musha-edit container, workspace, credentials, or caches. The container is an isolated runtime within the currently bound Codex Cloud environment, not a separate Cloud environment.

macOS build, signing, Sandbox behavior, drag-and-drop, and on-device release execution remain unverified until tested on a Mac. Follow [docs/RELEASE_0_2_0.md](docs/RELEASE_0_2_0.md) and [docs/C2PA_BUILD.md](docs/C2PA_BUILD.md); preserve the read-only source-file and offline verification guarantees.
