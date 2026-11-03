AGENTS.md version: 1.8.0

<!--
Based on M-M-M-M/perl-agents-md.
Project-specific additions are explicitly marked below.
-->

# Tools

Use GNU command-line tools such as gsed, gfind, ggrep, and gcat to ensure consistent behavior across macOS and Linux.
Prefer modern tools such as rg (ripgrep) when available.
Use perltidy with the repository `.perltidyrc` for formatting.
Use perlcritic for static analysis when available.
Use prove to run tests.
Use cpanm to manage dependencies.
Use Conventional Commits https://www.conventionalcommits.org/en/v1.0.0/

# Discipline

Push back on technical mistakes; defer to the user on vision and architecture.
Stay on scope; refactor only what the task requires.
Respect the requested change scope: test-only requests should not modify production code, and code-only requests should not rewrite tests beyond the requested behavior.
Keep test and production changes tied to the same behavior; avoid unrelated side effects.
Design top-down: behavior before modules, interfaces before implementation.
Before making changes, inspect the working tree and current branch.
Do not overwrite or discard existing user changes.
When the current branch tracks an upstream branch, synchronize with upstream before making changes when it is safe to do so, to avoid developing against a stale base and creating unnecessary merge conflicts.
Do not pull automatically when the working tree is dirty or synchronization could interfere with existing work.
Always TDD: reproduce bugs/features with tests before fixing.
Keep commits focused on one logical change; do not mix unrelated work in the same commit.
Use debug logging for hard problems, preferably through Log::Any or an existing project logger.
Don't fight upstream bugs; suggest filing an issue and wait for a fix unless a small local workaround is clearly justified.
Avoid large changes; leave TODO puzzles for follow-up.
Flag smells and refactoring; suggest issues, don't fix silently.
Do not merge changes without committing first and getting review or approval when the workflow requires it.

# Project Context

Before making changes, inspect existing project documentation relevant to the task.
The document names below are examples; use the project's existing equivalents when available. These guidelines do not require creating those files or a documentation index.

- Consult relevant project documentation, such as `README.md`, `DOCUMENTATION.md`, or `DEPLOYMENT.md`, before changing documented behavior, installation, deployment, configuration, or public interfaces.
- Consult `TODO.md` when present to understand related completed, current, and planned work.
- Consult `CHANGELOG.md` when historical behavior or compatibility may matter.
- Prefer existing project documentation and code over assumptions about how the project works.
- When a repository contains substantial documentation, prefer a small documentation index or table of contents that identifies authoritative documents and when they are relevant. Use it to locate documentation relevant to the task instead of reading all project documentation.

# Perl

