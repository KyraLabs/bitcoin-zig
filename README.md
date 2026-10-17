# bitcoin-zig

A Bitcoin node implementation in Zig, using Bitcoin Core as the behavioral reference.

This is an experiment. It is not suitable for use with real funds or on mainnet. At this stage the repository contains only the project skeleton; the node does not validate, store or relay anything yet.

## Requirements

- Zig 0.17.0 (pinned in `mise.toml`)
- A Bitcoin Core checkout at commit `924f4c4ac78b0cd3b917c694f42c0651a6f3003a`, used for its test vectors

## Build and test

```sh
zig build
zig build run -- -version
zig build test
zig build fmt
```

Tests read vectors from `../bitcoin/src/test/data` by default. A different location is set with `-Dcore-test-data=<path>`. A single module is tested with `-Dtest-module=<name>`.

## License

MIT. See [LICENSE](LICENSE).
