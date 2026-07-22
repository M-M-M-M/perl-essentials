use strict ;
use warnings ;

use Archive::Tar qw(COMPRESS_GZIP) ;
use Cwd          qw(abs_path) ;
use File::Find   qw(find) ;
use File::Path   qw(make_path) ;
use File::Spec ;
use File::Temp qw(tempdir) ;
use JSON::PP   qw(decode_json encode_json) ;
use Test::More ;

my $root   = abs_path('.') ;
my $script = File::Spec->catfile( $root, 'scripts', 'license-audit.pl' ) ;

ok -x $script, 'license audit script is executable' ;

my $dockerfile = _read_text('Dockerfile') ;
like $dockerfile, qr/cpanm .*--save-dists \/tmp\/cpan-dists/s,
  'Docker build retains installed CPAN distributions for auditing' ;
like $dockerfile,
  qr{/opt/perl-essentials/scripts/license-audit\.pl.*--output /opt/perl-essentials/licenses}s,
  'final Perl image generates an embedded license audit' ;
like $dockerfile, qr/--dpkg-status \/var\/lib\/dpkg\/status/,
  'license audit reads the installed Debian package database' ;
like $dockerfile, qr/--debian-copyright-root \/usr\/share\/doc/,
  'license audit reads Debian copyright notices' ;
like $dockerfile, qr/--cpan-dists \/tmp\/cpan-dists/,
  'license audit reads saved CPAN distributions' ;
like $dockerfile, qr/perlartistic\.pod.*perlgpl\.pod/s,
  'license audit retains both Perl license texts' ;
like $dockerfile, qr{/opt/oh-my-zsh/LICENSE\.txt},
  'license audit retains the Oh My Zsh license' ;
like $dockerfile, qr{raw\.githubusercontent\.com/openai/codex/main/LICENSE},
  'Codex target downloads the matching upstream license text' ;
like $dockerfile, qr{raw\.githubusercontent\.com/rtk-ai/rtk/master/LICENSE},
  'Codex target downloads the matching RTK license text' ;
like $dockerfile, qr/--base-inventory \/opt\/perl-essentials\/licenses\/inventory\.json/,
  'Codex audit extends the final-image inventory' ;
my $absolute_audit_calls
  = () = $dockerfile =~ m{/opt/perl-essentials/scripts/license-audit\.pl}g ;
is $absolute_audit_calls, 2,
  'both image audits use the absolute script path' ;

my $ci = _read_text('scripts/ci-build.sh') ;
like $ci, qr{licenses.*inventory\.json}s,
  'CI validates the embedded JSON inventory' ;
like $ci, qr{/opt/perl-essentials/licenses/SUMMARY\.md},
  'CI validates the embedded readable summary' ;
like $ci, qr/license-audit.*NOASSERTION|NOASSERTION.*license-audit/s,
  'CI reports unknown licenses without rejecting them' ;
like $ci, qr/codex-cli.*inventory|inventory.*codex-cli/s,
  'Codex CI requires Codex CLI in its inventory' ;
like $ci, qr/rtk.*inventory|inventory.*rtk/s,
  'Codex CI requires RTK in its inventory' ;

my $public_files = _read_text('.public-files') ;
like $public_files, qr{^scripts/license-audit\.pl$}m,
  'public export includes the license audit generator' ;
like $public_files, qr{^test/license-audit\.t$}m,
  'public export includes license audit tests' ;

