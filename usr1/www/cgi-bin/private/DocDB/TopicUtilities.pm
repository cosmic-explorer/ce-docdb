#      Author: Eric Vaandering (ewv@fnal.gov)
#    Modified: 

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

sub AllRootTopics {
  require "TopicSQL.pm";

  GetTopics();
  
  my @TopicIDs = keys %Topics;
  my @RootIDs  = ();
  
  foreach my $TopicID (@TopicIDs) {
    unless (@{$TopicParents{$TopicID}}) {
      push @RootIDs,$TopicID;
    }  
  }
  
  return @RootIDs;
}

sub TopicAndSubTopics {
  my ($ArgRef) = @_;
  my $TopicID = exists $ArgRef->{-topicid} ? $ArgRef->{-topicid} : 0;
  
  require "TopicSQL.pm";
  require "Utilities.pm";

  GetTopics();
  
  # A topic may have multiple parents, and old data may contain cycles.
  # Visit each descendant once instead of recursing once for every path.
  my @TopicIDs;
  my @Pending = ($TopicID);
  my %Seen;
  while (@Pending) {
    my $ID = pop @Pending;
    next if $Seen{$ID}++;
    push @TopicIDs,$ID;
    push @Pending,reverse @{$TopicChildren{$ID} || []};
  }

  return @TopicIDs;
}

sub TopicParentError {
  my ($TopicID,$ParentTopicID) = @_;

  return "You must select an existing topic to modify."
    unless $TopicID && exists $Topics{$TopicID};
  # An omitted parent means leave the existing hierarchy unchanged.
  return "" unless $ParentTopicID;
  return "You must select an existing parent topic."
    unless exists $Topics{$ParentTopicID};
  return "You cannot set a topic to be its own parent. No action taken."
    if $ParentTopicID == $TopicID;
  my @Descendants = TopicAndSubTopics({ -topicid => $TopicID });
  return "You cannot set a descendant of a topic as its parent. No action taken."
    if grep { $_ == $ParentTopicID } @Descendants;
  return "";
}

sub BuildTopicProvenance {
  %TopicProvenance = ();

  # Keep the ordered display path used by sorting and indentation. With
  # multiple parents this retains the legacy last-parent choice; descendant
  # reachability above must instead follow every branch.
  foreach my $TopicID (keys %Topics) {
    my %Seen;
    my $ID = $TopicID;
    my @IDs;
    while (defined $ID && exists $Topics{$ID} && !$Seen{$ID}++) {
      push @IDs,$ID;
      my @Parents = @{$TopicParents{$ID} || []};
      $ID = @Parents ? $Parents[-1] : undef;
    }
    $TopicProvenance{$TopicID} = \@IDs;
  }

  return;
}

1;
