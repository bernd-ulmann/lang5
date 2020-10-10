Lang5 - a stack oriented APL-like language
==========================================

What is Lang5?
--------------

Lang5 is a stack oriented programming language (if you are familiar with 
Forth, you will feel instantly at home in Lang5) with many APL-like 
features. Lang5 supports n-dimensional datastructures which can be easily
manipulated on the stack following the APL programming paradigm.

Platforms
---------

Lang5 has been written in Perl by Bernd Ulmann and Thomas Kratz and runs on
all platforms with a decent Perl interpreter installed. 

If you want to use the array processing features of Lang5 directly within 
Perl programs, you might want to have a closer look at the Perl module
[Array::APX](https://metacpan.org/pod/Array::APX).

First steps:
------------

Lang5 can be installed by unpacking lang5.zip which contains all required
modules etc. It is recommended to add the path to your local Lang5 installation
to your PATH-variable so that Lang5 can be invoked without the necessity
to specify an absolute or relative path. It can then be started by executing
`lang5`:
```
lang5
loading mathlib.5: Const..Basics..Set..Stat..Cplx..P..LA..Graph..Trig..NT..
loading stdlib.5:  Const..Misc..Stk..Struct..
lang5>
```

On startup the interpreter loads the modules found in the directory lib. As
of now there are two modules, the mathematical library `mathlib.5` and the 
standard library `stdlib.5`.

For a simple introductory example (a detailed description of the language etc.
can be found in [lang5_programming](doc/lang5_programming.pdf)) assume that 
we want to simulate the outcome of throwing a six sided dice 10 times.

We first create a vector containing 10 times the value 6 - the command `.` 
prints the top element of the stack (removing it):
```
lang5> 6 10 reshape .
[    6     6     6     6     6     6     6     6     6     6  ]
```

Applying the `?` operator to this vector replaces each vector element by a 
pseudorandom number between 0 and 6 (excluding 6):
```
lang5> 6 10 reshape ? .
[ 4.57888823093347  5.66943497823814  3.9537789693539  3.31383259974398  1.5666493855665  4.68637339529224  5.47878973919982  3.36891441444324  2.78258906253037  2.19838374189976  ]
```

Applying `int` will reduce each of these values to the nearest smaller integer 
yielding a vector of 10 elements, each in the interval [0,5]. Adding 1 yields
a vector of pseudorandom numbers in the interval [1,6]:
```
lang5> 6 10 reshape ? int 1 + .
[    5     6     2     5     5     5     1     5     4     6  ]
```

We now have to sum these values and divide the result by 10 to get the average
of this random experiment. Summing the values of a vector is done by means of
the reduce operator which expects a vector and a binary operator, effectively
applying the operator to each pair of successive vector elements:
```
lang5> 6 10 reshape ? int 1 + '+ reduce 10 / .
3.3
```

We can now simplify things by defining a new word `throw_dice` which expects
a scalar on the top of the stack which defined how often the dice should be 
rolled:
```
: throw_dice 6 over reshape ? int 1 + '+ reduce swap / ;
```

This new word can now be used to simulate 1000 runs of throwing the dice as
follows:
```
lang5> 1000 throw_dice .
3.496
```

Change history
==============

26-SEP-2020:
------------
/ The directory structure has been cleaned up, several small errors in the
  test programs were resolved. The documentation has been updated and cleaned
  up, the make_dist_kit.bash script has been revised.

26-MAY-2013:
------------
/ The introductory booklet has been revised, some (minor) faults have been 
  corrected and user input is now printed in red to distinguish it clearly from
  various system outputs.

04-MAY-2013:
------------
+ Part of the distribution kit is now a free book about the design and
  implementation of Lang5. It is named design_and_implementation.pdf and
  can be found in the directory named "doc". This book is intended to be 
  used for self-study as well as an introductory text into the implementation
  of small interpreters.
- Removed the old introductory text.
/ Fixed some nasty bugs in handling arrays and variables. (In fact, always
  pushing references onto the central stack resulted in some hard to debug
  phenomena - such data is now cloned using dclone from Array::DeepUtils 
  before pushing a reference onto the stack.)

04-APR-2013:
/ Corrected a rather nasty bug that made it impossible to push the string ';
  onto the stack (which caused the sort example to fail, among other programs).
/ Corrected some examples which did not work any longer due to some subtle
  changed in the interpreter. The matrix-vector-multiplication example even
  got simpler. :-)
+ There is now a tangens word in mathlib.5

20-OCT-2011:
------------
+ There are two new operators available: === and eql. Both work similar to the
  traditional comparison operators == and eq with the distinction that 0, "" and
  undef are handled as different values, so "0 undef ===" will yield 0 and not
  1.
/ CTRL-C is now handled correctly. A lang5-program containing an endless loop
  etc. can now interactively interrupted by pressing CTRL-C. If the interpreter
  was running in interactive mode this signal will return to the input prompt.
/ Update of the documentation.

30-AUG-2011:
------------
/ According to our doodle poll the language has been renamed to lang5. This
  was mainly due to the following facts: 1) lang5 had the most votes,
  2) SOLVO has been already used for consulting companies, data extraction
  software etc. and 3) lang5 already yields a number 1 hit in google.
/ The documentation has been extended a bit.
+ The '*-operator has been overloaded to perform matrix-matrix-multiplications,
  too.

