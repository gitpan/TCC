package C::TinyCompiler::StretchyBuffer;
use strict;
use warnings;
use parent 'C::TinyCompiler::package';

sub apply {
	my (undef, $state) = @_;
	
	# Make sure we have Perl's croak
	$state->apply_packages('C::TinyCompiler::Perl::Croak');
	
	# Add the stretchy buffer code
	$state->code('Head') .= C::TinyCompiler::line_number(__LINE__) . q{
	
		/* Need this so things work correctly on Mac */
		#define _ANSI_SOURCE
		
		#define sbfree(a)         ((a) ? free(stb__sbraw(a)),0 : 0)
		#define sbpush(a,v)       (stb__sbmaybegrow(a,1), (a)[stb__sbn(a)++] = (v))
		#define sbpop(a)          ((a && stb__sbn(a)) ? (a)[--stb__sbn(a)] : 0)
		#define sbcount(a)        ((a) ? stb__sbn(a) : 0)
		#define sbadd(a,n)        (stb__sbmaybegrow(a,n), stb__sbn(a)+=(n), &(a)[stb__sbn(a)-(n)])
		#define sbremove(a,n)     ((a) ? (stb__sbn(a) > n ? (stb__sbn(a) -= n) : (stb__sbn(a) = 0)) : 0)
		#define sblast(a)         ((a)[stb__sbn(a)-1])

		#include <stdlib.h>
		#define stb__sbraw(a) ((int *) (a) - 2)
		#define stb__sbm(a)   stb__sbraw(a)[0]
		#define stb__sbn(a)   stb__sbraw(a)[1]

		#define stb__sbneedgrow(a,n)  ((a)==0 || stb__sbn(a)+n >= stb__sbm(a))
		#define stb__sbmaybegrow(a,n) (stb__sbneedgrow(a,(n)) ? stb__sbgrow(a,n) : 0)
		#define stb__sbgrow(a,n)  stb__sbgrowf((void **) &(a), (n), sizeof(*(a)))

		static void stb__sbgrowf(void **arr, int increment, int itemsize)
		{
			int m = *arr ? 2*stb__sbm(*arr)+increment : increment+1;
			void *p = realloc(*arr ? stb__sbraw(*arr) : 0, itemsize * m + sizeof(int)*2);
			if (p == 0) croak("Unable to allocate StretchyBuffer memory!");
			if (p) {
				if (!*arr) ((int *) p)[1] = 0;
				*arr = (void *) ((int *) p + 2);
				stb__sbm(*arr) = m;
			}
		}

		#line 1 "whatever comes after C::TinyCompiler::StretchyBuffer"
	};
}

1;

__END__

=head1 NAME

C::TinyCompiler::StretchyBuffer - Enabling stretchy buffers in your context

=head1 SYNOPSIS

 use C::TinyCompiler;
 
 # Declare the compiler context with the stretchy buffer interface:
 my $context= C::TinyCompiler->new('::StretchyBuffer');
 
 # Create a function that uses stretchy buffers:
 $context->code('Body') = C::TinyCompiler::line_number(__LINE__) . q{
     void test_func() {
         /* stretchy buffers always start and end as null pointers */
         double * list = 0;
         
         /* Push some values onto the list */
         sbpush(list, 3.2);
         sbpush(list, -2.9);
         sbpush(list, 5);
         
         /* Eh, let's change that last one */
         list[2] = 22;
         
         /* Allocate room for five more */
         sbadd(list, 5);
         
         /* Get the list length */
         printf("List has %d available elements\n", sbcount(list));
         
          /* Set the last element */
         sblast(list) = 100;
         
         /* Pop the last element */
         printf("Last element was %f\n", sbpop(list));
         
         /* How many elements do we have? */
         printf("After a pop, we have %d available elements\n", sbcount(list));
         
         /* Remove two elements */
         int remaining = sbremove(list, 2);
         printf("sbremove returned %d\n", remaining);
         
         printf("After remove, we have %d available elements\n", sbcount(list));
         
         int i;
         printf("List:\n");
         for (i = 0; i < sbcount(list); i++) {
             printf("%d: %f\n", i, list[i]);
         }
         
         /* When we're all done, free the memory, restoring the value to null */
         sbfree(list);
     }
 };
 
 # Compile and call:
 $context->compile;
 $context->call_void_function('test_func');

