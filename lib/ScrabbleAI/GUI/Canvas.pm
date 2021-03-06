##########################################################################
# ScrabbleAI::GUI::Canvas
# GUI element that draws the tiles, the board, and the player's rack.
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

package ScrabbleAI::GUI::Canvas;

use strict;
use warnings;

use Gtk2 '-init';

use base qw(Gnome2::Canvas);

use ScrabbleAI::Backend::Move;
use ScrabbleAI::GUI::Board;
use ScrabbleAI::GUI::Rack;

use Data::Dumper;

sub new {
	my ($class, $window, $game) = @_;
	
	my $self = $class->SUPER::new();
	bless($self, $class);
	
	$self->{game} = $game;
	$self->{window} = $window;
	$self->{side} = 0;
	$self->{dragging} = undef;
	$self->{selected_blank_tile} = undef;
	$self->{disabled} = 0;
	$self->{replace_tiles} = 0;
	
	$self->set_center_scroll_region(0);
	
	my $white = Gtk2::Gdk::Color->new(0xFFFF, 0xFFFF, 0xFFFF);
	$self->modify_bg('normal', $white);
	
	my $root = $self->root();
	$self->{root} = $root;
	
	# Event that handles drawing the board whenever the canvas is resized
	$self->signal_connect(expose_event => sub {
		if ($self->{prevent_expose_event}) {
			$self->{prevent_expose_event} = 0;
			return 0;
		}

		$self->draw();
		return 0;
	});

	$self->signal_connect(button_press_event => \&_handle_press, $self);
	$self->signal_connect(motion_notify_event => \&_handle_drag, $self);
	$self->signal_connect(button_release_event => \&_handle_release, $self);

	$self->next_turn();

	return $self;
}

# Makes it so clicking on the canvas has no effect (tiles can't be dragged around)
sub set_disabled {
	my ($self, $disabled) = @_;

	$self->{disabled} = $disabled;
}

# Calling this puts the canvas into "Replace Tiles" mode, wher the user is prompted
# to click on tile(s) in their rack that they want to replace with different tiles
# from the bag. Calling this a second time makes the replacement actually happen.
sub replace_tiles {
	my ($self) = @_;

	if (!$self->{replace_tiles}) {
		$self->return_tiles_to_rack();
		$self->{replace_tiles} = 1;
		$self->{tile_list} = [];
	}
	else {
		$self->end_replace_tiles();
	}
}

# Calling this ends "Replace Tiles" mode (see replace_tiles)
sub end_replace_tiles {
	my ($self) = @_;

	my @tiles = @{$self->{tile_list}};
	if (scalar @tiles) {
		# Commit the rack with the newly missing tiles
		$self->{rack}->commit();

		# Advance to the next turn, which fills the player's rack with new tiles
		$self->next_turn();

		# Put the tiles back into the bag
		for my $tile (@tiles) {
			$self->{game}->get_bag()->add($tile);
		}
		$self->{window}->refresh_gameinfo();

		# Make an AI move.
		$self->{window}->set_status(sprintf("You have replaced %d tiles. Making AI move...", scalar @tiles));
		$self->{window}->make_ai_move();
	}
	else {
		$self->{window}->set_status("Tile replacement canceled.");
	}

	$self->{window}->set_disabled(0);
	$self->{replace_tiles} = 0;
	$self->{tile_list} = [];
}

