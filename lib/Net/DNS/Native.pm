package Net::DNS::Native;

use strict;
use XSLoader;
use Socket ();
use Config ();

our $VERSION = '0.06';

our $PERL_OK = $Config::Config{usethreads}||$Config::Config{libs}=~/-l?pthread\b/;
unless ($PERL_OK) {
	warn "This perl may crash while using this module. See `WARNING' section in the documentation";
}

use constant {
	INET_ATON     => 0,
	INET_PTON     => 1,
	GETHOSTBYNAME => 2,
	GETADDRINFO   => 3
};

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
		return
		  $err ? undef :
		  ( $res[0]{family} == Socket::AF_INET ?
		     Socket::unpack_sockaddr_in($res[0]{addr}) :
		     Net::DNS::Native::unpack_sockaddr_in6($res[0]{addr}) )[1];
	}
	
	if ($type == GETHOSTBYNAME) {
		return
		  $err ? () : 
		  ($res[0]{canonname}, undef, Socket::AF_INET, length($res[0]{addr}), map { (Socket::unpack_sockaddr_in($_->{addr}))[1] } @res);
	}
}

1;

__END__

=pod

=head1 NAME

Net::DNS::Native - non-blocking system DNS resolver

=head1 SYNOPSIS

=over

	use Net::DNS::Native;
	use IO::Select;
	use Socket;
	
	my $dns = Net::DNS::Native->new();
	my $sock = $dns->getaddrinfo("google.com");
	
	my $sel = IO::Select->new($sock);
	$sel->can_read(); # wait until resolving done
	my ($err, @res) = $dns->get_result($sock);
	die "Resolving failed: ", $err if ($err);
	
	for my $r (@res) {
		warn "google.com has ip ",
			$r->{family} == AF_INET ?
				inet_ntoa((unpack_sockaddr_in($r->{addr}))[1]) :                   # IPv4
				Socket::inet_ntop(AF_INET6, (unpack_sockaddr_in6($r->{addr}))[1]); # IPv6
	}

=back

=over

	use Net::DNS::Native;
	use AnyEvent;
	use Socket;
	
	my $dns = Net::DNS::Native->new;
	
	my $cv = AnyEvent->condvar;
	$cv->begin;
	
	for my $host ('google.com', 'google.ru', 'google.cy') {
		my $fh = $dns->inet_aton($host);
		$cv->begin;
		
		my $w; $w = AnyEvent->io(
			fh   => $fh,
			poll => 'r',
			cb   => sub {
				my $ip = $dns->get_result($fh);
				warn $host, $ip ? " has ip " . inet_ntoa($ip) : " has no ip";
				$cv->end;
				undef $w;
			}
		)
	}
	
	$cv->end;
	$cv->recv;

=back

=head1 DESCRIPTION

This class provides several methods for host name resolution. It is designed to be used with event loops. All resolving are done
by getaddrinfo(3) implemented in your system library. Since getaddrinfo() is blocking function and we don't want to block,
call to this function will be done in separate thread. This class uses system native threads and not perl threads. So overhead
shouldn't bee too big. Disadvantages of this method is that we can't provide timeout for resolving. And default timeout for
getaddrinfo() on my system is about 40 sec.

=head1 WARNING

To support threaded extensions like this one your perl should be linked with threads library. One of the possible solution
is to build your perl with perl threads support using C<-Dusethreads> for C<Configure> script. But it is not necessary to
build threaded perl. So, other solution is to not use C<-Dusethreads> and instead use C<-A prepend:libswanted="pthread ">.
This will link your perl executable with libpthread.

If this conditions are not met you may get segfault. To check it run this oneliner:

	perl -MConfig -le 'print $Config{usethreads}||$Config{libs}=~/-l?pthread\b/ ? "this perl may use threaded library" : "this perl may segfault with threaded library"'

=head1 METHODS

=head2 new

This is a class constructor. Accepts this optional parameters:

=over

=item pool => $size

If $size>0 will create thread pool with size=$size which will make resolving job. Otherwise will use default behavior:
create and finish thread for each resolving request. If thread pool is not enough big to process all supplied requests, than this
requests will be queued until one of the threads will become free to process next request from the queue.

=item extra_thread => $bool

If pool option specified and $bool has true value will create temporary extra thread for each request that can't be handled by the
pool (when all workers in the pool are busy) instead of pushing it to the queue. This temporary thread will be finished immediatly
after it will process request.

=back

=head2 getaddrinfo($host, $service, $hints)

This is the most powerfull method. May resolve host to both IPv4 and IPv6 addresses. For full documentation see L<getaddrinfo()|Socket/"($err, @result) = getaddrinfo $host, $service, [$hints]">.
This method accepts same parameters but instead of result returns handle on which you need to wait for availability to read.

=head2 inet_pton($family, $host)

This method will resolve $host accordingly to $family, which may be AF_INET to resolve to IPv4 or AF_INET6 to resolve to IPv6. For full
documentation see L<inet_pton()|Socket/"$address = inet_pton $family, $string">. This method accepts same parameters but instead of result returns
handle on which you need to wait for availability to read.

=head2 inet_aton($host)

This method may be used only for resolving to IPv4. For full documentation see L<inet_aton()|Socket/"$ip_address = inet_aton $string">. This method accepts same
parameters but instead of result returns handle on which you need to wait for availability to read.

=head2 gethostbyname($host)

This method may be used only for resolving to IPv4. For full documentation see L<gethostbyname()|http://perldoc.perl.org/5.14.0/functions/gethostbyname.html>.
This method accepts same parameters but instead of result returns handle on which you need to wait for availability to read.

=head2 get_result($handle)

After handle returned by methods above will became ready for read you should call this method with handle as argument. It will
return results appropriate to the method which returned this handle. For C<getaddrinfo> this will be C<($err, @res)> list. For
C<inet_pton> and C<inet_aton> C<$packed_address> or C<undef>. For C<gethostbyname()> C<$packed_address> or C<undef> in scalar context and
C<($name,$aliases,$addrtype,$length,@addrs)> in list context.

B<NOTE:> it is important to call get_result() on returned handle when it will become ready for read. Because this method destroys resources
associated with this handle. Otherwise you will get memory leaks.

=head1 AUTHOR

Oleg G, E<lt>oleg@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself

=cut
