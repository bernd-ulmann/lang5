package Lang5;

use strict;
use warnings;

our $VERSION = '1.0';

use constant {
    STATE_RUN                  => 0,
    STATE_START_WORD           => 1,
    STATE_EXPAND_WORD          => 2,
    STATE_SKIP_WORD_DEFINITION => 3,
    STATE_EXECUTE_IF           => 4,
    STATE_EXECUTE_ELSE         => 5,
    STATE_IF_COMPLETED         => 6,
    STATE_EXECUTE_DO           => 7,
    STATE_BREAK_EXECUTED       => 8,
};

use POSIX qw/strftime/;
use Storable qw/dclone/;
use Array::DeepUtils qw/:all/;
use Lang5::String;
use Data::Dumper;
 $Data::Dumper::Varname = undef;
 $Data::Dumper::Indent  = 1;

my %debug_level;
my $db_level;

# Simple logging.
BEGIN {
    %debug_level = qw/TRACE 0 DEBUG 1 INFO 2 WARN 3 ERROR 4 FATAL 5/;

    for my $lev ( keys %debug_level ) {
        no strict 'refs';
        *{$lev} = sub (@) {};
    }
}

# This regular expression recognizes an integer or floating point number.
# It is used to determine if an otherwise unrecognized element read from
# stdin or a file has to be pushed onto the stack.
my %re = (
    float => qr/^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/,
    whead => qr/\S+\{\[.+?\}/,
    strob => qr/\Qbless( do{\(my \E\$o = ('.*')\Q)}, 'Lang5::String' )/,
);

# These so called published variables are used to control various things
# within the interpreter and can be handled like any other user defined
# variable with the exception that it is not possible to delete any of
# these published variables.
my %published_vars = map { $_ => 1 } qw/
    log_level terminal_width number_format
/;

# Any language element must be of one of the types defined here:
my %element_type = qw/niladic n unary u binary b function f variable v/;
my %reverse_type = reverse %element_type;
my %stack_type   = ( n => [], u => ['X'], b => ['X', 'X'] );
my %op_count     = qw/0 n 1 u 2 b/;

# Parameter checks, $_[0] contains the interpreter object, $_[1] the parameter
# to be checked.
my %param_checks = (
    A  => {
        desc => 'array',
        code => sub { return eval { @{$_[1] } + 1} },
    },
    BO => {
        desc => 'binary operator',
        code => sub {
            exists $_[0]->{_words}{$_[1]} and $_[0]->{_words}{$_[1]}{type} eq 'binary'
        },
    },
    I => {
        desc => 'integer',
        code => sub { $_[1] =~ /^[+-]?\d+$/ },
    },
    F => {
        desc => 'float',
        code => sub { $_[1] =~ /^$re{float}$/ },
    },
    PI => {
        desc => 'positive integer',
        code => sub { $_[1] =~ /^[+]?\d+$/ },
    },
    V  => {
        desc => 'valid variable name',
        code => sub { $_[1] =~ /^\w+$/ },
    },
    S  => {
        desc => 'scalar value',
        code => sub { !ref($_[1]) or ref($_[1]) eq 'Lang5::String' },
    },
    X  => {
        desc => 'any value',
        code => sub { 1 },
    },
    U  => {
        desc => 'user defined word',
        code => sub {
            exists $_[0]->{_words}{$_[1]}
            and
            $_[0]->{_words}{$_[1]}{type} eq 'word'
        },
    },
    N  => {
        desc => 'name (user defined word or variable)',
        code => sub {
            my $wroot = $_[0]->_find_word($_[1]);
            return unless $wroot;

            my %wkeys = map { $_ => 1 } grep {
                ref($wroot->{$_[1]}{$_}) eq 'HASH'
            } keys %{ $wroot->{$_[1]} };

            $wroot->{$_[1]}{type} eq 'variable'
            or
            keys %wkeys;
        },
    },
);


# Builtin operators and functions:
my %builtin = (

    ### niladic operators
    exit  => {
        desc => 'Leave the interpreter immediately.',
        type => 'niladic',
        code => sub { $_[0]->{_exit_called} = 1; },
    },

    vlist => {
        desc => 'Generate a list of all variables.',
        type => 'niladic',
        push => [qw/A/],
        code => sub {

            my %names;

            for my $wr ( @{ $_[0]->{_word_exc_stack} } ) {
                $names{$_}++ for grep {
                    $wr->{$_}{type} eq 'variable'
                } keys %$wr;
            }

            [ sort keys %names ];
        },
    },

    ver => {
        desc => "Get the interpreter's version number.",
        type => 'niladic',
        push => [qw/F/],
        code => sub { $VERSION },
    },

    wlist => {
        desc => 'Generate a list of all user defined words.',
        type => 'niladic',
        push => [qw/A/],
        code => sub {
            [
                sort grep {
                    my @hkeys = grep {
                        ref($_) eq 'HASH'
                    } values %{ $_[0]->{_words}{$_} };
                    @hkeys > 0;
                } keys %{ $_[0]->{_words} }
            ]
        },
    },

    ### unary operators
    '?' => {
        desc => 'Generate a pseudo random number.',
        type => 'unary',
        pop  => [qw/X/],
        push => [qw/I/],
        ntrl => 0,
        code => sub { rand($_[1]); },
    },

    'chr' => {
        desc => 'Convert an integer to ASCII.',
        type => 'unary',
        pop  => [qw/X/],
        push => [qw/S/],
        ntrl => 0,
        code => sub { chr($_[1]); },
    },

    defined => {
        desc => 'Check definedness of element.',
        type => 'unary',
        pop  => [qw/X/],
        push => [qw/S/],
        ntrl => 0,
        code => sub { defined($_[1]) || 0; },
    },

    dump => {
        desc => 'Print a user defined word or variable definition.',
        type => 'unary',
        pop  => [qw/S/],
        pop  => [qw/S/],
        code => sub {
            $_[0]->_dump_word($_[1]);
        },
    },

    eval => {
        desc => 'Evaluate a variable.',
        type => 'unary',
        pop  => [qw/S/],
        push => [qw/X/],
        ntrl => undef,
        code => sub {
            my $wroot = $_[0]->_find_word($_[1]);
            return unless $wroot and $wroot->{$_[1]}{type} eq 'variable';
            return $wroot->{$_[1]}{value};
        },
    },

    int => {
        desc => 'Get integer part of a value.',
        type => 'unary',
        pop  => [qw/X/],
        push => [qw/I/],
        ntrl => undef,
        code => sub { int($_[1]) },
    },

    iota => {
        desc => 'Generate a vector with unit stride starting at 0 and ending with TOS value - 1.',
        type => 'unary',
        pop  => [qw/PI/],
        push => [qw/A/],
        ntrl => [],
        code => sub { [ 0 .. $_[1] - 1 ] },
    },

    lc => {
        desc => 'Convert string to lower case.',
        type => 'unary',
        pop  => [qw/S/],
        push => [qw/S/],
        ntrl => [],
        code => sub {
            lc($_[1]);
        }
    },

    neg => {
        desc => 'negation',
        type => 'unary',
        pop  => [qw/X/],
        push => [qw/I/],
        ntrl => undef,
        code => sub { -$_[1] },
    },

    not => {
        desc => 'logical not',
        type => 'unary',
        pop  => [qw/X/],
        push => [qw/X/],
        ntrl => 1,
        code => sub { ! $_[1] + 0 },
    },

    system => {
        desc => 'Execute a system command.',
        type => 'unary',
        pop  => [qw/S/],
        push => [qw/A/],
        ntrl => [],
        code => sub {
            unless ($_[0]->{steps}) # If steps is set, we are a CGI-script and system calls are forbidden
            {
                $_[1] =~ s/^\"//;
                $_[1] =~ s/\"$//;
                [ map { chomp; $_ } `$_[1]` ];
            }
            else
            {
                'Running in CGI mode, system calls are disabled!';
            }
        },
    },

    uc => {
        desc => 'Convert string to upper case.',
        type => 'unary',
        pop  => [qw/S/],
        push => [qw/S/],
        ntrl => [],
        code => sub {
            uc($_[1]);
        }
    },

    # direct mapping to perl operators
    ( map {
        $_ => {
            desc => "Basic unary operator $_, no neutral element.",
            type => 'unary',
            pop  => [qw/X/],
            push => [qw/S/],
            ntrl => undef,
            code => eval("sub { $_ \$_[1] }"),
        }
    } qw(
        sin cos sqrt exp 
    )),

    # ln
    ln => {
        desc => 'Natural logarithm, no neutral element.',
        type => 'unary',
        pop  => [qw/X/],
        push => [qw/S/],
        ntrl => undef,
        code => sub { log($_[1]) },
    },

    ### binary operators
    atan2 => {
        desc => 'arctan(TOS / TOS-1).',
        type => 'binary',
        pop  => [qw/S S/],
        push => [qw/S/],
        ntrl => [],
        code => sub { atan2 $_[1], $_[2] },
    },

    split => {
        desc => 'Split a string and place its parts into a vector.',
        type => 'binary',
        pop  => [qw/S S/],
        push => [qw/A/],
        ntrl => [],
        code => sub { [ split $_[1], $_[2] ] },
    },

    # direct mapping to perl operators
    # with 0 as neutral element
    ( map {
        $_ => {
            desc => "Basic binary operator $_, neutral element: 0.",
            type => 'binary',
            pop  => [qw/X X/],
            push => [qw/S/],
            ntrl => 0,
            code => eval("sub { no warnings qw/numeric/; \$_[2] $_ \$_[1] }"),
        }
    } qw(
        + -
    )),

    # with 1 as neutral element
    ( map {
        $_ => {
            desc => "Basic binary operator $_, neutral element: 1.",
            type => 'binary',
            pop  => [qw/X X/],
            push => [qw/S/],
            ntrl => 1,
            code => eval("sub { no warnings qw/numeric/; \$_[2] $_ \$_[1] }"),
        }
    } qw(
        * / % **
    )),

    # without a neutral element
    ( map {
        $_ => {
            desc => "Basic binary operator $_, no neutral element.",
            type => 'binary',
            pop  => [qw/X X/],
            push => [qw/S/],
            code => eval("sub { no warnings qw/numeric uninitialized/; ( \$_[2] $_ \$_[1] ) || 0 }"),
        }
    } qw(
        & | ^
        > < == >= <= != <=>
        cmp eq ne gt lt ge le
        && || and or
    )),

    concat => {
        desc => 'Concatenates strings.',
        type => 'binary',
        pop  => [qw/X X/],
        push => [qw/S/],
        code => sub {
            return $_[2] . $_[1];
        },
    },

    eql => {
        desc => 'eql binary operator testing real string equality.',
        type => 'binary',
        pop  => [qw/X X/],
        push => [qw/S/],
        ntrl => [],
        code => sub {
            if ( defined($_[1]) and defined($_[2]) ) {
                return ($_[1] eq $_[2]) ? 1 : 0;
            }
            if ( !defined($_[1]) and !defined($_[2]) ) {
                return 1;
            }
            return 0;
        },
    },

    '===' => {
        desc => '=== binary operator testing real numerical equality.',
        type => 'binary',
        pop  => [qw/X X/],
        push => [qw/S/],
        ntrl => [],
        code => sub {
            if ( defined($_[1]) and defined($_[2]) ) {
                return ($_[1] == $_[2]) ? 1 : 0;
            }
            if ( !defined($_[1]) and !defined($_[2]) ) {
                return 1;
            }
            return 0;
        },
    },

    ### functions
    '..' => {
        desc => 'Print the stack contents without destroying the stack.',
        type => 'function',
        code => sub {
            my($self, $stack) = @_;
            my $dout = Dumper($stack);
            $dout =~ s/$re{strob}/$1/g;
            $self->_output($dout);
        },
    },

    '.' => {
        desc => 'Remove TOS and dump it to an output buffer.',
        type => 'function',
        pop  => [qw/X/],
        code => sub {
            my($self, $stack) = @_;
            $self->_output($self->_element2text(pop @$stack));
        },
    },

    '.ofw' => {
        desc => 'Print a list of all defined words etc.',
        type => 'function',
        code => sub {
            my($self, $stack) = @_;
            $self->_words2text_buffer()
        },
    },

    apply => {
        desc => 'Apply an unary/binary operator/word along the first dimension of an array.',
        type => 'function',
        pop  => [qw/S A/],
        push => [qw/A/],
        code => sub {
            my ($self, $stack) = @_;

            my $name = pop @$stack;
            my $a1   = pop @$stack;

            unless ( ref($a1) eq 'ARRAY' ) {
                $self->{_last_error} = 'apply: TOS-1 is not an array';
                $self->{_error} = 1;
                return;
            }

            my $wroot = $self->_find_word($name);

            unless ( $wroot ) {
                $self->{_last_error}
                    = "apply: no operator/user defined word named '$name' found";
                $self->{_error} = 1;
                return;
            }

            my $word = $wroot->{$name};

            my $func = $self->_get_func($word);
            my $ntrl = $self->_get_ntrl($word);

            unless ( $word->{type} =~ /^unary|binary$/ ) {
                $self->{_last_error}
                    = "apply: '$name' is not of type unary or binary";
                $self->{_error} = 1;
                return;
            }

            my @result;

            if ( $word->{type} eq 'unary' ) {

                for my $element (@$a1) {
                    INFO "apply calling unary word: ", $word;
                    INFO "apply calling word with element: ", $element;
                    push @result, $func->($self, $element);
                }

            } else {

                my $a2 = pop @$stack;

                unless ( ref($a2) eq 'ARRAY' ) {
                    $self->{_last_error} = 'apply: TOS-2 is not an array';
                    $self->{_error} = 1;
                    return;
                }

                for (my $i = 0; $i < (@$a1 > @$a2 ? @$a1 : @$a2); $i++) {

                    my $x
                        = ref($a1->[$i % @$a1]) eq 'ARRAY'
                        ? dclone($a1->[$i % @$a1])
                        : $a1->[$i % @$a1];

                    my $y
                        = ref($a2->[$i % @$a2]) eq 'ARRAY'
                        ? dclone($a2->[$i % @$a2])
                        : $a2->[$i % @$a2];

                    push(@result, $func->($self, $x, $y));
                }
            }

            push @$stack, \@result;
        },
    },

    close => {
        desc => 'Close a file which has been opened before.',
        type => 'function',
        pop  => [qw/I/],
        code => sub {
            my($self, $stack) = @_;

            my $fileno = pop @$stack;

            DEBUG "closing file number $fileno";

            unless ( $self->{_files}{$fileno} ) {
                $self->{_last_error} = "No such file to close: $fileno";
                $self->{_error} = 1;
                return;
            }

            close  $self->{_files}{$fileno}{handle};
            delete $self->{_files}{$fileno};
        },
    },

    compress => {
        desc => 'Compress data found on the stack into a structure.',
        type => 'function',
        pop  => [qw/PI/],
        push => [qw/A/],
        code => sub {
            my($self, $stack) = @_;

            my $length = pop @$stack;
            if ( @$stack < $length ) {
                $self->{_last_error} = 'compress: not enough elements on stack!';
                $self->{_error} = 1;
                return;
            }

            push @$stack, [ splice @$stack, - $length, $length ];
        },
    },

    collapse => {
        desc => 'Collapses a higher dimensional structure into a one dimensional vector.',
        type => 'function',
        pop  => [qw/A/],
        push => [qw/A/],
        ntrl => [],
        code => sub {
            my($self, $stack) = @_;

            eval {
                push @$stack, collapse(pop @$stack);
            };

            if ( $@ ) {
                $self->{_last_error} = $Array::DeepUtils::LastError;
                $self->{_error} = 1;
                return;
            }
        },
    },

    del => {
        desc => 'Delete a variable or a word (if it does not exist nothing will happen).',
        type => 'function',
        pop  => [qw/S/],
        code => sub {
            my($self, $stack) = @_;

            my $name = pop @$stack;

            DEBUG "Deleting word or variable $name";

            my $wroot = $self->_find_word($name);

            unless ( $wroot ) {
                $self->{_last_error} = "del: no word named '$name' found";
                $self->{_error} = 1;
                return;
            }

            my $word = $wroot->{$name};

            my %wkeys = map { $_ => 1 } grep {
                ref($word->{$_}) eq 'HASH'
            } keys %$word;

            unless ( $word->{type} eq 'variable' or keys(%wkeys) ) {
                $self->{_last_error} = "del: '$name' is not of type variable or user defined word";
                $self->{_error} = 1;
                return;
            }

            (my $stripped = $name) =~ s/^__//;
            if ( $published_vars{$stripped} ) {
                $self->{_last_error} = "published variable $name cannot be deleted!";
                $self->{_error} = 1;
                return;
            }

            delete $wroot->{$name};
            DEBUG "deleted $name";
        },
    },

    depth => {
        desc => 'Return the depth of the stack.',
        type => 'function',
        push => [qw/I/],
        code => sub {
            my ($self, $stack) = @_;
            push @$stack, scalar @{$stack};
        },
    },

    dress => {
        desc => 'Set the type of a structure.',
        type => 'function',
        pop  => [qw/S A/],
        code => sub {
            my($self, $stack) = @_;

            my $name = pop @$stack;
            my $aref = pop @$stack;

            push @$stack, bless($aref, $name);
        },
    },

    'dressed' => {
        desc => "Return the type of an object or undef if it isn't an object at all.",
        type => 'function',
        pop  => [qw/X/],
        push => [qw/S/],
        code => sub {
            my ($self, $stack) = @_;

            my $type = ref($stack->[-1]);
            push @$stack,
                 (
                   !$type
                   or $type eq 'ARRAY'
                   or $type eq 'Lang5::String'
                 )
                 ? undef : $type;
        },
    },

    drop => {
        desc => 'Drop the TOS.',
        type => 'function',
        pop  => [qw/X/],
        code => sub {
            my($self, $stack) = @_;
            pop @$stack;
        },
    },

    dup => {
        desc => 'Duplicate the TOS.',
        type => 'function',
        pop  => [qw/X/],
        push => [qw/X X/],
        code => sub {
            my($self, $stack) = @_;

            my $data
                = ref($stack->[-1])
                ? dclone($stack->[-1])
                : $stack->[-1];

            push @$stack, $data;
        },
    },

    eof => {
        desc => 'Push 1 on the TOS if the next read on current input handle would fail due to eof, else 0.',
        type => 'function',
        push => [qw/I/],
        code => sub {
            my($self, $stack) = @_;

            DEBUG "test eof on current input file";

            my $fileno = $self->{_fin};
            my $handle = $self->{_files}{$fileno}{handle};

            push @$stack, eof($handle);
        },
    },

    execute => {
        desc => 'Execute an operator or function or word found on the TOS.',
        type => 'function',
        pop  => [qw/X/],
	    ntrl => undef,
        code => sub {
            my($self, $stack) = @_;

            my $el = pop @$stack;

            $el = [$el] unless ref($el) eq 'ARRAY';

            for my $instr ( @$el ) {
                next if $instr eq '';
                $self->add_source_line($_)
                    for split /\n/, $instr;
                $self->execute($stack);
                last if $self->{_break};
            }
        },
    },

    expand => {
        desc => 'Expand a structure to the next deeper level.',
        type => 'function',
        pop  => [qw/A/],
        code => sub {
            my($self, $stack) = @_;

            my $data = pop @$stack;
            push @$stack, @$data, scalar(@$data);
        },
    },

    fin => {
        desc => 'Set the currrent input file handle.',
        type => 'function',
        pop  => [qw/I/],
        code => sub {
            my($self, $stack) = @_;

            my $fileno = pop @$stack;

            DEBUG "select input file number to $fileno";

            unless( $self->{_files}{$fileno} ) {
                $self->{_last_error} = "no open file number $fileno";
                $self->{_error} = 1;
                return;
            }

            unless( $self->{_files}{$fileno}{type} eq 'in' ) {
                $self->{_last_error} = "file number $fileno: type '$self->{_files}{$fileno}{type}' <> 'in'";
                $self->{_error} = 1;
                return;
            }

            $self->{_fin} = $fileno;
        },
    },

    fout => {
        desc => 'Set the currrent output file handle.',
        type => 'function',
        pop  => [qw/I/],
        code => sub {
            my($self, $stack) = @_;

            my $fileno = pop @$stack;

            DEBUG "select output file number to $fileno";

            unless( $self->{_files}{$fileno} ) {
                $self->{_last_error} = "no open file number $fileno";
                $self->{_error} = 1;
                return;
            }

            unless( $self->{_files}{$fileno}{type} eq 'out' ) {
                $self->{_last_error} = "file number $fileno: type '$self->{_files}{$fileno}{type}' <> 'out'";
                $self->{_error} = 1;
                return;
            }

            $self->{_fout} = $fileno;
        },
    },

    grade => {
        desc => 'Generate an index vector for sorting the elements of a vector.',
        type => 'function',
        pop  => [qw/A/],
        push => [qw/A/],
        code => sub {
            my($self, $stack) = @_;

            my $data = $stack->[-1];

            my %h = map { $_ => $data->[$_] } 0 .. @$data - 1;

            push @$stack, [ sort { $h{$a} <=> $h{$b} } keys %h ];
        },
    },

    help => {
        desc => 'Print the description of a built in function or operator.',
        type => 'unary',
        pop  => [qw/X/],
        code => sub {
            my($self, $name) = @_;

            unless( $self->{_words}{$name}{desc} ) {
                $self->_output("No description found for '$name'.");
            } else {
                $self->_output("$name: $self->{_words}{$name}{desc}\n");
            }
        },
    },

    in => {
        desc => 'Set operation "in" - returns a structure consisting of 0 and 1.',
        type => 'function',
        pop  => [qw/X A/],
        push => [qw/A/],
        code => sub {
            my($self, $stack) = @_;

            my $a1 = pop @$stack;
            my $a2 = pop @$stack;
            my @res;

            if ( ref($a1) eq 'ARRAY' ) {
                push(@res, $self->_is_in($_, $a2)) for (@$a1);
                push @$stack, \@res;
            } else {
                push @$stack, $self->_is_in($a1, $a2);
            }
        },
    },

    index => {
        desc => 'Generate an index vector.',
        type => 'function',
        pop  => [qw/A A/],
        push => [qw/A/],
        code => sub {
            my($self, $stack) = @_;

            my $aref1 = pop @$stack;
            my $aref2 = pop @$stack;

            eval { push @$stack, idx($aref1, $aref2); };

            if ( $@ ) {
                $self->{_last_error} = $Array::DeepUtils::LastError;
                $self->{_error} = 1;
                return;
            }
        },
    },

    join => {
        desc => 'Concatenate elements of a vector forming a string.',
        type => 'function',
        pop  => [qw/S A/],
        push => [qw/S/],
        code => sub {
            my($self, $stack) = @_;

            my $glue = pop @$stack;

            my $aref = pop @$stack;

            push @$stack, join($glue, @$aref);
        },
    },

    length => {
        desc => 'Determine the length of an array.',
        type => 'function',
        pop  => [qw/A/],
        push => [qw/PI/],
        code => sub {
            my($self, $stack) = @_;

            push @$stack, scalar(@{$stack->[-1]});
        },
    },

    load => {
        desc => 'Load a program from a file.',
        type => 'function',
        pop  => [qw/S/],
        code => sub {
            my($self, $stack) = @_;

            my $file_name = pop @$stack;

            DEBUG "Load program from file $file_name";

            my $fh;
            unless ( open($fh, '<', $file_name) ) {
                $self->{_last_error} = "Could not open file '$file_name' for read!, $!";
                $self->{_error} = 1;
                return;
            }

            while ( my $line = <$fh> ) {
                next unless $line;
                $self->add_source_line($line);
            }

            close($fh);

            $self->execute();
        },
    },

    open => {
        desc => 'Open a file and store its handle in a hash for later use.',
        type => 'function',
        pop  => [qw/S S/],
        push => [qw/I/],
        code => sub {
            my($self, $stack) = @_;

            my $file_name = pop @$stack;
            my $mode      = pop @$stack;

            DEBUG "open $file_name with mode '$mode'...";

            my %open = map { $_->{name} => 1 } values %{ $self->{_files} };

            unless ( $mode =~ m/^[+<>]{1,3}$/ ) {
                $self->{_last_error} =
                    "invalid mode '$mode' specified for file '$file_name'!";
                $self->{_error} = 1;
                push @$stack, -1;
                return;
            }

            if ( $open{$file_name} ) {
                $self->{_last_error} =
                    "file '$file_name' has already been opened!";
                $self->{_error} = 1;
                push @$stack, -1;
                return;
            }

            my $handle;
            unless ( open($handle, $mode, $file_name) ) {
                $self->{_last_error} =
                    "Could not open file '$file_name' in mode '$mode', $!";
                $self->{_error} = 1;
                push @$stack, -1;
                return;
            }

            my $fileno = fileno($handle);
            $self->{_files}{$fileno} = {
                handle => $handle,
                type   => ($mode =~ />/ ? 'out' : 'in'),
                name   => $file_name,
            };

            push @$stack, $fileno;
        },
    },

    outer => {
        desc => 'Perform an outer "product" operation although any builtin binary word can be used as the basis for this.',
        type => 'function',
        pop  => [qw/BO A A/],
        push => [qw/A/],
        code => sub {
            my($self, $stack) = @_;

            my $name = pop @$stack;

            my $wroot = $self->_find_word($name);

            unless ( $wroot ) {
                $self->{_last_error} = "outer: no word named '$name' found";
                $self->{_error} = 1;
                return;
            }

            my $a1   = pop @$stack;
            my $a2   = pop @$stack;
            my @res;

            for my $i ( 0 .. @$a1 - 1 ) {
                for my $j ( 0 .. @$a2 - 1 ) {
                     my $value = $a2->[$j];
                     $self->_binary($wroot->{$name}, $a1->[$i], $value);
                     $res[$i][$j] = $value;
                }
            }

            push @$stack, \@res;
        },
    },

    over => {
        desc => 'Push TOS - 1 onto the stack.',
        type => 'function',
        pop  => [qw/X X/],
        push => [qw/X X X/],
        code => sub {
            my($self, $stack) = @_;

            my $data
                = ref($stack->[-2])
                ? dclone($stack->[-2])
                : $stack->[-2];

            push @$stack, $data;
        },
    },

    panic => {
        desc => 'Print TOS and leave current interpreter loop immediately.',
        type => 'function',
        pop  => [qw/X/],
        code => sub {
            my($self, $stack) = @_;

            $self->_output('PANIC: ');

            $self->{_words}{'.'}{code}->($self, $stack)
                if $stack->[-1];

            $self->{_error} = 1;
        },
    },

    read => {
        desc => 'Read a record from current input handle and push it on top of the stack.',
        type => 'function',
        push => [qw/S/],
        code => sub {
            my($self, $stack) = @_;

            my $fileno = $self->{_fin};
            my $handle = $self->{_files}{$fileno}{handle};

            DEBUG "read data from file number $fileno";

            my $value = <$handle>;
            chomp $value;
            push @$stack, $value;
        },
    },

    reduce => {
        desc => "Reduce a vector to a scalar by applying a binary word to all vector elements (cf. APL's '/').",
        type => 'function',
        pop  => [qw/BO A/],
        push => [qw/S/],
        code => sub {
            my($self, $stack) = @_;

            DEBUG "reduce stack: ", $stack;

            my $name = pop @$stack;

            my $wroot = $self->_find_word($name);

            unless ( $wroot ) {
                $self->{_last_error} = "reduce: no operator/user defined word named '$name' found";
                $self->{_error} = 1;
                return;
            }

            my $word = $wroot->{$name};

            unless ( $word->{type} eq 'binary' ) {
                $self->{_last_error} = "reduce: '$name' is not of type binary";
                $self->{_error} = 1;
                return;
            }

            my $aref = pop @$stack;

            unless ( @$aref ) {
                push @$stack, $word->{ntrl};
                return;
            }

            my $result = shift @$aref;

            for my $el ( @$aref ) {
                eval { $self->_binary($word, $el, $result); };

                if ( $@ ) {
                    $self->{_last_error} = "reduce: $@";
                    $self->{_error} = 1;
                    return;
                }

                DEBUG "reduce: result=$result, ", $el || '';
            }

            push @$stack, $result;
        },
    },

    remove => {
        desc => 'Remove elements from a nested structure found at TOS - 1 and controlled by a structure or value found at TOS.',
        type => 'function',
        pop  => [qw/X A/],
        push => [qw/A/],
        code => sub {
            my($self, $stack) = @_;

            my $list = pop @$stack;

            eval { remove($stack->[-1], $list); };

            if ( $@ ) {
                $self->{_last_error} = $Array::DeepUtils::LastError;
                $self->{_error} = 1;
                return;
            }

        },
    },

    reshape => {
        desc => 'Transform the array found on TOS-1 according to a dimension vector found on TOS.',
        type => 'function',
        pop  => [qw/X X/],
        push => [qw/A/],
        code => sub {
            my($self, $stack) = @_;

            my $dims = pop @$stack;
            my $src  = pop @$stack;

            $dims = [$dims] unless ref($dims) eq 'ARRAY';
            $src  = [$src]  unless ref($src)  eq 'ARRAY';

            eval { push @$stack, reshape($src, $dims); };

            if ( $@ ) {
                $self->{_last_error} = $Array::DeepUtils::LastError;
                $self->{_error} = 1;
                return;
            }

        },
    },

    reverse => {
        desc => 'Reverse the elements of a vector.',
        type => 'function',
        pop  => [qw/A/],
        push => [qw/A/],
        code => sub {
            my($self, $stack) = @_;

            push @$stack, [ reverse @{ pop @$stack } ]
        },
    },

    _roll => {
        desc => 'Rotate stack elements.',
        type => 'function',
        pop  => [qw/I I/],
        code => sub {
            my($self, $stack) = @_;

            my $nr_shift = pop @$stack;
            my $nr_elem  = pop @$stack;

            return unless $nr_shift and $nr_elem;

            $nr_shift   %= $nr_elem;

            push @$stack, splice(@$stack, - $nr_elem, $nr_shift);
        },
    },

    rotate => {
        desc => 'Rotate n-dimensional array.',
        type => 'function',
        pop  => [qw/A A/],
        push => [qw/A/],
        code => sub {
            my($self, $stack) = @_;

            my $rotvec = pop @$stack;
            my $struct = pop @$stack;

            eval { push @$stack, rotate($struct, $rotvec); };

            if ( $@ ) {
                $self->{_last_error} = $Array::DeepUtils::LastError;
                $self->{_error} = 1;
                return;
            }
        },
    },

    scatter => {
        desc => 'Distribute elements of a one dimensional vector into a new structure.',
        type => 'function',
        pop  => [qw/A A/],
        push => [qw/A/],
        code => sub {
            my($self, $stack) = @_;

            my $struct = pop @$stack;
            my $aref   = pop @$stack;

            eval { push @$stack, scatter($aref, $struct); };

            if ( $@ ) {
                $self->{_last_error} = $Array::DeepUtils::LastError;
                $self->{_error} = 1;
                return;
            }
        },
    },

    select => {
        desc => 'Select elements from a nested structure (TOS - 1) controlled by a selector structure containing 0 and non-zero values (TOS).',
        type => 'function',
        pop  => [qw/A A/],
        push => [qw/A/],
        code => sub {
            my($self, $stack) = @_;

            my $a1 = pop @$stack;
            my $a2 = pop @$stack;
            my @res;

            for my $i ( 0 .. @$a2-1 ) {
                push @res, $a2->[$i] if $a1->[$i];
            }
            push @$stack, \@res;
        },
    },

    set => {
        desc => 'Set and, if necessary, define a variable.',
        type => 'function',
        pop  => [qw/V X/],
        code => sub {
            my($self, $stack) = @_;

            my $name = pop @$stack;

            # first check for a non variable of the same
            # name in the visible word definitions
            my $wroot = $self->_find_word($name);

            if ( $wroot and $wroot->{$name}{type} ne 'variable' ) {
                $self->{_last_error} = "set: variable name $name conflicts with defined word";
                $self->{_error} = 1;
                return;
            }

            my $value = pop @$stack;
            DEBUG "setting variable '$name' to value '$value'.\n";

            $wroot = $self->{_word_exc_stack}[-1];
            $wroot->{$name} = {
                type  => 'variable',
                value => $value,
            };

            $name =~ s/^__//;
            $self->{$name} = $value if $published_vars{$name};
            $self->_setup_logger()
                if $name eq 'log_level';
        },
    },

    shape => {
        desc => 'Return dimension vector.',
        type => 'function',
        pop  => [qw/X/],
        push => [qw/A/],
        code => sub {
            my($self, $stack) = @_;

            eval { push @$stack, shape($stack->[-1]); };

            if ( $@ ) {
                $self->{_last_error} = $Array::DeepUtils::LastError;
                $self->{_error} = 1;
                return;
            }
        },
    },

    slice => {
        desc => 'Copies a substructure from within a larger structure.',
        type => 'function',
        pop  => [qw/A A/],
        push => [qw/A/],
        ntrl => [],
        code => sub {
            my ($self, $stack) = @_;

            my $coord  = pop @$stack;
            my $struct = pop @$stack;

            my $dest = eval { dcopy($struct, $coord) };

            if ( $@ ) {
                $self->{_last_error} = $Array::DeepUtils::LastError;
                $self->{_error} = 1;
                return;
            }

            push @$stack, $dest;
        },
    },

    spread => {
        desc => 'Apply a binary operator successively between elements of a vector.',
        type => 'function',
        pop  => [qw/BO A/],
        push => [qw/A/],
        code => sub {
            my ($self, $stack) = @_;

            DEBUG "spread stack: ", $stack;

            my $name = pop @$stack;
            my $wroot = $self->_find_word($name);

            unless ( $wroot ) {
                $self->{_last_error} = "spread: no operator/user defined word named '$name' found";
                $self->{_error} = 1;
                return;
            }

            my $word = $wroot->{$name};

            unless ( $word->{type} eq 'binary' ) {
                $self->{_last_error} = "spread: '$name' is not of type binary";
                $self->{_error} = 1;
                return;
            }

            my $aref = pop @$stack;

            unless ( @$aref ) {
                push @$stack, $word->{ntrl};
                return;
            }

            my @result;
            push @result, (my $last_value = shift @$aref);

            for my $el ( @$aref ) {
                eval { $self->_binary($word, $el, $last_value) };
                push @result, $last_value;

                if ( $@ ) {
                    $self->{_last_error} = "spread: $@";
                    $self->{_error} = 1;
                    return;
                }

                DEBUG "spread: result=$last_value, ", $el || '';
            }

            push @$stack, \@result;
        },
    },

    strip => {
        desc => 'Removes the object type from a nested data structure.',
        type => 'function',
        pop  => [qw/A/],
        push => [qw/A/],
        code => sub {
            my ($self, $stack) = @_;

            return unless _is_aref($stack->[-1]);

            push @$stack, [ @{ pop @$stack } ];
        },
    },

    subscript => {
        desc => 'Select elements from an array determined by their respective index numbers.',
        type => 'function',
        pop  => [qw/A A/],
        push => [qw/A/],
        code => sub {
            my($self, $stack) = @_;

            my $coordinates = pop @$stack; # Vector containing coordinates of element to be selected.
            my $source_data = pop @$stack; # Source data structure.

            my $aref;
            eval { $aref = subscript($source_data, $coordinates); };

            if ( $@ ) {
                $self->{_last_error} = $Array::DeepUtils::LastError;
                $self->{_error} = 1;
                return;
            }

            for ( @$aref ) { $_ = undef if ref($_) eq 'NaV' }
            push @$stack, $aref;
        },
    },

    swap => {
        desc => 'Swap TOS and TOS - 1.',
        type => 'function',
        pop  => [qw/X X/],
        push => [qw/X X/],
        code => sub {
            my($self, $stack) = @_;

            ($stack->[-1], $stack->[-2]) = ($stack->[-2], $stack->[-1]);
        },
    },

    transpose => {
        desc => 'Transpose n-dimensional array.',
        type => 'function',
        pop  => [qw/I A/],
        push => [qw/A/],
        code => sub {
            my($self, $stack) = @_;

            my $control = pop @$stack;
            my $struct  = pop @$stack;

            eval { push @$stack, transpose($struct, $control); };

            if ( $@ ) {
                $self->{_last_error} = $Array::DeepUtils::LastError;
                $self->{_error} = 1;
                return;
            }
        },
    },

    type => {
        desc => 'Determine type of TOS-element.',
        type => 'function',
        pop  => [qw/X/],
        push => [qw/S/],
        code => sub {
            my($self, $stack) = @_;

            my $tos = $stack->[-1] || '';

            my $wroot = $self->_find_word($tos);

            my $tref  = ref($tos);

            my $type
                = exists $wroot->{$tos}
                ? uc($element_type{ $wroot->{$tos}{type} })
                : (
                    $tref eq 'ARRAY'
                    ? 'A'
                    : ( $tref && $tref ne 'Lang5::String' ? 'D' : 'S' )
                  );

            push @$stack, $type;
        },
    },

    unlink => {
        desc => 'Delete a file (name on TOS).',
        type => 'function',
        pop  => [qw/S/],
        code => sub {
            my($self, $stack) = @_;

            my $file_name = pop @$stack;

            DEBUG "unlinking $file_name";

            unlink($file_name)
                or $self->{_last_error} = "error unlinking $file_name, $!";
        },
    },
);

# Default object parameters.
my %default = (
    # private
    _state          => STATE_RUN,
    _word_def_stack => [],
    _word_exc_stack => [],
    _stack          => [],
    _words          => {},
    _exec_hist      => [],
    _statistics     => {},
    _steps          => 0,
    _exit           => 0,
    _files          => {
        fileno(STDIN),  { handle => \*STDIN,  type => 'in',  name => 'STDIN'  },
        fileno(STDOUT), { handle => \*STDOUT, type => 'out', name => 'STDOUT' },
        fileno(STDERR), { handle => \*STDERR, type => 'out', name => 'STDERR' },
    },
    _fin            => fileno(STDIN),
    _fout           => fileno(STDOUT),
    _nocrlf         => 0,
    _text_buffer    => [],
    _line_buffer    => [],

    # public
    log_level       => 'DEBUG',
    terminal_width  => 80,
    libdir          => './lib',
    libautoload     => 1,
    text_callback   => undef,
    number_format   => '%4s',
    steps           => 0,
);


# Constructor.
sub new {
    my($class, %params) = @_;

    my $self = { %default };
    bless $self, $class;

    $self->init(\%params);

    return($self);
}


sub init {
    my($self, $params) = @_;

    $self->{$_} = $params->{$_}
        for grep { ! /^_/ and defined $params->{$_} } keys %$params;

    for my $name ( keys %builtin ) {
        $self->{_words}{$name}       = $builtin{$name};
        $self->{_words}{$name}{name} = $name;
    }

    $self->_setup_logger();

    $self->{_words}{"__$_"} = {
        type  => 'variable',
        value => $self->{$_},
    } for keys %published_vars;

    # initialize word search stack
    push @{ $self->{_word_exc_stack} }, $self->{_words};

    if ( $self->{libautoload} ) {
        my $path = "$self->{libdir}/*.5";
        if ($path =~ m/]/) # Its seems we are running on an OpenVMS system.
        {
            $path =~ s/]//;
            $path =~ s/\//\./g;
            $path =~ s/\.\*/]\*/;
        }
        for my $lib ( glob $path ) {
            push @{ $self->{_stack} }, $lib;
            $self->{_words}{load}{code}->($self, $self->{_stack});
        }
    }
}


