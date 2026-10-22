# The Tainted World's dedicated server: Godot's official Linux build, headless, running the game's
# exported pack (tainted.pck, made by deploy_server.ps1) as a server (Net.dedicated_requested).
# It plays no character and renders nothing; it only passes on who is where.

FROM debian:trixie-slim AS godot
ARG GODOT_VERSION=4.4.1
# Godot's published SHA512 for Godot_v4.4.1-stable_linux.x86_64.zip (SHA512-SUMS.txt in the release)
ARG GODOT_SHA512=ef4e76880a514257175544952c61191106fdef3095b909bafed9fcbeb230c3e5533920a0f3012882dd4bbde83028a67549825794e2d2c3cf76eba7918b71370e
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL -o /tmp/godot.zip \
      "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
 && echo "${GODOT_SHA512}  /tmp/godot.zip" | sha512sum -c - \
 && unzip -q /tmp/godot.zip -d /tmp \
 && mv "/tmp/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
 && chmod +x /usr/local/bin/godot

FROM debian:trixie-slim
# Godot looks for fontconfig even headless (only a log line without it); its display libraries only
# load with a window, which it never opens here.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libfontconfig1 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 1000 tainted
COPY --from=godot /usr/local/bin/godot /usr/local/bin/godot
COPY tainted.pck /game/tainted.pck
# The start script (a docker stop becomes a proper shutdown: everyone told, every account written)
# and the admin command (docker exec tainted tainted-admin status / kick / ban / ...)
COPY entrypoint.sh /usr/local/bin/tainted-server
COPY tainted-admin /usr/local/bin/tainted-admin
RUN sed -i 's/\r$//' /usr/local/bin/tainted-server /usr/local/bin/tainted-admin \
 && chmod 755 /usr/local/bin/tainted-server /usr/local/bin/tainted-admin
USER tainted
WORKDIR /home/tainted
# TAINTED_AUTH: Autharr's URL to require signing in (empty: a device key is an account, for the LAN)
# TAINTED_UPDATE: where to get the new build, told to a game too old to join
# TAINTED_STOP_WARNING: seconds' warning players get when the container is stopped
ENV TAINTED_NAME="Tainted World" TAINTED_MAX=32 TAINTED_AUTH="" TAINTED_UPDATE="" TAINTED_STOP_WARNING=10
# The players' characters (AccountStore), with its daily backups: a volume (docker-compose.yml)
VOLUME /data
EXPOSE 24601
# Healthy while the server's WebSocket port takes connections.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD bash -c '</dev/tcp/127.0.0.1/24601' || exit 1
CMD ["/usr/local/bin/tainted-server"]
