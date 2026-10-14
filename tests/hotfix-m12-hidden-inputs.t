use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

use HTML::Entities; use HTML::Parser;
our ($EventGroupID,$TopicID,$AuthorID);
$EventGroupID=$TopicID=$AuthorID=HTML::Entities::encode(q{1 extra=value "quoted"});
my $block=source_between('ListBy','   if ($EventGroupID) {','   print "<center>');
my $html=capture_output {run_source($block)};
my @inputs;
my $parser=HTML::Parser->new(api_version=>3,start_h=>[sub {my ($tag,$attrs)=@_; push @inputs,$attrs if $tag eq 'input'},'tagname, attr']);
$parser->parse($html);
is(scalar @inputs,3,'all filter inputs emitted');
for my $input (@inputs) {
    is_deeply([sort keys %$input],[qw(name type value)],'spaces cannot introduce another attribute');
    is($input->{value},q{1 extra=value "quoted"},'quoted input retains original encoded value');
}

done_testing;
