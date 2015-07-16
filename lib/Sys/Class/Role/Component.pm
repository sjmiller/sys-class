package Sys::Class::Role::Component;

use Moo::Role;
use strictures 2;

use namespace::clean;

requires '_adapter';

1;
