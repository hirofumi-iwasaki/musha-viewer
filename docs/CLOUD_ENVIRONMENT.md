# Viewer development runtime

When this runtime was introduced on 2026-11-02 (JST), the Codex Cloud task was bound to the same Cloud environment as musha-edit. The available Cloud tools could not create or rebind a separate Cloud environment. `musha-viewer-dev` is a separate Docker runtime **inside that Cloud environment**, not a separately provisioned Codex Cloud environment. To obtain a separate Cloud environment, create one named `musha-viewer` in the Codex Cloud UI, select repository `https://github.com/hirofumi-iwasaki/musha-viewer` and branch `release/0.1.0`, then reopen or attach the task to it. At the time of writing, `main` contains planning documents rather than the runnable release. Provision the runtime below in that environment if Docker is available. This UI step cannot be performed by the scripts.

The image is built from Debian trixie-slim, not from the musha-edit image or container. The running container mounts only this repository at `/project`, a read-only system CA bundle, and named viewer-specific volumes. `/home/viewer` holds private Cargo, Rustup, Pub, Flutter configuration, and caches; `/opt/viewer/flutter` is a private SDK copy. Separate volumes hold `/project/build`, `/project/.dart_tool`, and `/project/native/c2pa/target`. The editor repository, its container, and the workspace root are not mounted into this runtime. The Docker daemon and parent Cloud instance remain shared. This is a development setup, not an independent security boundary from the host or Docker administrator.

## Provision

The setup script expects UID/GID 1000 for the checkout and runs Docker against the local managed daemon. It refuses to replace an existing `musha-viewer-dev` container or overwrite seeded toolchain volumes. Before first use, provide paths to separately obtained, verified toolchains compatible with the project: Flutter 3.47.4 (framework revision `9584c6713b`) and Rust 1.96 or newer. The seed inputs contain the Flutter SDK, a Rustup `toolchains/stable-x86_64-unknown-linux-gnu` directory, and Cargo `bin` and public `registry` data. The current setup targets Linux x86-64 and checks that the stable toolchain is present before building. The script reads them only in a temporary seed container, copies them into private volumes, makes a fresh Rustup default and fresh Pub cache, and does not copy Cargo credentials or configuration. Flutter Git configuration is replaced with a public origin and copied hooks and reflogs are removed. SDK inputs and their provenance must be verified by the operator; this script does not authenticate them.

In the current managed workspace those verified copies are available at the following paths:

```sh
FLUTTER_SEED=/workspace/.tools/flutter \
RUSTUP_SEED=/workspace/.rustup \
CARGO_SEED=/workspace/.cargo \
scripts/cloud-setup
scripts/cloud-run flutter pub get
scripts/cloud-run cargo test --locked --manifest-path native/c2pa/Cargo.toml
scripts/cloud-run flutter build linux --release
scripts/cloud-run flutter analyze
scripts/cloud-run flutter test
```

The managed runtime supplies proxy defaults, the system CA bundle, and the local Docker daemon. The build uses a temporary BuildKit CA mount, and the running container receives the host CA bundle read-only at the system trust path for TLS verification, including Dart; neither is copied into an image layer. The script clears Docker endpoint/context/TLS selectors for every Docker command and targets the local Unix socket, retaining Docker configuration and registry credentials. A new Cloud environment may have different seed paths or network policy; provide verified SDKs there and use its own proxy and CA configuration. Do not copy a different project's home directory, credentials, or cache wholesale.

Use `scripts/cloud-run COMMAND [ARG ...]` for subsequent commands. Start an existing stopped viewer container with `docker --host=unix:///var/run/docker.sock start musha-viewer-dev` after clearing any Docker endpoint/context/TLS selectors as the scripts do. Setup is intentionally non-destructive; if it fails after creating volumes or the container, inspect the named resources before deciding how to recover. Do not remove volumes containing work without checking their contents. To rebuild an existing environment, preserve or deliberately replace those resources only after reviewing what they contain.

Linux tests and builds do not validate the macOS application, security-scoped drag/drop, signing, or native startup. Follow [the Mac device checklist](RELEASE_0_1_0.md) and [native verifier build instructions](C2PA_BUILD.md).

## Validation in the current runtime

On 2026-11-02 (JST), the dedicated Debian Linux x86-64 container used Flutter 3.47.4 / Dart 3.13.3 and Rust 1.99.1. Its private Pub cache resolved the locked dependencies with TLS verification; `cargo test --locked --offline --manifest-path native/c2pa/Cargo.toml` passed all three native tests. `flutter build linux --release` succeeded, `flutter analyze` reported no issues, and `flutter test` passed all ten tests, including native C2PA verification of signed and tampered fixtures. The release app opened a window under Xvfb. These checks were performed in Docker inside the shared Cloud environment and do not verify macOS or create a separate Codex Cloud environment.
