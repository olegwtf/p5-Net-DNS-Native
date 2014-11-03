use strict;
use Net::DNS::Native;
use Test::More;

my $dns = Net::DNS::Native->new;

for (1..3) {
	my @fh;
	
	for (1..100) {
		push @fh, $dns->getaddrinfo('localhost');
	}
	
	my $buf;
	sysread($_, $buf, 1) && $dns->get_result($_) for @fh;
}

pass('No segfault');
done_testing;
