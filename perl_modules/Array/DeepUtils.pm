package Array::DeepUtils;

use strict;
use warnings;

use Carp;
use Storable qw/dclone/;

require Exporter;
our @ISA         = qw(Exporter);
our @EXPORT_OK   = qw/
    binary collapse dcopy idx
    purge remove reshape rotate scatter shape subscript
    transpose unary value_by_path vector_iterator
/;
our %EXPORT_TAGS = (
    'all' => [ @EXPORT_OK ],
);

our $VERSION   = 0.2;
our $DEBUG     = 0;
our $LastError = '';

my $NaV = bless(\my $dummy, 'NaV');


=pod

=head1 NAME

Array::DeepUtils - utilities for the manipulation of nested arrays

=head1 VERSION

This document refers to version 0.2 of Array::DeepUtils

=head1 SYNOPSIS


    use Array::DeepUtils qw/:all/;

    binary(
        [1,2,3,4,5,6,7,8],
        [[1,1][2,2][3,3][4,4]],
        sub { $_[0] + $_[1] }
    );

yields:

    [
      [    2,     3  ],
      [    5,     6  ],
      [    8,     9  ],
      [   11,    12  ],
    ]

A more complex example:

  my $x = [1..9];

  my $y = reshape($x, [3,3,3,3], $x);

$y is now:

  [
   [
    [[1,2,3],[4,5,6],[7,8,9]],
    [[1,2,3],[4,5,6],[7,8,9]],
    [[1,2,3],[4,5,6],[7,8,9]],
   ],
   [
    [[1,2,3],[4,5,6],[7,8,9]],
    [[1,2,3],[4,5,6],[7,8,9]],
    [[1,2,3],[4,5,6],[7,8,9]],
   ],
   [
    [[1,2,3],[4,5,6],[7,8,9]],
    [[1,2,3],[4,5,6],[7,8,9]],
    [[1,2,3],[4,5,6],[7,8,9]],
   ]
  ];


  my $z = dcopy($y, [[1,1,1,1],[2,2,2,2]]);

$z is now:

  [
   [
    [[5,6],[8,9]],
    [[5,6],[8,9]],
   ],
   [
    [[5,6],[8,9]],
    [[5,6],[8,9]],
   ]
  ];

  my $c = reshape([], [2,2], collapse($z));

resulting in $c being:

  [[5,6],[8,9]]


=head1 DESCRIPTION

This module is a collection of subroutines for the manipulation of
deeply nested arrays. It provides routines for iterating along
coordinates and for setting, retrieving and deleting values.
The functions binary and unary are provided for applying arbitrary
operators as code references to deeply nested arrays. With shape() and
reshape() there are methods to determine and change the dimensions.

By default nothing is exported. The subroutines can be imported all at
once via the ':all' tag.

=head2 Subroutine short description

L</"binary()"> - appply a binary operator between two nested arrays

L</"collapse()"> - flatten a nested array to a one dimensional vector

L</"dcopy()"> - extract part of a nested array between two vectors

L</"idx()"> - build an index vector for values of another vector

L</"purge()"> - remove elements by value from a nested array

L</"remove()"> - remove elements by index

L</"reshape()"> - transform nested array by dimension vector

L</"rotate()"> - rotate a data structure along its axes

L</"scatter()"> - build a new data structure with data and index vector.

L</"shape()"> - get nested array dimension vector

L</"subscript()"> - extract nested array values by index vector

L</"transpose()"> - transpose a nested array

L</"unary()"> - appply a unary operator to all values of a nested array

L</"value_by_path()"> - extract nested array values by coordinate vector

L</"vector_iterator()"> - creates a subroutine for iterating between two coordinates

=cut


=pod

=head1 SUBROUTINES

=head2 binary()

B<binary($aref1, $aref2, $subref, $neutral_element [, $object, $fill_aref])>

Recursively apply a binary operator represented by a subroutine
reference to all elements of two nested data structures given in $aref1
and $aref2 and set the resulting values in $aref2. $aref2 will also be
returned.

If these structures differ in shape they will be reshaped according to
the larger structure. The value of $neutral_element will be used if one
of the operands is undefined or does not exist ($neutral_element can
also be a subroutine reference; it will be called on value retrieval and
given $aref1 respectively $aref2 as only parameter). To be able to use
methods as subroutines $object will be passed to the subroutine as first
parameter when specified. Since binary() calls reshape() a given
$fill_aref will be passed as the third parameter to reshape().

