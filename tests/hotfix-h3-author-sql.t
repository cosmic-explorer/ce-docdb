use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

our ($dbh,@ErrorStack,@WarnStack); load_sub('AuthorSQL.pm','ProcessManualAuthors'); load_sub('AuthorSQL.pm','GetAuthorFromNames');
for my $call (['ProcessManualAuthors','O"Brien, James A.'],['GetAuthorFromNames','O"Brien  James A.']) {
    $dbh=HotfixTest::DB->new; no strict 'refs'; &{$call->[0]}($call->[1],{-warn=>1});
    is(scalar @{$dbh->{executions}},2,'both exact and fuzzy queries exercised');
    is_deeply([@{$dbh->{executions}[0]}[1..3]],['James','A','O"Brien'],'exact names bound without SQL interpolation');
    is_deeply([@{$dbh->{executions}[1]}[1..3]],['James%','A%','O"Brien%'],'fuzzy suffix added to bound names');
    unlike(join('',@{$dbh->{queries}}),qr/O"Brien/,'name absent from SQL structure');
}

$dbh=HotfixTest::DB->new;
ProcessManualAuthors('Smith, J.',{-warn=>1});
is($dbh->{executions}[0][1],'J.','exact lookup retains first initial punctuation');
is($dbh->{executions}[1][1],'J%','fuzzy lookup removes first initial period before binding (R-C11)');

{
    package EmptyMiddleDB;
    our @ISA=('HotfixTest::DB');
    sub prepare { my $s=shift->SUPER::prepare(@_); bless $s,'EmptyMiddleStatement' }
    package EmptyMiddleStatement;
    our @ISA=('HotfixTest::Statement');
    sub execute {
        my ($s,@values)=@_; $s->SUPER::execute(@values);
        $s->{rows}= $s->{sql} =~ /FirstName =/ ?
            ((defined $values[1] && $values[1] eq '') ? [101] : []) : [102,103];
        return 1;
    }
    sub bind_columns { my ($s,undef,$ref)=@_; $s->{ref}=$ref }
    sub fetch { my ($s)=@_; return 0 unless @{$s->{rows}}; ${$s->{ref}}=shift @{$s->{rows}}; return 1 }
}
for my $call (['ProcessManualAuthors','Smith, John'],['GetAuthorFromNames','Smith  John']) {
    $dbh=EmptyMiddleDB->new; no strict 'refs'; my @ids=&{$call->[0]}($call->[1],{-warn=>1});
    is_deeply(\@ids,[101],'absent middle name selects exact author instead of ambiguous fuzzy names');
    is(scalar @{$dbh->{executions}},1,'exact no-middle match wins before fuzzy lookup');
    is($dbh->{executions}[0][2],'','missing middle bound as empty text rather than SQL NULL');
}
done_testing;
