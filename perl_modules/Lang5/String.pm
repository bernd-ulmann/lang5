package Lang5::String;

use strict;
use warnings;

use overload
    '""'  => sub { ${$_[0]} },
    'cmp' => sub {
        no warnings qw/uninitialized/;
        my($l, $r, $s) = @_;
        $l = $$l if ref($l);
        $r = $$r if ref($r);
        $s ? $l cmp $r : $r cmp $l;
    },
    '<=>' => sub {
        no warnings qw/uninitialized/;
        my($l, $r, $s) = @_;
        $l = $$l if ref($l);
        $r = $$r if ref($r);
        $s ? $l <=> $r : $r <=> $l;
    },
;

use Carp;

sub new {
    my($class, $val) = @_;

    croak "cannot bless reference"
        if ref($val);

    bless \$val, $class;
}

1;
