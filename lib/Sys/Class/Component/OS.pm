package Sys::Class::Component::OS;

use Moo::Role;
use strictures 2;

use Types::Standard -types;

use namespace::clean;

with 'Sys::Class::Role::Component';

#
# Here's the table of ID => MAJOR => MINOR for windows versions.
# See Win32::GetOSVersion() documentation here:
#    https://metacpan.org/pod/Win32 
# Or the MSDN Operating System Version article here:
#    http://msdn.microsoft.com/en-us/library/windows/desktop/ms724832.aspx
#
my %wintable = (
    1 => {
        4 => {
            0  => '95',
            10 => '98',
            90 => 'ME',
        },
    },
    2 => {
        3 => {
            51 => 'NT_3.51',
        },
        4 => {
            0 => 'NT',
        },
        5 => {
            0 => '2000',
            1 => 'XP',
            2 => '2003',
        },
        6 => {
            0 => '2008',
            1 => '2008R2',
            2 => '2012',
            3 => '2012R2',
        }
    },
);

has arch        => ( is => 'lazy', isa => Str,   init_arg => undef );
has bits        => ( is => 'lazy', isa => Str,   init_arg => undef );
has os_name     => ( is => 'lazy', isa => Str,   init_arg => undef );
has os_display  => ( is => 'lazy', isa => Str,   init_arg => undef );
has os_version  => ( is => 'lazy', isa => Str,   init_arg => undef );
has os_distro   => ( is => 'lazy', isa => Value, init_arg => undef );

sub _build_arch       { shift->_adapter->sysinfo->{os}->{arch}     }
sub _build_bits       { shift->_adapter->sysinfo->{os}->{bits}     }
sub _build_os_name    { shift->_adapter->sysinfo->{perl}->{osname} }
sub _build_os_display { shift->_adapter->sysinfo->{os}->{display}  }
sub _build_os_version {
    my $self = shift;

    if ($self->is_win) {
        my ($maj, $min, $bld, $id) = @{ $self->_adapter->sysinfo->{os}->{release} };
        return $wintable{$id}->{$maj}->{$min};
    }
    elsif ($self->os_name eq 'solaris') {
        return $self->_adapter->sysinfo->{os}->{release}->[1];
    }
    else {
        return join('.', @{ $self->_adapter->sysinfo->{os}->{release} });
    }
}

sub _build_os_distro {
    my $self = shift;

    if ( my $distro = $self->_adapter->sysinfo->{os}->{distro} ) {
        return $distro;
    }
    else {
        return '';
    }
}

sub is_win  { $_[0]->os_name eq 'MSWin32' || $_[0]->os_name eq 'cygwin' }
sub is_unix { !$_[0]->is_win }

1;
