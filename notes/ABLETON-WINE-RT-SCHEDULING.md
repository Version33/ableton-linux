# Wine and PipeASIO scheduling

The launcher and PipeASIO control different threads. The launcher uses
round-robin priority 10 when `chrt -r 10 true` succeeds. PipeASIO 1.5 keeps its
audio thread on normal scheduling by default, even if it inherited the
launcher's policy.

Compare the launcher with normal scheduling:

```bash
env ABLETON_RT=off ableton-live
```

Compare PipeASIO's own real-time request separately:

```bash
env PIPEASIO_REALTIME=on ableton-live
env PIPEASIO_REALTIME=off ableton-live
```

`scripts/setup-realtime.sh` can grant the required user limit when the
distribution does not already provide it.

## Low-core comparison still needed

Launcher-wide round-robin scheduling has not been measured across low-core
systems. Real-time work can be throttled after consuming the kernel's runtime
allowance, and normal-scheduled wineserver work may still sit behind Live
threads making synchronous requests.

Use the same Set, buffer, CPU set, and run length. Record thread classes with:

```bash
ps -eLo pid,tid,cls,rtprio,comm
```

Record PipeWire xruns, Live DSP load, UI response, and process CPU. Compare
`ABLETON_RT=off` with the default first, then compare
`PIPEASIO_REALTIME=on` only as a separate variable. The
`-DontCombineAPCs` playback failure was unrelated to real-time permission; see
[the APC option record](ABLETON-WINE-APC-COALESCING.md).
