use strict ;
use warnings ;

use Cwd        qw(abs_path) ;
use File::Path qw(make_path) ;
use File::Spec ;
use File::Temp qw(tempdir) ;
use Test::More ;

my $root    = abs_path('.') ;
my $checker = File::Spec->catfile( $root, 'scripts', 'check-runtime-tools.sh' ) ;

ok -x $checker, 'runtime tool checker is executable' ;

my $dockerfile = _read_text('Dockerfile') ;
for my $command (qw(cat find grep sed)) {
  like $dockerfile,
    qr{ln -s "\$\(command -v \Q$command\E\)" /usr/local/bin/g\Q$command\E},
    "Docker build derives the g$command alias from PATH" ;
}
unlike $dockerfile, qr{ln -s /usr/bin/(?:cat|find|grep|sed)},
  'Docker build does not assume GNU command locations' ;
like $dockerfile, qr/scripts\/check-runtime-tools\.sh/,
  'Docker build validates runtime tools' ;

my $ci = _read_text('scripts/ci-build.sh') ;
like $ci, qr{/opt/perl-essentials/scripts/check-runtime-tools\.sh},
  'CI invokes the image runtime tool checker' ;
like $ci,
  qr{docker_run \\\n\s+--user "\$\(id -u\):\$\(id -g\)" \\\n\s+--volume "\$\{PWD\}:/work:ro" \\\n\s+"\$\{image\}" \\\n\s+/work/test/check-perl-format\.sh},
  'CI runs the repository format check as the checkout owner' ;

SKIP: {
  skip 'runtime tool checker is not available yet', 6 if !-x $checker ;

  my $tmp = tempdir( CLEANUP => 1 ) ;
  my $bin = File::Spec->catdir( $tmp, 'bin' ) ;
  make_path($bin) ;
  _write_text( File::Spec->catfile( $tmp, '.perltidyrc' ), "# local profile\n" ) ;

  for my $command (qw(perlcritic rg gcat gfind ggrep gsed)) {
    _write_command( $bin, $command, "#!/bin/sh\nexit 0\n" ) ;
  }
  _write_command(
    $bin, 'perltidy',
    <<'SH',
#!/bin/sh
if [ "$PWD" = / ]; then
    printf '%s\n' "# Dump of file: '/etc/perltidyrc'"
else
    printf '%s\n' "# Dump of file: '.perltidyrc'"
fi
SH
  ) ;

  my ( $success_status, $success_output )
    = _run_with_path( $checker, $bin, $tmp ) ;
  is $success_status, 0,
    'runtime checker validates the system profile from a neutral directory'
    or diag $success_output ;
  like $success_output, qr/Runtime tool checks passed/,
    'successful runtime check is visible' ;

  unlink File::Spec->catfile( $bin, 'perlcritic' )
    or die "Cannot remove perlcritic fixture: $!" ;
  my ( $missing_status, $missing_output )
    = _run_with_path( $checker, $bin, $tmp ) ;
  isnt $missing_status, 0, 'runtime checker rejects a missing command' ;
  like $missing_output, qr/Required command not found: perlcritic/,
    'missing-command diagnostic identifies perlcritic' ;

  _write_command( $bin, 'perlcritic', "#!/bin/sh\nexit 0\n" ) ;
  _write_command(
    $bin, 'perltidy',
    "#!/bin/sh\nprintf '%s\\n' '# No default profile found'\n",
  ) ;
  my ( $profile_status, $profile_output )
    = _run_with_path( $checker, $bin, $tmp ) ;
  isnt $profile_status, 0, 'runtime checker rejects the wrong default profile' ;
  like $profile_output, qr{Expected perltidy profile /etc/perltidyrc},
    'profile diagnostic identifies the expected file' ;
}

done_testing ;

sub _read_text {
  my ($path) = @_ ;
  open my $fh, '<:encoding(UTF-8)', $path
    or die "Cannot read '$path': $!" ;
  local $/ ;
  my $content = <$fh> ;
  close $fh or die "Cannot close '$path': $!" ;
  return $content ;
}

sub _write_command {
  my ( $bin, $name, $content ) = @_ ;
  my $path = File::Spec->catfile( $bin, $name ) ;
  _write_text( $path, $content ) ;
  chmod 0755, $path or die "Cannot make '$path' executable: $!" ;
  return ;
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

sub _run_with_path {
  my ( $checker, $bin, $workdir ) = @_ ;
  local $ENV{PATH} = $bin ;
  my $quoted_checker = _shell_quote($checker) ;
  my $quoted_workdir = _shell_quote($workdir) ;
  my $output         = qx{cd $quoted_workdir && /bin/sh $quoted_checker 2>&1} ;
  return ( $? >> 8, $output ) ;
}

sub _shell_quote {
  my ($value) = @_ ;
  $value =~ s/'/'"'"'/g ;
  return "'$value'" ;
}
