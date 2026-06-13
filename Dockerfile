ARG PERL_VERSION=5.43.9
FROM perl:${PERL_VERSION}-threaded AS system

ARG PERL_VERSION

LABEL org.opencontainers.image.title="perl-essentials" \
      org.opencontainers.image.description="Threaded Perl with a curated, up-to-date set of CPAN modules" \
      org.opencontainers.image.version="${PERL_VERSION}" \
      org.opencontainers.image.licenses="MIT"

# These packages support interactive troubleshooting.
RUN if grep -q '^VERSION_CODENAME=buster$' /etc/os-release; then \
      sed -i \
        -e 's|deb.debian.org/debian|archive.debian.org/debian|g' \
        -e 's|security.debian.org/debian-security|archive.debian.org/debian-security|g' \
        -e '/buster-updates/d' \
        /etc/apt/sources.list; \
      printf 'Acquire::Check-Valid-Until "false";\n' \
        > /etc/apt/apt.conf.d/99archive; \
    fi \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      coreutils \
      findutils \
      git \
      grep \
      ripgrep \
      sed \
      spell \
      vim \
      zsh \
 && git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /opt/oh-my-zsh \
 && ln -s "$(command -v cat)" /usr/local/bin/gcat \
 && ln -s "$(command -v find)" /usr/local/bin/gfind \
 && ln -s "$(command -v grep)" /usr/local/bin/ggrep \
 && ln -s "$(command -v sed)" /usr/local/bin/gsed \
 && rm -rf /var/lib/apt/lists/*

ENV ZSH=/opt/oh-my-zsh

COPY config/perl-essentials.zsh /etc/zsh/zshrc

WORKDIR /opt/perl-essentials

COPY cpanfile cpanfile-notest perl-versions.conf ./
COPY AGENTS.md .perltidyrc THIRD-PARTY-NOTICES.md ./
COPY LICENSES/ ./LICENSES/
COPY .perltidyrc /etc/perltidyrc
COPY scripts/ ./scripts/

# Interactive target for debugging the base image and CPAN installations
# manually. No broad CPAN update or curated module installation has run yet.
FROM system AS debug-base
CMD ["zsh", "-l"]

FROM debug-base AS modules

# This image deliberately favors current CPAN modules over reproducible
# dependency versions. Tests are skipped only for this broad upgrade because
# unrelated upstream test failures must not prevent the curated test pass.
RUN cpanm -in App::cpanoutdated \
 && cpan-outdated -p | cpanm -in

# Curated distributions that need installation run their CPAN test suites.
# Current core/dual-life modules are not downgraded merely to rerun tests.
# Documented exceptions are installed separately without upstream tests.
# Every module in both groups still has to pass the smoke test.
RUN cpanm --configure-timeout 300 --installdeps --cpanfile cpanfile . \
 && if scripts/list-cpanfile-modules.pl cpanfile-notest | grep -q .; then \
      cpanm --configure-timeout 300 -in --installdeps --cpanfile cpanfile-notest .; \
    fi \
 && scripts/check-manifests.pl cpanfile cpanfile-notest \
 && scripts/smoke-test.pl cpanfile cpanfile-notest \
 && scripts/check-runtime-tools.sh \
 && scripts/module-versions.pl cpanfile cpanfile-notest > /opt/perl-essentials/module-versions.txt \
 && rm -rf /root/.cpanm

FROM modules AS debug
CMD ["zsh", "-l"]

FROM modules AS final
WORKDIR /work
CMD ["perl", "-v"]

FROM final AS codex

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bubblewrap \
      curl \
      gawk \
 && mkdir -p /opt/codex \
 && curl -fsSL https://chatgpt.com/codex/install.sh \
      | CODEX_HOME=/opt/codex \
        CODEX_INSTALL_DIR=/usr/local/bin \
        CODEX_NON_INTERACTIVE=1 \
        sh \
 && curl -fsSL \
      https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh \
      | RTK_INSTALL_DIR=/usr/local/bin sh \
 && rm -rf /var/lib/apt/lists/*

ENV CODEX_HOME=/codex \
    HOME=/codex \
    RTK_TELEMETRY_DISABLED=1

RUN mkdir -p "${CODEX_HOME}"

WORKDIR /work
ENTRYPOINT ["/opt/perl-essentials/scripts/codex-entrypoint.sh"]
CMD ["codex"]
