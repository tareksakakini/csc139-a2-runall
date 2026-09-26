FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Core toolchain + the tracing tools this course needs.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential \
      gdb \
      strace \
      ltrace \
      valgrind \
      man-db \
      manpages \
      manpages-dev \
      file \
      tree \
 && rm -rf /var/lib/apt/lists/*

# POSIX section-3p man pages live in multiverse and may be unavailable on some
# mirrors; never fail the image build over them.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      manpages-posix manpages-posix-dev \
 ; rm -rf /var/lib/apt/lists/* ; true
