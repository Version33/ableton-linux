# Tempo-ramp export length differs from Windows, 2026-07-31

Issue 101 reported a stable 0.33-second difference across a seven-minute song
containing tempo ramps. The same machine exported different lengths on Windows
and Linux. No code change has been proposed because the engine difference has
not been isolated.

## Evidence from the sample Set

The supplied Live 12.4.3 Set contains a linear ramp from 70 to 150 BPM across
beats 0 to 128, then 150 BPM to beat 160. Its exact duration is 85.965445
seconds, or 4,126,342 samples at 48 kHz.

A simulation that held tempo once per audio buffer produced these errors above
the exact length:

| Frames at 48 kHz | Error |
|---:|---:|
| 64 | 0.51 ms |
| 256 | 2.03 ms |
| 512 | 4.07 ms |
| 1024 | 8.13 ms |
| 2048 | 16.26 ms |

The buffer effect is measurable but far too small to explain 330 ms at normal
settings.

An export does not use audio-device timing, so PipeASIO timestamps, ntsync,
and live-playback scheduling do not explain the exported-file length. The
Wine patch series also did not change the Windows math libraries or Live's
playback-position code.

## Next comparisons

1. Record the Live version saved in a Windows-created backup. A difference
   between Windows and Linux Live versions remains the strongest unbounded
   explanation.
2. Export the sample at two buffers on Linux:

   ```bash
   env PIPEASIO_PREFERRED_BUFFERSIZE=64 ableton-live
   env PIPEASIO_PREFERRED_BUFFERSIZE=2048 ableton-live
   ```

   Compare sample counts with `soxi -s`. About 756 samples would match the
   once-per-buffer model; a much larger change would show coarser evaluation.
3. Record `pw-top` while Live plays and the Windows sample rate and buffer.
4. Repeat the two-buffer export on Windows when available.

Keep the exported files, exact loop range, Live versions, sample rates, and
sample counts together. Playback drift and export-length differences need
separate evidence.
