#!/usr/bin/env bash
# Run from anywhere (nothing on the host is mounted):
#   ./devbox.sh          open a shell in the container
#   ./devbox.sh <cmd>    run a command in the container
set -euo pipefail

# Resource limits (applied when the container is first created;
# to change them later: docker rm -f devbox-$USER, then run again)
CPUS="${CPUS:-16}"
MEMORY="${MEMORY:-64g}"
PIDS="${PIDS:-4096}"

# Claude Code (1 = install it in the container, 0 = don't)
CLAUDE="${CLAUDE:-1}"

IMAGE="devbox:${USER}"

# Build the image on first run (the Dockerfile is inlined below)
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
docker build -t "$IMAGE" --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" - <<'DOCKERFILE'
FROM ubuntu:24.04
ARG UID GID
RUN userdel -r ubuntu 2>/dev/null || true \
 && groupadd -o -g $GID dev \
 && useradd -m -o -u $UID -g $GID -s /bin/bash dev
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates curl ripgrep less procps sudo \
 && rm -rf /var/lib/apt/lists/* \
 && echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev \
 && chmod 440 /etc/sudoers.d/dev \
 && mkdir -p /workspace && chown dev:dev /workspace
USER dev
ENV PATH="/home/dev/.local/bin:${PATH}"
WORKDIR /workspace
DOCKERFILE
fi

NAME="devbox-${USER}"

# Create the container once and keep it (software you install stays)
if ! docker container inspect "$NAME" >/dev/null 2>&1; then
  # All data lives in the container and Docker volumes, not in host directories.
  # Never add --privileged or mount /var/run/docker.sock here
  docker run -d --name "$NAME" \
    --cpus="$CPUS" --memory="$MEMORY" --pids-limit="$PIDS" \
    -v "devbox-work-${USER}":/workspace \
    -v "devbox-home-${USER}":/home/dev \
    "$IMAGE" sleep infinity >/dev/null
fi

# Start it again if it was stopped (e.g. after a server reboot)
docker start "$NAME" >/dev/null

# Install Claude Code once (it is stored in the home volume, so it persists)
# and alias "claude" to always run with --dangerously-skip-permissions
if [[ "$CLAUDE" == "1" ]]; then
  docker exec "$NAME" bash -c '
    command -v claude >/dev/null || curl -fsSL https://claude.ai/install.sh | bash
    ALIAS="alias claude=\"claude --dangerously-skip-permissions\""
    grep -qxF "$ALIAS" ~/.bashrc 2>/dev/null || echo "$ALIAS" >> ~/.bashrc
  '
fi

if [[ $# -gt 0 ]]; then CMD=("$@"); else CMD=(bash); fi
docker exec -it "$NAME" "${CMD[@]}"
