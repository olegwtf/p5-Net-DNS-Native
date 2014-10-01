use strict;
use Net::DNS::Native;
use Socket;
use IO::Select;
use Test::More;

my $dns = Net::DNS::Native->new(pool => 1, notify_on_begin => 1);
my $sel = IO::Select->new();

my %map;
for my $host (qw/google.com google.cy google.ru/) {
	my $sock = $dns->inet_aton($host);
	$sel->add($sock);
	$map{$sock} = 0;
}

while ($sel->count() > 0) {
	my @ready = $sel->can_read(60);
	ok(@ready, "select() took less than 60 sec");
	
	for my $sock (@ready) {
		$map{$sock}++;
		sysread($sock, my $buf, 1);
		is($buf, $map{$sock}, "correct notification value");
		if ($map{$sock} == 2) {
			my $ip = $dns->get_result($sock);
			if ($ip) {
				ok(eval{inet_ntoa($ip)}, "correct ip");
			}
			$sel->remove($sock);
		}
	}
}

done_testing;