sub _setup_logger {
    my($self) = @_;

    for my $lev ( keys %debug_level ) {

        no strict 'refs';
        no warnings qw/redefine uninitialized prototype/;

        *{$lev} = $debug_level{$lev} < $debug_level{$self->{log_level}}
                ? sub () {}
                : sub (@) {

                     my $ts = strftime("%Y-%m-%d %H:%M:%S ", localtime);

                     warn
                         $ts,
                         $lev,
                         ' ',
                         map {
                            ref($_)
                            ? do {
                                my $d = Dumper($_);
                                $d =~ s/$re{strob}/$1/g;
                                $d;
                              }
                            : $_
                         } @_,
                         $_[-1] =~ /\n$/ ? '' : "\n";

                     exit(1) if $lev eq 'FATAL';
                 };
    }
}


# Return 1 if a scalar element is found in a structure (set operation in).
sub _is_in {
    my($self, $el, $data) = @_;

    for my $d ( @$data ) {

        if ( ref($d) eq 'ARRAY' ) {
            return 1 if $self->_is_in($el, $d);
        } else {
            return 1 if $el eq $d;
        }
    }

    return 0;
}


# Quote a string and convert its contents to hexadecimal representation.
# This is done to avoid splitting strings by the simple parser - in the
# hex representation a string does not contain any special or whitespace
# characters which would confuse the parser.
sub _secure_string {
    my($str, $do_quote) = @_;

    INFO '_secure_string: >>', $str, '<<';

    if ( $do_quote ) {
        # mask variable markers to avoid unwanted side effects
        # TODO better resolve the metachars manually and not in
        # a string eval
        $str =~ s/(?<!\\)([\$\@\%\&\*])/\\$1/g;
        $str = eval qq("$str");

    }

    return ' {' . unpack('H*', $str) . '} ';
}


