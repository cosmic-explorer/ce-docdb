# Copyright 2001-2007 Eric Vaandering, Lynn Garren, Adam Bryant

#    This file is part of DocDB.

#    DocDB is free software; you can redistribute it and/or modify
#    it under the terms of version 2 of the GNU General Public License 
#    as published by the Free Software Foundation.

#    DocDB is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.

#    You should have received a copy of the GNU General Public License
#    along with DocDB; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

sub SendEmail (%) {
  unless ($MailInstalled) {
    return 0;
  }    

  require Mail::Send;          #FIXME: Why not use?
  require Mail::Mailer;
  my (%Params) = @_;
  
  my %Headers = ();
  my @Addressees = @{$Params{-to}};
  my $From       =   $Params{-from}    || "$Project Document Database <$DBWebMasterEmail>";
  my $Subject    =   $Params{-subject} || "$Project Document Database";
  my $Body       =   $Params{-body}    || "";
     
  my %Headers = ();
   
  if (@Addressees) {
    print "Sending mail to: ",join ", ",@Addressees,"<br/>\n";
    $Headers{To}      = \@Addressees;
    $Headers{From}    = $From;
    $Headers{Subject} = $Subject;

    # Send through the relay named in SiteConfig.pm ($MailServer). Without a
    # server Mail::Mailer tries no host at all (nothing listens on port 25 in
    # the container), so the access-request mail never left. A failure is
    # reported instead of aborting the page: by the time this runs the
    # request has already been recorded.
    my @Server = $MailServer ? (Server => $MailServer) : ();
    eval {
      my $Mailer = new Mail::Mailer 'smtp', @Server;
      $Mailer -> open(\%Headers);    # Start mail with headers
      print $Mailer $Body;
      $Mailer -> close;              # Complete the message and send it
      1;
    } or do {
      my $Error = $@ || "unknown error";
      $Error =~ s/\s+/ /g;
      warn "DCC ERROR: SendEmail failed: $Error";
      print "<b>Warning:</b> the notification e-mail could not be sent; the administrators have been informed through the server log.<br/>\n";
      return 0;
    };
  }
  return int(@Addressees);
}

1;
