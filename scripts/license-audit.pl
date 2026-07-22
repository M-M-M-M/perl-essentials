#!/usr/bin/env perl

use strict ;
use warnings ;

use Archive::Tar ;
use CPAN::Meta ;
use File::Basename qw(basename dirname) ;
use File::Copy     qw(copy) ;
use File::Find     qw(find) ;
use File::Path     qw(make_path remove_tree) ;
use File::Spec ;
use Getopt::Long qw(GetOptions) ;
use JSON::PP     qw(decode_json) ;

my $output ;
my $base_inventory ;
my $dpkg_status ;
my $debian_copyright_root ;
my $cpan_dists ;
my $direct_components ;
my $perl_version ;
my @perl_license ;

GetOptions(
  'output=s'                => \$output,
  'base-inventory=s'        => \$base_inventory,
  'dpkg-status=s'           => \$dpkg_status,
  'debian-copyright-root=s' => \$debian_copyright_root,
  'cpan-dists=s'            => \$cpan_dists,
  'direct-components=s'     => \$direct_components,
  'perl-version=s'          => \$perl_version,
  'perl-license=s@'         => \@perl_license,
) or die _usage() ;

die _usage()                               if !defined $output ;
die "Output directory must not be empty\n" if $output eq q{} ;

remove_tree($output) if -e $output ;
make_path( File::Spec->catdir( $output, 'texts' ) ) ;

my @components ;

if ( defined $base_inventory ) {
  my $base = _read_json($base_inventory) ;
  push @components, @{ $base->{components} || [] } ;
  _copy_tree(
    File::Spec->catdir( dirname($base_inventory), 'texts' ),
    File::Spec->catdir( $output,                  'texts' ),
  ) ;
}

if ( defined $dpkg_status ) {
  die "--debian-copyright-root is required with --dpkg-status\n"
    if !defined $debian_copyright_root ;
  push @components,
    _debian_components( $dpkg_status, $debian_copyright_root, $output ) ;
}

if ( defined $perl_version ) {
  my @license_files ;
  for my $source (@perl_license) {
    die "Perl license file not found: $source\n" if !-f $source ;
    my $target = File::Spec->catfile(
      $output, 'texts', 'perl', 'perl', basename($source),
    ) ;
    make_path( dirname($target) ) ;
    copy( $source, $target )
      or die "Cannot copy Perl license '$source': $!\n" ;
    push @license_files, File::Spec->abs2rel( $target, $output ) ;
  }
  push @components,
    {
    ecosystem     => 'perl',
    name          => 'perl',
    version       => $perl_version,
    licenses      => ['Artistic-1.0-Perl OR GPL-1.0-or-later'],
    source        => 'https://www.perl.org',
    license_files => \@license_files,
    } ;
}

if ( defined $cpan_dists ) {
  push @components, _cpan_components( $cpan_dists, $output ) ;
}

if ( defined $direct_components ) {
  push @components, _direct_components( $direct_components, $output ) ;
}

@components = sort { _component_cmp( $a, $b ) } @components ;

my %seen ;
for my $component (@components) {
  my $key = join "\0", @{$component}{qw(ecosystem name)} ;
  die "Duplicate component: $component->{ecosystem}:$component->{name}\n"
    if $seen{$key}++ ;
  $component->{licenses} = ['NOASSERTION']
    if !@{ $component->{licenses} || [] } ;
  if ( grep { $_ eq 'NOASSERTION' } @{ $component->{licenses} } ) {
    warn "NOASSERTION: $component->{ecosystem}:$component->{name}\n" ;
  }
}

my $inventory = {
  schema_version  => 1,
  component_count => scalar @components,
  components      => \@components,
} ;

_write_text(
  File::Spec->catfile( $output, 'inventory.json' ),
  JSON::PP->new->canonical->pretty->encode($inventory),
) ;
_write_summary( File::Spec->catfile( $output, 'SUMMARY.md' ), \@components ) ;

exit 0 ;

sub _copy_tree {
  my ( $source, $destination ) = @_ ;
  return if !-d $source ;

  find(
    {
      no_chdir => 1,
      wanted   => sub {
        my $path     = $File::Find::name ;
        my $relative = File::Spec->abs2rel( $path, $source ) ;
        return if $relative eq '.' ;
        my $target = File::Spec->catfile( $destination, $relative ) ;
        if ( -d $path ) {
          make_path($target) ;
          return ;
        }
        make_path( dirname($target) ) ;
        copy( $path, $target )
          or die "Cannot copy '$path' to '$target': $!\n" ;
      },
    },
    $source,
  ) ;
  return ;
}

