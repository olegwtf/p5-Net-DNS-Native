use v5.6;
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME           => 'Net::DNS::Native',
	LICENSE        => 'perl',
	VERSION_FROM   => 'lib/Net/DNS/Native.pm',
	META_MERGE     => {resources => {repository => 'https://github.com/olegwtf/p5-Net-DNS-Native'}},
	ABSTRACT_FROM  => 'lib/Net/DNS/Native.pm',
	AUTHOR         => 'Oleg G <oleg@cpan.org>',
	LIBS           => ['-lpthread'],
	PREREQ_PM      => { 'Socket' => 1.95 },
	BUILD_REQUIRES => { 'Test::More' => 0.88 },
);
