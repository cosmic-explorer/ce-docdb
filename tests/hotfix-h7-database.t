use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;
# Use only a disposable database; this test changes the connection's SQL mode.
# Example: HOTFIX_TEST_MYSQL_DSN='DBI:mysql:database=test;mysql_socket=/tmp/hotfix-mysql/mysql.sock' prove tests/hotfix-h7-database.t
plan skip_all => 'set HOTFIX_TEST_MYSQL_DSN for a disposable MariaDB test database'
    unless $ENV{HOTFIX_TEST_MYSQL_DSN};
require DBI;
load_sub('SearchAtoms.pm','TextSearch');
my $dbh=DBI->connect($ENV{HOTFIX_TEST_MYSQL_DSN}, $ENV{HOTFIX_TEST_MYSQL_USER} || 'root',
    $ENV{HOTFIX_TEST_MYSQL_PASSWORD} || '', {RaiseError=>1, PrintError=>0});
for my $sql_mode ('', 'NO_BACKSLASH_ESCAPES', 'ANSI_QUOTES,NO_BACKSLASH_ESCAPES') {
    $dbh->do('SET SESSION sql_mode = ?',undef,$sql_mode);
    for my $server_prepare (0,1) {
        local $dbh->{mysql_server_prepare}=$server_prepare;
        for my $mode (qw(anysub allsub)) {
            my @values;
            my $needle=q{O"Brien\_100%};
            my $phrase=TextSearch('DocumentTitle',$mode,$needle,\@values);
            my $sql="SELECT COUNT(*) FROM (SELECT ? AS DocumentTitle) AS doc WHERE $phrase";
            is($dbh->selectrow_array($sql,undef,$needle,@values),1,"$mode literal match, sql_mode=$sql_mode server_prepare=$server_prepare");
            is($dbh->selectrow_array($sql,undef,q{O"Brien\_100MORE},@values),0,'literal percent does not become a wildcard');
        }
        for my $mode (qw(anyword allword)) {
            my @values;
            my $phrase=TextSearch('DocumentTitle',$mode,'Alpha"Beta',\@values);
            my $sql="SELECT COUNT(*) FROM (SELECT ? AS DocumentTitle) AS doc WHERE $phrase";
            is($dbh->selectrow_array($sql,undef,'Alpha"Beta',@values),1,"$mode quote stays data in REGEXP pattern");
            is($dbh->selectrow_array($sql,undef,'Alphabet',@values),0,'nonmatching word excluded');
        }
    }
}
$dbh->disconnect;
done_testing;
