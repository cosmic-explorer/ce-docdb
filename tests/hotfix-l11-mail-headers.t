use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/lib";
use HotfixTest;

our ($headers,$body,$sent);
BEGIN {
    $INC{$_}=1 for qw(Email/Sender/Simple.pm Email/Sender/Transport/SMTP.pm Email/Simple.pm Email/Simple/Creator.pm Sys/Syslog.pm);
}
{ package Email::Sender::Simple; sub import { *main::sendmail=sub {$main::sent++;return 1} } }
{ package Email::Sender::Transport::SMTP; sub new {bless {},shift} }
{ package Email::Simple; sub create {shift; my %args=@_; $main::headers=$args{header};$main::body=$args{body};return bless {},__PACKAGE__} }
{ package Sys::Syslog; sub import { *main::syslog=sub {} } }
load_sub('Utilities.pm','send_email');
send_email("Sender\r\nName", "user\n\@example.test", "Title\r\nExtra", "Body\nkeeps lines");
is_deeply($headers,[From=>'Sender Name',To=>'user @example.test',Subject=>'Title Extra'],'all header values are single lines before message creation');
is($body,"Body\nkeeps lines",'message body remains intact');
is($sent,1,'message handed to mocked transport exactly once');

done_testing;