# Push a single line of code into the line buffer.
sub add_source_line {
    my($self, $line) = @_;

    # skip empty elements
    return unless $line =~ /\S/;

    # remove control characters resulting from sloppy typing!
    $line =~ tr/\x80-\xFF/ /;

    # mark quoted backslashes
    $line =~ s/\\\\/__CTBS__/g;

    # mark quoted double quotes
    $line =~ s/\\"/__CTDQ__/g;

    # mark quoted single quotes
    $line =~ s/\\'/__CTSQ__/g;

    # mark spaces in word headers (spaces in brackets in braces)
    my @parts = split /($re{whead})/, $line;

    for ( @parts ) {

        next unless /$re{whead}/;

        s/\[/__CTOB__/g;
        s/\]/__CTCB__/g;
        s/\s+/__CTWS__/g;

        TRACE 'after word header: ', $line;
    }

    $line = join('', @parts);

    # convert metachars in double_quoted strings
    # and convert strings to hex strings in braces
    $line =~ s/"([^"]*)"/_secure_string($1, 1)/eg;
    $line =~ s/'([^\s\]]+)/_secure_string($1, 0)/eg;

    # remove comments
    $line =~ s/#.*$//;

    INFO 'parsed line: >>', $line , '<<';

    push @{ $self->{_line_buffer} }, $line;
}

