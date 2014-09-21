use v5.6;
use ExtUtils::MakeMaker;

my @additional;
if ($^O eq 'MSWin32') {
	push @additional, INC => '-Ipthreads-win32\\include';
	push @additional, DEFINE => '-D_WIN32_WINNT=0x0501 -DPTW32_STATIC_LIB';
}

WriteMakefile(
	NAME           => 'Net::DNS::Native',
	LICENSE        => 'perl',
	VERSION_FROM   => 'lib/Net/DNS/Native.pm',
	META_MERGE     => {resources => {repository => 'https://github.com/olegwtf/p5-Net-DNS-Native'}},
	ABSTRACT_FROM  => 'lib/Net/DNS/Native.pm',
	AUTHOR         => 'Oleg G <oleg@cpan.org>',
	LIBS           => [$^O eq 'MSWin32' ? ':nosearch -Lpthreads-win32/lib -lpthread -lWS2_32' : '-lpthread'],
	PREREQ_PM      => { 'Socket' => 1.95 },
	BUILD_REQUIRES => { 'Test::More' => 0.88 },
	@additional
);