06-AUG-2011:
------------
* 5 is now at version 1.0!!! :-)
+ Added new function "transpose" to perform a generalized matrix transposition.
/ Updated the documentation (transpose + a more detailed description of the
  Game-of-Life example).

01-AUG-2011:
------------
+ New generic function "rotate" added - this replaces the 5-implemented rmx and
  rmy functions in a general way. rmx and rmy have been remove from stdlib.5
+ Documentation reflects these changes.
/ The Game-of-Life-example has been adapted to the rotate function (and runs now
  approximately 5 times faster :-) ).

26-JUL-2011:
------------
+ Two new words for matrix rotation along their x- and y-axis have been 
  added to stdlib.5 (rmx and rmy).
+ A new example has been added: Conway's game of life.
! Lots of bugfixes and cleanups.

06-JUL-2011:
------------
+ execute can now work on arrays of strings containing 5 program sequences.
  This is very useful to avoid explicit loops by unrolling loops into such
  arrays and processing them with execute.
+ exit did not end a program, instead it caused the next instruction(s) to
  be read but then the interpreter collapsed. This has been fixed, too, exit
  does now what one would expect from it. :-)
+ A new example (the most complicated until now) has been added. It shows the
  calculation of a Mandelbrot set without any explicit loops (execution time
  is rather high - expect a run time of about 1 minute!).
+ The documentation has been updated and expanded.
+ Some additional operators have been overloaded to work on complex numbers.

29-JUN-2011:
------------
+ The documentation is now up to date and has been enhanced a lot! :-) 
+ A minor bug in explain was fixed that prevented the interpreter from loading
  workspace files that had been created using the word save.
+ Two support words were made local in stdlib.5 and mathlib.5.

24-MAY-2011:
------------
+ 5 is now able to work with overloaded operators. Therefore types were 
  introduced in the form of "dressed structures". The following example
  will show the basic idea (the documentation is still a bit behind - 
  sorry!):

  [[1 2 3][4 5 6][7 8 9]](m) [10 11 12](v)

  This will create a matrix with "dress" (m) and a vector, dressed as (v).
  Performing a matrix-vector-multiplication can now be performed by typing

  * .

  This works since * has been overloaded in lib/mathlib.5 (have a look).
+ The interpreter has undergone major changes.

29-JAN-2011:
------------
+ A lot of major changes has happened - mostly due to Thomas' great work. The
  most important aspect is that most of the basic array functions have now 
  found their way into an own module that will some day published on CPAN.
+ Fixed some minor problems in the mathlib.

20-SEP-2010:
------------
+ Added a new word, dreduce, to stdlib.5.
+ Modified ".s" in stdlib.5 to yield more readable output.
+ Added a new example for calculating perfect numbers.
+ Updated the documentation.

06-AUG-2010:
------------
+ The interpreter can now handle things like 1 [1 2 3] - .
+ We sped up the interpreter by a factor of about 3 yesterday using the
  NYTProf profiler Tim Bunce demonstrated on the YAPC::Europe 2010. :-)

21-JUN-2010:
------------
+ Added readline functionality to 5, so it is now possible to use command
  line editing functions. Unfortunately this currently works not on Windows
  and VMS systems.

05-JUN-2010:
------------
! "rho" and "dim" have been renamed "reshape" and "shape" to be more 
  compatible with APL and even Fortran 2003. :-) The documentation and
  examples etc. have been adapted accordingly.
+ Added an additional sanity check for "copy" which detects non-uniform
  coordinate vectors.
+ "reshape" can now handle scalar values as well, 1 10 reshape will 
  yield a ten element vector [1 1 1 1 1 1 1 1 1 1].
+ The dice example has been changed to make use of "reshape".
+ An additional example has been included which computes all numbers
  between 1 and 999 which equal the sum of the cubes of their individual
  digits.

31-MAY-2010:
------------
+ subscript can now handle even complex coordinate vectors and is not restricted
  to selecting elements along the first dimension only, as the following 
  example shows: 

		64 iota [4 4 4] rho [1 [1 2] [1 2 3]] subscript .

+ Added a function "copy" which copies successive elements from a deeply
  nested structure, controlled by a two element coordinate vector which 
  contains the coordinates of the upper left and lower right corner of an
  n-dimensional sub-cube of the basic nested structure. The following example
  shows the behaviour of copy quite well:

		64 iota [4 4 4] rho [[1 1 1] [2 2 2]] copy .

+ Added a function "help" which prints the description of builtin functions
  and operators. Try 

		'+ help

+ The output generated by specifying the statistics option -s now contains
  the maximum stack depth encountered during a program run (this value is
  surprisingly small).
+ Quite some comments have been added to the interpreter code to make it more
  readable and extensible.
+ Made some minor changed to stdlib.5 (extract had to be adapted to the new
  implementation of subscript) and mathlib.5.

04-MAY-2010:
------------
+ Fixed a problem with local stacks (thanks, Thomas! :-) )
+ Adapted the health_check to the fact that "deptbh" is now a function
+ Adapted the documentation and included an additional example concerning 
  Fibonacci numbers

02-MAY-2010:
------------
 5 is now available in version 0.1! :-)

 The documentation is up to date by now and reflects the current interpreter
version.

 More examples have been written.
