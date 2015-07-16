package Sys::Class::Adapter::Local;

use Moo;
use strictures 2;

use Config;
use Future;
use File::pushd;
use File::Path qw(make_path);
use File::Spec;
use File::Temp;
use File::Which;
use Future;
use IPC::Run3 qw(run3);
use Module::Runtime qw(use_module);
use Net::Domain;
use POSIX ();

use namespace::clean;

with 'Sys::Class::Role::Adapter';

sub _build_sysinfo {
   return( 
      {
         perl => _perl_info(),
         net  => _net_info (),
         os   => _os_info(),
         env  => { %ENV },
      }
   );
}

sub batch {}
sub ping {}
sub filetest {}
sub time {}
sub gmtime {}
sub localtime {}
sub strftime {}
sub file {}
sub dir {}

sub run_command {
   my $self = shift;
   my %args = @_;

   my $cmd   = $args{cmd};
   my $path  = $args{path};
   my $env   = $args{env};
   my $cwd   = $args{cwd};
   my $stdin = $args{stdin};

   if (defined $env) {
      die "Provided env to run_command() must be a hash"
         if not ref($env) eq 'HASH';
   }
   else {
      $env = {};
   }

   if (defined $stdin) {
      die "Provided stdin to run_command() must be an ARRAY ref"
         if not ref($stdin) eq 'ARRAY';
   }

   # Done for Win32 mostly, IPC::Run3 will croak if STDOUT/STDERR aren't 
   # opened to SOMETHING, and a Win32::Process DETACHED_PROCESS closes both
   open(STDOUT, '>', File::Spec->devnull) 
      if not Scalar::Util::openhandle(*STDOUT);
   open(STDERR, '>', File::Spec->devnull)
      if not Scalar::Util::openhandle(*STDERR);

   {
      my $dir = pushd($cwd);
      local %ENV = ( %ENV, %$env );

      if (defined $path) {
         $ENV{PATH} = join( $Config{path_sep}, ($path, $ENV{PATH}) );
      }

      my $start = CORE::time();
      run3( 
         $cmd,
         [ map { "$_\n" } @$stdin ], 
         \my $out, 
         \my $err, 
         { return_if_system_error => 1 }
      );

      my $end = CORE::time();
      my $return = {
         exit     => $?,
         start    => $start,
         end      => $end,
         duration => $end - $start,
         env      => { %ENV },
         stdout   => $out,
         stderr   => $err,
      };

      return Future->done($return);
   }
}

sub _net_info {
   my $net = { 
      hostname   => lc( Net::Domain->hostname   ),
      hostfqdn   => lc( Net::Domain->hostfqdn   ),
      hostdomain => lc( Net::Domain->hostdomain ),
   };

   # Work around a bug in Net::Domain that doesn't account for the fact that uname
   # only returns the first 8 characters of a hostname on HPUX
   #   https://rt.cpan.org/Public/Bug/Display.html?id=94153
   #
   if ($^O eq 'hpux') {
      my $host = `(hostname) 2>/dev/null`;
      chomp($host);
      $net->{hostname} = lc($host);
      $net->{hostfqdn} = lc($host) . '.' . $net->{hostdomain};
   }

   return $net;
}

sub _perl_info {
   return (
      {
         bin     => $Config{perlpath},
         osname  => $^O,
         version => $Config{version},
      }
   );
}

sub _os_info {
   if    ($^O eq 'aix'    ) { return _os_info_aix()     }
   elsif ($^O eq 'cygwin' ) { return _os_info_mswin32() }
   elsif ($^O eq 'darwin' ) { return _os_info_darwin()  }
   elsif ($^O eq 'freebsd') { return _os_info_freebsd() }
   elsif ($^O eq 'hpux'   ) { return _os_info_hpux()    }
   elsif ($^O eq 'linux'  ) { return _os_info_linux()   }
   elsif ($^O eq 'MSWin32') { return _os_info_mswin32() }
   elsif ($^O eq 'solaris') { return _os_info_solaris() }
   else {
      die "Unsupported OS: [$^O]";
   }
}

sub _os_info_aix {
   my %os;

   my ($arch, $uname) = _uname(qw(p a));
   # /usr/bin/oslevel gets us the release data, split on dot
   my $release = `/usr/bin/oslevel`;
   chomp($release);
   $os{release} = [ split(/\./, $release) ];

   # /usr/bin/getconf can get use the bitness
   my $bit = `/usr/bin/getconf HARDWARE_BITMODE`;
   chomp($bit);
   $os{bits}    = $bit;
   $os{arch}    = $arch;
   $os{display} = $uname;

   return { %os };
}

sub _os_info_darwin {
   my %os;

   my $release = `/usr/bin/sw_vers -productVersion`;
   chomp($release);
   $os{release} = [ split(/\./, $release) ];

   my ($bit, $arch, $uname) = _uname(qw(m p a));

   $os{bits}    = $bit =~ /64/ ? 64 : 32; 
   $os{arch}    = $arch eq 'x86_64' ? 'x64' : 'x86';
   $os{display} = $uname;

   return { %os };
}

