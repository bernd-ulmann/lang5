use strict;
use warnings;

use Test::More;
use lib '../perl_modules/';

BEGIN { use_ok( 'Lang5' ); }

my $obj;
my $err;
my $txt;

my @tests = (
    sub {
        $obj = Lang5->new(
            log_level      => 'ERROR',
            libautoload    => 0,
        );

        is( ref($obj), 'Lang5', 'constructor without libraries');
    },
    sub {
        my $s = addexec('42');
        is_deeply( $s, [42], 'put value onto stack');
    },
    sub {
        my $s = addexec('.');
        is_deeply( $s, [], 'output value with . a) empty stack');
    },
    sub {
        like( $txt, qr/^\s*42\s*$/, 'output value with . b) check output');
    },
);

plan(tests => scalar(@tests) + 1);

$_->() for @tests;

sub addexec {
    $obj->add_source_line($_) for @_;
    $obj->execute();
    if ( $obj->error() ) {
        $err = $obj->last_error();
        return;
    }
    $txt = join('', $obj->get_text());
    return $obj->get_stack();
}
