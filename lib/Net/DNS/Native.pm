package Net::DNS::Native;

use strict;
use warnings;
use Socket ();
use XSLoader;

our $VERSION = '0.01';

XSLoader::load('Net::DNS::Native', $VERSION);

sub inet_aton {
	my ($self, $host) = @_;
	
	my $fd = $self->inet_aton_fd($host);
	open my $sock, '+<&=' . $fd
		or die "Can't convert file descriptor `$fd' to file handle: ", $!;
	return $sock;
}

sub get_result {
	my ($self, $sock) = @_;
	return $self->get_result_fd(fileno($sock));
}

1;
