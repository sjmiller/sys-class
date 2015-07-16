package Sys::Class::Role::Adapter;

use Moo::Role;
use strictures 2;

use Types::Standard -types;

use namespace::clean;

requires 'batch';
requires 'ping';
requires 'filetest';
requires 'time';
requires 'gmtime';
requires 'localtime';
requires 'strftime';
requires 'run_command';
requires 'file';
requires 'dir';

# sysinfo 
requires '_build_sysinfo';
has sysinfo => ( 
   is       => 'ro',
   required => 1,
   builder  => 1, 
   isa      => Dict[
      perl => HashRef,
      net  => HashRef,
      os   => HashRef,
      env  => HashRef,
   ],
);

1;
