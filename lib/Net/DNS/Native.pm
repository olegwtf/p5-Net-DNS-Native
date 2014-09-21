package Net::DNS::Native;

use strict;
use XSLoader;
use Socket ();

use constant {
	INET_ATON     => 0,
	INET_PTON     => 1,
	GETHOSTBYNAME => 2,
	GETADDRINFO   => 3
};

our $VERSION = '0.01';

XSLoader::load('Net::DNS::Native', $VERSION);

sub _fd2socket($) {
	open my $sock, '+<&=' . $_[0]
		or die "Can't transform file descriptor to handle: ", $!;
	$sock;
}

sub getaddrinfo {
	my $self = shift;
	_fd2socket $self->_getaddrinfo($_[0], $_[1], $_[2], GETADDRINFO);
}

sub inet_aton {
	my $self = shift;
	_fd2socket $self->_getaddrinfo($_[0], undef, {family => Socket::AF_INET}, INET_ATON);
}

sub inet_pton {
	my $self = shift;
	_fd2socket $self->_getaddrinfo($_[1], undef, {family => $_[0]}, INET_PTON);
}

sub gethostbyname {
	my $self = shift;
	_fd2socket $self->_getaddrinfo($_[0], undef, {family => Socket::AF_INET, flags => Socket::AI_CANONNAME}, GETHOSTBYNAME);
}

sub get_result {
	my ($self, $sock) = @_;
	
	my ($type, $err, @res) =  $self->_get_result(fileno($sock));
	
	if ($type == GETADDRINFO) {
		return ($err, @res);
	}
	
	if ($type == INET_ATON || $type == INET_PTON || (!wantarray() && $type == GETHOSTBYNAME)) {
		return $err ? undef : (Socket::unpack_sockaddr_in($res[0]{addr}))[1];
	}
	
	if ($type == GETHOSTBYNAME) {
		return
		  $err ? () : 
		  ($res[0]{canonname}, undef, Socket::AF_INET, length($res[0]{addr}), grep { (Socket::unpack_sockaddr_in($_->{addr}))[1] } @res);
	}
}

1;