# Process lines from the line buffer and return an array
# reference to the parsed results.
sub _parse_source {
    my($self) = @_;

    # split all lines in line buffer to program elements
    my @prog = grep {
        # last throw away empty elements
        /\S+/
    } map {
        # then split on brackets but keep them in the list
        split /([\[\]])/;
    } map {
        # first split on whitespace
        split /\s+/;
    } @{ $self->{_line_buffer} };

    for ( @prog ) {
        next unless /^\{([0-9a-f]*)\}$/;
        $_ = Lang5::String->new(
            $self->_cleanup_string(pack('H*', $1))
        );
    }

    INFO "_parse_source: parsed ", \@prog;

    # empty line buffer
    @{ $self->{_line_buffer} } = ();

    return \@prog;
}


# Parse, preprocess and execute a program:
sub execute {
    my($self, $stack) = @_;

    # parse lines from the line buffer
    my $prog = $self->_parse_source();

    # bring arrays back into shape
    return unless $self->_transmogrify_arrays($prog);

    # create nested substructures for ifs and loops
    return unless $self->_if_do_structures($prog);

    # execute program
    $self->{_break} = 0;
    $self->_execute($prog, 1, $stack);
}


# Since the parser splits its input on every whitespace a routine is
# necessary to detect the definition of nested arrays which are then
# converted into real datastructures pushed to the data stack.
sub _transmogrify_arrays {
    my($self, $prog) = @_;

    my $i = 0;
    my @arrays;

    while ( 1 ) {

        unless ( defined $prog->[$i]  ) {
            $self->{_last_error} = 'undefined value in array definition!';
            $self->{_error} = 1;
            return;
        }

        # start a new array
        # push empty array_ref on stack
        if ( $prog->[$i] eq '[' ) {
            push @arrays, [];
            splice @$prog, $i, 1;
            next;
        }

        # end of current array
        # get next element from array_stack
        if ( $prog->[$i] eq ']' ) {
            my $aref = pop @arrays;

            # Now that we found the closing bracket of an array we
            # have to look at the next element in @$prog if it exists
            # to determine if it looks like "(...)" denoting an
            # object type. If such an element is found, we will bless
            # the array we just created and remove the type name from
            # @$prog.
            if ($i < $#$prog and $prog->[$i + 1] =~ /^\((\w+)\)$/ ) {
                $aref = bless($aref, $1);
                splice @$prog, $i + 1, 1;
            }

            if ( @arrays ) {
                push @{$arrays[-1]}, $aref;
                splice @$prog, $i, 1;
            } else {
                $prog->[$i] = $aref;
            }
            next;
        }

        # push all elements from raw data
        # to previously created array
        if ( @arrays ) {
            $prog->[$i] =~ s/^'(\S+)$/$1/;
            $prog->[$i] = undef if $prog->[$i] eq 'undef';

            if (
                $prog->[$i]
                and
                $prog->[$i] !~ /^$re{float}$/
                and
                ref($prog->[$i]) ne 'Lang5::String'
            ) {
                $self->{_last_error} = "unquoted string >>$prog->[$i]<< in array!";
                $self->{_error} = 1;
                return;
            }

            push @{$arrays[-1]}, $prog->[$i];
            splice @$prog, $i, 1;
            next;
        }

        last if ++$i >= @$prog;
    }

    return 1;
}