=head1 DESCRIPTION

This C::TinyCompiler package provides Sean Barrett's implementation of stretchy buffers, as
well as a couple of extensions by David Mertens for popping and removing values
off the end. For more of Sean Barrett's cool work, see his website at
http://nothings.org/.

How do you begin? Always start by declaring a null pointer of whatever type you
want, like so:

 int * data = 0;
 char * input = 0;
 special_type * array_of_structs = 0;

You then allocate memory using C<sbpush> and C<sbadd>. Thanks to the magic of
preprocessor macros, accessing data in stretchy buffers is B<completely identical>
to accessing data from a normal array. The difference
between the two is the way that memory is managed for you (or not):

 /* Memory allocation is less verbose and includes the assertion */
 double * observations;
 sbadd(observations, 20);
 /* Iterating over values is identical */
 int i;
 for (i = 0; i < 20; ++i) {
     observations[i] = get_observation(i);
 }
 /* Different function for cleanup */
 sbfree(observations);
 
 /* Memory allocation is more verbose */
 double * observations = (double *) malloc (20 * sizeof(double));
 assert(observations);
 /* Iterating over values is identical */
 for (i = 0; i < 20; ++i) {
     observations[i] = get_observation(i);
 }
 /* Different function for cleanup */
 free(observations);

Again, the really cool part about stretchy buffers is that they automatically
handle extending the memory block when you push values or request the addition
of more space on the 'far' end. That is, pushing and popping data off the end is
easy and relatively fast (though shifting and unshifting off the front is not
provided).

C::TinyCompiler::StretchyBuffer provides the following interface:

=over

=item sbpush (array, value)

Pushes the given value onto the array, extending it if neccesary. This returns
the value that was just added to the list.

=item sbcount (array)

Returns the number of elements currently available for use.

=item sbadd (array, count)

Makes C<count> more elements available, allocating more memory if necessary.
This returns the address of the new section of memory.

=item sblast (array)

Returns the last available element in the array, an lvalue! Note that this
assumes that the array is B<not> null, so only call this when you know your
array is allocated.

=item sbpop (array)

Returns (the value of) the last available element in the array (or zero if the
array is empty), reducing the array length by 1 (unless the array is empty).
This does not deallocate the memory, however; that sticks around in case you
later perform a push or add.

=item sbremove (array, count)

Removes C<count> elements from the array, or if C<count> is greater than the
number of elements, empties the array. As with pop, this does not deallocate any
memory but rather holds onto it in case it can be used for a later push or add.
As an unplanned but pleasant side-effect, it returns the number of elements that
remain after the removal.

=item sbfree (array)

Frees the memory associated with the stretchy buffer, if any is allocated. It
always returns 0.

=back

=head1 AUTHORS

Sean Barrett, C<< http://nothings.org/ >>
David Mertens, C<< <dcmertens.perl at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests at the project's main github page:
L<http://github.com/run4flat/perl-TCC/issues>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc C::TinyCompiler::StretchyBuffer

You can also look for information at:

=over 4

=item * The Github issue tracker (report bugs here)

L<http://github.com/run4flat/perl-TCC/issues>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/C-TinyCompiler>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/C-TinyCompiler>

=item * Search CPAN

L<http://p3rl.org/C::TinyCompiler>
L<http://search.cpan.org/dist/C-TinyCompiler/>

=back

=head1 ACKNOWLEDGEMENTS

Sean Barett, of course, for creating such a simple but useful chunk of code, and
for putting that code in the public domain!

=head1 LICENSE AND COPYRIGHT

Sean Barett's original code is in the public domain. All modifications made by
David Mertens are Copyright 2012 Northwestern University.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut
