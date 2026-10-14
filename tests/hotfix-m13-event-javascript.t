use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

our (%Conferences,$EventID); sub EventsByDate {0}
$Conferences{1}{Full}="a'b'c\\d\n</script>";
my $block=source_between('Scripts.pm','  foreach $EventID (sort EventsByDate','  print "//');
my $output=capture_output {run_source($block)};
like($output,qr/a\\'b\\'c\\\\d /,'all quotes and backslashes escaped');
unlike($output,qr{</script>},'event cannot close script element');

done_testing;