A simple example, after:

 my $v1   = [1,2,3];
 my $v2   = [9,8,7];
 my $func = sub { $_[0] * $_[1] }
 binary($v1, $v2, $func);

$v2 will have a value of

 [9, 16, 21]

Making it a bit more complicated:

 my $v1   = [1,2,3,4,5,6];
 my $v2   = [9,8,7];
 my $func = sub { $_[0] * $_[1] }
 binary($v1, $v2, $func);

results in:

 [9,16,21,36,40,42]

because missing values will be filled with the flattened structure
repeated as often as it is needed, so the above is exactly the same as:

 my $v1   = [1,2,3,4,5,6];
 my $v2   = [9,8,7,9,8,7];
 my $func = sub { $_[0] * $_[1] }
 binary($v1, $v2, $func);

Using the fill parameter gives the opportunity to assign the values
used for filling. It will also be repeated when necessary.

 my $v1   = [1,2,3,4,5,6];
 my $v2   = [9,8,7];
 my $fill = [1,2];
 my $func = sub { $_[0] * $_[1] };
 binary($v1, $v2, $func, 1, undef, $fill);

results in:

 [9,16,21,4,10,6];

because $v2 will have been reshaped to [9,8,7,1,2,1] before the
multiplication.

This works for vectors of arbitrary depth, so that:

 my $v1   = [[1,2,3], [4,5,6], [7,8,9]];
 my $v2   = [[11,12], [13,14]];
 my $fill = [1, -1];
 my $func = sub { $_[0] * $_[1] };
 binary($v1, $v2, $func, 1, undef, $fill);

yields:

 [[11,24,3], [52,70,-6], [7,-8,9]]

=cut

sub binary {
    my($func, $neutral, $obj, $fill) = @_[2..5];

    # param checks
    croak $LastError = 'binary: not a code ref'
        unless ref($func) eq 'CODE';
    croak $LastError = 'binary: not an object'
        if $obj and !ref($obj);

    # determine the "bigger" vector
    # (run 'shape '* reduce' and compare)
    my @dims;
    my @inner;
    for my $i ( 0 .. 1 ) {
        $dims[$i]   = shape($_[$i]);
        $dims[$i]   = [1] unless @{ $dims[$i] };
        $inner[$i]  = 1;
        $inner[$i] *= $_ for @{ $dims[$i] };
    }

    my $reshape_dim = $inner[0] >= $inner[1] ? $dims[0] : $dims[1];

    # reshape both with reshape_dim vector
    for my $i ( 0 .. 1 ) {
        $_[$i] = [$_[$i]] unless ref($_[$i]) eq 'ARRAY';
        $_[$i] = reshape($_[$i], $reshape_dim, $fill ? $fill : ());
    }

    # create start and end vector
    my $start = [ map { 0      } @$reshape_dim ];
    my $end   = [ map { $_ - 1 } @$reshape_dim ];

    # shortcut for empty arrays
    if ( !@$start or !@$end ) {
        $_[1] = [];
        return $_[1];
    }

    # iterate over the arrays, call function and store
    # the value in second array
    my $iterator = vector_iterator($start, $end);

    while ( my ($vec) = $iterator->() ) {

        # get values with value_by_path()
        my @vals;
        for my $i ( 0 .. 1 ) {
            $vals[$i] = value_by_path($_[$i], $vec);
            $vals[$i] = (ref($neutral) eq 'CODE' ? $neutral->($_[$i]) : $neutral)
                if !defined($vals[$i]) or ref($vals[$i]) eq 'NaV';
        }

        # call fuction and set value
        value_by_path(
            $_[1],
            $vec,
            $func->($obj ? ($obj, @vals) : @vals),
        );
    }

    return $_[1];
}


=pod

=head2 collapse()

B<collapse($aref1)>

Collapse the referenced array of arrays of arbitrary depth, i.e
flatten it to a simple array and return a reference to it.

Example:

 collapse([[1,2,3],4,[5,[6,7,8,[9,0]]]]);

will return:

 [1,2,3,4,5,6,7,8,9,0]

=cut

