package Sys::Class::Component::Cmd;

use Moo::Role;
use strictures 2;

use Types::Standard -types;

use namespace::clean;

with 'Sys::Class::Role::Component';

has _cmd_path => ( 
   is       => 'rw',
   lazy     => 1,
   builder  => 1, 
   isa      => ArrayRef, 
   init_arg => 'cmd_path', 
);

sub _build__cmd_path {
   my $self = shift;
   my @path;

   if ($self->os_name eq 'linux') {
      push @path, '/usr/local/bin';
   }

   if ($self->is_unix) {
      push @path, '/sbin', '/usr/sbin', '/usr/bin', '/bin';
   }

   return [ @path ];
}

sub cmd_path {
   my $self = shift;
   return undef if not @{ $self->_cmd_path};
   return join( $self->is_win ? ';' : ':', @{ $self->_cmd_path} );
}

sub add_cmd_path {
   my $self  = shift;
   my @paths = @_;

   foreach my $path ( @paths ) {
      push @{ $self->_cmd_path }, $path
         if not grep { $path eq $_ } @{ $self->_cmd_path };
   }
}

sub remove_cmd_path {
   my $self = shift;
   my @paths = @_;

   my @cmd_path = @{ $self->_cmd_path };

   PATH: foreach my $path (@paths) {
      for my $i (0..$#cmd_path) {
         splice @cmd_path, $i, 1 if $cmd_path[$i] eq $path;
         next PATH;
      }
   }
   $self->_cmd_path([ @cmd_path ]);
}

sub run_command {
   my $self = shift;
   my %args = @_ == 1 ? ( cmd => $_[0] ) : ( @_ );
   my $cstr = ref($args{cmd}) ? join(' ', @{$args{cmd}}) : $args{cmd};
   my $pass = delete $args{pass_status};
   my $run  = $self->_adapter->run_command(%args, path => $self->cmd_path)->get;

   if ($run->{exit} == -1 || $run->{exit} == 127) {
      die 'Command not found: [%s]', $cstr;
   }

   my $raw_status  = $run->{exit};
   my $exit_status = $raw_status >> 8;
   my $signal_num  = $raw_status & 127;
   my $core_dump   = $raw_status & 128;

   $run->{exit}      = $exit_status;
   $run->{signal}    = $signal_num;
   $run->{core_dump} = $core_dump;

   if ( defined $pass and !grep { $_ == $exit_status} @{$pass} ) {
      die sprintf(
         'command [%s] failed with status [%i]: valid statuses: [%s]',
         $cstr,
         $exit_status,
         join(' ', @{$pass}),
      );
   }

   return $run;
}




1;
