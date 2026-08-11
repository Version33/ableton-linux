# Set up and verify Ableton Link

The installer saves one Link mode. Installation, the Live and Max launchers,
the user service, and the uninstaller use the same mode.

## Choose when Link runs

Run one of these commands:

```bash
sh install-ableton-latest.run link enable --mode=session
sh install-ableton-latest.run link enable --mode=always
sh install-ableton-latest.run link disable
sh install-ableton-latest.run link status
```

- `off` leaves Link disabled and removes only the Link files and settings that
  this project created.
- `session` starts the Link peer with Live or Max. The peer exits after the
  session ends and its idle time expires.
- `always` enables the user service and starts the Link peer after login.

The `install` and `update` commands also accept
`--link=off|session|always`. An update keeps the saved mode unless you choose
another one.

From a repository checkout, run the same command through the source script:

```bash
./scripts/installer.sh link enable --mode=session
```

## Link files and host settings

When you enable Link, the installer can make three host changes:

1. It removes the NetworkManager dispatcher hook from setup versions 1 and 2.
   It also removes that hook's obsolete `224.0.0.0/4` route.
2. It opens UDP port 20808 when UFW or firewalld is active. The installer
   records whether it added the rule. Disable and uninstall then remove only
   that rule. They keep any rule that already existed.
3. It writes a user unit with a project ownership marker to
   `${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/ableton-linkd.service`
   with the `ABLETON_LINKD` path. Session mode keeps the unit disabled. Always
   mode enables and starts it.

The installer gives each change a time limit. A failed change returns a
non-zero status. During an install or update, the installer saves the existing
firewall rule, unit, service state, process, files, and Link mode. It restores
that state if a later step fails.

## Link settings from older releases

Setup versions 1 and 2 added a `224.0.0.0/4` route on the LAN interface and
a NetworkManager hook to maintain it. Version 3 removed both. The Link SDK
sets `IP_MULTICAST_IF` on every discovery socket. This option selects the
outgoing interface without consulting the routing table. Live under Wine and
`ableton-linkd` both set the option for each interface. The
[implementation record](ABLETON-WINE-LINK-FIRSTCLASS.md) contains the trace.
Version 4 stopped enabling the user unit. It also made the daemon exit after a
session ends.

## Run `ableton-linkd`

The build uses the vendored Ableton Link 4.0 SDK to create `ableton-linkd`.
The installer copies it to:

```text
~/.local/share/ableton-wine/ableton-linkd
```

The daemon joins the Link session as a native peer. It holds the shared tempo
and timeline while Live restarts, so Live rejoins the same beat. It enables
Start Stop Sync. After startup, it does not call the SDK methods that set the
tempo or beat position.

In session mode, the daemon exits after 15 minutes with no peers. Live counts
as a peer after you enable Link in its settings. The daemon therefore stays
open through a Live restart or crash and exits after the session ends. Use
`--linger` to change the idle time.

Its modes are:

- With no arguments, it runs in the foreground. It writes startup information
  and reports changes to the peer count, tempo, and transport state to stderr.
- `--daemon` runs it in the background with its old log location. Current
  launchers use `ableton-linkctl` instead. The controller runs the daemon in
  the foreground and writes its output to
  `$XDG_STATE_HOME/ableton-wine/logs/ableton-linkd.log`.
- `--probe [seconds]` joins a session and waits for another peer. The default
  limit is ten seconds. It prints `peers: N` and `tempo: T.T`, then exits with
  status zero when it finds another peer.
- `--tempo BPM` sets the starting tempo when this process creates a new
  session. It does not change the tempo of an existing session.
- `--linger SECONDS` sets the idle time before the daemon exits. The value
  must use whole seconds. The default is 900. A value of `0` keeps it running,
  which the user service requires. `ABLETON_LINKD_LINGER` sets the same value.
- `--verbose` or `ABLETON_LINKD_VERBOSE=1` writes a status line every ten
  seconds. Before 2026.08, the daemon always wrote these lines. The user
  service then wrote 8,640 identical journal lines each day, which made an
  idle process look busy.

