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

COPY cpanfile cpanfile-bootstrap-notest cpanfile-notest perl-versions.conf ./
COPY AGENTS.md .perltidyrc THIRD-PARTY-NOTICES.md ./
COPY LICENSES/ ./LICENSES/
COPY .perltidyrc /etc/perltidyrc
COPY scripts/ ./scripts/

# Interactive target for debugging the base image and CPAN installations
# manually. No broad CPAN update or curated module installation has run yet.
FROM system AS debug-base
CMD ["zsh", "-l"]

FROM debug-base AS modules

ARG CPAN_CONFIGURE_TIMEOUT=1200
ARG CPAN_TEST_TIMEOUT=7200

# This image deliberately favors current CPAN modules over reproducible
# dependency versions. Tests are skipped only for this broad upgrade because
# unrelated upstream test failures must not prevent the curated test pass.
RUN cpanm --save-dists /tmp/cpan-dists -in App::cpanoutdated \
 && cpan-outdated -p | cpanm --save-dists /tmp/cpan-dists -in

# Curated distributions that need installation run their CPAN test suites.
# Current core/dual-life modules are not downgraded merely to rerun tests.
# Bootstrap exceptions are installed first when a dependency's upstream tests
# would otherwise block a tested curated module. Documented direct exceptions
# are installed after the tested manifest. Every module in all groups still has
# to pass the smoke test.
RUN if scripts/list-cpanfile-modules.pl cpanfile-bootstrap-notest | grep -q .; then \
      cpanm --save-dists /tmp/cpan-dists \
        --configure-timeout "${CPAN_CONFIGURE_TIMEOUT}" \
        -in --installdeps --cpanfile cpanfile-bootstrap-notest .; \
    fi \
 && cpanm --save-dists /tmp/cpan-dists \
      --configure-timeout "${CPAN_CONFIGURE_TIMEOUT}" \
      --test-timeout "${CPAN_TEST_TIMEOUT}" \
      --installdeps --cpanfile cpanfile . \
 && if scripts/list-cpanfile-modules.pl cpanfile-notest | grep -q .; then \
      cpanm --save-dists /tmp/cpan-dists \
        --configure-timeout "${CPAN_CONFIGURE_TIMEOUT}" \
        -in --installdeps --cpanfile cpanfile-notest .; \
    fi \
 && scripts/check-manifests.pl cpanfile cpanfile-bootstrap-notest cpanfile-notest \
 && scripts/smoke-test.pl cpanfile cpanfile-bootstrap-notest cpanfile-notest \
 && scripts/check-runtime-tools.sh \
 && scripts/module-versions.pl cpanfile cpanfile-bootstrap-notest cpanfile-notest > /opt/perl-essentials/module-versions.txt \
 && perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode([{ \
      name => "ohmyzsh", version => $ARGV[0], license => "MIT", \
      source => "https://github.com/ohmyzsh/ohmyzsh", \
      license_file => "/opt/oh-my-zsh/LICENSE.txt" \
    }])' "$(git -C /opt/oh-my-zsh rev-parse HEAD)" \
      > /tmp/direct-components.json \
 && /opt/perl-essentials/scripts/license-audit.pl \
      --output /opt/perl-essentials/licenses \
      --dpkg-status /var/lib/dpkg/status \
      --debian-copyright-root /usr/share/doc \
      --cpan-dists /tmp/cpan-dists \
      --direct-components /tmp/direct-components.json \
      --perl-version "$(perl -MConfig -e 'print $Config{version}')" \
      --perl-license "$(perl -MConfig -e 'print "$Config{privlib}/pod/perlartistic.pod"')" \
      --perl-license "$(perl -MConfig -e 'print "$Config{privlib}/pod/perlgpl.pod"')" \
 && rm -rf /root/.cpanm /tmp/cpan-dists /tmp/direct-components.json

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
 && curl -fsSL \
      https://raw.githubusercontent.com/openai/codex/main/LICENSE \
      -o /tmp/LICENSE-CODEX \
 && curl -fsSL \
      https://raw.githubusercontent.com/rtk-ai/rtk/master/LICENSE \
      -o /tmp/LICENSE-RTK \
 && perl -MJSON::PP -e 'print JSON::PP->new->canonical->encode([ \
      { name => "codex-cli", version => $ARGV[0], license => "Apache-2.0", \
        source => "https://github.com/openai/codex", \
        license_file => "/tmp/LICENSE-CODEX" }, \
      { name => "rtk", version => $ARGV[1], license => "Apache-2.0", \
        source => "https://github.com/rtk-ai/rtk", \
        license_file => "/tmp/LICENSE-RTK" } \
    ])' \
      "$(codex --version | awk '{ print $2 }')" \
      "$(rtk --version | awk '{ print $2 }')" \
      > /tmp/codex-components.json \
 && /opt/perl-essentials/scripts/license-audit.pl \
      --output /tmp/licenses-codex \
      --base-inventory /opt/perl-essentials/licenses/inventory.json \
      --direct-components /tmp/codex-components.json \
 && rm -rf /opt/perl-essentials/licenses \
 && mv /tmp/licenses-codex /opt/perl-essentials/licenses \
 && rm -f /tmp/LICENSE-CODEX /tmp/LICENSE-RTK /tmp/codex-components.json \
 && rm -rf /var/lib/apt/lists/*

ENV CODEX_HOME=/codex \
    HOME=/codex \
    RTK_TELEMETRY_DISABLED=1

RUN mkdir -p "${CODEX_HOME}"

WORKDIR /work
ENTRYPOINT ["/opt/perl-essentials/scripts/codex-entrypoint.sh"]
CMD ["codex"]

# Keep unqualified builds equivalent to the Perl-only final image.
FROM final AS default
