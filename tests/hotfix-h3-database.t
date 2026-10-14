use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;
plan skip_all => 'set HOTFIX_TEST_MYSQL_DSN for a disposable MariaDB test database'
    unless $ENV{HOTFIX_TEST_MYSQL_DSN};
require DBI;
load_sub('AuthorSQL.pm',$_) for qw(ProcessManualAuthors GetAuthorFromNames);
our $dbh=DBI->connect($ENV{HOTFIX_TEST_MYSQL_DSN}, $ENV{HOTFIX_TEST_MYSQL_USER} || 'root',
    $ENV{HOTFIX_TEST_MYSQL_PASSWORD} || '', {RaiseError=>1,PrintError=>0});
# TEMPORARY shadows any existing table only on this disposable connection.
$dbh->do('CREATE TEMPORARY TABLE Author (AuthorId INT, FirstName VARCHAR(80), MiddleInitials VARCHAR(80), LastName VARCHAR(80))');
my $insert=$dbh->prepare('INSERT INTO Author VALUES (?,?,?,?)');
$insert->execute(@$_) for ([101,'John','','Smith'],[102,'John','A','Smith'],[103,'John','B','Smith'],[104,'James','A','O"Brien']);
for my $call (['ProcessManualAuthors','Smith, John'],['GetAuthorFromNames','Smith  John']) {
    no strict 'refs'; my @ids=&{$call->[0]}($call->[1],{-warn=>1});
    is_deeply(\@ids,[101],'no-middle exact match wins over two fuzzy alternatives in MariaDB');
}
my @quoted=ProcessManualAuthors('O"Brien, James A.',{-warn=>1});
is_deeply(\@quoted,[104],'quote in surname is bound as literal text');
$dbh->disconnect;
done_testing;
