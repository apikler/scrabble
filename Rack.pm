package Rack;

use strict;
use warnings;

use Tile;

sub new {
	my ($class) = @_;
	
	my $self = bless({
		tiles => [],
	}, $class);
	
	return $self;
}

sub add_tile {
	my ($self, $tile) = @_;
	
	push(@{$self->{tiles}}, $tile);
}

sub contains {
	my ($self, $letter) = @_;
	
	$letter = lc($letter);
	return scalar(grep {$_->get() eq $letter} @{$self->{tiles}});
}

# Returns and removes a tile of the chosen letter type from the rack, or returns undef if there
# is no such tile.
sub remove {
	my ($self, $letter) = @_;
	
	$letter = lc($letter);
	my $tiles = $self->{tiles};
	for my $index (0..$#$tiles) {
		return splice(@$tiles, $index, 1) if $tiles->[$index]->get() eq $letter;
	}
	
	return undef;
}

# Returns the number of tiles currently in the rack.
sub size {
	my ($self) = @_;
	
	return scalar(@{$self->{tiles}});
}

1;