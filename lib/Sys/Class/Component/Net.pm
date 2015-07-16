package Sys::Class::Component::Net;

use Moo::Role;
use strictures 2;

use Types::Standard -types;

use namespace::clean;

with 'Sys::Class::Role::Component';

has hostname   => ( is => 'lazy', isa => Str, init_arg => undef );
has hostfqdn   => ( is => 'lazy', isa => Str, init_arg => undef );
has domainname => ( is => 'lazy', isa => Str, init_arg => undef );
has hostdomain => ( is => 'lazy', isa => Str, init_arg => undef );

sub _build_hostname   { shift->_adapter->sysinfo->{net}->{hostname} }
sub _build_hostfqdn   { shift->_adapter->sysinfo->{net}->{hostfqdn} }
sub _build_hostdomain { shift->_adapter->sysinfo->{net}->{hostdomain} }
sub _build_domainname { shift->hostfqdn }

1;
