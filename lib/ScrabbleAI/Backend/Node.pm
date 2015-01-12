##########################################################################
# ScrabbleAI::Backend::Node
# A Node in the word tree generated by Backend::Library. Each Node can
# have up to N children, where N is the number of distinct playable
# letters, with each child designated by a corresponding letter. A Node
# can also be a valid endpoint for word(s) independently of whether it
# has children.
#
# Copyright (C) 2015 Andrew Pikler
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
##########################################################################

package ScrabbleAI::Backend::Node;

use strict;
use warnings;

use Data::Dumper;

sub new {
	my ($class) = @_;
	
	# children is a hashref of character => Node
	my $self = bless({
		children => {},
		endpoint => 0,
	}, $class);
	
	return $self;
}

# If this node has a child Node at that given letter, returns that Node.
# Otherwise returns undef.
sub get_child {
	my ($self, $letter) = @_;
	
	return defined($self->{children}{$letter}) ? $self->{children}{$letter} : undef;
}

sub get_edges {
	my ($self) = @_;
	
	return [keys %{$self->{children}}];
}

# Adds the given Node as a child at $letter. Overwrites any existing child for
# that letter.
sub set_child {
	my ($self, $letter, $node) = @_;
	
	$self->{children}{$letter} = $node;
}

# Adds the $letters (taken as an arrayref of characters, for speed purposes)
# to the tree.
sub add_word {
	my ($self, $letters) = @_;

	unless (@$letters) {
		$self->set_endpoint();
		return;
	}
	
	my $letter = shift(@$letters);
	my $child = $self->get_child($letter);
	unless ($child) {
		$child = $self->set_child($letter, ScrabbleAI::Backend::Node->new());
	}
	
	$child->add_word($letters);
}

sub set_endpoint {
	my ($self) = @_;
	
	$self->{endpoint} = 1;
}

sub is_endpoint {
	my ($self) = @_;
	
	return $self->{endpoint};
}

# Traverse the tree, from the given node, using the path in the prefix (an array of characters).
# Returns the resulting node, or undef if the traversal isn't possible.
sub get_node {
	my ($node, @prefix) = @_;
	
	return $node unless @prefix;
	
	my $edge = shift @prefix;
	if (my $child = $node->get_child($edge)) {
		return get_node($child, @prefix);
	}
	else {
		return undef;
	}
}

1;