SKIP: {
  skip 'license audit script is not available yet', 21 if !-x $script ;

  my $tmp       = tempdir( CLEANUP => 1 ) ;
  my $dpkg      = File::Spec->catfile( $tmp, 'status' ) ;
  my $copyright = File::Spec->catdir( $tmp, 'copyright' ) ;
  my $dists     = File::Spec->catdir( $tmp, 'dists' ) ;
  my $direct    = File::Spec->catfile( $tmp, 'direct.json' ) ;
  my $output    = File::Spec->catdir( $tmp, 'output' ) ;

  make_path( File::Spec->catdir( $copyright, 'curl' ), $dists ) ;
  _write_text(
    $dpkg,
    <<'STATUS',
Package: curl
Version: 8.14.1-2
Architecture: arm64

Package: undocumented
Version: 1.2.3
Architecture: all
STATUS
  ) ;
  _write_text(
    File::Spec->catfile( $copyright, 'curl', 'copyright' ),
    <<'COPYRIGHT' . "License: BSD-3-Viag\x{e9}ne\n",
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Files: *
Copyright: Example
License: curl
COPYRIGHT
  ) ;

  _create_distribution(
    $dists,
    'Example-Licensed-1.0',
    {
      name    => 'Example-Licensed',
      version => '1.0',
      license => [ 'perl_5', 'mit' ],
    },
    {
      LICENSE => "Example license text\n",
      NOTICE  => "Example notice text\n",
    },
  ) ;
  _create_distribution(
    $dists,
    'Example-Unknown-2.0',
    {
      name    => 'Example-Unknown',
      version => '2.0',
    },
    {},
  ) ;
  _create_distribution(
    $dists,
    'Example-License-Directory-3.0',
    {
      name    => 'Example-License-Directory',
      version => '3.0',
      license => ['mit'],
    },
    {
      LICENSE => undef,
    },
  ) ;

  my $ohmyzsh_license = File::Spec->catfile( $tmp, 'ohmyzsh-license.txt' ) ;
  _write_text( $ohmyzsh_license, "Oh My Zsh MIT license\n" ) ;
  _write_text(
    $direct,
    encode_json(
      [
        {
          name         => 'ohmyzsh',
          version      => 'fixture',
          license      => 'MIT',
          source       => 'https://github.com/ohmyzsh/ohmyzsh',
          license_file => $ohmyzsh_license,
        },
      ],
    ),
  ) ;

  my ( $status, $audit_output ) = _run(
    $script,
    '--output',                $output,
    '--dpkg-status',           $dpkg,
    '--debian-copyright-root', $copyright,
    '--cpan-dists',            $dists,
    '--direct-components',     $direct,
    '--perl-version',          '5.43.9',
  ) ;
  is $status, 0, 'license audit succeeds on representative fixtures'
    or diag $audit_output ;
  unlike $audit_output, qr/Use of uninitialized value \$content/,
    'unreadable CPAN license entries do not emit content warnings' ;
  like $audit_output, qr/NOASSERTION: deb:undocumented/,
    'missing Debian license is reported' ;
  like $audit_output, qr/NOASSERTION: cpan:Example-Unknown/,
    'missing CPAN license is reported' ;

  my $inventory_path = File::Spec->catfile( $output, 'inventory.json' ) ;
  my $summary_path   = File::Spec->catfile( $output, 'SUMMARY.md' ) ;
  ok -f $inventory_path, 'JSON inventory is generated' ;
  ok -f $summary_path,   'Markdown summary is generated' ;

  my $inventory = _read_json($inventory_path) ;
  is $inventory->{schema_version},  1, 'inventory schema is versioned' ;
  is $inventory->{component_count}, 7, 'all fixture components are inventoried' ;

  my %component = map {
    ( "$_->{ecosystem}:$_->{name}" => $_ )
  } @{ $inventory->{components} } ;

  is_deeply $component{'deb:curl'}{licenses},
    [ "BSD-3-Viag\x{e9}ne", 'curl' ],
    'UTF-8 Debian license identifiers are parsed' ;
  is_deeply $component{'deb:undocumented'}{licenses}, ['NOASSERTION'],
    'missing Debian metadata uses NOASSERTION' ;
  is_deeply $component{'cpan:Example-Licensed'}{licenses},
    [ 'Artistic-1.0-Perl OR GPL-1.0-or-later', 'MIT' ],
    'CPAN license identifiers are normalized' ;
  is_deeply $component{'cpan:Example-Unknown'}{licenses}, ['NOASSERTION'],
    'missing CPAN metadata uses NOASSERTION' ;
  is_deeply $component{'cpan:Example-License-Directory'}{licenses}, ['MIT'],
    'CPAN distribution with unreadable license entry is still inventoried' ;
  is scalar @{ $component{'cpan:Example-License-Directory'}{license_files} },
    0, 'unreadable CPAN license entry is not referenced' ;
  is_deeply $component{'perl:perl'}{licenses},
    ['Artistic-1.0-Perl OR GPL-1.0-or-later'],
    'Perl dual licensing is explicit' ;
  is_deeply $component{'direct:ohmyzsh'}{licenses}, ['MIT'],
    'direct component license is inventoried' ;

  my @cpan_files = @{ $component{'cpan:Example-Licensed'}{license_files} } ;
  is scalar @cpan_files, 2, 'CPAN LICENSE and NOTICE files are retained' ;
  ok !grep( { !-f File::Spec->catfile( $output, $_ ) } @cpan_files ),
    'CPAN inventory references existing files' ;

  my $summary = _read_text($summary_path) ;
  like $summary, qr/\| cpan \| Example-Licensed \| 1\.0 \|/,
    'summary lists licensed CPAN distributions' ;
  like $summary, qr/\| cpan \| Example-Unknown \| 2\.0 \| NOASSERTION \|/,
    'summary highlights unknown CPAN licenses' ;

  my $codex_license = File::Spec->catfile( $tmp, 'codex-license.txt' ) ;
  my $codex_direct  = File::Spec->catfile( $tmp, 'codex-direct.json' ) ;
  my $codex_output  = File::Spec->catdir( $tmp, 'codex-output' ) ;
  _write_text( $codex_license, "Apache License 2.0\n" ) ;
  _write_text(
    $codex_direct,
    encode_json(
      [
        {
          name         => 'codex-cli',
          version      => 'fixture',
          license      => 'Apache-2.0',
          source       => 'https://github.com/openai/codex',
          license_file => $codex_license,
        },
        {
          name         => 'rtk',
          version      => 'fixture',
          license      => 'Apache-2.0',
          source       => 'https://github.com/rtk-ai/rtk',
          license_file => $codex_license,
        },
      ],
    ),
  ) ;

  ( $status, $audit_output ) = _run(
    $script,
    '--output',            $codex_output,
    '--base-inventory',    $inventory_path,
    '--direct-components', $codex_direct,
  ) ;
  is $status, 0, 'Codex audit extends the final-image inventory'
    or diag $audit_output ;

  my $codex_inventory
    = _read_json( File::Spec->catfile( $codex_output, 'inventory.json' ) ) ;
  my %codex_component = map {
    ( "$_->{ecosystem}:$_->{name}" => $_ )
  } @{ $codex_inventory->{components} } ;
  ok $codex_component{'direct:codex-cli'}, 'Codex CLI is added to Codex audit' ;
  ok $codex_component{'direct:rtk'},       'RTK is added to Codex audit' ;
  ok $codex_component{'cpan:Example-Licensed'},
    'base inventory components survive Codex enrichment' ;
  is $codex_inventory->{component_count}, 9,
    'Codex inventory includes base and Codex-only components' ;
}

