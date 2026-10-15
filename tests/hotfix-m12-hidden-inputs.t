use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

# M12: the ListBy filter inputs must be quoted so a hostile value cannot add
# attributes. Since C07 the inputs come from ListByHiddenFilters, which
# emits every current filter.
use HTML::Entities; use HTML::Parser;
no strict 'vars';
my $hostile = HTML::Entities::encode(q{1 extra=value "quoted"});
%params = (eventgroupid => $hostile, topicid => $hostile, authorid => $hostile);
load_sub('ListBy', 'ListByHiddenFilters');
my $html = ListByHiddenFilters();
my @inputs;
my $parser=HTML::Parser->new(api_version=>3,start_h=>[sub {my ($tag,$attrs)=@_; push @inputs,$attrs if $tag eq 'input'},'tagname, attr']);
$parser->parse($html);
is(scalar @inputs,3,'all filter inputs emitted');
for my $input (@inputs) {
    is_deeply([sort keys %$input],[qw(name type value)],'spaces cannot introduce another attribute');
    is($input->{value},q{1 extra=value "quoted"},'quoted input retains original encoded value');
}

done_testing;