# if and do structures are represented within a program as nested arrays.
# This subroutine loops over the raw program represented by a flat array of
# words and values and converts the conditional and loop constructs to
# the internal representation using nested arrays.
sub _if_do_structures {
    my($self, $prog) = @_;

    my @stack;

    my $i = 0;
    my @last;
    while ( $i < @$prog ) {

        if (
            $prog->[$i] eq 'if'
            or
            $prog->[$i] eq 'do'
            or
            $prog->[$i] eq 'else'
        ) {
            if ( $prog->[$i] eq 'else' ) {
                if ( !@last or $last[-1] ne 'if' ) {
                    $self->{_last_error} = 'else without prior if';
                    $self->{_error} = 1;
                    return;
                }
                pop @stack;
            }

            push @last, $prog->[$i];
            my $cref = [];

            if ( @stack ) {
                push @{ $stack[-1] }, splice(@$prog, $i, 1), $cref;
            } else {
                splice @$prog, $i + 1, 0, $cref;
                $i += 2;
            }

            push @stack, $cref;
            next;
        }

        if ( $prog->[$i] eq 'then' or $prog->[$i] eq 'loop' ) {

            if (
                $prog->[$i] eq 'then'
                and
                ( !@last or ($last[-1] ne 'if' and $last[-1] ne 'else') )
            ) {
                $self->{_last_error} = 'then without prior if or else';
                $self->{_error} = 1;
                return;
            }

            if (
                $prog->[$i] eq 'loop'
                and
                ( !@last or $last[-1] ne 'do' )
            ) {
                $self->{_last_error} = 'loop without prior do';
                $self->{_error} = 1;
                return;
            }

            splice(@$prog, $i, 1);
            pop @stack;
            pop @last if $last[-1] eq 'else';
            pop @last;
            next;
        }

        if ( @stack ) {
            push @{ $stack[-1] }, splice(@$prog, $i, 1);
        } else {
            $i++;
        }

    }

    return 1;
}