done_testing ;

sub _create_distribution {
  my ( $directory, $name, $metadata, $files ) = @_ ;
  $metadata = {
    'meta-spec' => {
      version => 2,
      url     => 'https://metacpan.org/pod/CPAN::Meta::Spec',
    },
    abstract       => 'License audit fixture',
    author         => ['Fixture Author'],
    dynamic_config => JSON::PP::false,
    generated_by   => 'test/license-audit.t',
    release_status => 'stable',
    %{$metadata},
  } ;
  my $source = File::Spec->catdir( $directory, "$name-source", $name ) ;
  make_path($source) ;
  _write_text(
    File::Spec->catfile( $source, 'META.json' ),
    JSON::PP->new->canonical->pretty->encode($metadata),
  ) ;
  for my $file ( sort keys %{$files} ) {
    my $path = File::Spec->catfile( $source, $file ) ;
    if ( !defined $files->{$file} ) {
      make_path($path) ;
      next ;
    }
    _write_text( $path, $files->{$file} ) ;
  }

  my $archive      = File::Spec->catfile( $directory, "$name.tar.gz" ) ;
  my $cwd          = Cwd::getcwd() ;
  my $archive_root = File::Spec->catdir( $directory, "$name-source" ) ;
  my @archive_files ;
  find(
    {
      no_chdir => 1,
      wanted   => sub {
        push @archive_files,
          File::Spec->abs2rel( $File::Find::name, $archive_root )
          if -f $File::Find::name || -d $File::Find::name ;
      },
    },
    $source,
  ) ;
  chdir $archive_root
    or die "Cannot enter distribution fixture: $!" ;
  Archive::Tar->create_archive(
    $archive, COMPRESS_GZIP,
    @archive_files,
  ) ;
  chdir $cwd or die "Cannot restore working directory: $!" ;
  return ;
}

sub _read_text {
  my ($path) = @_ ;
  open my $fh, '<:encoding(UTF-8)', $path
    or die "Cannot read '$path': $!" ;
  local $/ ;
  my $content = <$fh> ;
  close $fh or die "Cannot close '$path': $!" ;
  return $content ;
}

sub _read_json {
  my ($path) = @_ ;
  open my $fh, '<:raw', $path or die "Cannot read '$path': $!\n" ;
  local $/ ;
  my $content = <$fh> ;
  close $fh or die "Cannot close '$path': $!\n" ;
  return decode_json($content) ;
}

sub _run {
  my @command = @_ ;
  my $command = join q{ }, map { _shell_quote($_) } @command ;
  my $output  = qx{$command 2>&1} ;
  return ( $? >> 8, $output ) ;
}

sub _shell_quote {
  my ($value) = @_ ;
  $value =~ s/'/'"'"'/g ;
  return "'$value'" ;
}

sub _write_text {
  my ( $path, $content ) = @_ ;
  open my $fh, '>:encoding(UTF-8)', $path
    or die "Cannot write '$path': $!" ;
  print {$fh} $content
    or die "Cannot write '$path': $!" ;
  close $fh or die "Cannot close '$path': $!" ;
  return ;
}
