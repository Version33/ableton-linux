# Missing ntsync support in a built runtime

One container build produced a Wine runtime without usable ntsync even though
the host kernel exposed `/dev/ntsync`. Live then used slower wineserver waits
and the release did not match its intended configuration.

## Cause and build checks

The build environment lacked the header or configure result needed to compile
Wine's ntsync path. Host device presence alone could not detect that omission.
The build now checks configure output and the built runtime, while
`scripts/check-ntsync.sh` reports the host device and Wine result separately.

Run:

```bash
./scripts/check-ntsync.sh
```

Then start the project Wine in a test prefix and confirm its reported sync
backend. Do not copy or remove a production prefix for this check.

ntsync availability is distinct from PipeASIO real-time scheduling. Compare
audio and UI behaviour with the same Set and buffer, and record the kernel,
Wine build information, CPU allocation, and PipeWire xrun count.