# Execute a program - this routine is called for programs as well as for
# user defined words etc. 'execute' is recursive as it calls itself on
# nested structures like user defined words, if-else-then or do-loop
# constructions.
sub _execute {
    my($self, $program, $keep_state, $stack) = @_;

    INFO "_execute: program ", $program;
    INFO "_execute: stack ", $stack;

    $stack ||= $self->{_stack};

    # holds the last condition of an if-else-structure.
    my $condition;

    # Holds the result of an executed program block.
    # This may be undef or STATE_BREAK_EXECUTED.
    my $block_result;

    $self->{_error} = 0;

    DEBUG "Stack contents: ", $stack;
    DEBUG "Executing program or word: ", $program;

    $self->{_state} = STATE_RUN unless $keep_state;

    for my $element ( @$program ) {

        $self->{_steps}++; # Count the instruction just executed
        if ($self->{steps} > 0 and $self->{_steps} >= $self->{steps})
        {
            $self->{_last_error} = 'Maximum number of steps execeeded - abort';
            $self->{_error} = 1;
            $self->{_exit_called} = 1;
            return;
        }

        if ( $self->{_exit_called} ) {
            DEBUG "exit called";
            $self->{_break} = 1;
            return;
        }

        $self->{_statistics}{'Max. stack depth'} = @$stack
            if $stack
               && (!$self->{_statistics}{'Max. stack depth'}
               || @$stack > $self->{_statistics}{'Max. stack depth'});

        TRACE "Stack contents: ", $stack, "\nElement type: ", ref($element);

        last if $self->{_error} or $self->{_break};

        push  @{ $self->{_exec_hist} }, $element;
        shift @{ $self->{_exec_hist} }
            if @{ $self->{_exec_hist} } > 10;

        # If we are in the state STATE_SKIP_WORD_DEFINITION we
        # will skip source elements until a ';' is found.
        if ( $self->{_state} == STATE_SKIP_WORD_DEFINITION ) {
            $self->{_state} = STATE_RUN if $element eq ';' and ref($element) ne 'Lang5::String';
            next;
        }

        if ( $self->{_state} == STATE_IF_COMPLETED ) {
            DEBUG "State is STATE_IF_COMPLETED";
            if ( $element eq 'else' ) {
                $self->{_state} = STATE_EXECUTE_ELSE;
                next; # Skip the else instruction itself
            } else {
                $self->{_state} = STATE_RUN;
            }
        }

        # The following block deals with the definition of new words:
        if ( $element eq ';' and ref($element) ne 'Lang5::String' ) {

            # 1. End of word definition

            if ( $self->{_state} != STATE_EXPAND_WORD ) {
                $self->{_last_error} = 'End of word definition not preceded by word definition!';
                $self->{_error} = 1;
                return;
            }

            # transfer program to subroutine ref in the
            # currently defined word
            my $wref = pop @{ $self->{_word_def_stack} };
            my $word = $self->_prog2code($wref);

            if ( @{ $self->{_word_def_stack} } > 0 ) {
                $self->{_state} = STATE_EXPAND_WORD;
            } else {
                $self->{_state} = STATE_RUN;
            }

            INFO "End definition of word >>$wref->{wname}<<: ", $word;

        } elsif ( $self->{_state} == STATE_START_WORD ) {

            # 2. Word header parsing

            my($wname, $ops, $ntrl)
                = $self->_parse_word_header($element);

            unless ( $wname ) {
                ERROR "Error in word header '$element'";
                $self->{_state} = STATE_SKIP_WORD_DEFINITION;
                next;
            }

            if ( $ntrl ) {
                if ( $ntrl =~ /^\[/ ) {
                    my @parts = split /([\[\]])/, $ntrl;
                    $self->_transmogrify_arrays(\@parts);
                    $ntrl = $parts[1];
                } else {
                    $ntrl = undef if $ntrl eq 'undef';
                }
            }

            INFO 'wname: ', $wname;
            INFO 'ops: ',   $ops;
            INFO 'ntrl: ',  $ntrl;

            my $wtype
                = ref($ops)
                ? $op_count{@$ops}
                : 'f';

            INFO 'wtype: ', $wtype;

            my $word_skeleton
                = $self->_begin_word($wname, $wtype, $ops, $ntrl);

            if ( $word_skeleton ) {
                $self->{_state} = STATE_EXPAND_WORD;
                DEBUG "Begin new word '$wname', ", $word_skeleton;
            } else {
                $self->{_state} = STATE_SKIP_WORD_DEFINITION;
                ERROR "Error redefining word '$wname'";
            }

        } elsif ( $element eq ':' ) {

            # 3. Start a new word

            $self->{_statistics}{'Word definitions'}++;
            unless (
                $self->{_state} == STATE_RUN
                or
                $self->{_state} == STATE_EXPAND_WORD
            ) {
                $self->{_last_error} = 'Word definition not in run or expand_word mode!';
                $self->{_error} = 1;
                return;
            }

            $self->{_state} = STATE_START_WORD;

            DEBUG "':' found";

        } elsif ( $self->{_state} == STATE_EXPAND_WORD ) {

            # 4. Extending the word

            # Read elements and append them to the new word
            push @{ $self->{_word_def_stack}[-1]{prog} }, $element;

            DEBUG "Extend word with '$element'";

        } elsif ( $self->{_state} == STATE_EXECUTE_IF ) {

            # Handle if-else-then construction.
            DEBUG "State is STATE_EXECUTE_IF";
            unless ( ref($element) eq 'ARRAY' ) {
                $self->{_last_error} = 'Internal error executing if-construct!';
                $self->{_error} = 1;
                return;
            }

            # The result code could be BREAK_EXECUTED and has to be handled.
            if ( $condition ) {
                $block_result = $self->_execute($element, 0, $stack);
                return if $self->{_error} or $self->{_break};
            }

            $self->{_state} = STATE_IF_COMPLETED;

            return $block_result
                if $block_result and $block_result == STATE_BREAK_EXECUTED;

        } elsif ( $self->{_state} == STATE_EXECUTE_ELSE ) {

            $self->{_statistics}{'Else'}++;

            DEBUG "State is STATE_EXECUTE_ELSE";

            unless ( ref($element) eq 'ARRAY' ) {
                $self->{_last_error} = 'Internal error executing else-construct!';
                $self->{_error} = 1;
                return;
            }

            unless ( $condition ) {
                $block_result = $self->_execute($element, 0, $stack);
                return if $self->{_error} or $self->{_break};
            }

            $self->{_state} = STATE_RUN;

            return $block_result
                if $block_result and $block_result == STATE_BREAK_EXECUTED;

        } elsif ( $self->{_state} == STATE_EXECUTE_DO ) {

            # Handle do-loop constructions.
            DEBUG "State is STATE_EXECUTE_DO";

            $self->{_statistics}{'Do...Loop'}++;

            unless ( ref($element) eq 'ARRAY' ) {
                $self->{_last_error} = 'Internal error executing do-loop!';
                $self->{_error} = 1;
                return;
            }

            my $result = 0;
            while ( ! $result ) {
                $result = $self->_execute($element, 0, $stack);
                return if $self->{_error} or $self->{_break};
            }

            DEBUG "Loop exited by break!"
                if $result == STATE_BREAK_EXECUTED;

            $self->{_state} = STATE_RUN;

        } elsif ( $element eq 'if' ) {

            DEBUG ">>> Execute if";

            $self->{_statistics}{'If'}++;

            $condition = pop @$stack;

            $self->{_state} = STATE_EXECUTE_IF;

        } elsif ( $element eq 'else' ) {

            $self->{_last_error} = 'Else not within if-context!';
            $self->{_error} = 1;
            return;

        } elsif ( $element eq 'do' ) {

            # Execute a do-loop structure
            DEBUG "Executing a do loop.";

            $self->{statistics}{'Do...Loop'}++;

            $self->{_state} = STATE_EXECUTE_DO;

        } elsif ( $element eq 'break' ) {

            DEBUG "Execute break.";

            $self->{statistics}{'Break'}++;

            return STATE_BREAK_EXECUTED;

        } elsif ( ref($element) eq 'Lang5::String' ) {

            DEBUG "Push string '$element'";
            push @$stack, $element;
            $self->{_statistics}{'Push data'}++;

        } elsif ( $element =~ /^$re{float}$/ ) {
            # numbers should end up as "real" numbers on the stack

            DEBUG "Push number $element";
            push @$stack, $element + 0;
            $self->{_statistics}{'Push data'}++;

        } elsif ( ref($element) ) {

            DEBUG "Push array ", $element;
            push @$stack, dclone($element);
            $self->{_statistics}{'Push data'}++;

        } elsif ( $element eq 'undef' ) {

            DEBUG "Push undef";
            push @$stack, undef;
            $self->{_statistics}{'Push data'}++;

        } elsif ( my $wroot = $self->_find_word($element) ) {

            $self->{_statistics}{'execute word'}++;
            $self->{_statistics}{$element}++;

            $self->_execute_word($wroot, $element, $stack);

        } else  {

            ERROR "unknown element '$element'";
            $self->{_error} = 1;
            $self->{_last_error} = "unknown element '$element'";
            return;

        }
    }
}


sub _check_params {
    my($self, $ptype, $stack) = @_;

    $ptype ||= [];

    DEBUG "_check_params: types: ", join(' ', @$ptype), " stack: ", $stack;

    if ( @$stack < @$ptype ) {
        $self->{_last_error} = "too few elements on stack, expected @$ptype";
        return;
    }

    my $i = -1;
    for my $type ( @$ptype ) {
        unless ( $param_checks{$type}{code}->($self, $stack->[$i]) ) {
            $self->{_last_error} = "stack element $i does not match type $type";
            return;
        }
        $i--;
    }

    DEBUG "_check_params: stack after: ", $stack;

    return 1;
}


# Apply an unary word to all elements of a nested structure.
sub _unary {
    my $self = shift;
    my $word = shift;

    INFO "_unary: word: ", $word;
    INFO "_unary: data: ", $_[0];

    my $func = $self->_get_func($word);
    my $ntrl = $self->_get_ntrl($word);

    INFO "_unary: func:", $func;
    INFO "_unary: ntrl:", $ntrl;

    unless ( ref($_[0]) eq 'ARRAY' ) {
        $_[0] = defined($_[0])
              ? $func->($self, $_[0])
              : $ntrl->($_[0]);
        return;
    }

    # no eval because _unary will be called in an evel {}
    unary($_[0], $func, $ntrl, $self);

    return 1;
}


# Apply a binary word to a nested data structure.
sub _binary {
    my($self) = shift;
    my($word) = shift;

    TRACE "_binary: word: ", $word;
    TRACE "_binary: x: ",    $_[0];
    TRACE "_binary: y: ",    $_[1];

    my $func = $self->_get_func($word);
    my $ntrl = $self->_get_ntrl($word);

    TRACE "_binary: func:", $func;
    TRACE "_binary: ntrl:", $ntrl;

    # both operands not array refs -> exec and early return
    if ( ref($_[0]) ne 'ARRAY' and ref($_[1]) ne 'ARRAY' ) {
        $_[1] = ( defined($_[0]) and defined($_[1]) )
              ? $func->($self, $_[0], $_[1])
              : $ntrl->($_[0], $_[1]);
        DEBUG "binary op func returned ", $_[1] ? $_[1] : 'undef';
        return(1);
    }

    # no eval because _binary will be called in an evel {}
    binary($_[0], $_[1], $func, $ntrl, $self);

    return 1;
}


# Strings enclosed in double quotes have been converted into hex ASCII
# representation to avoid getting them split by the simple parser.
# After parsing the program, these strings have to be converted back
#  into readable text which is done here. Note that strings can be recognized
# throughout the interpreter by their enclosing double quotes which are retained.
sub _cleanup_string {
    my($self, $string) = @_;

    INFO '_cleanup_string got >>', $string, '<<';

    # marked double quotes to escaped double quotes
    $string =~ s/__CTSQ__/'/g;  # "

    # marked double quotes to escaped double quotes
    $string =~ s/__CTDQ__/"/g;  # "

    # marked backslashes to escaped backslashes
    $string =~ s/__CTBS__/\\\\/g;

    # marked spaces to real spaces
    $string =~ s/__CTWS__/ /g;

    # marked opening brackets to real opening brackets
    $string =~ s/__CTOB__/\[/g;

    # marked closing brackets to real closing brackets
    $string =~ s/__CTCB__/\]/g;

    INFO '_cleanup_string cleaned >>', $string, '<<';

    return $string;
}


sub _is_aref {
    return eval { @{$_[0]} + 1 };
}


sub get_text {
    my($self) = @_;

    my @lines = @{ $self->{_text_buffer} };

    @{ $self->{_text_buffer} } = ();

    return @lines;
}

# Implements '.'; dump a scalar or structure to text.
sub _element2text {
    my($self, $element, $quote_strings) = @_;

    INFO "_element2text: formatting element ", $element;
    INFO "_element2text: strings will"
         , $quote_strings ? ' ' : ' not '
         ,"be quoted";

    # shortcut for simple scalars
    if ( !ref($element) or ref($element) eq 'Lang5::String' ) {
        $element = 'undef' unless defined $element;
        $element .= "\n" if $element =~ /^$re{float}$/;
        return $element;
    }

    my $indent = 2;
    my @estack = ( $element );
    my @istack = ( 0 );

    my $txt = '';

    while ( @estack ) {

        my $e = $estack[-1];
        my $i = $istack[-1];

        # new array: output opening bracket
        if ( $i == 0 ) {
            if ( $txt ) {
                $txt .= "\n";
                $txt .= ' ' x ( $indent * ( @istack - 1 ) );
            }
            $txt .= '[';
        }

        if ( $i <= $#$e  ) {
            # push next reference and a new index onto stacks
            if ( ref($e->[$i]) and ref($e->[$i]) ne 'Lang5::String' ) {
                push @estack, $e->[$i];
                push @istack, 0;
                next;
            }

            # output element
            if ( $txt =~ /\]$/ ) {
                $txt .= "\n";
                $txt .= ' ' x ( $indent * @istack );
            } else {
                $txt .= ' ';
            }
            $txt .= defined($e->[$i])
                    ? ( $e->[$i] =~ m/^$re{float}$/
                        ? sprintf("$self->{number_format} ", $e->[$i])
                        : ( $quote_strings
                            ? $self->_quote_if_string($e->[$i])
                            : $e->[$i]
                          )
                      )
                    : 'undef';
        }

        # after last item, close arrays
        # on an own line and indent next line
        if ( $i >= $#$e ) {

            my($ltxt) = $txt =~ /(?:\A|\n)([^\n]*?)$/;

            #  The current text should not end in a closing bracket as it
            # would if we had typed an array and it should not end in a
            # parenthesis as it would if we typed an array with an object
            # type .
            if ( $ltxt =~ /\[/ and $ltxt !~ /\]|\)$/ ) {
                $txt .= ' ';
            } else {
                $txt .= "\n";
                $txt .= ' ' x ( $indent * ( @istack - 1 ) );
            }
            $txt .= ']';

            # Did we print an element that had an object type set?
            my $last_type = ref(pop @estack);
            $txt .= "($last_type)"
                if $last_type
                   and
                   $last_type ne 'ARRAY'
                   and
                   $last_type ne 'Lang5::String';
            pop @istack;
        }

        $istack[-1]++
            if @istack;
    }

    $txt .= "\n" unless $txt =~ /\n$/;

    return $txt;
}


