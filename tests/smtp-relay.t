# Outgoing mail (2026-11-16): smtp-host.syr.edu left campus DNS and no DCC
# notification had been delivered since 2026-10-23. Both mail paths must use
# the relay named in SiteConfig.pm ($MailServer = smtp-relay.syr.edu).
use strict; use warnings; use Test::More;
use FindBin; use lib "$FindBin::Bin/lib"; use HotfixTest;
use File::Find;

# --- no trace of the dead host name anywhere in the application -------------
my @dead;
find(sub {
    return unless -f $_ && !-l $_;
    open my $fh, '<', $_ or return; local $/; my $t = <$fh>;
    push @dead, $File::Find::name if $t =~ /smtp-host\.syr\.edu/;
}, "$HotfixTest::root/usr1/www/cgi-bin");
is_deeply(\@dead, [], 'smtp-host.syr.edu appears nowhere under cgi-bin');

# --- SiteConfig.pm names the relay, in both instances ------------------------
for my $f ('usr1/www/cgi-bin/private/DocDB/SiteConfig.pm', 'usr1/www/cgi-bin/DocDB/SiteConfig.pm') {
    like(source($f), qr/^\$MailServer\s*=\s*"smtp-relay\.syr\.edu";/m, "$f sets \$MailServer to the campus relay");
}
is(source('usr1/www/cgi-bin/DocDB/Utilities.pm'), source('Utilities.pm'), 'public and private Utilities.pm are identical');

# --- send_email (notifications, signoffs) uses $MailServer -------------------
our (%transport, $sent);
BEGIN {
    $INC{$_} = 1 for qw(Email/Sender/Simple.pm Email/Sender/Transport/SMTP.pm Email/Simple.pm Email/Simple/Creator.pm Sys/Syslog.pm);
}
{ package Email::Sender::Simple; sub import { *main::sendmail = sub { $main::sent++; return 1 } } }
{ package Email::Sender::Transport::SMTP; sub new { my ($c, $a) = @_; %main::transport = %$a; bless {}, $c } }
{ package Email::Simple; sub create { bless {}, __PACKAGE__ } }
{ package Sys::Syslog; sub import { *main::syslog = sub {} } }
load_sub('Utilities.pm', 'send_email');

$main::MailServer = 'relay.test';
send_email('DCC <dcc@example.test>', 'user@example.test', 'Subject', 'Body');
is($transport{host}, 'relay.test', 'send_email connects to the SiteConfig relay');
is($transport{port}, 25, 'on port 25');
is($sent, 1, 'message handed to the transport');

undef $main::MailServer; %transport = ();
send_email('DCC <dcc@example.test>', 'user@example.test', 'Subject', 'Body');
is($transport{host}, 'smtp-relay.syr.edu', 'without a configured server it still falls back to the campus relay');

# --- SendEmail (access requests) passes the relay and survives a failure -----
our (@mailer_new, $opened, $closed, $fail_open, $mail_body);
BEGIN { $INC{$_} = 1 for qw(Mail/Send.pm Mail/Mailer.pm) }
{
    # A real Mail::Mailer object is a blessed glob that the caller prints to,
    # so the stand-in must be a printable handle as well.
    package Mail::Mailer;
    use Symbol ();
    sub new { my $c = shift; @main::mailer_new = @_; my $fh = Symbol::gensym(); CORE::open($fh, '>', \$main::mail_body) or die $!; bless $fh, $c }
    sub open { die "Cannot connect to relay\n" if $main::fail_open; $main::opened++; return 1 }
    sub close { $main::closed++; return 1 }
}
load_sub('EmailUtilities.pm', 'SendEmail');
$main::MailInstalled = 1; $main::Project = 'CE'; $main::DBWebMasterEmail = 'dcc@example.test';

$main::MailServer = 'relay.test';
my $rv; my $out = capture_output { $rv = SendEmail(-to => ['a@example.test'], -body => 'hi') };
is($rv, 1, 'SendEmail reports one addressee');
is_deeply(\@mailer_new, ['smtp', Server => 'relay.test'], 'Mail::Mailer is given the SiteConfig relay');
is($opened, 1, 'message opened'); is($closed, 1, 'message closed'); is($mail_body, 'hi', 'body written to the mailer');
like($out, qr/Sending mail to: a\@example\.test/, 'page still lists the addressee');

undef $main::MailServer; @mailer_new = ();
capture_output { SendEmail(-to => ['a@example.test'], -body => 'hi') };
is_deeply(\@mailer_new, ['smtp'], 'with no \$MailServer the upstream call is unchanged');

$main::MailServer = 'relay.test'; $main::fail_open = 1;
my $warned = '';
{
    local $SIG{__WARN__} = sub { $warned .= shift };
    $out = capture_output { $rv = SendEmail(-to => ['a@example.test'], -body => 'hi') };
}
is($rv, 0, 'a relay failure returns 0 instead of dying');
like($warned, qr/DCC ERROR: SendEmail failed: Cannot connect to relay/, 'failure goes to the server log');
like($out, qr/notification e-mail could not be sent/, 'and the page says so');

done_testing;
