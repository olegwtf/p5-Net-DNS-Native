package Net::DNS::Native;

use strict;
use warnings;
use Socket ();
use XSLoader;

our $VERSION = '0.01';

XSLoader::load('Net::DNS::Native', $VERSION);

1;
