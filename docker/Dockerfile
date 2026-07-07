ARG platform=linux/amd64

FROM --platform=$platform python:3.14-slim-trixie

RUN \
    apt-get update -y && \
    apt-get upgrade -y && \
    apt-get dist-upgrade -y && \
    apt-get install -y --no-install-recommends \
    build-essential \
    bzip2 \
    curl \
    g++ \
    gh \
    git \
    less \
    locales \
    make \
    texlive \
    tmux \
    wget \
    zip && \
    # cleanup
    apt-get autoremove -y && \
    apt-get purge -y --auto-remove && \
    rm -rf /var/lib/apt/lists/*

# timezone and locale
RUN ln -fs /usr/share/zoneinfo/UTC /etc/localtime && \
    sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && \
    locale-gen en_US.UTF-8

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# non-root user
RUN \
    adduser --disabled-password --gecos "" --uid 1002 --gid 100 --force-badname guser && \
    usermod -aG sudo guser && \
    echo 'guser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

COPY docker/root/* /root/
COPY docker/guser/.bashrc docker/guser/.tmux.conf /home/guser/
COPY docker/guser/.claude/ /home/guser/.claude/

RUN chown -R guser:users /home/guser

USER guser
WORKDIR /home/guser

# install claude for guser
RUN curl -fsSL https://claude.ai/install.sh | bash