# Handling the content of the output text buffer.
sub _output {
    my $self = shift;

    TRACE "_output: ", \@_;

    push @{ $self->{_text_buffer} }, @_;

    my $current_fout = $self->{_files}{$self->{_fout}}{name};
    my $current_hout = $self->{_files}{$self->{_fout}}{handle};

    if ( $current_fout ne 'STDOUT' and $current_fout ne 'STDERR' ) {

        # an output file is specified -> print buffer to file

        print $current_hout @{ $self->{_text_buffer} };

    } elsif ( $self->{text_callback} ) {

        # STDOUT|STDERR and callback set -> call callback
        TRACE "calling text_callback";
        $self->{text_callback}->( @{ $self->{_text_buffer} } );

    } else {

        # let calling app handle text with get_text()
        return;
    }

    # clearing text_buffer
    @{ $self->{_text_buffer} } = ();
}

# Put an evenly spaced multiline list of all user defined words known to
# the interpreter into the text buffer. Each word is preceded by a letter
# denoting its type (cf. subroutine word_list).
sub _words2text_buffer {
    my($self) = @_;

    my $i = 0;
    my $txt = '';
    for my $entry ( sort keys %{ $self->{_words} } ) {

        my $type = uc($element_type{$self->{_words}{$entry}{type}}) || '-';

        $txt .= sprintf "%s:%-12s ", $type, $entry;
        $txt .= "\n" if ++$i % 5 == 0;
    }

    $txt .= "\n" if $i % 5 != 0;

    $self->_output($txt);
}


# Dump the definition of a word, making use of
# _explain_word, defined below:
sub _dump_word {
    my($self, $name) = @_;

    my $wroot = $self->_find_word($name);

    unless ( $wroot ) {
        ERROR "no user defined word or element named '$name' found";
        return;
    }

    my $word  = $wroot->{$name};
    my $type  = $word->{type};

    INFO "_dump_word: word: ", $word;

    my %wkeys = map { $_ => 1 } grep {
        ref($word->{$_}) eq 'HASH'
    } keys %$word;

    INFO "_dump_word: wkeys:", \%wkeys;

    unless ( $type eq 'variable' or keys(%wkeys) ) {
        ERROR "'$name' is not of type variable or user defined word";
        return;
    }

    if ( $type eq 'variable' ) {
        my $value = (ref($word->{value}) || $word->{value} =~ /$re{float}/)
                  ? $word->{value}
                  : "\"$word->{value}\"";
        return "$value '$name set\n";
    }

    my $wtype = $element_type{$type};

    my $txt;
    for my $wkey ( sort keys %wkeys ) {
        my $exp  = $self->_explain_word($word, $name, $wkey);
        my $ntrl = $word->{$wkey}{ntrl};
        $txt .= ": $name";
        if ( $word->{pop} ) {
            my @wk = split(/\s/, $wkey);
            my $oc = $#{ $word->{pop} };
            $txt  .= '(';
            $txt  .= join(',', map { $wk[$_] || '*' } 0..$oc);
            $txt  .= ')';
        }
        $txt .= "{$ntrl}" if $ntrl;
        $txt .= "\n$exp";
        $txt .= "\n" unless $exp =~ /\n$/;
        $txt .= ";\n"
    }

    $txt .= "\n";

    return($txt);
}


