# Third-Party Notices

This project was inspired by Yegor Bugayenko's `yegor256/prompt` repository:

https://github.com/yegor256/prompt

Some guidance ideas were adapted into Perl-specific coding-agent instructions.

`yegor256/prompt` is licensed under the MIT License.

Copyright (c) 2025 Yegor Bugayenko

The upstream MIT license notice is included in
[`LICENSES/MIT-YEGOR.txt`](LICENSES/MIT-YEGOR.txt).

See:

- https://github.com/yegor256/prompt/blob/master/LICENSE.txt
- https://github.com/yegor256/prompt/tree/master

The optional, unpublished `codex` Docker target downloads the `rtk-ai/rtk`
binary during local and CI builds. RTK is licensed under the Apache License
2.0.

See:

- https://github.com/rtk-ai/rtk/blob/master/LICENSE
- https://github.com/rtk-ai/rtk

The Docker images contain additional software from Debian, Perl, CPAN, Oh My
Zsh, and, for the optional Codex target, Codex CLI and RTK. Each concrete image
contains a generated inventory and the available corresponding license texts
under `/opt/perl-essentials/licenses`. This generated audit is authoritative
for the versions bundled by that build. Entries marked `NOASSERTION` identify
upstream metadata that requires manual review; they are reported by CI without
being treated as a false license declaration.
