# perl-essentials

`perl-essentials` extends the official Perl images with a curated,
production-oriented CPAN stack commonly required for automation, data
processing, reporting, database access, testing, profiling, and web
integrations.

Source and complete documentation:
https://github.com/M-M-M-M/perl-essentials

## Included module families

- Database: DBI, DBD::Pg, DBD::SQLite
- JSON: JSON, JSON::XS, Cpanel::JSON::XS, JSON::MaybeXS
- XML: XML::LibXML, XML::Hash, XML::XML2JSON
- HTTP/Web: LWP::UserAgent, REST::Client, HTTP::Cookies
- Spreadsheet: Excel::Writer::XLSX, Spreadsheet::XLSX
- Testing: Test::More, Test::MockModule
- Quality: Perl::Critic, Perl::Tidy
- Profiling: Devel::NYTProf
- Concurrency: threads, threads::shared, Thread::Queue
- Date/Time: DateTime, Date::Calc

## Usage examples

```sh
docker run --rm perlessentials/perl-essentials:5.42 \
  perl -MDBI -MJSON -e 'print "ready\n"'
```

```sh
docker run --rm -it \
  -v "$PWD":/work \
  perlessentials/perl-essentials:5.42
```

```sh
docker run --rm -it \
  -v "$PWD":/work \
  -v "$PWD/codex-auth":/codex \
  perlessentials/perl-essentials:codex zsh -l
```

```sh
docker run --rm perlessentials/perl-essentials:5.26 perl -e 'print "$^V\n"'
```

## Perl development tools

The image includes `perltidy`, `perlcritic`, `prove`, `cpanm`, `rg`, and the
GNU-prefixed commands `gcat`, `gfind`, `ggrep`, and `gsed`.

Perl::Tidy uses `/etc/perltidyrc` by default. A project-local `.perltidyrc`
under `/work` takes precedence. Use `-pro=/work/custom.perltidyrc` to select a
specific profile, or `-npro` to ignore all profiles.

Preview formatting without modifying the mounted file:

```sh
docker run --rm -v "$PWD":/work \
  perlessentials/perl-essentials:5.42 \
  perltidy -st -se /work/path/to/script.pl
```

Format in place without creating a backup, using the host user to preserve
file ownership:

```sh
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/work \
  perlessentials/perl-essentials:5.42 \
  perltidy -b -bext='/' /work/path/to/script.pl
```

## Available targets

<!-- PERL_TARGETS_START -->
| Perl series | Image version | Role |
| --- | --- | --- |
| 5.26 | 5.26.3 | Legacy baseline |
| 5.32 | 5.32.1 | Broad legacy compatibility |
| 5.36 | 5.36.3 | Common LTS distributions |
| 5.38 | 5.38.5 | Established production series |
| 5.40 | 5.40.4 | Maintained stable series |
| 5.42 | 5.42.2 | Latest stable series |
| 5.43 | 5.43.9 | Development compatibility |
<!-- PERL_TARGETS_END -->

## Codex target

A `codex` target is also available, based on the Perl 5.43.9 development image:

<!-- CODEX_TARGET_START -->
| Target | Perl base | Codex CLI | RTK | Publication |
| --- | --- | --- | --- | --- |
| `codex` | 5.43.9 | Latest at no-cache build; 0.139.0 observed 2026-06-12 | Latest at no-cache build; 0.42.4 observed 2026-06-12 | `codex`, release, and timestamp tags |
<!-- CODEX_TARGET_END -->

## Included Perl modules

<!-- MODULE_VERSIONS_START -->
Versions captured on 2026-06-19 10:11:10 (UTC).

This inventory was captured from the default development image at the
timestamp above. Module versions may differ between publication runs. For an
exact image, see `/opt/perl-essentials/module-versions.txt`.

| Module | Version |
| --- | --- |
| `Archive::Zip` | `1.68` |
| `Archive::Zip::MemberRead` | `1.68` |
| `Array::Compare` | `3.0.8` |
| `Cpanel::JSON::XS` | `4.42` |
| `Cwd` | `3.95` |
| `DBD::Pg` | `3.20.2` |
| `DBD::SQLite` | `1.78` |
| `DBI` | `1.648` |
| `Data::Dumper` | `2.192` |
| `Data::Peek` | `0.54` |
| `Date::Calc` | `6.4` |
| `DateTime` | `1.66` |
| `DateTime::Format::Excel` | `0.31` |
| `DateTime::Format::ISO8601` | `0.19` |
| `DateTime::Locale` | `1.45` |
| `Devel::NYTProf` | `6.15` |
| `Digest::SHA` | `6.04` |
| `Encode` | `3.24` |
| `Excel::Writer::XLSX` | `1.15` |
| `Excel::Writer::XLSX::Utility` | `1.15` |
| `File::Copy` | `2.43` |
| `File::Path` | `2.18` |
| `File::Spec` | `3.95` |
| `File::Temp` | `0.2312` |
| `File::Which` | `1.27` |
| `Getopt::Long` | `2.58` |
| `HTTP::Cookies` | `6.11` |
| `HTTP::Request::Common` | `7.02` |
| `I18N::Langinfo` | `0.24` |
| `IO::Pty` | `1.31` |
| `Imager` | `1.031` |
| `JSON` | `4.11` |
| `JSON::Lines` | `1.11` |
| `JSON::MaybeXS` | `1.004008` |
| `JSON::PP` | `4.18` |
| `JSON::XS` | `4.04` |
| `LWP::UserAgent` | `6.83` |
| `List::MoreUtils` | `0.430` |
| `List::Util` | `1.70` |
| `MIME::Base64` | `3.16_01` |
| `MIME::Lite` | `3.038` |
| `MIME::Parser` | `5.517` |
| `Math::Units` | `1.3` |
| `Mojolicious::Lite` | `9.46` |
| `Net::LDAP` | `0.68` |
| `Net::SFTP::Foreign` | `1.93` |
| `Perl::Critic` | `1.156` |
| `Perl::Tidy` | `20260204` |
| `Scalar::Util` | `1.70` |
| `Schedule::RateLimiter` | `0.01` |
| `Sort::Key` | `1.33` |
| `Spreadsheet::XLSX` | `0.18` |
| `Test::MockModule` | `0.185.2` |
| `Test::More` | `1.302220` |
| `Text::CSV` | `2.06` |
| `Text::Iconv` | `1.7` |
| `Thread::Queue` | `3.14` |
| `Time::Duration` | `1.21` |
| `Time::HiRes` | `1.9780` |
| `Time::Limit` | `0.003` |
| `URI::Escape` | `5.34` |
| `XML::Hash` | `0.95` |
| `XML::LibXML` | `2.0213` |
| `XML::LibXML::XPathContext` | `2.0213` |
| `threads` | `2.45` |
| `threads::shared` | `1.73` |
| `utf8` | `1.29` |
| `utf8::all` | `0.026` |
| `REST::Client` | `281` |
| `XML::XML2JSON` | `0.06` |
<!-- MODULE_VERSIONS_END -->
