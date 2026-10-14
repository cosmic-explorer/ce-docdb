use strict;
use warnings;
no warnings 'once';
use FindBin;
use File::Spec;
use Test::More;
use XML::Twig;

# Load the actual exporter, replacing only its application/database boundaries.
# No site configuration, database connection, HTTP request, or mail is loaded.
our ($TRUE, $ShortProject, %DocRevisions, %DocXRefs, %Incoming);
$TRUE = 1;
$ShortProject = 'CE';
$INC{$_} = 1 for qw(Utilities.pm DocumentSQL.pm XRefSQL.pm);
sub FetchDocRevisionByID { return $_[0]; }
sub FetchDocumentAlias { return 'T' . $_[0]; }
sub FetchXRefs {
    my %args = @_;
    %DocXRefs = %{ $Incoming{$args{-docid}} || {} };
    return sort { $a <=> $b } keys %DocXRefs;
}
my $root = $ENV{DOCDB_TEST_ROOT}
    || File::Spec->rel2abs("$FindBin::Bin/..");
require "$root/usr1/www/cgi-bin/private/DocDB/XMLOutput.pm";

%DocRevisions = (
    101 => { DOCID => 10, Version => 1 },
    102 => { DOCID => 11, Version => 2 },
    201 => { DOCID => 20, Version => 3, Obsolete => 0 },
    202 => { DOCID => 20, Version => 2, Obsolete => 0 },
    301 => { DOCID => 30, Version => 1, Obsolete => 1 },
);
%Incoming = (
    10 => {
        1 => { DocRevID => 201, Version => '', Project => '' },
        2 => { DocRevID => 202, Version => 1, Project => 'CE' },
        3 => { DocRevID => 301, Version => '', Project => '' },
        4 => { DocRevID => 201, Version => 9, Project => '' },
    },
    11 => {
        5 => { DocRevID => 201, Version => 2, Project => '' },
        6 => { DocRevID => 202, Version => '', Project => '' },
        7 => { DocRevID => 301, Version => '', Project => '' },
    },
);

sub export_in_order {
    my @revision_ids = @_;
    my $export = XML::Twig::Elt->new('docdb');
    for my $revision_id (@revision_ids) {
        my $target = XML::Twig::Elt->new(
            'document', { id => $DocRevisions{$revision_id}{DOCID} }
        );
        $target->paste(last_child => $export);
        for my $reference (XRefByXMLOut({ -docrevid => $revision_id })) {
            $reference->paste(last_child => $target) if $reference;
        }
    }
    # Check the real serialized/reparsed response, not just Perl return counts.
    my $parsed = XML::Twig->new;
    $parsed->parse($export->sprint);
    return $parsed;
}

for my $order ([101, 102], [102, 101], [101, 102]) {
    my $parsed = export_in_order(@$order);
    my @targets = $parsed->root->children('document');
    is(scalar @targets, 2, 'both target documents survive XML serialization');
    for my $target (@targets) {
        my @references = $target->children('xrefby');
        is(scalar @references, 1,
           'target ' . $target->att('id') . ' has its incoming document exactly once');
        is($references[0] && $references[0]->att('docid'), 20,
           'active referring document retained for each target');
        is($references[0] && $references[0]->att('alias'), 'T20',
           'referring alias survives real XML serialization');
    }
}
done_testing();
