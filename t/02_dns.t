use strict;
use Test::More;
use Net::DNS::Native;
use Socket;
use IO::Select;

my $ip = inet_aton("google.com");
unless ($ip) {
	plan skip_all => "no DNS access on this computer";
}

my $dns = Net::DNS::Native->new();
my $sel = IO::Select->new();

# inet_aton
for my $host ("google.com", "google.ru", "google.cy") {
	my $fh = $dns->inet_aton($host);
	$sel->add($fh);
}

while ($sel->count() > 0) {
	my @ready = $sel->can_read(60);
	ok(scalar @ready, "inet_aton: resolved less then 60 sec");
	
	for my $fh (@ready) {
		$sel->remove($fh);
		my @res = $dns->get_result($fh);
		is(scalar @res, 1, "1 result for inet_aton");
		if ($res[0]) {
			ok(eval{inet_ntoa($res[0])}, "inet_aton: properly packed ip") or diag $@;
		}
	}
}

# inet_pton
# AF_INET6
for my $host ("google.com", "google.ru", "google.cy") {
	my $fh = $dns->inet_pton(AF_INET6, $host);
	$sel->add($fh);
}

while ($sel->count() > 0) {
	my @ready = $sel->can_read(60);
	ok(scalar @ready, "inet_pton: resolved less then 60 sec");
	
	for my $fh (@ready) {
		$sel->remove($fh);
		my @res = $dns->get_result($fh);
		is(scalar @res, 1, "1 result for inet_pton");
		if ($res[0]) {
			ok(eval{Socket::inet_ntop(AF_INET6, $res[0])}, "inet_pton: properly packed ip") or diag $@;
		}
	}
}

# AF_INET
for my $host ("google.com", "google.ru", "google.cy") {
	my $fh = $dns->inet_pton(AF_INET, $host);
	$sel->add($fh);
}

while ($sel->count() > 0) {
	my @ready = $sel->can_read(60);
	ok(scalar @ready, "inet_pton: resolved less then 60 sec");
	
	for my $fh (@ready) {
		$sel->remove($fh);
		my @res = $dns->get_result($fh);
		is(scalar @res, 1, "1 result for inet_pton");
		if ($res[0]) {
			ok(eval{Socket::inet_ntop(AF_INET, $res[0])}, "inet_pton: properly packed ip") or diag $@;
		}
	}
}

# gethostbyname
for my $host ("google.com", "google.ru", "google.cy") {
	my $fh = $dns->gethostbyname($host);
	$sel->add($fh);
}

while ($sel->count() > 0) {
	my @ready = $sel->can_read(60);
	ok(scalar @ready, "gethostbyname: resolved less then 60 sec");
	
	for my $fh (@ready) {
		$sel->remove($fh);
		
		if (rand > 0.5) {
			my $ip = $dns->get_result($fh);
			if ($ip) {
				ok(eval{inet_ntoa($ip)}, "gethostbyname: properly packed ip") or diag $@;
			}
		}
		else {
			my @res = $dns->get_result($fh);
			if (@res) {
				ok(scalar @res >= 5, ">=5 return values for gethostbyname() in list context");
				splice @res, 0, 4;
				
				for my $ip (@res) {
					ok(eval{inet_ntoa($ip)}, "gethostbyname: properly packed ip") or diag $@;
				}
			}
		}
		
		ok(!eval{$dns->get_result($fh)}, "get result when result already got");
	}
}

# getaddrinfo
for my $host ("google.com", "google.ru", "google.cy") {
	my $fh = $dns->getaddrinfo($host);
	$sel->add($fh);
}

while ($sel->count() > 0) {
	my @ready = $sel->can_read(60);
	ok(scalar @ready, "getaddrinfo: resolved less then 60 sec");
	
	for my $fh (@ready) {
		$sel->remove($fh);
		
		my ($err, @res) = $dns->get_result($fh);
		ok(defined $err, "error SV defined");
		if (!$err) {
			ok(@res >= 1, "getaddrinfo: one or more result");
			for my $r (@res) {
				is(ref $r, 'HASH', 'result is hash ref');
				for (qw/family socktype protocol addr canonname/) {
					ok(exists $r->{$_}, "result hash $_ key");
				}
				
				ok($r->{family} == AF_INET || $r->{family} == AF_INET6, "correct family");
				ok(eval {$r->{family} == AF_INET ? unpack_sockaddr_in($r->{addr}) : unpack_sockaddr_in6($r->{addr})}, "has correct address");
			}
		}
	}
}

open my $fh, __FILE__;
ok(!eval{$dns->get_result($fh)}, "get_result for unknow handle");

done_testing;
