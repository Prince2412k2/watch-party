# Shared browser for watch parties.
#
# Chromium does capture, encode and WebRTC; this image adds only a virtual
# display, a window manager, an audio loopback, and a small control agent. There
# is no gstreamer/pion/RTP code anywhere — the browser publishes itself into the
# party's existing LiveKit room as an ordinary participant.
#
# Derived from spikes/remote-browser (see docs/specs/2026-08-04-remote-browser-spike.md).
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# xdotool is the input-injection path. pulseaudio is required because
# getDisplayMedia on Linux hands back no system audio, so the publisher takes it
# from a null sink's monitor instead. matchbox is not optional: with no window
# manager there is no input focus, so injected keystrokes land nowhere.
RUN apt-get update && apt-get install -y --no-install-recommends \
      chromium \
      xvfb \
      matchbox-window-manager \
      xdotool \
      x11-utils \
      pulseaudio \
      pulseaudio-utils \
      dbus-x11 \
      fonts-liberation \
      fonts-noto-core \
      ca-certificates \
      libnss3-tools \
      curl \
      python3 \
      procps \
      psmisc \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/browser
COPY publisher/ ./publisher/
COPY agent.py ./agent.py
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Chromium profiles live here and are destroyed between sessions. Mounted as a
# tmpfs in compose so nothing survives even a failed wipe or a container kill.
RUN mkdir -p /profiles

ENV DISPLAY=:99 \
    SCREEN_W=1280 \
    SCREEN_H=720 \
    SCREEN_FPS=30 \
    MAX_BITRATE_KBPS=2500 \
    AGENT_PORT=8080 \
    PROFILE_ROOT=/profiles

# The control API. Never published to the host — only app/server, on the same
# docker network, is meant to reach it.
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/health || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
