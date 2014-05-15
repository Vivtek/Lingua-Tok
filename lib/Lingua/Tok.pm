package Lingua::Tok;

use warnings;
use strict;

use Iterator::Simple qw(:all);
use Carp;

=head1 NAME

Lingua::Tok - Implements a generalized tokenizer for space- and punctuation-delimited natural languages

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Lingua::Tok takes a document containing natural language text, and returns an iterator that emits a stream of words and other
tokens.  The "non-word" tokens include: whitespace (permitting the exact input string to be restored), punctuation, and various other items -
numbers, number/unit combinations, URLs, and ID-like strings consisting of capital letters, dashes, and so on.
(Note that this model doesn't work very well for Chinese and Japanese, where word boundaries are non-trivial. If you work with Chinese
or Japanese, though, you already know that.)

A "token" is an arrayref whose first element is a type identifier and the remainder can be anything.

A "document" in this sense can be a simple string, or it can be any iterator that returns either a series of strings or a series of
strings interspersed with formatting tokens.  (A formatting token has type 'F' and can be interpreted by an output processor to create
a new document, or can act as a hook back into the original document for more detailed information.) A document is therefore itself
effectively a tokenizer; I kind of think of it as a "pre-tokenizer".

The token stream can be subject to lexical analysis as it passes through. There are two levels of lexical analysis that can be useful;
the first is stopword analysis, which identifies certain words as not being significant for content discovery (in English, these are
basically prepositions, pronouns, and articles, like a, the, he, of, and so on). The second and more involved level is part-of-speech
(POS) tagging; you can see that stopword analysis is just a degenerate form of POS tagging where the classification is binary.

Since natural languages have ambiguity at the lexical level (some words can play different roles depending on how they're used in a
sentence, ["Time flies like an arrow" vs. "Fruit flies like a banana"]), a lexicon has to be able to return a list of possible
parts of speech for some words. When used in a parser like Marpa, these ambiguities can then be resolved at the syntactic level.

At any rate, if you're using stopword lexical analysis, you can ask for a list of n-grams appearing in the token stream.

=head1 METHODS

=head2 new (document, lexicon)

The tokenizer can be given a blessed object, a coderef or a string upon initialization as the "document" containing text to be
tokenized (and additional text can also be added later, in the form of the same options).

If a string, it's the text itself. If it's a blessed object, it's considered to be a document object, which essentially means it
exposes a "tokens" method to get a pretokenized input stream. And if it's a coderef, then it I<is> that input stream,
that is, it's a closure to call each time the buffer runs dry; if that closure returns undef, there's
no more text. Tokens received from the coderef are passed through to the output without further ado.

In the case of a string input, this is considered a kind of "degenerate document" and tokens are simply split out naively on whitespace
and punctuation.

If no document is provided, the tokenizer starts out empty.

The other input to the tokenizer is the lexicon, which can be seen as a database that, given a word, can tell us a category
for it. If no lexicon is provided, then no assumptions are made about lexical entities at all, and punctuation will largely
be treated in terms of English.

Lexicons can be chained, so that certain types of string (like URLs) can be recognized before asking an English dictionary about
the other words.

=cut

sub new {
   my $self = bless {}, shift;
   
   $self->{document} = shift;
   $self->{reader} = $self->{document}->tokens;
   
   #$self->{splitter} = \&_split_with_sgml if not defined $self->{splitter};
   $self->{splitter} = \&_vanilla_split;# if defined $self->{splitter} eq 'plain';
   #$self->{splitter} = \&_split_with_sgml unless ref $self->{splitter} ne 'CODE';
   
   $self->{stopwords} = {};
   
   $self->{min_ngram} = 0;
   $self->{max_ngram} = 0;
   
   $self->{buffer} = [];
   
   #if (not defined $_[0]) {
   #} elsif (ref $_[0] eq 'CODE') {
   #   $self->{reader} = $_[0];
   #} elsif (not ref $_[0]) {
   #   $self->buffer ($_[0]);
   #} else {
   #   croak ("Can't understand input of type " . ref($_[0]));
   #}
   return $self;
}

=head2 setlang ($lang)

Sets the probable language of the text being tokenized.  Ignored for now. May be available from the input document.

=head2 split ($string)

The first step in tokenization is done with a simple regex.  Mostly it just splits on whitespace, but it can (and does by default)
also consider <...> to be a unit. Note that this could result in some problems, so (TODO:) it will have to be possible to change this
regexp in some way.

Note: formatting I<must> be taken into consideration at this stage, because formatting takes priority over spaces in reading text.
Really we need a formatting type of some kind; the generic SGML markup will do for now, but I don't entirely trust it.

=cut

sub _vanilla_split   { split /(\s+)/, join (' ', @_); }
sub _split_with_sgml { map {/^<.*>$/ ? ['F', $_] : decode_entities(split /(\S+)/)} split /(<.*?>)/, join (' ', @_); }

sub split {
   my $self = shift;
   $self->{splitter}->(@_);
}

