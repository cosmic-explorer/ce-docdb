package HotfixTest;
use strict;
use warnings;
use Exporter 'import';
use File::Basename 'dirname';
use File::Spec;
our @EXPORT = qw(source load_sub source_between run_source stub_modules capture_output);
our $root = File::Spec->rel2abs(dirname(__FILE__).'/../..');
sub source {
    my ($file) = @_;
    $file = "usr1/www/cgi-bin/private/DocDB/$file" unless $file =~ m{/};
    open my $fh, '<', "$root/$file" or die "$file: $!";
    local $/; return <$fh>;
}
# Evaluate the verbatim production subroutine. Dependencies are explicitly
# stubbed by each test; no replacement implementation is tested.
sub load_sub {
    my ($file, $name) = @_;
    my $text = source($file);
    my ($body) = $text =~ /^(sub \Q$name\E\b[^\n]*\{.*?^\})/ms;
    die "Cannot locate $name in $file" unless defined $body;
    run_source($body);
}
sub source_between {
    my ($file, $begin, $end) = @_;
    my $text = source($file);
    my $a = index($text, $begin); die "Missing start $begin" if $a < 0;
    my $b = index($text, $end, $a + length($begin)); die "Missing end $end" if $b < 0;
    return substr($text, $a, $b-$a);
}
sub run_source {
    my ($body) = @_;
    my $result = eval "package main; no strict; no warnings; $body";
    die $@ if $@; return $result;
}
sub stub_modules { $INC{$_} = 1 for @_ }
sub capture_output (&) {
    my ($code) = @_; my $text = '';
    open my $fh, '>', \$text or die $!;
    { local *STDOUT = $fh; $code->(); }
    return $text;
}
package HotfixTest::DB;
sub new { bless { queries => [], executions => [] }, shift }
sub prepare {
    my ($self, $sql) = @_;
    push @{$self->{queries}}, $sql;
    bless { db => $self, sql => $sql, mysql_insertid => 41 }, 'HotfixTest::Statement';
}
package HotfixTest::Statement;
sub execute {
    my ($self, @values) = @_;
    push @{$self->{db}{executions}}, [$self->{sql}, @values]; return 1;
}
sub bind_columns { return 1 }
sub fetch { return 0 }
sub fetchrow_array { return 23 }
sub finish { return 1 }
1;
