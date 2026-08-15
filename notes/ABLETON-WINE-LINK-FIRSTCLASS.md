# Ableton Link implementation record

Release 2026.07.23.1 introduced the native Link peer and Wine multicast probe.
Current setup commands are in [ABLETON-WINE-LINK.md](ABLETON-WINE-LINK.md).

## Wine and native peers

Live joins Link directly through Wine. The Link SDK uses `SO_REUSEADDR`,
`IP_ADD_MEMBERSHIP`, and `IP_MULTICAST_IF`, which Wine passed in the recorded
test. The SDK did not depend on Wine's `WSAJoinLeaf` stub.

`tools/ableton-linkd.cpp` builds a native peer with the vendored Link 4.0 SDK.
It retains session tempo, phase, and transport state while Live restarts. Once
joined, it does not call the SDK methods that change tempo or beat position.
Its initial tempo applies only when it creates a new session.

`tools/linkprobe.c` builds a Windows probe that binds UDP 20808, joins
`224.76.78.75`, sends on each IPv4 interface, and distinguishes local from LAN
traffic. It checks Wine multicast sockets but does not become a complete Link
peer.

## Host integration

Early setup versions added a multicast route and NetworkManager hook. Tracing
showed that both Live and the native peer set `IP_MULTICAST_IF` for each
interface, so later setup removed the route and hook. Current setup opens UDP
20808 only when UFW or firewalld is active and records whether this project
added the rule.

Current modes are `off`, `session`, and `always`. Session mode starts the peer
with Live or Max and lets it exit after the idle period. Always mode enables a
systemd user service. `ableton-linkctl` serialises start and stop operations and
checks a recorded process against the resolved executable before signalling it.

## Recorded checks

Tests on 2026-07-22 covered host and container builds, daemon modes, signal
handling, joining an existing 133 BPM session, local Wine multicast, package
contents, installation, and removal. A system-call trace showed per-interface
membership and outgoing-interface selection.

Still useful on new releases: test a second LAN computer, bidirectional tempo
and transport changes in Live, beat and phase under audio load, session
continuity across a Live restart, idle exit, and migration from an older
enabled user service.

`tools/jacklinkd.c` is an older JACK port restorer. It is not an Ableton Link
bridge and current launchers do not start it.
