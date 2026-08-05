FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# chromium does capture + encode + WebRTC, so there is no gstreamer/pion here.
# xdotool is the input-injection path; pulseaudio only matters in screen mode
# (tab capture carries the tab's own audio).
RUN apt-get update && apt-get install -y --no-install-recommends \
      chromium \
      xvfb \
      matchbox-window-manager \
      xdotool \
      x11-utils \
      x11-apps \
      pulseaudio \
      pulseaudio-utils \
      dbus-x11 \
      fonts-liberation \
      fonts-noto-core \
      ca-certificates \
      libnss3-tools \
      curl \
      netpbm \
      python3 \
      procps \
      psmisc \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/spike
COPY publisher/ ./publisher/
# Served at /viewer/viewer.html by the same localhost http server. Baked in so a
# subscriber can be run inside the container when the host has no browser —
# hand-copying it into a running container does not survive `probe.sh down`.
COPY viewer/ ./publisher/viewer/
COPY viewer-server.py ./viewer-server.py
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV DISPLAY=:99 \
    SCREEN_W=1280 \
    SCREEN_H=720 \
    SCREEN_FPS=30 \
    CAPTURE_MODE=tab \
    CODEC=vp8 \
    MAX_BITRATE_KBPS=2500

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
