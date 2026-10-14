#        Name: $RCSfile: SignoffHTML.pm,v $
# Description: Generates HTML for things related to signoffs
#
#    Revision: $Revision: 1.10.4.6 $
#    Modified: $Author: vondo $ on $Date: 2007/09/20 19:53:14 $
#
#      Author: Eric Vaandering (ewv@fnal.gov)

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

require "NotificationSQL.pm";
require "EmailSecurity.pm";
use POSIX;

sub SignoffBox { # Just a text box for now with a list of names
   my (%Params) = @_;

   my $Default  = $Params{-default}  || "";

   #  my $ChooserLink  = "- <a href=\"Javascript:signoffchooserwindow(\'$SignoffChooser\');\">".
   #        "<b>Signoff Chooser</b></a>";
   my $ElementTitle = &FormElementTitle(-helplink  => "signoffs",
                                       -helptext  => "Signoffs",
                                       -extratext => $ChooserLink);

   print "\n<script>\n   var Signers = [";

   my @EmailUserIDs = sort EmailUserIDsByName GetEmailUserIDs();
   my $EmailUserID;
   my @Signers = ();
   
   foreach $EmailUserID (@EmailUserIDs) {
      FetchEmailUser($EmailUserID);
      unless (CanSign($EmailUserID)) {next;}
      my $Name = $EmailUser{$EmailUserID}{Name};
      push @Signers,$Name;
      print '"'.$Name.'", ';
   }
   
   print "];\n</script>\n";

   print "<td><table><tr><td>".$ElementTitle."</td><td>\n";

   print FormElementTitle(-helplink => 'signoffs', -helptext  => 'Select authors here ...');

   print $query -> scrolling_list(-name => "signoffscroll", -id => "signoffscroll",
                                   -values => \@Signers,
                                   -onClick => "packValues(event, 'signoffscroll','signofflist');",
                                   -onBlur => "unfocus();",
                                   -size => 10, -multiple => $Multiple);

   print "</td><td>\n";


   print FormElementTitle(-helplink => 'signoffs', -helptext  => '...or type here');
   print "         <div id=\"signoffdiv\">\n";
   print $query -> textarea (-name    => "signofflist", -id => "signofflist",
                            -default => $Default,
                            -columns => 30,    -rows    => 10);
   print "</div>\n</td></tr></table></td>\n";
};

sub PrintRevisionSignoffInfo ($) { # FIXME: Handle more complicated topologies?
  require "SignoffSQL.pm";
  require "Security.pm";

  my ($DocRevID) = @_;
  my $DocumentID = $DocRevisions{$DocRevID}{DOCID};
  my $Version    = $DocRevisions{$DocRevID}{Version};

  # Don't display anything unless the user is logged into a group that can
  # modify the DB. Maybe we want to display but not provide signature boxes?

  unless (&CanAccess($DocumentID,$Version)) {
    return;
  }

  my @RootSignoffIDs = &GetRootSignoffs($DocRevID);
  if (@RootSignoffIDs) {
    print "<div id=\"Signoffs\">\n";
    print "<dl>\n";
   #print "<dt class=\"InfoHeader\"><span class=\"InfoHeader\">Signoffs:</span></dt>\n";
    print "<dt class=\"InfoHeader\"><span class=\"InfoHeader\">Signoffs:"; 
    ##########
    # Email to all signers - VK 06-2013
    #print "DocRevID: $DocRevID\n";
    require "SignoffSQL.pm";
    #print "SignoffID: $SignoffID\n";
    GetAllEmails($DocRevID);
    if (scalar(@AllAddresses) > 1) {
      require "DocumentSQL.pm"; # get alias
      my $DocAlias = FetchDocumentAlias($DocumentID);

      my ($LinkStart,$MailTo,$LinkEnd,$EmailToAll);
      $LinkStart = " <a href\=\"mailto:";
      $MailTo = join ',', map qq($_), @AllAddresses;
      $LinkEnd = "\?Subject\=DCC document LIGO-$DocAlias\"><img src\=\"".$ImgURLPath."/mail-all.png\" title\=\"Contact all signers\" alt\=\"Email all signers\"></a>";
      $EmailToAll = $LinkStart.$MailTo.$LinkEnd;
      print "$EmailToAll\n";
    }
    ##########
    print "</span></dt>\n";
    print "</dl>\n";

    print "<ul>\n";
    foreach my $RootSignoffID (@RootSignoffIDs) {
      &PrintSignoffInfo($RootSignoffID);
    }
    print "</ul>\n";
    print "</div>\n";
  }
}

sub PrintSignoffInfo ($) {
  require "SignoffSQL.pm";

  my ($SignoffID) = @_;

  if ($Public) { return; }

  my @SubSignoffIDs = &GetSubSignoffs($SignoffID);
  print "<li>";
  &PrintSignatureInfo($SignoffID);
  if (@SubSignoffIDs) {
    print "<ul>\n";
    foreach my $SubSignoffID (@SubSignoffIDs) {
      &PrintSignoffInfo($SubSignoffID);
    }
    print "</ul>\n";
  }
  print "</li>\n";
  return;
}