For new standalone scripts and new projects without an existing Perl compatibility requirement, default to stable Perl 5.44 when the target runtime supports it.
For existing projects, the project's minimum supported Perl version, established conventions, and coding style take precedence, including when adding new files.
Before using newer syntax, establish the supported Perl version from project documentation, build configuration, CI, Docker images, or deployment requirements; do not assume the locally installed Perl version is the project's baseline.
Do not raise the minimum supported Perl version or change the language feature bundle without explicit approval or a task-specific justification.
For new code targeting Perl 5.44 or later, prefer `use v5.44;`, which enables `strict`, `warnings`, and the Perl 5.44 stable feature bundle; do not redundantly add `use strict;`, `use warnings;`, or feature pragmas already provided by that bundle.
For code targeting older Perl versions, use the compatible version declaration and explicitly enable `strict`, `warnings`, and individual features where the chosen version does not already enable them.
Prefer signatures for new subroutines and methods when they improve readability; include `$self` explicitly in object method signatures. Respect existing `@_` conventions in older code instead of converting them mechanically.
Prefer native `try` / `catch` for meaningful exception handling when supported (stable without `finally` since Perl 5.40). Preserve exception propagation, return behavior, and existing error-handling conventions.
Avoid experimental features by default; `finally` remains experimental in Perl 5.44. Use an experimental feature only for a justified, explicitly approved need.
When `module_true` is enabled (as with `use v5.44;`), a trailing `1;` is unnecessary in new modules; do not remove it from existing modules solely for modernization.
Use stable features such as `say`, `isa`, `state`, and `fc` where they improve clarity, without forcing syntax changes to unrelated code.
Do not introduce `given` / `when` or smartmatch (`~~`) in new code. Preserve existing uses unless a change or compatibility requirement justifies replacing them.
Do not mechanically rewrite existing `eval`, traditional parameter handling, or other working idioms merely to adopt newer syntax.
When maintaining existing code, prioritize consistency, compatibility, and minimal changes over adopting the newest Perl syntax.
Prefer lexical variables with my.
Avoid package globals unless required by the framework.
Avoid indirect object syntax.
Avoid symbolic references.
Avoid bareword filehandles; use lexical filehandles.
Use three-argument open.
Always check I/O errors.
Prefer autodie when appropriate.
Use UTF-8 deliberately. For text data, declare encodings explicitly at boundaries: source files, command-line arguments, environment variables, file I/O, STDIN, STDOUT, STDERR, network responses, database connections, and templates.
Do not apply UTF-8 layers to binary data such as archives, images, Excel files, compressed files, sockets carrying binary protocols, or raw checksums.
Prefer decoding bytes into Perl character strings as early as practical, and encoding character strings back to bytes only at output boundaries.
For source files containing non-ASCII text, use `use utf8;`.
For text file I/O, prefer explicit modes such as `>:encoding(UTF-8)` and `<:encoding(UTF-8)`, or an existing project abstraction that does the same.
Use modules for behavior, not large procedural scripts.
Keep packages small and cohesive.
Use namespaces that reflect domain concepts.
Avoid clever Perl when clear Perl is better.
Avoid excessive punctuation-heavy idioms when they reduce readability.
Prefer named subroutines over large anonymous blocks.
Avoid modifying $_ implicitly in non-trivial code.
Avoid hidden side effects in map and grep.
Use map for transformation, grep for filtering, foreach for side effects.
Do not introduce heavy dependencies without justification.
Error/log messages: no trailing period, single sentence, include context.
When a non-core module is needed, prefer this known module set before introducing another dependency: Archive::Zip, Archive::Zip::MemberRead, Array::Compare, Cwd, DBD::Pg, DBD::SQLite, DBI, Data::Dumper, Data::Peek, Date::Calc, DateTime, DateTime::Format::Excel, DateTime::Format::ISO8601, Devel::NYTProf, Encode, Excel::Writer::XLSX, Excel::Writer::XLSX::Utility, File::Copy, File::Path, File::Which, Getopt::Long, HTTP::Cookies, HTTP::Request::Common, I18N::Langinfo, IO::Pty, JSON, JSON::PP, JSON::Lines, LWP::UserAgent, List::MoreUtils, List::Util, Mojolicious::Lite, Math::Units, MIME::Base64, MIME::Lite, MIME::Parser, Net::LDAP, Net::SFTP::Foreign, Perl::Tidy, REST::Client, Scalar::Util, Sort::Key, Schedule::RateLimiter, Spreadsheet::XLSX, Text::CSV, Text::Iconv, Time::Duration, Time::HiRes, Time::Limit, URI::Escape, XML::Hash, XML::XML2JSON, XML::LibXML, XML::LibXML::XPathContext, Math::Units, Test::MockModule, threads, threads::shared, Thread::Queue, utf8, utf8::all, strict
Before introducing new modules, prefer modules that are actively maintained.

# Objects

Avoid object-oriented design unless it models the domain or matches the project style.
Prefer Moo, Moose, or the project’s existing object system.
Favor immutable objects where practical.
Favor "fail fast" over "fail safe".
Constructors should validate required data and leave objects in a valid state.
Avoid inheritance unless the domain model clearly requires it.
Favor composition and roles over inheritance.
Avoid generic names like Manager, Processor, Handler, and Helper unless required by the framework.
Avoid utility modules full of unrelated functions.
Keep object attributes few and meaningful.
Do not expose raw internal state unnecessarily.
Avoid setters unless mutation is part of the domain behavior.
Prefer explicit methods that express intent.
Never return undef to signal normal absence when a clearer value object, empty list, Maybe type, or exception is better.
Avoid type introspection and ref checks when polymorphism or roles are clearer.
Use exceptions consistently; do not mix silent failure, undef, and die randomly.

# Code Style

Format Perl files with perltidy using the repository `.perltidyrc`.
When formatting files in place, prefer `perltidy -b -bext='/' path/to/file.pl` to avoid creating `.bak` backup files.
Do not change `.perltidyrc` unless the user explicitly asks for style changes.
No inline comments for obvious code.
Use comments to explain why, not what.
Document public modules with POD.
Document purpose, invariants, and domain meaning rather than usage examples only.
Variables: short nouns for local scope, clear nouns for wider scope.
Subroutines: verbs for commands, nouns for queries.
Avoid long subroutines.
Avoid deeply nested conditionals.
Prefer early return for guard clauses.
Keep indentation monotonic and readable.
Keep paired delimiters visually clear.
Avoid blank-line noise, but allow blank lines to separate logical steps.

# Tests

