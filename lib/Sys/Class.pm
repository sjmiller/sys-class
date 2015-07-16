package Sys::Class;

use Moo;
use strictures 2;

use Module::Runtime qw(use_module);
use Types::Standard -types;

use namespace::clean;

use Module::Pluggable 
   search_path => 'Sys::Class::Component', 
   require     => 1, 
   max_depth   => 4, 
   sub_name    => 'components';

has _adapter => ( 
   is      => 'ro', 
   isa     => ConsumerOf['Sys::Class::Role::Adapter'], 
   default => sub { use_module('Sys::Class::Adapter::Local')->new },
);

with __PACKAGE__->components;

1;