The Live and Max launchers ask `ableton-linkctl` to start the daemon when the
saved mode allows it. The controller handles one start or stop at a time and
records the process ID. Before it sends a signal, it checks `/proc/PID/exe`
against the resolved `ABLETON_LINKD` path. The user unit runs `--linger 0` in
always mode.

## Test Wine networking with `linkprobe.exe`

The repository includes `tools/linkprobe.exe`. The `.run` installer does not
install it. Run the program under Wine to test `SO_REUSEADDR`, a bind to
`0.0.0.0:20808`, `IP_ADD_MEMBERSHIP` on each interface, multicast transmission,
and multicast reception.

Its exact verdict lines are:

```text
LINKPROBE TX OK
LINKPROBE RX-LOOPBACK OK
LINKPROBE RX-NETWORK OK
LINKPROBE PEERS: N
```

The process exits with status zero when transmission and loopback reception
succeed.
`RX-NETWORK OK` requires a datagram whose source is not one of the local
machine's addresses. The daemon on the same machine is not enough for that
line, even though it can appear in `PEERS`.

`linkprobe.exe` sends discovery datagrams without a session payload. It tests
Wine's multicast socket behaviour, not full Ableton Link session membership.

`tools/jacklinkd.c` restores JACK port links. It uses `ableton-linkd` as its
JACK client name, but current launchers do not start it.

## Verify Link

Check the saved mode, firewall rule, and daemon state:

```bash
sh install-ableton-latest.run link status
```

In session mode, the command reports `state: stopped` after Live has stayed
closed for the configured idle time. In always mode, it reports the daemon
started by the user service.

For `ufw`, run `sudo ufw status` and look for `20808/udp`. For firewalld, run
`firewall-cmd --list-ports`.

If you enable a firewall later, repeat `link enable`. The installer then checks
the firewall and records any rule it adds.

Start the daemon, then use its probe to check that two native peers can join:

```bash
"$HOME/.local/share/ableton-wine/ableton-linkctl" start
"$HOME/.local/share/ableton-wine/ableton-linkd" --probe 10
```

The probe prints `peers: 1` or a larger number and exits with status zero. The
daemon exits 15 minutes after the probe finishes. This result confirms that
two native SDK instances can join. It does not confirm that Live joined.

From a checkout, test Wine's local multicast socket behaviour:

```bash
env WINEPREFIX="$HOME/.wine-ableton" \
  "$HOME/.local/opt/wine-d2d1-nspa-11.13/bin/wine" tools/linkprobe.exe
```

Confirm that the output contains `LINKPROBE TX OK` and
`LINKPROBE RX-LOOPBACK OK`. To check `LINKPROBE RX-NETWORK OK`, run another
Link peer on a second computer on the same LAN.

In Live, open `Preferences > Link, Tempo & MIDI` and enable `Show Link Toggle`.
Enable Link in the control bar and confirm that Live shows at least one peer.
Change the tempo from each peer in turn, then check the beat and phase. Restart
Live and confirm that it rejoins at the same tempo and phase.

For packet-level checks:

```bash
sudo tcpdump -i <interface> -n udp port 20808
```

Discovery uses `224.76.78.75:20808`. The Wireshark filter
`ip.dst == 224.76.78.75 || ip.dst == 224.0.0.22` also includes IGMPv3
membership reports.

If neither the native probe nor `tcpdump` sees an active peer, check the
firewall and access point. Many access points block or filter multicast. Also
confirm that both computers use the same LAN segment. If the native tools see
the peer but Live does not, compare the `linkprobe.exe` results with the packet
capture before diagnosing a Wine socket fault.

## Check the network requirements

Ableton Link discovers peers through UDP multicast on
`224.76.78.75:20808`. Pairs of peers measure their timelines through unicast
UDP on temporary ports. The host tracks replies to those outgoing exchanges,
so the installer opens only UDP port 20808.

Peers must use a LAN that carries multicast. Linux applications with Ableton
Link support join the session directly. JACK-only applications can use the
separate upstream
[`jack_link`](https://github.com/rncbc/jack_link) project.

PipeASIO has no JACK transport layer, so the native peer cannot synchronise
Live through JACK. Live joins the Link session as a Wine peer and follows the
shared timeline itself.

Ableton Link is Ableton's technology. This project follows its naming and
enablement guidelines and is not affiliated with or endorsed by Ableton.