sub collapse {
    my($struct) = @_;

    croak $LastError = 'collapse: not an array reference'
        unless ref($struct) eq 'ARRAY';

    my @result;

    # simply travel the array iteratively and store
    # every value in @result

    # element and index stack
    my @estack = ( $struct );
    my @istack = ( 0 );

    while ( @estack ) {

        # always opereate on the top of the stacks
        my $e = $estack[-1];
        my $i = $istack[-1];

        if ( $i <= $#$e  ) {

            # in currrent array, if value is array ref
            # push next reference and a new index onto stacks
            if ( ref($e->[$i]) eq 'ARRAY' ) {
                push @estack, $e->[$i];
                push @istack, 0;
                next;
            }

            # push value into result array
            push @result, $e->[$i];
        }

        # after last item, pop last item and last index from stacks
        if ( $i >= $#$e ) {
            pop @estack;
            pop @istack;
        }

        # increment index for next fetch
        $istack[-1]++ if @istack;
    }

    return \@result;
}


=pod

=head2 dcopy()

B<dcopy($aref, $coord_aref)>

Extract a part of an deeply nested array between two vectors given in
the array referenced by $coord_ref. This is done via an iterator
generated with vector_iterator() running from the first to the second
coordinate given.

Example:

 dcopy([[1,2,3], [4,5,6], [7,8,9]], [[1,0], [2,1]]);

will return

  [ [4,5], [7,8] ]

This will work in either direction, so:

 dcopy([[1,2,3], [4,5,6], [7,8,9]], [[2,1], [1,0]]);

will give:

  [ [8,7], [5,4] ]

as expected.

=cut

sub dcopy {
    my($struct, $coord) = @_;

    # param checks
    croak $LastError = 'dcopy: not an array ref'
        unless ref($struct) eq 'ARRAY' and ref($coord) eq 'ARRAY';

    croak $LastError = 'dcopy: coordinate vector with element count != 2!'
        unless @$coord == 2;

    croak $LastError = 'dcopy: coordinate vector elements have different length!'
        unless @{$coord->[0]} == @{$coord->[1]};

    # simply iterate and set values in $dest
    my $iterator = vector_iterator(
        ref($coord->[0]) eq 'ARRAY' ? $coord->[0] : [$coord->[0]],
        ref($coord->[1]) eq 'ARRAY' ? $coord->[1] : [$coord->[1]]
    );
    my $dest = [];
    while ( my ($svec, $dvec) = $iterator->() ) {
        value_by_path(
            $dest,
            $dvec,
            value_by_path($struct, $svec)
        );
    }

    return $dest;
}


=pod

=head2 idx()

B<idx($aref1, $aref2)>

Return an index vector that contains the indices of the elements of the
first argument vector with respect to the second index vector.

Example:

 idx([[1,3],[4,5]], [[1,2,3], [4,5,6], [7,8,9]]);

will return:

 [[[0,0],[0,2]],[[1,0],[1,1]]]

=cut

sub idx {
    my ($aref1, $aref2) = @_;

    # param checks
    croak $LastError = 'idx: not an array ref'
        unless ref($aref1) eq 'ARRAY' and ref($aref2) eq 'ARRAY';

    my ($dim1, $dim2) = (shape($aref1), shape($aref2));
    my ($start1, $end1) = ([ map { 0 } @$dim1 ], [ map { $_ - 1 } @$dim1 ]);
    my ($start2, $end2) = ([ map { 0 } @$dim2 ], [ map { $_ - 1 } @$dim2 ]);
    my ($iterator1, $iterator2) = (vector_iterator($start1, $end1),
                                   vector_iterator($start2, $end2));

    return [] unless scalar @$aref1;

    # Create a hash with indices of the elements of $aref2, making sure
    # that multiple occurrences of an element don't destroy the first
    # index of this element:
    my %lookup;
    while ( my($index) = $iterator2->() ) {
        my $value = value_by_path($aref2, $index);
        $lookup{$value} = $index if $value and !$lookup{$value};
    }

    # Now lookup every single element from $aref1 in the lookup hash:
    while ( my($index) = $iterator1->() ) {
        my $position = $lookup{value_by_path($aref1, $index)};
        value_by_path($aref1, $index, $position ? $position : []);
    }

    return $aref1;
}


=pod

=head2 purge()

B<purge($aref, $what)>

Remove all values from the array referenced by $aref that equal $what in
a string comparison.

Example:

 $v = [1,0,1,0,1,0,1,0];
 purge($v, '0');

will have $v reduced to:

 [1,1,1,1]

=cut

