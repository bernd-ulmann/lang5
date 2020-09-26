use strict;
use warnings;

use Data::Dumper;
 $Data::Dumper::Indent  = 0;

use Test::More;
use Storable qw/dclone/;
use File::Spec::Functions;
use FindBin qw/$Bin/;
use lib catfile($Bin, '../perl_modules');

BEGIN { use_ok( 'Array::DeepUtils', qw/:all/ ) }

my $a1  = [[1,2,3], [4,5,6], [7,8,9]];
my $a2  = [1,2,3,4,5,6,7,8,9];
my $a3  = [[1,0], [1,1], [2,0], [2,1]];
my $a4  = [[0,0], [0,1], [1,0], [1,1]];
my $a5  = [4,5,7,8];
my $a6  = [[2,3], [5,6], [8,9]];
my $a7  = [[1,2,3], [4,6], [7,8,9]];
my $a8  = [[1,1], [2,0]];
my $a9  = [2, 6, [7,8,9]];
my $a10 = [[1,2,3],4,[5,[6,7,8,[9,0]]]];
my $a11 = [3,3,4,2];
my $a12 = [[1,2,3],4,[5,6],[7,8,9]];
my $a13 = [[1,2,3],[0,0,0],[5,6,0],[7,8,9]];
my $a14 = [1,0,2,0,3,[1,0,3]];
my $a15 = [1,0,2,0,3,[0,1,0]];
my $a16 = [[11,12], [13,14]];
my $a17 = [1, -1];
my $a18 = [[11,24,3], [52,70,-6], [7,-8,9]];
my $a19 = [[1,2,3], [7,8,9]];
my $a20 = [[1,3],[4,5]];
my $a21 = [[1,0], [2,1]];
my $a22 = [[9,7,8],[3,1,2],[6,4,5]];
my $a23 = [[1,2],[3,4]];
my $a24 = [[[0,0],[0,2]],[[1,0],[1,1]]];
my $a25 = [[8,9,7],[2,3,1],[5,6,4]];
my $a26 = [[1,4,7],[2,5,8],[3,6,9]];

my(@s, @d, @v);
my @tests = (

    sub {
        my $c = collapse($a1);
        is_deeply($c, $a2, 'collapse');
    },

    sub {
        my $iterator = vector_iterator([1,0], [2,1]);

        while ( my($svec, $dvec) = $iterator->() ) {
            push @s, $svec;
            push @d, $dvec;
            push @v, value_by_path($a1, $svec);
        }

        is_deeply([\@s, \@d], [$a3, $a4], 'vector_iterator forwards');
    },

    sub {

        @s = @d = ();
        my $iterator = vector_iterator([2,1], [1,0]);

        while ( my($svec, $dvec) = $iterator->() ) {
            push @s, $svec;
            push @d, $dvec;
        }

        is_deeply([[reverse @s], \@d], [$a3, $a4], 'vector_iterator backwards');
    },

    sub {
        is_deeply(\@v, $a5, 'value_by_path');
    },

    sub {
        my $c = dcopy($a1, [[0,1], [2,2]]);

        is_deeply($c, $a6, 'dcopy');
    },

    sub {
        my $c = dclone($a1);

        purge($c, '5');

        is_deeply($c, $a7, 'purge');
    },

    sub {
        my $c = dclone($a1);

        remove($c, 1);

        is_deeply($c, $a19, 'remove 1');
    },

    sub {
        my $c = dclone($a3);

        remove($c, [0,3]);

        is_deeply($c, $a8, 'remove 2');
    },

    sub {
        my $c = dclone($a1);

        remove($c, [[0,1], [1,2], 2]);

        is_deeply($c, $a20, 'remove 3');
    },

    sub {
        my $c = dclone($a1);

        my $s = subscript($c, 1);

        is_deeply($s, [[4,5,6]], 'subscript 1');
    },

    sub {
        my $c = dclone($a3);

        my $s = subscript($c, [0,3]);

        is_deeply($s, $a21, 'subscript 2');
    },

    sub {
        my $c = dclone($a1);

        my $s = subscript($a1, [[0,1], [1,2], 2]);

        is_deeply($s, $a9, 'subscript 3');
    },

    sub {
        my $c = shape($a10);

        is_deeply($c, $a11, 'shape');
    },

    sub {
        my $c = dclone($a12);
        my $s = shape($c);

        my $r = reshape($c, $s, [0]);

        is_deeply($r, $a13, 'reshape');
    },

    sub {
        my $c = dclone($a14);

        unary($c, sub { ! $_[0] + 0 });

        is_deeply($c, $a15, 'unary');
    },

    sub {
        my $c = dclone($a1);

        binary($a16, $c, sub { $_[0] * $_[1] }, 1, undef, $a17);

        is_deeply($c, $a18, 'binary');
    },

    sub {
        my $x = dclone($a2);

        my $y = reshape($x, [3,3,3,3], $a2);

        my $z = dcopy($y, [[1,1,1,1],[2,2,2,2]]);

        my $c = reshape([], [2,2], collapse($z));

        is_deeply($c, [[5,6],[8,9]], 'combined');
    },

    sub {
        my $x = dclone($a1);

        my $y = rotate($x, [1,1]);

        is_deeply($y, $a22, 'rotate');
    },

    sub {
        my $y = scatter($a2, $a4);

        is_deeply($y, $a23, 'scatter');
    },

    sub {
        my $y = idx($a20, $a1);

        is_deeply($y, $a24, 'idx');
    },

    sub {
        my $y = rotate($a1, $a17);

        is_deeply($y, $a25, 'rotate');
    },

    sub {
        my $y = transpose($a1, 1);

        is_deeply($y, $a26, 'transpose');
    },
);

die "using module Array::DeepUtils failed\n"
    unless $Array::DeepUtils::VERSION;

plan(tests => scalar(@tests) + 1);

$_->() for @tests;