sub _os_info_freebsd {
   my %os;

   my ($release, $bit, $arch, $uname) = _uname(qw(r m p a));

   $os{release} = [ split(/[.-]/, $release) ];
   $os{bits}    = $bit =~ /64/ ? 64 : 32; 
   $os{arch}    = $arch eq 'x86_64' ? 'x64' : $arch =~ /i\d86/ ? 'x86' : $arch;
   $os{display} = $uname;

   return { %os };
}

sub _os_info_hpux {
   my %os;

   my ($release, $arch, $uname) = _uname(qw(r m a));

   $os{arch}    = $arch;
   $os{display} = $uname;

   if ($release =~ /B\.((?:\d+\.?)+)/) {
      $os{release} = [ split(/\./, $1) ];
   }
   else {
      $os{release} = [];
   }

   my $bit = `/usr/bin/getconf KERNEL_BITS`;
   $bit =~ s/\s*$//;
   $os{bits} = $bit;

   return { %os };
}

sub _os_info_linux {
   my %os;

   my $lsb = _lsb_release();
   $os{lsb} = $lsb;

   # SLES
   if (-e '/etc/SuSE-release') {
      $os{distro}  = 'suse';
      $os{release} = [];
      if (open( my $fh, '<', '/etc/SuSE-release') ) {
         my ($major, $minor);
         while (my $line = <$fh>) {
            chomp($line);
            if ($line =~ m/VERSION = (\d+)/) {
               $major = $1;
            }
            elsif ($line =~ m/PATCHLEVEL = (\d+)/) {
               $minor = $1;
            }
         }
         close $fh;
         $os{release} = [$major, $minor];
      }
   }
   # RHEL
   elsif (-e '/etc/redhat-release') {
      my $release = `cat /etc/redhat-release`;
      chomp($release);
      if ($release =~ /release ((?:\d+\.?)+)/) {
         $os{release} = [ split(/\./, $1) ];
      }
      else {
         $os{release} = [];
      }
      $os{distro}  = 'redhat';
   }
   # Last ditch, this should catch Ubuntu/Debian
   else {
      $os{distro}  = lc($lsb->{'Distributor ID'});
      $os{release} = [ split(/\./, $lsb->{Release}) ];
   }

   my ($bit, $arch, $uname) = _uname(qw(m p a));

   $os{bits}    = $bit =~ /64/ ? 64 : 32; 
   $os{arch}    = $arch eq 'x86_64' ? 'x64' : $arch =~ /i\d86/ ? 'x86' : $arch;
   $os{display} = $uname;

   return { %os };
}

sub _os_info_mswin32 {
   my %os;

   # Win32::GetChipName() returns the chip identifier of the CPU
   # We can determine bitness from this.
   my $chip = Win32::GetChipName();
   if ($chip eq '8664') {
      $os{bits} = 64;
      $os{arch} = 'x64';
   }
   elsif($chip eq '2200') {
      $os{bits} = 64;
      $os{arch} = 'ia64';
   }
   else {
      $os{bits} = 32;
      $os{arch} = 'x86';
   }

   #
   # Win32::GetOSVersion() returns a list of STRING, MAJOR, MINOR, BUILD, ID.
   # It is up to the caller to make sense of this information
   # For more details, see the documentation for Win32::GetOSVersion() at:
   #   https://metacpan.org/pod/Win32
   #
   my (undef, $major, $minor, $build, $id) = Win32::GetOSVersion();
   $os{release} = [ $major, $minor, $build, $id ];
   
   # Win32::GetOSDisplayName gets the human-readable 'marketing' name
   $os{display} = Win32::GetOSDisplayName();

   return { %os };
}

sub _os_info_solaris {
   my %os;

   my $bit = `/usr/bin/isainfo -b`;
   chomp($bit);
   $os{bits} = $bit;

   my ($release, $arch, $uname) = _uname(qw(r p a));
   $os{arch}    = $arch eq 'sparc' ? $arch : $arch =~ /i\d86/ ? 'x86' : $arch;
   $os{release} = [ split(/\./, $release) ];
   $os{display} = $uname;

   return { %os };
}

sub _lsb_release {

   my %release;
   my $lsb_release = which('lsb_release');
   return '' if not $lsb_release;

   my $lsb = `$lsb_release -a 2> /dev/null`; 

   foreach my $line ( split /\n/, $lsb ) {
      my ($key, $val) = $line =~ m/^([\w\s]+):\s*(.+)$/;
      $release{$key} = $val if defined $key and defined $val;
   }

   return \%release;
}

sub _uname {
   my @opt   = @_;
   my $uname = which('uname');

   return if not $uname;
   return map { my $r = `$uname -$_`; $r =~ s/\s*$//; $r } @opt;
}

1;