=head2 stopwords ($word, $word, ...)

Add any number of words to the stop word list for phrase delineation.  They're all stored in a hash for quick access.

=cut

sub stopwords {
   my $self = shift;
   foreach (@_) {
      $self->{stopwords}->{lc($_)} = 1;
   }
}

=head2 stopword ($word)

Checks whether the given word is a stop word.

=cut

sub stopword {
   my $self = shift;
   $self->{stopwords}->{lc($_[0])};
}

=head2 buffer ($string)

Text can be pushed into the buffer.  This text will go onto the existing buffer and will take precedence over the document
(if you specified a document) or other reader (if you specified a reader).

=cut

sub buffer {
   my $self = shift;
   foreach my $incoming (@_) {
      next unless defined $incoming;
      if (ref $incoming) {
         push @{$self->{buffer}}, $incoming;
      } else {
         push @{$self->{buffer}}, $self->split($incoming);
      }
   }
}

=head2 tokens ($text)

Gets all the tokens it can from the tokenizer, optionally after passing in more text to tack onto the end of whatever buffer
is already there.

=cut

sub tokens {
   my $self = shift;
   $self->buffer(@_) if @_;
   my @return = ();
   my $token;
   while (defined ($token = $self->token())) {
      push @return, $token;
   }
   return @return;
}

=head2 text ($text)

Like C<tokens> but drops all space tokens.  The reconstructed string won't be spaced quite right, especially around punctuation, unless
you reconstruct it carefully.

=cut

sub text {
   my $self = shift;
   $self->buffer(@_) if @_;
   my @return = ();
   my $token;
   while (defined ($token = $self->token())) {
      next if ref $token and defined $token->[0] and $token->[0] eq 'S';
      push @return, $token;
   }
   return @return;
}

=head2 words ($text)

Like C<tokens> or C<text> but drops all special tokens entirely - no spaces, no punctuation, no special things like URLs, just the plain
words; this is useful for spell checking.

=cut

sub words {
   my $self = shift;
   $self->buffer(@_) if @_;
   my @return = ();
   my $token;
   while (defined ($token = $self->token())) {
      next if ref $token;
      push @return, $token;
   }
   return @return;
}

=head2 phrases ($text)

Returns the same series of words as C<words>, but broken into subarrayrefs on punctuation/formatting and any stop words defined using
the C<stopwords> function.

