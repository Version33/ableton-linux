# shellcheck shell=bash
# Sourceable host light/dark-scheme detection. ableton_detect_theme prints "dark" or "light"
# or returns 1 when no probe answers (probes: XDG settings portal via gdbus, busctl,
# then dbus-send — each tried until one answers — then GNOME gsettings).

_adt_portal() {
  local out val=""
  if command -v gdbus >/dev/null 2>&1; then
    # serializes as "(<<uint32 1>>,)"
    out="$(timeout 5 gdbus call --session \
      --dest org.freedesktop.portal.Desktop \
      --object-path /org/freedesktop/portal/desktop \
      --method org.freedesktop.portal.Settings.Read \
      org.freedesktop.appearance color-scheme 2>/dev/null)" &&
      val="$(printf '%s\n' "$out" | grep -oE 'uint32 [0-9]+' | awk '{print $2; exit}')"
  fi
  if [ -z "$val" ] && command -v busctl >/dev/null 2>&1; then
    # replies "v v u 1"
    out="$(timeout 5 busctl --user call org.freedesktop.portal.Desktop \
      /org/freedesktop/portal/desktop org.freedesktop.portal.Settings Read \
      ss org.freedesktop.appearance color-scheme 2>/dev/null)" &&
      val="$(printf '%s\n' "$out" | awk '{print $NF; exit}' | grep -xE '[0-9]+')"
  fi
  if [ -z "$val" ] && command -v dbus-send >/dev/null 2>&1; then
    # replies "   variant       variant          uint32 1"
    out="$(timeout 5 dbus-send --session --print-reply \
      --dest=org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
      org.freedesktop.portal.Settings.Read \
      string:org.freedesktop.appearance string:color-scheme 2>/dev/null)" &&
      val="$(printf '%s\n' "$out" | grep -oE 'uint32 [0-9]+' | awk '{print $2; exit}')"
  fi
  case "$val" in '' | *[!0-9]*) return 1 ;; esac
  # 0 = no preference, 1 = prefer dark, 2 = prefer light
  case "$val" in
  1) echo dark ;;
  *) echo light ;;
  esac
}

_adt_gsettings() {
  command -v gsettings >/dev/null 2>&1 || return 1
  local scheme
  scheme="$(timeout 5 gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)" || return 1
  case "$scheme" in
  *prefer-dark*) echo dark ;;
  *prefer-light* | *default*) echo light ;;
  *) return 1 ;;
  esac
}

ableton_detect_theme() {
  local theme
  for probe in _adt_portal _adt_gsettings; do
    if theme="$($probe)"; then
      printf '%s\n' "$theme"
      return 0
    fi
  done
  return 1
}