# iteratively dump a word definition.
sub _explain_word {
    my($self, $word, $name, $wkey) = @_;

    $wkey ||= ' ';

    my @prog  = @{ $word->{$wkey}{prog} };

    INFO "_explain_word: prog: ", \@prog;

    my $i     = -1;
    while ( ++$i < @prog ) {

        next if !ref($prog[$i]) or ref($prog[$i]) eq 'Lang5::String';

        my $flatten = 0;
        if ( $i > 0 and $prog[$i - 1] eq 'do' ) {
            splice @prog, $i + 1, 0, 'loop';
            $flatten = 1;
        }

        if ( $i > 0 and $prog[$i - 1] eq 'else' ) {
            splice @prog, $i + 1, 0, 'then';
            $flatten = 1;
        }

        if ( $i > 0 and $prog[$i - 1] eq 'if' ) {
            splice @prog, $i + 1, 0, 'then'
                unless $prog[$i + 1] and $prog[$i + 1] eq 'else';
            $flatten = 1;
        }

        splice @prog, $i , 1, @{ $prog[$i] }
            if $flatten;
    }

    $i = -1;
    my $indent = " " x 2;
    my $depth = 1;
    my $txt = '';

    while ( ++$i < @prog ) {

        INFO "E:$prog[$i], D:$depth";

        my $el;
        if ( $prog[$i] =~ /^(?:if|else|then|do|loop)$/ ) {
            $el = $prog[$i];
        } elsif ( ref($prog[$i]) eq 'ARRAY' ) {
            INFO "_explain_word: formatting ", $prog[$i];
            $el = $self->_element2text($prog[$i], 1);
        } else {
            $el = $self->_quote_if_string($prog[$i]);
        }

        my($lastline) = $txt =~ /([^\n]+)$/;
        $lastline ||= '';
        TRACE "L: >>$lastline<<";

        if (
            $prog[$i] eq 'else'
            or (
                $prog[$i] =~ /^(?:if|then|do|loop)$/
                and
                $prog[$i-1] !~ /^(?:if|then|do|loop)$/
            )
            or
            length($lastline || '') + length($el) > $self->{terminal_width} - 10
        ) {
            TRACE "add newline before element";
            $txt .= "\n";
        }

        my $prefix;
        if ( $prog[$i] =~ /^(?:if|do)$/ ) {
            $prefix =  $indent x $depth++;
        } elsif ( $prog[$i] =~ /^(?:loop|then)$/ ) {
            $prefix = $indent x --$depth;
        } elsif ( $prog[$i] eq 'else' ) {
            $prefix = $indent x ($depth - 1);
        } else {
            $prefix = $indent x $depth;
        }

        $prefix = ' ' if $txt !~ /(\A|\n)$/;

        my $postfix = '';
        if ( $prog[$i] =~ /^(?:if|else|then|do|loop)$/ ) {
            $postfix = "\n";
        }

        $txt .= $prefix . $el . $postfix;
    }

    return $txt;
}


sub _parse_word_header {
    my($self, $el) = @_;

    TRACE '_parse_word_header -> el: ', $el;

    my@parts = $el =~ /^
        ([^\(\)]+)      # non parens --> name
        (?:             # do not capture
            \((.*?)\)   # everything in parens --> opstr
        )?              # the parens section is optional
        (?:             # do not capture
            \{(.+?)\}   # everything in braces --> ntrl
        )?              # the braces section is optional
    $/x;

    TRACE 'parts:', \@parts;

    $parts[1] = [ split /\s*,\s*/, $parts[1] || '' ]
        if defined $parts[1] ;

    return @parts;
}


sub _begin_word {
    my($self, $wname, $wtype, $ops, $ntrl) = @_;

    # long name for word type wtype==b --> type==binary
    my $type = $wtype eq 'f' ? 'function' : $reverse_type{$wtype};

    # hash key for operand types
    my $wkey = ' ';
    if ( $type eq 'unary' ) {
        $wkey = $ops->[0] || '*';
    } elsif ( $type eq 'binary') {
        $wkey = join(' ', map { $ops->[$_] || '*' } 0 .. 1);
    }

    my $wroot
        = @{ $self->{_word_def_stack} }
        ? $self->{_word_def_stack}[-1]{words}
        : $self->{_words};

    # checks
    if ( exists $wroot->{$wname} ) {

        # type cannot be changed
        my $old_type = $wroot->{$wname}{type};
        if ( $type ne $old_type ) {
            my $msg = "Word name '$wname' already defined with type '$old_type'";
            $self->{_last_error} = $msg;
            ERROR $msg;
            return;
        }

        if ( exists $wroot->{$wname}{$wkey} ) {
            WARN "redefining word $wname($wkey)";
        }

    } else {

        # create default entry
        $wroot->{$wname} = {
            name  => $wname,
            type  => $type,
            $wtype eq 'f' ? () : ( pop   => $stack_type{$wtype} ),
            $wtype eq 'f' ? () : ( stack => [] ),
        };
    }

    # create entry in word hash
    $wroot->{$wname}{$wkey} = {
        prog  => [],
        words => {},
        $ntrl  ? ( ntrl  => $ntrl ) : (),
    };

    # push new word definition values to word_stack
    push @{ $self->{_word_def_stack} }, {
        words => $wroot->{$wname}{$wkey}{words},
        wkey  => $wkey,
        wname => $wname,
        prog  => $wroot->{$wname}{$wkey}{prog},
    };

    return $wroot->{$wname};
}


sub _prog2code {
    my($self, $wref) = @_;

    my $wroot
        = @{ $self->{_word_def_stack} }
        ? $self->{_word_def_stack}[-1]{words}
        : $self->{_words};

    my $wkey  = $wref->{wkey};
    my $wname = $wref->{wname};

    my $word  = $wroot->{$wname};
    my $wpop  = $word->{pop} || [];

    INFO "_prog2code: wname:>>$wname<<, wkey:>>$wkey<<";

    $word->{$wkey}{code} = sub {

        INFO "called anon sub '$wname' with key '$wkey'";
        INFO "Params: ", [@_[1..$#_]];

        my $udf
            = $word->{type} =~ /^unary|binary$/
              and
              exists($word->{prog});

        my $wstack;
        if ( $udf ) {
            push @{ $word->{stack} }, $_[$_]
                for reverse 1 .. @$wpop;
            $wstack = $word->{stack};
        } else {
            $wstack = $_[1];
        }

        INFO "$wname: wstack: ", $wstack;

        push @{ $self->{_word_exc_stack} }, $word->{$wkey}{words} || {};

        $self->{_last_error} = undef;
        $self->_execute($word->{$wkey}{prog}, 1, $wstack);

        pop @{ $self->{_word_exc_stack} };

        # $word->{code} should be run in an eval
        die $self->{_last_error} . "\n"
            if $self->{_last_error};

        INFO 'word stack: ', $word->{stack};

        if ( $udf ) {
            return pop @{ $word->{stack} };
        } else {
            return;
        }
    };

    TRACE "_prog2code: word: ", $word;

    return $word;
}


sub _execute_word {
    my($self, $wroot, $wname, $stack) = @_;

    my $word = $wroot->{$wname};

    INFO "_execute_word: word ", $word;
    INFO "_execute_word: stack ", $stack;

    if ( $word->{type} eq 'variable' ) {

        # if the current element is the name of a variable,
        # push its contents onto the data stack
        DEBUG "Push contents of variable $wname onto stack";
        $self->{_statistics}{'Push variable'}++;
        push @$stack, ref($word->{value}) ? dclone($word->{value}) : $word->{value};
        return 1;
    }

    # check the stack
    if ( $word->{pop} and @{ $word->{pop} } ) {
        unless ( $self->_check_params($word->{pop}, $stack) ) {
            $self->{_error} = 1;
            return;
        }
    }

    my @result;
    if ( $word->{type} eq 'unary' ) {

        eval { $self->_unary($word, $stack->[-1]) };

    } elsif ( $word->{type} eq 'binary' ) {

        eval { $self->_binary($word, $stack->[-1], $stack->[-2]) };

    } else {

        my $func
            = exists($word->{' '})
            ? $word->{' '}{code}
            : $word->{code};

        @result = eval { $func->($self, $stack) };

    }

    if ( $@ ) {
        $self->{_last_error} = $@;
        $self->{_error}      = 1;
        return;
    } else {
        push @$stack, @result
            if $word->{type} eq 'niladic';
    }

    $self->{_statistics}{ucfirst($word->{type})}++;

    # binary words modify TOS - 1 --> remove TOS
    pop @$stack
        if $word->{type} eq 'binary';

    return 1;
}


sub _get_func {
    my($self, $word) = @_;

    return sub {

        my @refs = map {
            my $r = ref($_[$_]);
            (!$r or $r eq 'Lang5::String') ? '*' : $r;
        } 1 .. 2;
        my $wkey
            = $word->{type} eq 'unary'
            ? ($refs[0] eq 'ARRAY' ? '*' : $refs[0])
            : join(' ', map {
                $_ eq 'ARRAY' ? '*' : $_
              } reverse @refs);

        if ( exists $word->{$wkey} ) {
            $word->{$wkey}{code}->(@_);
        } elsif (
            ($wkey eq '*' or $wkey eq '* *')
            and
            exists $word->{code}
        ) {
            $word->{code}->(@_);
        } else {
            die "no handler for type '$wkey'\n";
        }
    };
}


sub _get_ntrl {
    my($self, $word) = @_;

    return sub {

        my @refs = map {
            my $r = ref($_[$_]);
            (!$r or $r eq 'Lang5::String') ? '*' : $r;
        } 1 .. 2;
        my $wkey
            = $word->{type} eq 'unary'
            ? ($refs[0] eq 'ARRAY' ? '*' : $refs[0])
            : join(' ', map {
                $_ eq 'ARRAY' ? '*' : $_
              } reverse @refs);

        if ( exists $word->{$wkey} ) {
            return $word->{$wkey}{ntrl};
        } else {
            return $word->{ntrl} || '';
        }

    };
}


sub _find_word {
    my($self, $wname) = @_;

    my $wroot;
    for $wroot ( reverse @{ $self->{_word_exc_stack} } ) {
        return $wroot if $wroot->{$wname};
    }

    return;
}

# quote item if its a string
sub _quote_if_string {
    my($self, $value) = @_;

    return $value unless ref($value) eq 'Lang5::String';

    (my $quoted = $$value) =~ s/\\/\\\\/;
    $quoted =~ s/\n/\\n/;
    $quoted =~ s/\t/\\t/;
    $quoted = '"' . $quoted . '"';

    return $quoted;
}


sub statistics { $_[0]->{_statistics} }

sub error { $_[0]->{_error} }

sub exit_called { $_[0]->{_exit_called} }

sub set_break { $_[0]->{_break} = 1 }

sub break_called { $_[0]->{_break} }

sub last_error { $_[0]->{_last_error} }

sub get_stack { [ @{ $_[0]->{_stack} } ] }

1;
