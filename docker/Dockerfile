# Среда, в которой curskill ставится с нуля.
# Cursor, cursor-proxy, sudo и таймер сюда не входят: это отдельное согласие.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      hostname \
      iproute2 \
      procps \
      xdotool \
      xclip \
      python3 \
      python3-pil \
      imagemagick \
      scrot \
      tesseract-ocr \
      tesseract-ocr-eng \
      tesseract-ocr-rus \
      xserver-xorg-core \
      x11-utils \
      x11-xserver-utils \
      xvfb \
      openbox \
      x11vnc \
 && rm -rf /var/lib/apt/lists/*