sub _component_cmp {
  my ( $left, $right ) = @_ ;

  my $ecosystem_cmp = $left->{ecosystem} cmp $right->{ecosystem} ;
  return $ecosystem_cmp if $ecosystem_cmp ;

  my $name_cmp = $left->{name} cmp $right->{name} ;
  return $name_cmp if $name_cmp ;

  return $left->{version} cmp $right->{version} ;
}

sub _cpan_components {
  my ( $directory, $audit_root ) = @_ ;
  die "CPAN distribution directory not found: $directory\n" if !-d $directory ;

  my @archives ;
  find(
    {
      no_chdir => 1,
      wanted   => sub {
        return if !-f $File::Find::name ;
        push @archives, $File::Find::name
          if $File::Find::name =~ /\.(?:tar\.gz|tgz)\z/i ;
      },
    },
    $directory,
  ) ;

  my @components ;
  for my $archive ( sort @archives ) {
    my $tar = Archive::Tar->new ;
    $tar->read( $archive, 1 )
      or die "Cannot read CPAN archive '$archive'\n" ;

    my @metadata = grep {m{(?:\A|/)META\.(?:json|yml)\z}i} $tar->list_files ;
    next if !@metadata ;
    @metadata = sort {
      ( $a =~ /\.json\z/i ? 0 : 1 ) <=> ( $b =~ /\.json\z/i ? 0 : 1 )
        || $a cmp $b
    } @metadata ;

    my $metadata_content = $tar->get_content( $metadata[0] ) ;
    my $metadata_file
      = File::Spec->catfile( $audit_root, '.metadata-' . _safe_name( basename($archive) ) ) ;
    _write_bytes( $metadata_file, $metadata_content ) ;
    my $meta = eval { CPAN::Meta->load_file($metadata_file)  } ;
    unlink $metadata_file
      or die "Cannot remove temporary metadata '$metadata_file': $!\n" ;
    die "Cannot parse metadata in '$archive': $@\n" if !$meta ;

    my $name             = $meta->name ;
    my $version          = $meta->version ;
    my @declared_license = $meta->license ;
    my @license          = map { _normalize_cpan_license($_) } @declared_license ;
    my @license_files ;

    my @notice_paths = grep {
      my $file = basename($_) ;
      $file =~ /\A(?:LICENSE|LICENCE|COPYING|NOTICE)(?:[._-].*)?\z/i
    } $tar->list_files ;

    my $component_dir
      = File::Spec->catdir( $audit_root, 'texts', 'cpan', _safe_name($name) ) ;
    for my $path ( sort @notice_paths ) {
      my $content = $tar->get_content($path) ;
      next if !defined $content ;

      my $target = File::Spec->catfile( $component_dir, basename($path) ) ;
      make_path($component_dir) ;
      _write_bytes( $target, $content ) ;
      push @license_files, File::Spec->abs2rel( $target, $audit_root ) ;
    }

    push @components,
      {
      ecosystem     => 'cpan',
      name          => $name,
      version       => "$version",
      licenses      => @license ? \@license : ['NOASSERTION'],
      source        => 'https://metacpan.org/dist/' . $name,
      license_files => \@license_files,
      } ;
  }
  return @components ;
}

sub _debian_components {
  my ( $status_file, $copyright_root, $audit_root ) = @_ ;
  my $content = _read_text($status_file) ;
  my @components ;

  for my $record ( split /\n\n+/, $content ) {
    my %field ;
    for my $line ( split /\n/, $record ) {
      next if $line !~ /\A([^:]+):\s*(.*)\z/ ;
      $field{$1} = $2 ;
    }
    next if !defined $field{Package} || !defined $field{Version} ;

    my $name     = $field{Package} ;
    my $source   = File::Spec->catfile( $copyright_root, $name, 'copyright' ) ;
    my @licenses = ('NOASSERTION') ;
    my @license_files ;

    if ( -f $source ) {
      my $copyright = _read_text($source) ;
      my %license ;
      for my $line ( split /\n/, $copyright ) {
        next if $line !~ /\ALicense:\s*(\S.*)\z/ ;
        $license{$1} = 1 ;
      }
      @licenses = sort keys %license if %license ;

      my $target = File::Spec->catfile(
        $audit_root, 'texts', 'debian', _safe_name($name), 'copyright',
      ) ;
      make_path( dirname($target) ) ;
      copy( $source, $target )
        or die "Cannot copy Debian copyright '$source': $!\n" ;
      push @license_files, File::Spec->abs2rel( $target, $audit_root ) ;
    }

    push @components,
      {
      ecosystem     => 'deb',
      name          => $name,
      version       => $field{Version},
      licenses      => \@licenses,
      source        => 'https://packages.debian.org/' . $name,
      license_files => \@license_files,
      } ;
  }
  return @components ;
}