Use Test::More or the project’s existing test framework.
Use Test2::V1 when already adopted by the project.
Run tests with prove
Add or update tests for the behavior being changed.
Increase coverage for touched behavior, but do not chase 100% coverage unless explicitly asked.
One behavior per test.
Keep tests short and explicit.
Name test files after the module or feature they cover.
Default to creating a new test file for each new feature; add to an existing file only when it belongs to the same functional area.
Use meaningful test names.
Avoid shared mutable state between tests.
Avoid global fixtures unless they are read-only and stable.
Use temp directories with File::Temp.
Do not rely on Internet access.
Use ephemeral ports for network tests.
Disable or capture logging in tests.
Prefer fakes/stubs over excessive mocks.
Use irregular/random-looking inputs where useful.
Inline small fixtures, generate large fixtures at runtime.
Test failure paths, not only happy paths.
Use timeouts for blocking operations.
Test concurrency when the code is concurrent.
Refactored code must keep the existing tests passing.
Do not test private implementation details.
Do not test accessors unless they encode behavior.
Do not assert exact error messages unless the message is part of the public contract.
Run test coverage.

# Browser Testing

Use browser-based testing when relevant to the changes being made.
Prefer Playwright for automated browser tests when available.
Prefer running Playwright in Docker rather than directly on the host, when Docker is available and suitable for the test.
Reuse existing Playwright Docker images when possible, ensuring compatibility between Playwright and browser versions.
Use isolated, ephemeral containers for Docker-based browser tests.
Do not mount sensitive host directories or the Docker socket into browser-testing containers.
Fall back to existing local browser installations or testing tools if Docker is unavailable or unsuitable.
Use isolated browser profiles without personal sessions or credentials.
Use dedicated test credentials when authenticated testing is required.
Prefer local or test environments over production.
Do not perform destructive or state-changing actions on production systems without explicit approval.
Do not install browser automation dependencies, pull new Docker images, or modify the system environment solely for testing without explicit approval.
If browser execution is blocked by sandbox restrictions, explain the limitation before requesting narrowly scoped elevated permissions.
Never disable sandbox protections globally to enable browser testing.
If browser testing cannot be performed, report the limitation and any tests that were skipped.
Never claim that a browser test passed unless it was actually executed.

# Markdown

Use Prettier for Markdown formatting when available.
Do not run Prettier on AGENTS.md or CHANGELOG.md unless the user explicitly asks or the diff is reviewed before commit.
Use markdownlint-cli2 for Markdown linting when available.
After modifying Markdown files, run Prettier and then markdownlint-cli2 on the modified files when available.
Let Prettier format Markdown tables; do not manually align table columns.
Do not reformat unrelated Markdown files.
Review the resulting diff after formatting and avoid unrelated formatting changes.
Known markdownlint exceptions are acceptable for AGENTS.md and CHANGELOG.md when they come from intentional project structure.
Do not rewrite AGENTS.md or CHANGELOG.md only to satisfy markdownlint line-length, first-heading, bare-URL, or duplicate-heading rules.
Allow markdownlint line-length exceptions for Markdown tables when Prettier expands columns beyond the configured limit.

# Documentation

Treat documentation as part of the change, not as a separate follow-up task.
Prefer updating the canonical document over creating a second description of the same behavior.
Avoid independent, overlapping descriptions of the same project behavior; link to the canonical documentation instead. Language translations are supported and should remain synchronized with the source document.
Update README.md and README.xx.md language versions when a change affects documented behavior, installation, configuration, or usage.
Apply the same rule to DOCUMENTATION.md and DOCUMENTATION.xx.md when documentation is maintained there instead of the README.
Update TODO.md when a completed task is tracked there, marking it as `- [x]`.
Update CHANGELOG.md when the change is user-visible or otherwise belongs in the changelog.
Before finishing a task, check whether the implementation changed any documented behavior, assumptions, deployment instructions, TODO items, or changelog-worthy behavior.

# Publication

<!-- Project-specific: perl-essentials -->

For GitHub public publication, do not use `gh release create` from this private
checkout. First publish the filtered public snapshot with `./publish-public.zsh`;
then the GitHub Release is created manually in the public GitHub repository.
Publishing that GitHub Release triggers the Docker Hub workflow.

# Local image inventories

<!-- Project-specific: perl-essentials -->

After relevant validated local builds and before releases affecting Perl, CPAN,
Codex, or RTK, run `scripts/refresh-local-inventory.sh` before removing images.
Use `--build` to build both Codex variants under temporary tags, capture their
inventories, and clean up those temporary images. This requires no published
project image. Review and commit README.md and DOCKERHUB.md together.
Do not refresh dates for documentation-only commits. Never invent capture dates.
The publication workflow refreshes Docker Hub separately; its generated artifact
is not automatically committed to Bitbucket or GitHub.
