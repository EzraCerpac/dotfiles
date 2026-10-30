# dots-up releases

The dashboard release workflow builds the Go module in `setup-scripts/dots-up`
from a `dots-up-vX.Y.Z` tag and publishes four executables:

- `dots-up-darwin-arm64`
- `dots-up-darwin-amd64`
- `dots-up-linux-arm64`
- `dots-up-linux-amd64`

`SHA256SUMS` contains the SHA-256 digest of each executable.
The build uses the checked-in `go.mod` and `go.sum`,
verifies downloaded modules, and refuses module file updates.

The tag pipeline runs module verification, Go tests, vet, and CLI PTY fixtures
on Linux and macOS before publishing the binaries.

Publish a release before separately activating the dashboard in the setup source.
The release workflow does not install or activate it on any host,
and does not deploy to either NAS.
