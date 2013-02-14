package Player::AIPlayer;
use base qw(Player);

use strict;
use warnings;

use Data::Dumper;

use Tile;
use Move;

sub new {
	my ($class, $board, $library) = @_;
	
	my $self = Player->new($board);
	
	bless($self, $class);
	$self->{library} = $library;
	
	return $self;
}

sub get_move {
	my ($self) = @_;
	
	$self->{moves} = [];
	$self->get_moves();
	
	my @moves = sort {$a->{value} <=> $b->{value}} @{$self->{moves}};
	print "Rack: " . $self->{rack}->str() . "\n";
	my $best_move = $moves[0];
	print "best move: " . Dumper($best_move->{tiles});
}

# Returns an arrayref of all the legal moves the AI can make, sorted in order of decreasing value
sub get_moves {
	my ($self) = @_;
	
	my $anchors = $self->get_anchors();
	my $restrictions = $self->get_restrictions();
	
	while (my ($location, $anchor) = each %$anchors) {
		$location =~ /(\d+)\,(\d+)/;
		my ($i, $j) = ($1, $2);
		
		# Backtrack to find the number of spaces before an anchor to the left of $i, $j
		my $limit = 0;
		my $new_i = $i;
		while (1) {
			$new_i--;
			if ($self->{board}->in_bounds($new_i, $j) && !defined($anchors->{"$new_i,$j"})) {
				$limit++;
			}
			else {
				last;
			}
		}
		
		$self->left_part('', $self->{library}->get_tree(), $limit, $restrictions, $i, $j);
	}
}

sub left_part {
	my ($self, $partial_word, $node, $limit, $restrictions, $i, $j) = @_;
	
	# print "left part limit: $limit, partial word: $partial_word \n";
	# print "rack: " . $self->{rack}->str() ."\n";
	
	$self->extend_right($partial_word, $node, $restrictions, $i, $j);
	if ($limit > 0) {
		for my $letter (@{$node->get_edges()}) {
			#print "letter: $letter \n";
			#print "rack: " . $self->{rack}->str() ."\n";
			my $tile;
			if ($self->{rack}->contains($letter)) {
				$tile = $self->{rack}->remove($letter);
			}
			elsif ($self->{rack}->contains('*')) {
				$tile = $self->{rack}->remove('*');
			}
			# print "rack after: " . $self->{rack}->str() ."\n";
			
			if ($tile) {
				$self->left_part(
					$partial_word . $letter,
					$node->get_child($letter),
					$limit - 1,
					$restrictions,
					$i,
					$j,
				);
				$self->{rack}->add_tile($tile);
			}
		}
	}
}

sub extend_right {
	my ($self, $partial_word, $node, $restrictions, $i, $j) = @_;
	
	my $board = $self->{board};
	return unless $board->in_bounds($i, $j);
	
	my $board_tile = $board->get_space($i, $j)->get_tile();
	unless ($board_tile) {
		if ($node->is_endpoint()) {
			my $move = Move->new($board);
			$move->set_word_reverse($partial_word, $i, $j);
			$move->evaluate();
			push(@{$self->{moves}}, $move);
		}
		
		for my $letter (@{$node->get_edges()}) {
			my $tile;
			if ($self->{rack}->contains($letter)) {
				$tile = $self->{rack}->remove($letter);
			}
			elsif ($self->{rack}->contains('*')) {
				$tile = $self->{rack}->remove('*');
			}
			
			if ($tile && passes_restrictions($tile->get(), $restrictions, $i, $j)) {
				$self->extend_right(
					$partial_word . $letter, 
					$node->get_child($letter),
					$restrictions,
					$i + 1,
					$j,
				);
			}
			$self->{rack}->add_tile($tile) if $tile;
		}
	}
	else {
		my $letter = $board_tile->get();
		my $new_node = $node->get_child($letter);
		if ($new_node) {
			$self->extend_right(
				$partial_word . $letter, 
				$new_node,
				$restrictions,
				$i + 1,
				$j,
			);
		}
	}
}

# Cross-checks. Returns a hashref of
# {'i,j' => arrayref of allowed letters}
# where "allowed letters" is an arrayref of letters that can be placed
# in the space at i,j to create a legal word vertically.
# An empty arrayref means any tile is allowed.
sub get_restrictions {
	my ($self) = @_;
	
	my $letters = Tile::get_allowed_letters();
	my %restrictions;
	
	$self->{board}->foreach_space(sub {
		my ($space, $i, $j) = @_;
		my $index = "$i,$j";
		
		# No need to calculate restrictions if this space has a tile.
		if ($space->get_tile()) {
			$restrictions{$index} = [];
			return;
		}
		
		my $top_tiles = $self->{board}->get_tiles_in_direction($i, $j, 0, -1);
		my $top_letters = join('', map {$_->get()} @$top_tiles);
		my $bottom_tiles = $self->{board}->get_tiles_in_direction($i, $j, 0, 1);
		my $bottom_letters = join('', map {$_->get()} @$bottom_tiles);
		
		if (length($top_letters.$bottom_letters) > 0) {
			# Cycle through all the valid letters to see which ones make a valid
			# word with the adjacent tiles
			
			my @restriction;
			for my $letter (@$letters) {
				if ($self->{library}->is_tree_word($top_letters.$letter.$bottom_letters)) {
					push (@restriction, $letter);
				}
			}
			
			$restrictions{$index} = \@restriction;
		}
		else {
			# There are no tiles vertically adjacent to this space, so there are no restrictions.
			$restrictions{$index} = [];
		}
	});
	
	return \%restrictions;
}

# Returns 1 if $letter is OK to place at $i, $j, give $restrictions as generated 
# by get_restrictions. 
sub passes_restrictions {
	my ($letter, $restrictions, $i, $j) = @_;
	
	return 1 if $letter eq '*';
	
	my $restriction = $restrictions->{"$i,$j"};
	return 1 unless $restriction;
	
	for my $allowed (@$restriction) {
		return 1 if $allowed eq $letter;
	}
	
	return 0;
}

# Returns hashref of {"$i,$j" => Space} for each space that is adjacent to at least one other tile
# and is itself empty;
sub get_anchors {
	my ($self) = @_;
	
	my %anchors;
	$self->{board}->foreach_space(sub {
		my ($space, $i, $j) = @_;
		
		# This space can't be an anchor because it isn't empty.
		return if $space->get_tile();
		
		my $neighbors = $self->{board}->adjacent_spaces($i, $j);
		for my $neighbor (@$neighbors) {
			if ($neighbor->get_tile()) {
				$anchors{"$i,$j"} = $space;
				last;
			}
		}
	});
	
	# If at this point we have no anchors, that means there are no tiles on the board. So make
	# the middle space on the board an anchor
	$anchors{'7,7'} = $self->{board}->get_space(7, 7) unless keys %anchors;
	
	return \%anchors;
}

1;
