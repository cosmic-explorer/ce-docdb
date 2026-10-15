# L30: the three scripts that used CGI::Untaint (absent from the image) now
# use UntaintParams.pm. Check the extractors' acceptance rules and that the
# scripts no longer reference CGI::Untaint.
use strict; use warnings; use Test::More;
use FindBin; use lib "$FindBin::Bin/lib"; use HotfixTest;
run_source(source('UntaintParams.pm'));
my %p = (id => ' 42 ', neg => '-7', bad => '12abc', huge => '1'x30, multi => "3\0004",
         text => "Hello, world\r\n", ctrl => "a\x01b", nul => "x\0y", utf => "caf\xE9");
is(UntaintInteger(\%p,'id'), 42, 'surrounding whitespace tolerated');
is(UntaintInteger(\%p,'neg'), -7, 'negative integers accepted as CGI::Untaint did');
is(UntaintInteger(\%p,'bad'), 0, 'trailing garbage rejected');
is(UntaintInteger(\%p,'huge'), 0, 'absurdly long numbers rejected');
is(UntaintInteger(\%p,'multi'), 0, 'multi-valued parameter rejected');
is(UntaintInteger(\%p,'missing'), 0, 'missing parameter is 0');
is(UntaintPrintable(\%p,'text'), "Hello, world\r\n", 'printable text with CR/LF kept');
is(UntaintPrintable(\%p,'ctrl'), '', 'control characters rejected');
is(UntaintPrintable(\%p,'nul'), '', 'NUL-joined multi-value rejected');
is(UntaintPrintable(\%p,'utf'), "caf\xE9", 'high-bit bytes kept as CGI::Untaint::printable did');
is(UntaintPrintable(\%p,'missing'), '', 'missing parameter is empty string');
for my $script (qw(ListEventsBy TopicAdminister BulkCertificateInsert)) {
  my $src = source($script);
  unlike($src, qr/CGI::Untaint/, "$script no longer loads CGI::Untaint");
  like($src, qr/require "UntaintParams\.pm"/, "$script loads UntaintParams.pm");
  unlike($src, qr/\$Untaint\s*->/, "$script has no leftover extract calls");
}
done_testing;