sub PrintSignatureInfo ($) {
  require "SignoffSQL.pm";
  require "SignoffUtilities.pm";
  require "NotificationSQL.pm";

  my ($SignoffID) = @_;

  if ($Public) { return; }

  my $ServerTimeZone = strftime "%Z", localtime() ;
  my @SignatureIDs = &GetSignatures($SignoffID);

  my @SignatureSnippets = ();

  foreach my $SignatureID (@SignatureIDs) {
    my $SignatureIDOK = &FetchSignature($SignatureID);
    if ($SignatureIDOK) {
      my $EmailUserID = $Signatures{$SignatureID}{EmailUserID};
      &FetchEmailUser($EmailUserID);

      my $SignoffID = $Signatures{$SignatureID}{SignoffID};
      my $Status = &SignoffStatus($SignoffID);

      # If the Signoff is ready for a signature, put a password field
      # If signed, allow rescinding the signature
      # Otherwise, note that it's waiting

      my $SignatureText = "";
      my $SignatureLink = &SignatureLink($EmailUserID);
      if ($Status eq "Ready" || $Status eq "Signed") {
        if ($Status eq "Ready") {
          $Action = "sign";
          $ActionText = "Sign Document";
        } else {
          $Action = "unsign";
          $ActionText = "Remove Signature";
        }

        if ($UserValidation eq "kerberos") {
          if (FetchEmailUserIDFromRemoteUser() == $EmailUserID) {
            $SignatureText .= $query -> start_form('GET',"$SignRevision");
            $SignatureText .= "<div>\n";
            $SignatureText .= "$SignatureLink ";
            $SignatureText .= $query -> hidden(-name => 'docid',   -default => $DocumentID);
            $SignatureText .= $query -> hidden(-name => 'version',   -default => $Version);
            $SignatureText .= $query -> hidden(-name => 'signatureid',   -default => $SignatureID);
            $SignatureText .= $query -> hidden(-name => 'emailuserid',   -default => $EmailUserID);
            $SignatureText .= $query -> hidden(-name => 'action',   -default => $Action);
            $SignatureText .= $query -> submit (-value => $ActionText);
            $SignatureText .= "</div>\n";
            $SignatureText .= $query -> end_multipart_form;
          } else {
            if ($Status eq "Signed") {
              $SignatureText .= "$SignatureLink (signed  ";
              $SignatureText .= $Signatures{$SignatureID}{TimeStamp};
              $SignatureText .= " $ServerTimeZone)";
            } else {
              my $DaysSince = NumberOfDaysSince($SignoffID);
              $SignatureText .= "$SignatureLink (waiting for signature for $DaysSince days)";
            }
          }
        } else {
          $SignatureText .= $query -> start_form('GET',"$SignRevision");
          $SignatureText .= "<div>\n";
          $SignatureText .= "$SignatureLink ";

          $SignatureText .= $query -> hidden(-name => 'docid',   -default => $DocumentID);
          
          $SignatureText .= $query -> hidden(-name => 'version',   -default => $Version);
          $SignatureText .= $query -> hidden(-name => 'signatureid',   -default => $SignatureID);
          $SignatureText .= $query -> hidden(-name => 'emailuserid',   -default => $EmailUserID);
          $SignatureText .= $query -> hidden(-name => 'action',   -default => $Action);
          $SignatureText .= $query -> password_field(-name => "password-$EmailUserID", -size => 16, -maxlength => 32);
          $SignatureText .= " ";
          $SignatureText .= $query -> submit (-value => $ActionText);
          $SignatureText .= "</div>\n";
          $SignatureText .= $query -> end_multipart_form;
        }
      } elsif ($Status eq "NotReady") {

        $SignatureText .= "$SignatureLink (waiting for other signatures)";
      } else {
        $SignatureText .= "$SignatureLink (unknown status)";
      }
      push @SignatureSnippets,$SignatureText;
    } # if ($SignatureIDOK)
  } # foreach (@SignatureIDs)

  my $SignoffText = join ' or <br>',@SignatureSnippets;
  print "$SignoffText\n";
}

sub SignatureLink ($) {
  require "NotificationSQL.pm";
  require "DocumentSQL.pm"; ###
  my ($EmailUserID,$DocumentID_asArg) = @_; ###
  # If DocID is not available as a global (as in multiple doc lists), pass it:  ###
  if (defined($DocumentID_asArg) && $DocumentID_asArg ne "") { ###
    $DocumentID = $DocumentID_asArg; ###
  } ###
  my $DocAlias = &FetchDocumentAlias($DocumentID); ###

  # has been moved above:
  #my ($EmailUserID) = @_; ###
  require "SignoffSQL.pm"; ###

  &FetchEmailUser($EmailUserID);
  my $Link = "<a href=\"$SignatureReport?emailuserid=$EmailUserID\">";
     $Link .= $EmailUser{$EmailUserID}{Name};
     $Link .= "</a>";
     GetSignerEmail($EmailUserID); ###
    #my $Name = $EmailUser{$EmailUserID}{Name}; ###
    #$mail = " <a href\=\"mailto:$EmailAddress\?Subject\=DCC document LIGO\-$DocAlias\"><img src\=\"".$ImgURLPath."/mail.png\" title\=\"Contact $Name\"></a>"; ###
     $mail = " <a href\=\"mailto:$EmailAddress\?Subject\=DCC document LIGO\-$DocAlias\"><img src\=\"".$ImgURLPath."/mail.png\" title\=\"Contact this signer\"></a>"; ###
     $Link .= $mail; ###

  return $Link;
}

1;