sub _direct_components {
  my ( $manifest, $audit_root ) = @_ ;
  my $entries = _read_json($manifest) ;
  die "Direct component manifest must contain an array\n"
    if ref $entries ne 'ARRAY' ;

  my @components ;
  for my $entry ( @{$entries} ) {
    for my $field (qw(name version license source license_file)) {
      die "Direct component is missing '$field' in '$manifest'\n"
        if !defined $entry->{$field} || $entry->{$field} eq q{} ;
    }
    die "Direct component license file not found: $entry->{license_file}\n"
      if !-f $entry->{license_file} ;

    my $target = File::Spec->catfile(
      $audit_root, 'texts', 'direct', _safe_name( $entry->{name} ),
      basename( $entry->{license_file} ),
    ) ;
    make_path( dirname($target) ) ;
    copy( $entry->{license_file}, $target )
      or die "Cannot copy direct license '$entry->{license_file}': $!\n" ;

    push @components,
      {
      ecosystem     => 'direct',
      name          => $entry->{name},
      version       => "$entry->{version}",
      licenses      => [ $entry->{license} ],
      source        => $entry->{source},
      license_files => [ File::Spec->abs2rel( $target, $audit_root ) ],
      } ;
  }
  return @components ;
}

sub _normalize_cpan_license {
  my ($license) = @_ ;
  my %normalized = (
    apache_2_0  => 'Apache-2.0',
    artistic_1  => 'Artistic-1.0',
    artistic_2  => 'Artistic-2.0',
    bsd         => 'BSD-3-Clause',
    freebsd     => 'BSD-2-Clause-FreeBSD',
    gpl_1       => 'GPL-1.0-only',
    gpl_2       => 'GPL-2.0-only',
    gpl_3       => 'GPL-3.0-only',
    lgpl_2_1    => 'LGPL-2.1-only',
    lgpl_3_0    => 'LGPL-3.0-only',
    mit         => 'MIT',
    mozilla_1_0 => 'MPL-1.0',
    mozilla_1_1 => 'MPL-1.1',
    openssl     => 'OpenSSL',
    perl_5      => 'Artistic-1.0-Perl OR GPL-1.0-or-later',
    qpl_1_0     => 'QPL-1.0',
    ssleay      => 'SSLeay-standalone',
    sun         => 'SunPro',
    zlib        => 'Zlib',
    unknown     => 'NOASSERTION',
  ) ;
  return $normalized{$license} || $license || 'NOASSERTION' ;
}

sub _read_json {
  my ($path) = @_ ;
  open my $fh, '<:raw', $path or die "Cannot read '$path': $!\n" ;
  local $/ ;
  my $content = <$fh> ;
  close $fh or die "Cannot close '$path': $!\n" ;
  return decode_json($content) ;
}

sub _read_text {
  my ($path) = @_ ;
  open my $fh, '<:encoding(UTF-8)', $path
    or die "Cannot read '$path': $!\n" ;
  local $/ ;
  my $content = <$fh> ;
  close $fh or die "Cannot close '$path': $!\n" ;
  return $content ;
}

sub _safe_name {
  my ($name) = @_ ;
  $name =~ s/[^A-Za-z0-9_.-]+/_/g ;
  return $name ;
}

sub _usage {
  return
    "Usage: $0 --output DIR [--base-inventory FILE] [--dpkg-status FILE "
    . "--debian-copyright-root DIR] [--cpan-dists DIR] "
    . "[--direct-components FILE] [--perl-version VERSION] "
    . "[--perl-license FILE]\n" ;
}

sub _write_bytes {
  my ( $path, $content ) = @_ ;
  make_path( dirname($path) ) ;
  open my $fh, '>:raw', $path
    or die "Cannot write '$path': $!\n" ;
  print {$fh} $content
    or die "Cannot write '$path': $!\n" ;
  close $fh or die "Cannot close '$path': $!\n" ;
  return ;
}

sub _write_summary {
  my ( $path, $components ) = @_ ;
  my $content = <<'HEADER';
# Image License Inventory

This file is generated from the components present during the image build.
`NOASSERTION` means that the upstream package metadata did not declare a
machine-readable license.

| Ecosystem | Component | Version | License |
| --- | --- | --- | --- |
HEADER

  for my $component ( @{$components} ) {
    my @values = (
      $component->{ecosystem},
      $component->{name},
      $component->{version},
      join( ', ', @{ $component->{licenses} } ),
    ) ;
    s/\|/\\|/g for @values ;
    $content .= '| ' . join( ' | ', @values ) . " |\n" ;
  }
  _write_text( $path, $content ) ;
  return ;
}

sub _write_text {
  my ( $path, $content ) = @_ ;
  make_path( dirname($path) ) ;
  open my $fh, '>:encoding(UTF-8)', $path
    or die "Cannot write '$path': $!\n" ;
  print {$fh} $content
    or die "Cannot write '$path': $!\n" ;
  close $fh or die "Cannot close '$path': $!\n" ;
  return ;
}