For example, given typical stop words for English and assuming we had a POD reader, we'd get the following phrases for the sentence above:
"Returns", "same series", "words", "words",
"broken", "subarrayrefs", "punctuation/formatting", "stop words defined", "stopwords", "function".  Probably.
(I'm assuming all articles, pronouns, and prepositions are in the stopword list.)

=cut

sub phrases {
   my $self = shift;
   $self->buffer(@_) if @_;
   my @return = ();
   my @phrase = ();
   my $token;
   while (defined ($token = $self->token())) {
      next if ref $token and defined $token->[0] and $token->[0] eq 'S';
      if (ref $token or $self->stopword($token)) {
         if (@phrase) {
            push @return, [@phrase];
            @phrase = ();
         }
      } else {
         push @phrase, $token;
      }
   }
   push @return, [@phrase] if @phrase;
   return @return;
}

=head2 min_ngram, max_ngram

These are parameters for the minimum and maximum n-gram sizes for the C<ngrams> retrieval method below.  If they're not specified,
C<ngrams> will return n-grams of all lengths, including single words.

Call these without a value to retrieve the current values.

=cut

sub min_ngram {
   my ($self, $value) = @_;
   if (defined $value) {
      $self->{min_ngram} = $value;
   }
   $self->{min_ngram};
}
sub max_ngram {
   my ($self, $value) = @_;
   if (defined $value) {
      $self->{max_ngram} = $value;
   }
   $self->{max_ngram};
}

=head2 ngrams ($text)

Returns a list of all the n-grams in the given text, broken on the stop words configured.  The n-grams are returned as strings with the
words delineated by spaces. If a maximum I<n> is given in C<$max>, then only n-grams up to that window will be returned; if a minimum
I<n> is given, then only n-grams that size or above will be returned.  Single words are returned (if no C<$min> is supplied), since
they're 1-grams.  If a maximum number of 0 is given, no maximum will be applied, so you can get n-grams of size 2 and higher by specifying
C<..., 0, 2>.

=cut

sub ngrams {
   my $self = shift;
   my @return;
   foreach my $phrase ($self->phrases(@_)) {
      my $len = @$phrase;
      for (my $n  = ($self->{min_ngram} ? $self->{min_ngram} : 1);
              $n <= ($self->{max_ngram} ? $self->{max_ngram} : $len);
              $n += 1) {
         for (my $i = 0; $i + $n <= $len; $i += 1) {
            push @return, join (' ', @$phrase[$i .. $i + $n - 1]);
         }
      }
   }
   return @return;
}

=head2 token ($flag)

If C<$flag> is "peek", returns a token without consuming it (i.e. leaves it on the queue); otherwise, takes the next token from the
queue and returns it.

A token may be a string (which is a vanilla word) or an arrayref with a type string and arbitrary other components.  The type string
can be at least one of C<S> (whitespace), C<P> (punctuation), C<I> (index - an arbitrary placeholder provided by the text source),
C<F> (formatting code), C<NUM> (a number), C<NUMU> (a number/unit combination), C<URL> (a URL), C<ID> (a non-word ID - non-word in
the sense that it won't be in a dictionary, but still acts as a word in the sentence, generally a noun).  Other types may follow.
In general, single-letter types (S, P, I, F) are grammatically not words, while other types (NUM, URL, ID) act as grammatical words but are
artificial in nature and are not expected to be in a lexicon or spelling list.

(You can see from the presence of numbers and numbers-with-units in the special token list that I'm a technical translator, by the way.)

The C<iterator> method just returns the actual iterator (and builds it if it hasn't already been built).

=cut

sub token { $_[0]->_iterator->($_[1]); }
sub _iterator {
   my ($self) = @_;
   $self->_build_iterator unless $self->{iterator};
   $self->{iterator};
}

# A little implementation chat here.
# The tokenizing iterator simply returns a token each time it's called.  To do this, it goes through the following steps:
# 1. If the token buffer in $self->{buffer} is empty and if a retriever is defined, call the retriever for more buffer.
#    If no retriever is defined or the retriever returns undef, we're done tokenizing, so return undef as the token.
# 2. Now there are tokens available; get the first one.
# 2a. There are three ways this can go; if this is a finished token from the last time around the loop, return it.
# 2b. If not, it's a string; either it's whitespace or not.  If so, and it's just a single space, don't
#     return anything; go to the next token.  If it's more than a single space, return it as a space token.
# 3. The third possibility is that it's a string that's not whitespace and thus probably a word.
#    We have a number of heuristics to classify "special" punctuation-containing non-lexical words:
#    a. URLs are first.
#    b. Numeric.
#    c. Numeric plus unit.
#    d. Some plugin structure.
#    The plugin architecture should provide a couple of services: splitting off initial and trailing punctuation, and optionally attaching
#    parts of the upcoming tokens.

sub _build_iterator {
   my ($self) = @_;
   $self->{iterator} = iterator {
      GET:
      # Get more buffer if possible.
      if (not @{$self->{buffer}}) {
         if ($self->{reader}) {
            $self->buffer ($self->{reader}->());
         }
      }
      
      # Return end-of-stream if there's still no buffer.
      return undef unless @{$self->{buffer}};
      
      # Get a token; return it if it's already been tokenized.  Get another if it's a single space.
      my $token = shift @{$self->{buffer}};
      goto GET if not defined $token or $token eq '';   # First-line splitting may produce some artifacts.
      return $token if ref $token;
      
      # If the next token is still all whitespace return it as a space token.
      return ['S', $token] if $token =~ /^\s*$/;
      
      # Special-case punctuation handlers here, including language-specific stuff like Mr. or 'n (Afrikaans - thanks, Wikipedia!)
      
      # Check for any punctuation that wasn't handled by special cases.
      # - initial punctuation
      if ($token =~ /^(\p{Punct})(.*)$/) {
         unshift @{$self->{buffer}}, $2;
         return ['P', $1];
      }
      # - final punctuation
      if ($token =~ /^(.*?)(\p{Punct}+)$/) {
         $token = $1;
         unshift @{$self->{buffer}}, $2;
      }
      
      # Word-internal punctuation is passed through.  I think.  TODO: resolve that.
      
      # All else failing, this is a word.  Return it as a plain string.
      return $token;
   };
   $self->{iterator};
}

=head2 word(), texttok()

Acts like C<token()> but skips any tokens that are not plain-text words.

=cut

sub word {
   my $self = shift;
   AGAIN:
   my $word = $self->token;
   goto AGAIN if ref $word;
   $word;
}
sub texttok {
   my $self = shift;
   AGAIN:
   my $word = $self->token;
   goto AGAIN if ref $word and $word->[0] eq 'S';
   $word;
}

=head2 restring (tokenlist, formatter)

Given an arrayref of tokens, generates the text string that should have given rise to it.  Index tokens will be turned into line breaks
and formatting codes will be ignored unless C<$formatter> is specified - if it is specified, it will be given each formatting token
and must return the string representation of that token. If your particular formatting won't fit into that model, don't use C<restring>.

=cut

sub restring {
}

=head1 AUTHOR

Michael Roberts, C<< <michael at vivtek.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-Lingua-tokenizer at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Lingua-Tokenizer>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Lingua::Tok


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Lingua-Tokenizer>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Lingua-Tokenizer>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Lingua-Tokenizer>

=item * Search CPAN

L<http://search.cpan.org/dist/Lingua-Tokenizer/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2013 Michael Roberts.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1; # End of Lingua::Tok
