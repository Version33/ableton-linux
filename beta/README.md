# Beta testing

The beta kit checks a candidate Ableton Linux installer on a separate Wine
prefix and writes one redacted session report.

## Run a session

From the repository root:

```bash
./beta/tester-kit/run-session
```

The default prefix is `~/.wine-ableton`. The runner refuses a non-empty prefix
unless you pass `--reuse-prefix`. Use a separate account or an explicit test
prefix if that path contains an installation you need to keep:

```bash
./beta/tester-kit/run-session --prefix "$HOME/.wine-ableton-beta"
```

The finished report is named `session-YYYY-MM-DD-HHMMSS.txt`. Read it before
sharing it. If a private value appears, keep the report local and file a
collector bug instead of editing the report.

Use [TESTING.md](TESTING.md) for the release test sequence. The
[tester-kit reference](tester-kit/README.md) lists every option and check.
