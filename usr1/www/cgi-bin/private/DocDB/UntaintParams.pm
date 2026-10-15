#        Name: UntaintParams.pm
# Description: Minimal replacement for the two CGI::Untaint extractors DocDB
#              used (-as_integer and -as_printable). CGI::Untaint is not
#              installed in the production image, so the three scripts that
#              loaded it failed to compile (review finding L30). The
#              acceptance rules mirror CGI::Untaint::integer and
#              CGI::Untaint::printable: anything that does not match is
#              treated as absent.

sub UntaintInteger {
  my ($Params, $Name) = @_;
  my $Value = $Params->{$Name};
  return 0 unless defined $Value;
  if ($Value =~ /\A\s*(-?[0-9]{1,18})\s*\z/) {
    return int($1);
  }
  return 0;
}

sub UntaintPrintable {
  my ($Params, $Name) = @_;
  my $Value = $Params->{$Name};
  return "" unless defined $Value;
  if ($Value =~ /\A([\x20-\x7E\x80-\xFF\r\n\t]*)\z/) {
    return $1;
  }
  return "";
}

1;
