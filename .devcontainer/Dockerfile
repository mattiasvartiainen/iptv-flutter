FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG FLUTTER_WEBOS_REF=7ba5d507dd03393093fef3675c70f87e640b039f
ARG WEBOS_NDK_VERSION=11.2.0

ENV DEBIAN_FRONTEND=noninteractive \
    FLUTTER_WEBOS_HOME=/opt/flutter-webos \
    WEBOS_FLUTTER_NDK_ENV=/usr/local/starfish-sdk-x86_64/environment-setup-ca9v1-webosmllib32-linux-gnueabi \
    PATH=/opt/flutter-webos/bin:/home/vscode/.nvm/versions/node/v16.20.2/bin:${PATH}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        clang \
        cmake \
        curl \
        file \
        git \
        libepoxy-dev \
        libgtk-3-0 \
        libgtk-3-dev \
        libmpv-dev \
        mpv \
        ninja-build \
        pkg-config \
        unzip \
        wget \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/lg-flutter-webos/flutter-webos.git "${FLUTTER_WEBOS_HOME}" \
    && cd "${FLUTTER_WEBOS_HOME}" \
    && git checkout "${FLUTTER_WEBOS_REF}" \
    && chown -R vscode:vscode "${FLUTTER_WEBOS_HOME}"

RUN su vscode -c 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash' \
    && su vscode -c '. /home/vscode/.nvm/nvm.sh \
        && nvm install 16.20.2 \
        && nvm alias default 16.20.2'

RUN su vscode -c '. /home/vscode/.nvm/nvm.sh \
    && nvm use 16.20.2 \
    && npm install --global @webos-tools/cli'

RUN mkdir -p /tmp/webos-ndk \
    && cd /tmp/webos-ndk \
    && wget -q "https://github.com/lg-flutter-webos/ndk/releases/download/${WEBOS_NDK_VERSION}/webos-ndk-flutter-starfish-x86_64-ca9v1-${WEBOS_NDK_VERSION}.sh" \
    && chmod +x "webos-ndk-flutter-starfish-x86_64-ca9v1-${WEBOS_NDK_VERSION}.sh" \
    && "./webos-ndk-flutter-starfish-x86_64-ca9v1-${WEBOS_NDK_VERSION}.sh" -y \
    && rm -rf /tmp/webos-ndk

RUN printf '%s\n' \
    'export FLUTTER_WEBOS_HOME=/opt/flutter-webos' \
    'export WEBOS_FLUTTER_NDK_ENV=/usr/local/starfish-sdk-x86_64/environment-setup-ca9v1-webosmllib32-linux-gnueabi' \
    'export PATH="$FLUTTER_WEBOS_HOME/bin:$HOME/.nvm/versions/node/v16.20.2/bin:$PATH"' \
    > /etc/profile.d/flutter-webos.sh \
    && echo 'source /etc/profile.d/flutter-webos.sh' >> /home/vscode/.bashrc \
    && chown -R vscode:vscode /opt/flutter-webos /home/vscode/.bashrc

USER vscode

WORKDIR /workspaces/iptv-flutter

RUN . /etc/profile.d/flutter-webos.sh \
    && flutter-webos precache