sub purge {
    my $what = pop;

    croak $LastError = 'purge: not an array ref'
        unless ref($_[0]) eq 'ARRAY';

    my @estack = ($_[0]);
    my @istack = ( $#{ $estack[-1] } );

    while ( @estack ) {

        my $e = $estack[-1];
        my $i = $istack[-1];

        if ( $i >= 0  ) {

            # push next reference and a new index onto stacks
            if ( ref($e->[$i]) eq 'ARRAY' ) {
                push @estack, $e->[$i];
                push @istack, $#{ $e->[$i] };
                next;
            }

            splice(@$e, $i, 1) if $e->[$i] eq $what;

        } else {

            pop @estack;
            pop @istack;

        }

        $istack[-1]-- if @istack;

    }
}


=pod

=head2 remove()

B<remove($aref, $index|$coordinate_aref)>

Remove all values with indices or coordinates given by $index or by the
array referenced by $coordinate_aref from an array referenced by $aref.

Example:

 my $v = [1,2,3,4,5,6,7,8,9,0];
 remove($v, [1,2,3]);

will have $v reduced to:

 [1,5,6,7,8,9,0]

and:

 my $aref = [[1,2,3],[4,5,6],[7,8,9]];

 remove($aref, [[0,1], [1,2], 2]);

will leave:

 [[1,3],[4,5]]

in $aref.

=cut

sub remove {
    my $coords = pop;

    croak $LastError = 'remove: not an array ref'
        unless ref($_[0]) eq 'ARRAY';

    $coords = [$coords]
        unless ref($coords) eq 'ARRAY';

    for ( @$coords ) {
        $_ = [$_] unless ref($_) eq 'ARRAY';
        value_by_path($_[0], $_, $NaV)
            unless ref(value_by_path($_[0], $_)) eq 'NaV';
    }

    purge($_[0], $NaV);
}


=pod

=head2 reshape()

B<reshape($aref, $dims_aref [, $fill_aref])>

Create an array with the dimension vector given in $dims_aref and take
the values from $aref provided there is a value at the given position.
Additional values will be taken from the array referenced by $fill_aref
or - if it is not provided - from a flattened (call to collapse())
version of the original array referenced by $aref. If the fill source is
exhausted, reshape will start from index 0 again. This will be repeated
until the destination array is filled.

Example:

 reshape([[1,2,3]], [3, 3]);

will return:

 [ [1,2,3], [1,2,3], [1,2,3] ]

and:

 reshape([[1,2,3]], [3, 3], ['x']);

will return:

 [ [1,2,3], ['x','x','x'], ['x','x','x'] ]

=cut

sub reshape {
    my($struct, $dims, $fill) = @_;

    if (
        ref($struct) ne 'ARRAY' or
        ref($dims)   ne 'ARRAY' or
        ( $fill and ref($fill) ne 'ARRAY' )
    ) {
        $LastError = "usage: reshape(AREF, AREF[, AREF])";
        croak $LastError;
    }

    return undef unless @$dims;
    return [] if $dims->[0] == 0;

    # get a flattened copy of the source
    $fill = collapse(dclone($struct))
        unless $fill;
    @$fill = ( undef ) unless @$fill;

    my $start = [ map { 0      } @$dims ];
    my $end   = [ map { $_ - 1 } @$dims ];

    my $iterator = vector_iterator($start, $end);

    my $i = 0;
    my $dest = [];
    while ( my ($vec) = $iterator->() ) {
        my $val = value_by_path($struct, $vec);
        value_by_path(
            $dest,
            $vec,
            ( ($val and ref($val) eq 'NaV') or ref($val) eq 'ARRAY' )
                ? $fill->[$i++ % @$fill]
                : $val,
            1,
        );
    }

    return $dest;
}


=pod

=head2 rotate()

B<rotate($aref1, $aref2 [, $fill_aref])>

Rotate a data structure along its axes. It is possible to perform more
than one rotation at once, so rotating a two dimensional matrix along
its x- and y-axes by +1 and -1 positions is no problem.

Example:

 rotate([[1, 2, 3], [4, 5, 6], [7, 8, 9]], [1, -1]);

will return:

 [[8,9,7],[2,3,1],[5,6,4]]

Using the optional third parameter it is possible to fill previously
empty array elements with a given value via L</"reshape()">.

=cut

sub rotate {
    my($struct, $rotvec, $fill) = @_;

    # param checks
    croak $LastError = 'rotate: not an array ref'
        unless ref($struct) eq 'ARRAY' and ref($rotvec) eq 'ARRAY';

    my $dim = shape($struct);

    croak "rotate: rotation vector does not fit array dimensions"
        unless @$rotvec == @$dim;

    $struct  = reshape($struct, $dim, $fill);

    my $start = [ map { 0 } @$dim ];
    my $end   = [ map { $_ - 1 } @$dim ];

    my $iterator = vector_iterator($start, $end);

    my $dest = [];
    while ( my($svec) = $iterator->() ) {
        my $dvec = [ map {
            ( $svec->[$_] + $rotvec->[$_] ) % $dim->[$_]
        } 0 .. $#$svec ];
        value_by_path($dest, $dvec, value_by_path($struct, $svec));
    }

    return $dest;
}


=pod

=head2 scatter()

B<scatter($aref, $struct)>

This function behaves inverse to subscript. While subscript selects
values from a nested data structure, controlled by an index vector,
scatter will distribute elements into a new data structure, controlled
by an index vector.

Example:

 scatter([1, 2, 3, 4, 5, 6, 7], [[0,0], [0,1], [1,0], [1,1]]);

will return:

 [[1, 2], [3, 4]]

=cut

sub scatter {
    my ($aref, $struct) = @_;

    # param checks
    croak $LastError = 'scatter: not an array ref'
        unless ref($aref) eq 'ARRAY' and ref($struct) eq 'ARRAY';

    # Make sure that the raw data to be scattered will not be exhausted
    # by the indices contained in $struct:
    my $source = reshape($aref, [scalar @$struct], $aref);

    # Built new data structure (possibly containing empty elements):
    my $result = [];
    for my $position (@$struct) {
        $position = [$position] unless ref($position) eq 'ARRAY';
        value_by_path($result, $position, shift(@$source))
            if ref($position) eq 'ARRAY' and ref($position->[0]) ne 'NaV';
    }

    return $result;
}


=pod

=head2 shape()

B<shape($aref)>

Determine the dimensions of an array and return it as
a vector (an array reference)

Example:

 shape([[1,2,3], [4,5,6], [7,8,9]]);

will return:

 [3,3]

and:

 shape([[1,2,3],4,[5,[6,7,8,[9,0]]]]);

will return:

 [3,3,4,2]

A combination of shape() and reshape() will effectively turn an
"irregular" array into a regular one.

For example:

 $aref = [[1,2,3],4,[5,6],[7,8,9]];

 reshape($aref, shape($aref), [0]);

will return:

 [[1,2,3],[0,0,0],[5,6,0],[7,8,9]]

=cut

sub shape {
    my($struct) = @_;

    return [] unless ref($struct) eq 'ARRAY';

    my @out = ( 0 );
    my @idx = ( 0 );
    my @vstack = ( $struct );

    my $depth = 0;
    while ( $depth >= 0 ) {

        # get the top reference from the stack
        my $aref = $vstack[-1];

        if ( ref($aref->[$idx[$depth]]) eq 'ARRAY') {

            # found a reference push it on the stack and increase depth
            push @vstack, $aref->[$idx[$depth++]];
            # push a new index on the index stack
            push @idx, 0;
            # initialize the counter on the new level on first entry
            $out[$depth] = 0 unless defined $out[$depth];

        } elsif ( $idx[$depth] <= $#$aref  ) {

            # no reference and we still have elements in the array
            # --> increase index for the current level
            ++$idx[$depth];

        } else {

            # reached the end of the array
            # --> remove it from the stack
            pop @vstack;

            # remove last index from the index stack
            pop @idx;

            # save the number of elements of the level
            # if it is bigger than before
            $out[$depth] = @$aref if @$aref > $out[$depth];

            # decrease the current level
            $depth--;

            # increase the index for the current level
            ++$idx[$depth] if $depth >= 0;

        }
    }

    return \@out;
}


=pod

=head2 subscript()

B<subscript($aref, $index|$coord_aref)>

Retrieve and return values of a deeply nested array for a single index a
list of indices or a list of coordinate vectors.

Example:

 my $aref = [[1,2,3],[4,5,6],[7,8,9]];

 subscript($aref, 1);

returns:

 [[4,5,6]]

whereas:

 subscript($aref, [[0,1], [1,2], 2]);

returns:

 [2,6,[7,8,9]]

=cut

sub subscript {
    my($struct, $coords) = @_;

    croak $LastError = 'subscript: not an array ref'
        unless ref($_[0]) eq 'ARRAY';

    $coords = [$coords]
        unless ref($coords) eq 'ARRAY';

    for ( @$coords ) {
        $_ = [$_] unless ref($_) eq 'ARRAY';
    }

    my @out;
    for my $position (@$coords) {
        push @out, value_by_path($struct, $position)
            if ref($position) eq 'ARRAY' and ref($position->[0]) ne 'NaV';
    }

    return \@out;
}


=pod

=head2 transpose()

B<transpose($aref1, $control [, $fill_aref])>

Transpose a nested data structure. In the easiest two-dimensional case
this is the traditional transposition operation.

Example:

 transpose([[1,2,3], [4,5,6], [7,8,9]], 1);

will return:

 [[1,4,7],[2,5,8],[3,6,9]]

Using the optional third parameter, it is possible to fill previously
empty array elements with a given value via L</"reshape()">.

=cut

sub transpose {
    my($struct, $control, $fill) = @_;

    croak $LastError = 'transpose: not an array ref'
        unless ref($struct) eq 'ARRAY';

    my $dim = shape($struct);

    $struct  = reshape($struct, $dim, $fill);

    my $start = [ map { 0 } @$dim ];
    my $end   = [ map { $_ - 1 } @$dim ];

    my $iterator = vector_iterator($start, $end);

    my $dest = [];
    while ( my($svec) = $iterator->() ) {
        my $dvec = [
            map {
                $svec->[($_ + $control) % scalar(@$svec)]
            } 0 .. $#$svec
        ];
        value_by_path($dest, $dvec, value_by_path($struct, $svec));
    }

    return $dest;
}


=pod

=head2 unary()

B<unary($aref1, $subref, $neutral_element [, $object])>

Recursively apply a unary operator represented by a subroutine
reference to all elements of a nested data structure given in $aref
and set the resulting values in the referenced array itself.
The reference will also be returned.

The value of $neutral_element will be used if the original is
undefined or does not exist. To be able to use methods as subroutines
$object will be passed to the subroutine as first parameter when
specified.

A simple example, after:

 my $v    = [1,0,2,0,3,[1,0,3]];
 my $func = sub { ! $_[0] + 0 };

 unary($v, $func);

will return:

 [1,0,2,0,3,[0,1,0]]

=cut

sub unary {
    my($func, $neutral, $obj) = @_[1..3];

    # param checks
    croak $LastError = 'unary: not a code ref'
        unless ref($func) eq 'CODE';
    croak $LastError = 'unary: not an object'
        if $obj and !ref($obj);

    return $_[0]
        if ref($_[0]) eq 'ARRAY' and @{ $_[0] } == 0;

    my $dim = shape($_[0]);

    my $start = [ map { 0      } @$dim ];
    my $end   = [ map { $_ - 1 } @$dim ];

    my $iterator = vector_iterator($start, $end);

    while ( my ($vec) = $iterator->() ) {
        my $val = value_by_path($_[0], $vec);
        value_by_path(
            $_[0],
            $vec,
            (!defined($val) or ref($val) eq 'NaV')
                ? (ref($neutral) eq 'CODE' ? $neutral->($_[0]) : $neutral)
                : $func->($obj ? ($obj, $val) : $val),
        );
    }

    return($_[0]);
}


=pod

=head2 value_by_path()

B<value_by_path($aref, $coordinate [, $value [, $force]])>

Get or set a value in a deeply nested array by a coordinate vector.

Example:

 my $vec = [[1,2,3], [4,5,6], [7,8,9]];

 value_by_path($vec, [1,1], 99);

will give:

 [[1,2,3], [4,99,6], [7,8,9]];

in $vec. This is not spectacular since one could easily write:

 $vec->[1][1] = 99;

but value_by_path() will be needed if the coordinate vector is created
dynamically and can be of arbitrary length.
If you explicitly want to set an undefined value, you have to set
$force to a true value.

When retrieving values value_by_path() will return an object of class
"NaV" when there is no scalar at the given coordinate. The object is
just a blessed scalar with an undefined value. Beware: it will always be
the same object.

=cut

sub value_by_path {
    my($aref, $coordinate, $value, $force) = @_;

    croak $LastError = 'value_by_path: not an array ref'
        unless ref($aref) eq 'ARRAY';

    my $vref = $aref;
    my $vec  = ref($coordinate) eq 'ARRAY'
             ? $coordinate
             : [$coordinate];

    my $end  = @$vec - 1;

    my $i = 0;
    while ( $i < $end ) {

        if ( defined($value) ) {
            $vref->[$vec->[$i]] = []
                unless defined($vref->[$vec->[$i]])
                       and
                       ref($vref->[$vec->[$i]]) eq 'ARRAY';
        } else {
            return $NaV unless ref($vref->[$vec->[$i]]) eq 'ARRAY';
        }

        $vref = $vref->[$vec->[$i++]];
    }

    if ( defined($value) or $force ) {
        $vref->[$vec->[$i]]
            = ref($value) eq 'ARRAY'
              ? dclone($value)
              : $value;
    } else {
        return $NaV
            if $vec->[$i] > $#$vref;
        return(
            ref($vref->[$vec->[$i]]) eq 'ARRAY'
            ? dclone($vref->[$vec->[$i]])
            : $vref->[$vec->[$i]]
        );
    }
}


=pod

=head2 vector_iterator()

B<vector_iterator($from_aref, $to_aref)>

This routine returns a subroutine reference to an iterator which
is used to generate successive coordinate vectors starting with the
coordinates in $from_aref to those in $to_aref.

The resulting subroutine will return a pair of coordinate vectors on
each successive call or an empty list if the iterator has reached the
last coordinate. The first coordinate returned is related to the given
coordinate pair, the second one to a corresponding zero based array.

Example:

 my $aref = [[1,2,3], [4,5,6], [7,8,9]];

 my $iterator = vector_iterator([0,1], [1,2]);

 while ( my($svec, $dvec) = $iterator->() ) {
   my $val = value_by_path($aref, $svec);
   print "[$svec->[0] $svec->[1]] [$dvec->[0] $dvec->[1]] -> $val\n";
 }

will print:

 [0 1] [0 0] -> 2
 [0 2] [0 1] -> 3
 [1 1] [1 0] -> 5
 [1 2] [1 1] -> 6

=cut

sub vector_iterator {
    my($from, $to) = @_;

    croak $LastError = 'value_by_path: not an array ref'
        unless ref($from) eq 'ARRAY' and ref($to) eq 'ARRAY';

    my @start    = @$from;
    my @current  = @$from;
    my @end      = @$to;
    my @dir      = map { $end[$_] <=> $start[$_]        } 0 .. $#end;
    my @diff     = map { abs($end[$_] - $start[$_]) + 1 } 0 .. $#end;
    my @dvec     = map { 0 } 0 .. $#end;

    my $end_reached = 0;

    return sub {

        return if $end_reached;

        $end_reached = 1;
        for my $i ( 0 .. $#end ) {
            $end_reached &&= $current[$i] == $end[$i];
            last unless $end_reached;
        }

        my $sretvec = [ @current ];
        my $dretvec = [ @dvec ];

        for my $i ( reverse 0 .. $#end ) {

            $current[$i] += $dir[$i];
            $dvec[$i]++;
            if ( $current[$i] == $end[$i] + $dir[$i] ) {
                $current[$i]  = $start[$i];
                $dvec[$i] = 0;
            }

            last if $current[$i] != $start[$i];
        }

        return($sretvec, $dretvec);
    };
}


=pod

=head1 SEE ALSO

Array::DeepUtils was developed during the implementation of lang5 a
stack based array language. The source will be maintained in the source
repository of lang5.

=head2 Links

=over

=item *

L<The lang5 Home Page|http://lang5.svn.sourceforge.net/>.

=item *

L<The lang5 SVN repository|https://lang5.svn.sourceforge.net/svnroot/lang5/>.

=back

=head2 Bug Reports and Feature Requests

=over

=item *

L<Bugs|https://sourceforge.net/tracker/?group_id=299543&atid=1263531>

=item *

L<Feature Requests|https://sourceforge.net/tracker/?group_id=299543&atid=1263534>

=back

=head1 AUTHOR

Thomas Kratz E<lt>tomk@cpan.orgE<gt>

Bernd Ulmann E<lt>ulmann@vaxman.deE<gt>

=head1 COPYRIGHT

Copyright (C) 2011 by Thomas Kratz, Bernd Ulmann

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself, either Perl version
5.8.8 or, at your option, any later version of Perl 5 you may
have available.

=cut

1;