# OnMouseDown callback
sub _handle_press {
	my ($widget, $event, $canvas) = @_;

	return 1 if $canvas->{disabled};

	my ($x, $y) = $event->get_coords();
	my $item = $canvas->get_item_at($x, $y);
	return 1 unless $item;

	my $group = $canvas->get_item_at($x, $y)->parent();
	if ($group->isa('ScrabbleAI::GUI::Tile')) {		# The user clicked on a tile
		my $tile = $group;
		my $space = $tile->parent();
		if ($canvas->{replace_tiles} && $event->button() == 1) {
			# We are replacing tiles, so delete the clicked tiles and store them
			if (!$tile->get_tile()->is_on_board()) {
				push(@{$canvas->{tile_list}}, $tile->get_tile());
				$space->remove_tile();
				$tile->destroy();

				# If we've gotten the maximum number of tiles to replace (i.e., the
				# number of tiles left in the bag), end tile replacement.
				if (@{$canvas->{tile_list}} >= $canvas->{game}->bag_count()) {
					$canvas->end_replace_tiles();
				}
			}
		}
		elsif (!$canvas->{dragging}) {
			if ($event->button() == 1) {
				# Left click; initiate tile dragging if no tile is currently being dragged.
				if (!$tile->get_tile()->is_on_board()) {
					$tile->reparent($canvas->root);
					$tile->set(x => $x - $canvas->{side}/2, y => $y - $canvas->{side}/2);
					$tile->draw($canvas->{side});

					$canvas->{dragging} = {
						tile => $tile,
						source => $space,
						draw_count => 0,
					};
				}
			}
			elsif ($event->button() == 3) {
				# Right click. Check if it's a blank tile, and if so, allow user to set its letter.
				if ($tile->get_tile()->is_blank() && !$tile->get_tile()->is_on_board()) {
					$canvas->{window}->set_status("Type a letter to set for this blank tile.");
					$canvas->{selected_blank_tile} = $tile;
				}
			}
		}
	}

	return 1;
}

# Callback for mouse movement. If the user is dragging a tile (and the canvas is not disabled),
# handles redrawing the dragged tile at the cursor's location.
sub _handle_drag {
	my ($widget, $event, $canvas) = @_;

	return 1 if $canvas->{disabled};

	my ($x, $y) = $event->get_coords();
	if ($canvas->{dragging}) {
		my $tile = $canvas->{dragging}{tile};

		$tile->set(x => $x - $canvas->{side}/2, y => $y - $canvas->{side}/2);
		$canvas->{dragging}->{draw_count} = 0;
		$tile->draw($canvas->{side});
	}

	return 1;
}

# OnMouseUp callback
sub _handle_release {
	my ($widget, $event, $canvas) = @_;

	return 1 if $canvas->{disabled};

	if ($canvas->{dragging}) {
		# The user was dragging a tile. If this release happens above an empty space, we want to put the
		# tile there; otherwise, return the tile to the space it came from.
		my $tile = $canvas->{dragging}{tile};
		my $source = $canvas->{dragging}{source};

		# HACK: temporarily hide the tile being dragged so we can get what's underneath.
		$tile->hide();

		my ($x, $y) = $event->get_coords();
		my $item = $canvas->get_item_at($x, $y);
		my $drop_success = 0;
		if ($item) {
			my $group = $canvas->get_item_at($x, $y)->parent();
			if ($group->isa('ScrabbleAI::GUI::Space')) {
				my $space = $group;
				$tile->reparent($space);
				$source->remove_tile();
				$space->set_tile($tile);

				# Same reasoning as in _handle_press.
				my @coords = $space->get_coords();
				if (@coords) {
					$canvas->{move}->add(@coords, $tile->get_tile());
				}

				# Only spaces on the board will have coordinates. If we're removing a tile from
				# a space on the board, we want to also remove that space from the move that we're
				# creating. Similarly, if we've moved the tile into a board space, we want to add
				# that to the move.
				my @new_coords = $space->get_coords();
				my @source_coords = $source->get_coords();
				$canvas->{move}->remove(@source_coords) if @source_coords;
				$canvas->{move}->add(@new_coords, $tile->get_tile()) if @new_coords;

				$drop_success = 1;
			}
		}

		unless ($drop_success) {
			$tile->reparent($source);
		}

		$tile->set(x => 0, y => 0);

		$canvas->{dragging} = undef;
		$tile->show();
		$canvas->draw();
	}

	return 1;
}

# Returns the tiles the user has placed on the board this turn to their rack.
sub return_tiles_to_rack {
	my ($self) = @_;

	$self->{board}->foreach_space(sub {
		my ($space, $i, $j) = @_;

		if ($space->has_tile() && !$space->get_tile()->is_committed()) {
			my $tile = $space->get_tile();
			my $rack_space = $self->{rack}->get_first_empty_space();

			$tile->reparent($rack_space);
			$space->remove_tile();
			$rack_space->set_tile($tile);

			$self->{move}->remove($i, $j);
		}
	});
}

# Refreshes the players' racks and continues onto the next turn
sub next_turn {
	my ($self) = @_;

	$self->{game}->next_turn();
	$self->{move} = ScrabbleAI::Backend::Move->new($self->{game}->get_board());

	if ($self->{rack}) {
		$self->{rack}->refresh();
	}
}

