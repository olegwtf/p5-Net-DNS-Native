use strict;
use Net::DNS::Native;
use Socket;
use IO::Select;
use Test::More;

my $ip = inet_aton("google.com");
unless ($ip) {
	plan skip_all => "no DNS access on this computer";
}

my $dns = Net::DNS::Native->new(pool => 3);
my $sel = IO::Select->new();

for my $domain ('mail.ru', 'google.com', 'google.ru', 'google.cy', 'mail.com', 'mail.net') {
	my $sock = $dns->gethostbyname($domain);
	if ($domain eq 'mail.ru') {
		$dns->timedout($sock);
	}
	else {
		$sel->add($sock);
	}
}

while ($sel->count() > 0) {
	my @ready = $sel->can_read(60);
	ok(@ready > 0, 'resolving took less than 60 sec');
	
	for my $sock (@ready) {
		$sel->remove($sock);
		
		if (my $ip = $dns->get_result($sock)) {
			ok(eval{inet_ntoa($ip)}, 'correct ipv4 address');
		}
	}
}

$dns = Net::DNS::Native->new(pool => 1, extra_thread => 1);
$sel = IO::Select->new();

for my $domain ('mail.ru', 'google.com', 'google.ru', 'google.cy', 'mail.com', 'mail.net') {
	my $sock = $dns->gethostbyname($domain);
	if ($domain eq 'mail.ru') {
		$dns->timedout($sock);
	}
	else {
		$sel->add($sock);
	}
}

while ($sel->count() > 0) {
	my @ready = $sel->can_read(60);
	ok(@ready > 0, 'extra_thread: resolving took less than 60 sec');
	
	for my $sock (@ready) {
		$sel->remove($sock);
		
		if (my $ip = $dns->get_result($sock)) {
			ok(eval{inet_ntoa($ip)}, 'extra_thread: correct ipv4 address');
		}
	}
}

done_testing;