# Returns value: (x, y), the dimensions of the canvas in pixels
sub get_dimensions {
	my ($self) = @_;

	my $allocation = $self->allocation();
	return ($allocation->width(), $allocation->height());
}

# This gets called when the user presses the "Make Move" button
sub make_move {
	my ($self) = @_;

	delete $self->{selected_blank_tile};

	# Don't allow the move if it contains a blank tile that hasn't been set.
	if ($self->{move}->contains_unset_blank()) {
		$self->{window}->set_status("Please right-click the blank tile to set its letter.");
		return;
	}

	# Check if all the words formed by this move are valid
	my $invalid_word = '';
	my @words = @{$self->{move}->get_words()};
	for my $word (@words) {
		unless ($self->{game}{library}->is_legal_word($word)) {
			$invalid_word = $word;
			last;
		}
	}

	if (scalar @words == 0) {
		$self->{window}->set_status("That is not a legal move!");
	}
	elsif ($invalid_word) {
		$self->{window}->set_status("\"$invalid_word\" is not a valid word.");
	}
	else {
		my $score = $self->{move}->evaluate();
		$self->{window}->set_status("You have played \"$words[0]\" for $score points. Making AI move...");
		$self->{game}->get_player()->increment_score($score);

		$self->{board}->commit_spaces();
		$self->{rack}->commit();

		$self->next_turn();
		$self->{window}->refresh_gameinfo();

		$self->{window}->make_ai_move();
	}
}

# Refreshes the canvas and all elements therein.
sub draw {
	my ($self) = @_;

	# If the user is dragging a tile, we want to skip the redraw. Perl GTK spams lots of
	# unnecessary redraws that slow the user interface to a crawl if we don't do this.
	if ($self->{dragging}) {
		$self->{dragging}->{draw_count}++;
		return if $self->{dragging}->{draw_count} >= 1;
	}

	my ($w, $h) = $self->get_dimensions();

	# Margin to leave at the sides of the canvas, in pixels
	my $margin = 10;

	# Space between various elements, in pixels
	my $space = 10;

	# Padding on some elements, like the rack
	my $padding = 5;

	# Tile side length vertically
	my $side_vert = ($h - (2*$margin + 2*$padding + $space)) / 16;	# There has to be room for 16 tiles vertically (board + rack)

	# Tile side length horizontally
	my $side_horiz = ($w - 2*$margin) / 15;	# There has to be room for 15 tiles horizontally (just the board)

	# We want the side length to be whichever of the above measurements is less, so that
	# the board doesn't spill off screen in the other dimension.
	my $side = $side_horiz <= $side_vert ? $side_horiz : $side_vert;
	$self->{side} = $side;

	# The dimensions of the play area. The rest of the area outside of this is just whitespace, depending
	# on the dimensions of the window.
	my $area_w = 15*$side + 2*$margin;
	my $area_h = 16*$side + 2*$margin + 2*$padding + $space;

	# Now we want to figure out $x and $y, the coordinates of the upper left corner of the board, such that
	# the board is centered.
	my ($x, $y);
	if ($side_horiz >= $side_vert) {
		# The window is sized such that there is more whitespace horizontally.
		$y = $margin;
		$x = ($w - $area_w) / 2 + $margin;
	}
	else {
		# There is more whitespace vertically
		$x = $margin;
		$y = ($h - $area_h) / 2 + $margin;
	}

	my %coords = (
		x => $x,
		y => $y,
	);

	if ($self->{board}) {
		$self->{board}->set(%coords);
	}
	else {
		my $board = ScrabbleAI::GUI::Board->new(
			$self->{game}->get_board(),
			$self->{root},
			'Gnome2::Canvas::Group',
			%coords,
		);
		$self->{board} = $board;
	}

	$self->{board}->draw($side);

	# Draw the player's visible rack
	my $rack = $self->{game}->get_player()->get_rack();
	unless ($self->{rack}) {
		$self->{rack} = ScrabbleAI::GUI::Rack->new($self->{root}, $rack);
	}

	$self->{rack}->draw($x, $y + 15*$side + $space, $side, $padding);

	$self->{prevent_expose_event} = 1;
}

1;
